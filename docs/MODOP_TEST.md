# Mode opératoire de test — pipeline dbt Chicago Taxi

Ce document décrit, pas à pas, comment tester le pipeline en local et quels résultats attendre.
Les commandes sont données pour **Windows (PowerShell)** ; l'équivalent macOS / Linux est indiqué quand il diffère.

Les valeurs attendues ont été mesurées sur le fichier de test `Taxi_Trips_sample.csv`
(200 000 premières lignes de l'export du 1er trimestre 2023 au format français).

---

## Récapitulatif des scénarios

| # | Scénario | Ce qu'on vérifie | Résultat attendu |
|---|---|---|---|
| T0 | Installation | l'environnement est prêt | `dbt --version` affiche dbt-core et duckdb |
| T1 | Test rapide (échantillon versionné) | le pipeline tourne sans aucune donnée externe | `PASS=43`, contrôle OK |
| T2 | Test de référence (200 000 lignes) | volumétrie, qualité et KPIs sur données réelles | `PASS=43`, chiffres du § T2 |
| T3 | Relance | idempotence : mêmes résultats à chaque exécution | chiffres identiques à T2 |
| T4 | Tests unitaires | parsing des 4 formats et motifs de rejet | `PASS=2` |
| T5 | Anomalies connues | chaque cas invalide est mis en quarantaine avec le bon motif | 3 valides, 6 rejets |
| T6 | Format de source cassé | le pipeline s'arrête avant gold | `ERROR=1` sur `assert_no_parsing_loss` |
| T7 | Doublons entre fichiers | la déduplication neutralise un fichier chargé deux fois | silver identique à T2 |
| T8 | Seuil qualité modifié | les règles sont paramétrables | plus de rejets `invalid_duration` |
| T9 | Exécution partielle | on peut ne reconstruire qu'une couche | `PASS=17` |
| T10 | Documentation et lignage | la doc dbt se génère | page web avec le graphe des modèles |
| T11 | Export complet (optionnel) | tenue de la volumétrie réelle | `PASS=43`, contrôle OK |

---

## T0 — Installation

**Prérequis** : Python 3.11 à 3.13 installé (`python --version`).

```powershell
cd <dossier>\chicago-taxi-dbt
python -m venv .venv
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass   # autorise l'activation du venv pour cette fenêtre
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
dbt --version
```

macOS / Linux : `python3 -m venv .venv` puis `source .venv/bin/activate`.

**Attendu** : `dbt --version` affiche `core: 1.12.6` et le plugin `duckdb: 1.11.1`.

> Toutes les commandes suivantes se lancent depuis la racine du projet, avec le venv activé
> (le prompt commence par `(.venv)`).

---

## T1 — Test rapide sur l'échantillon versionné

```powershell
dbt build --profiles-dir . --vars "{raw_csv_glob: 'data/sample/*.csv'}"
python scripts/check_results.py
```

**Attendu**

- dbt : `Done. PASS=43 WARN=0 ERROR=0 SKIP=0`
- contrôle :

| Indicateur | Valeur |
|---|---|
| bronze | 5 000 |
| silver valides | 4 881 |
| rejets | 119 (`invalid_duration` 111, `invalid_amount` 8) |
| période | du 2023-03-30 23:30 au 2023-03-31 10:30 |
| résultat global | `OK` |

---

## T2 — Test de référence sur le fichier de 200 000 lignes

**Préparation** : le fichier de test doit se trouver dans `data/raw/`. Il y est déjà si le projet vient de
l'archive zip ; sinon, le copier depuis Documents. Ce dossier ne doit contenir **que** ce CSV, car le pipeline
lit tous les CSV qu'il y trouve.

```powershell
Get-ChildItem data\raw\*.csv          # un seul fichier attendu : Taxi_Trips_sample.csv
# s'il est absent :
Copy-Item "$HOME\Documents\Taxi_Trips_sample.csv" data\raw\
dbt build --profiles-dir .
python scripts/check_results.py
```

**Attendu — exécution dbt** : `Done. PASS=43 WARN=0 ERROR=0 SKIP=0` (une dizaine de secondes).

**Attendu — volumétrie et qualité**

| Indicateur | Valeur |
|---|---|
| bronze (lignes brutes) | 200 000 |
| silver (courses valides) | 195 776 |
| rejets | 4 224 |
| dont `invalid_duration` (durée nulle) | 4 045 |
| dont `invalid_amount` (montant absent) | 179 |
| taux de rejet | 2,11 % |
| bronze = valides + rejets | OK |
| période | du 2023-03-20 18:15 au 2023-03-31 10:30 (12 jours) |

**Attendu — couche gold**

| Table | Nb de lignes | Point de contrôle |
|---|---|---|
| `gld_daily_kpis` | 12 | 22/03/2023 : 22 018 courses, 600 061,46 $ |
| `gld_pickup_area_ranking` | 78 (77 zones + « Hors Chicago / inconnue ») | n°1 en volume : Near North Side (39 983 courses) ; n°1 en revenu : O'Hare (1 853 141,31 $) |
| `gld_hourly_demand` | 168 (7 jours × 24 h) | — |
| `gld_payment_mix` | 7 | Credit Card : 77 298 courses (39,48 %) |

Revenu total silver : **5 285 186,30 $**. Les 4 fichiers Parquet sont présents dans `output/gold/`.

**Vérification manuelle (facultatif)**

```powershell
python -c "import duckdb; c=duckdb.connect('warehouse/chicago_taxi.duckdb', read_only=True); print(c.sql('select * from gold.gld_pickup_area_ranking limit 10'))"
```

Le fichier `output/gold/gld_daily_kpis.parquet` peut aussi être ouvert dans Power BI ou Excel (via Power Query).

---

## T3 — Relance (idempotence)

```powershell
dbt build --profiles-dir .
python scripts/check_results.py
```

**Attendu** : exactement les mêmes chiffres qu'en T2. Pas de doublon, car chaque table est reconstruite intégralement.

---

## T4 — Tests unitaires seuls

```powershell
dbt test --profiles-dir . --select test_type:unit
```

**Attendu** : `PASS=2`.

- `test_parsing_handles_both_export_formats` : une même course est lue identiquement dans les quatre formats suivants.

  | Format | Date | Durée | Montant |
  |---|---|---|---|
  | site en anglais | `01/31/2019 11:45:00 PM` | `1,020` | `$1,234.50` |
  | API | `2019-01-31T23:45:00.000` | `1020` | `1234.5` |
  | site en français | `01/31/2019 11:45:00 PM` | `1 020` | `$1 234,50` |
  | ré-encodé par PowerShell | `01/31/2019 11:45:00 PM` | `1â€¯020` | `$1â€¯234,50` |

- `test_invalid_rows_get_a_rejection_reason` : chaque type d'anomalie reçoit le bon motif.

---

## T5 — Anomalies connues

Le fichier `data/test_cases/anomalies.csv` contient 9 lignes construites à la main.

```powershell
dbt build --profiles-dir . --vars "{raw_csv_glob: 'data/test_cases/anomalies.csv'}"
python scripts/check_results.py
```

**Attendu — exécution** : `PASS=41 WARN=2 ERROR=0`. Les deux avertissements sont normaux :

- `not_null_brz_taxi_trips_trip_id` : une ligne sans identifiant est arrivée en bronze ;
- `assert_rejection_rate_below_threshold` : 6 rejets sur 9 lignes dépassent le seuil d'alerte de 10 %.

**Attendu — répartition**

| trip_id | Anomalie | Résultat |
|---|---|---|
| `TEST_OK_1` | aucune | silver |
| `TEST_OK_2` | aucune (milliers avec espace fine : `1 140` s, `$1 020,00`) | silver, durée 1 140 s, tarif 1 020,00 $ |
| `TEST_DUP` (1re occurrence) | aucune | silver |
| `TEST_DUP` (2e occurrence) | doublon | rejet `duplicate_trip_id` |
| *(vide)* | identifiant manquant | rejet `missing_trip_id` |
| `TEST_DUREE_0` | durée 0 s | rejet `invalid_duration` |
| `TEST_NEGATIF` | montant négatif | rejet `invalid_amount` |
| `TEST_FIN_AVANT_DEBUT` | fin avant début | rejet `end_before_start` |
| `TEST_DISTANCE` | 9 999 miles | rejet `invalid_distance` |

Contrôle : bronze 9, silver 3, rejets 6, `bronze = valides + rejets : OK`.

---

## T6 — Format de source cassé (test de robustesse)

Le fichier `data/test_cases/format_casse.csv` contient une date dans un format inconnu (`31.03.2023 10h30`).

```powershell
dbt build --profiles-dir . --vars "{raw_csv_glob: 'data/test_cases/format_casse.csv'}"
```

**Attendu** :

- `FAIL 1 assert_no_parsing_loss` ;
- `Done. PASS=10 WARN=1 ERROR=1 SKIP=31` : les modèles silver finaux et gold ne sont pas reconstruits.

C'est le comportement voulu : un changement de format de la source arrête le pipeline au lieu de produire
des KPIs faux.

> Après T6, la base contient un état partiel : relancer T2 pour revenir à l'état de référence.

---

## T7 — Doublons entre fichiers

On simule un même export chargé deux fois.

```powershell
Copy-Item data\raw\Taxi_Trips_sample.csv data\raw\Taxi_Trips_sample_copie.csv
dbt build --profiles-dir .
python scripts/check_results.py
Remove-Item data\raw\Taxi_Trips_sample_copie.csv     # nettoyage
```

**Attendu** :

| Indicateur | Valeur |
|---|---|
| exécution dbt | `PASS=42 WARN=1` (alerte sur le taux de rejet, attendue) |
| bronze | 400 000 |
| silver | **195 776**, identique à T2 : aucun KPI n'est doublé |
| rejets | 204 224 (`duplicate_trip_id` 200 000, `invalid_duration` 4 045, `invalid_amount` 179) |

---

## T8 — Seuil qualité paramétrable

On abaisse la durée maximale autorisée de 24 h à 1 h.

```powershell
dbt build --profiles-dir . --vars "{max_trip_seconds: 3600}"
python scripts/check_results.py
```

**Attendu** :

- `PASS=43` ;
- silver 192 008 ;
- rejets 7 992 (`invalid_duration` 7 835, `invalid_amount` 157).

Une ligne ne reçoit qu'un motif, le premier dans l'ordre des règles : certaines lignes à montant absent sont
désormais classées en durée invalide.

Relancer ensuite `dbt build --profiles-dir .` pour revenir aux seuils par défaut.

---

## T9 — Exécution partielle

```powershell
dbt build --profiles-dir . --select gold
```

**Attendu** : `PASS=17`. Seuls les 4 modèles gold et leurs tests sont exécutés ; bronze et silver ne sont pas recalculés.

---

## T10 — Documentation et lignage

```powershell
dbt docs generate --profiles-dir .
dbt docs serve --profiles-dir .
```

**Attendu** : une page s'ouvre sur http://localhost:8080. Le graphe de lignage (bouton en bas à droite) montre
la chaîne `source raw.taxi_trips → brz_taxi_trips → int_taxi_trips_validated → slv_taxi_trips → gld_*`.
Arrêter le serveur avec `Ctrl+C`.

---

## T11 — Export complet du trimestre (optionnel)

```powershell
Remove-Item data\raw\*.csv
Copy-Item "$HOME\Documents\Taxi_Trips_(2013-2023)_20261105.csv" data\raw\
dbt build --profiles-dir .
python scripts/check_results.py
```

**Attendu** :

- `PASS=43` et `RÉSULTAT GLOBAL : OK` ;
- une période couvrant le trimestre ;
- un taux de rejet du même ordre qu'en T2 (environ 2 %).

La durée d'exécution dépend du poste ; compter de quelques dizaines de secondes à quelques minutes.

---

## En cas de problème

| Symptôme | Cause probable | Action |
|---|---|---|
| `Activate.ps1 cannot be loaded` | politique d'exécution PowerShell | `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass` |
| `No files found that match the pattern` | aucun CSV dans `data/raw/` | refaire la préparation de T2 |
| bronze à 400 000 ou plus en T2 | plusieurs CSV dans `data/raw/` | n'y laisser que le fichier de test |
| `Could not set lock on file` | la base est ouverte ailleurs (DBeaver, notebook…) | fermer l'autre connexion puis relancer |
| `FAIL assert_no_parsing_loss` hors T6 | nouveau format de la source | lancer `dbt test --profiles-dir . --select assert_no_parsing_loss --store-failures`, puis consulter la table `dbt_test__audit.assert_no_parsing_loss` |
| taux de rejet inhabituel | changement de format ou de qualité de la source | consulter `silver.slv_taxi_trips_rejected` |
