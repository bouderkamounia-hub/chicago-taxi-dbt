# Chicago Taxi Trips — pipeline dbt (bronze → silver → gold)

Pipeline de transformation **dbt + DuckDB**, exécutable en local sans serveur.
Il prend les courses de taxi brutes du dataset public
[Chicago Taxi Trips (2013-2023)](https://data.cityofchicago.org/Transportation/Taxi-Trips-2013-2023-/wrvz-psew),
les nettoie, puis expose des tables d'indicateurs prêtes pour la BI : revenus par jour,
durée moyenne des courses, classement des zones de prise en charge, etc.

---

## 1. Prérequis

| Outil | Version | Rôle |
|---|---|---|
| Python | 3.11 à 3.13 | exécute dbt |
| pip | récent | installe les dépendances |
| Git | — | récupérer le repo |

Les dépendances Python (`requirements.txt`) sont **dbt-core**, **dbt-duckdb** et **duckdb**.
DuckDB est une base embarquée : un simple fichier sur le disque, sans service ni Docker à installer.

---

## 2. Lancement pas à pas

### Étape 1 — Récupérer le projet et installer les dépendances

**Windows (PowerShell)**
```powershell
git clone <url-du-repo> chicago-taxi-dbt
cd chicago-taxi-dbt
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

**macOS / Linux**
```bash
git clone <url-du-repo> chicago-taxi-dbt
cd chicago-taxi-dbt
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

### Étape 2 — Récupérer une tranche des données depuis le portail

Le fichier complet pèse plusieurs dizaines de Go. On n'en extrait qu'une tranche :
**période retenue : 1er trimestre 2019 (du 01/01/2019 au 31/03/2019 inclus)**, soit quelques millions de courses.

1. Ouvrir l'éditeur de requêtes du dataset :
   <https://data.cityofchicago.org/Transportation/Taxi-Trips-2013-2023-/wrvz-psew/explore/query>.
2. Passer en mode SQL (SoQL) et coller la requête ci-dessous :

   ```sql
   SELECT
     `trip_id`, `taxi_id`, `trip_start_timestamp`, `trip_end_timestamp`,
     `trip_seconds`, `trip_miles`,
     `pickup_census_tract`, `dropoff_census_tract`,
     `pickup_community_area`, `dropoff_community_area`,
     `fare`, `tips`, `tolls`, `extras`, `trip_total`,
     `payment_type`, `company`,
     `pickup_centroid_latitude`, `pickup_centroid_longitude`,
     `dropoff_centroid_latitude`, `dropoff_centroid_longitude`
   WHERE
     `trip_start_timestamp` >= "2019-01-01T00:00:00" :: floating_timestamp
     AND `trip_start_timestamp` < "2019-04-01T00:00:00" :: floating_timestamp
   ```

3. **Export → CSV**, en choisissant l'export **des données de la requête** et non l'ensemble du dataset.
4. Déposer le fichier dans `data/raw/`, par exemple `data/raw/taxi_trips_2019Q1.csv`.

Pour vérifier le volume avant l'export, remplacer `SELECT …` par `SELECT count(*)` en gardant le même `WHERE`.
Si l'export d'un trimestre est trop lourd pour le navigateur, exporter un fichier par mois :
le pipeline lit **tous** les CSV de `data/raw/`.

### Étape 3 — Lancer le pipeline

```bash
dbt build --profiles-dir .
```

Cette seule commande fait tout, dans l'ordre des dépendances :

1. charge le référentiel des zones (seed) ;
2. construit bronze, puis silver, puis gold ;
3. exécute les tests unitaires et les tests de qualité de données.

Un test en échec bloque les modèles qui en dépendent.

### Étape 4 — Consulter les résultats

- **Base DuckDB** : `warehouse/chicago_taxi.duckdb`, avec les schémas `bronze`, `silver`, `gold` et `ref`.
- **Fichiers Parquet de la couche gold** : `output/gold/*.parquet`, lisibles par n'importe quel outil (Power BI, Python, Spark…).

Exemple d'interrogation avec Python :
```python
import duckdb
con = duckdb.connect("warehouse/chicago_taxi.duckdb", read_only=True)
con.sql("select * from gold.gld_daily_kpis order by trip_date").show()
con.sql("select * from gold.gld_pickup_area_ranking limit 10").show()
con.sql("select rejection_reason, count(*) from silver.slv_taxi_trips_rejected group by 1").show()
```

Documentation et lignage des modèles :
```bash
dbt docs generate --profiles-dir .
dbt docs serve --profiles-dir .      # ouvre http://localhost:8080
```

### Commandes utiles

| Commande | Effet |
|---|---|
| `dbt build --profiles-dir .` | pipeline complet (modèles + tests) |
| `dbt build --profiles-dir . --select gold` | reconstruit uniquement la couche gold (et ses tests) |
| `dbt test --profiles-dir . --select test_type:unit` | tests unitaires seuls |
| `dbt build --profiles-dir . --vars "{raw_csv_glob: 'D:/exports/*.csv'}"` | lit les CSV depuis un autre dossier |

---

## 3. Architecture

```
  Portail Chicago Data Portal
  (export CSV filtré : T1 2019)
               │
               ▼
     data/raw/*.csv                     fichiers déposés tels quels
               │
               │  dbt source (lecture directe des CSV par DuckDB)
               ▼
  ┌──────────────────────────┐
  │ BRONZE  brz_taxi_trips   │  données brutes : toutes colonnes en texte,
  │                          │  + fichier d'origine et date de chargement
  └────────────┬─────────────┘
               │  typage, normalisation, déduplication, règles qualité
               ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ SILVER  int_taxi_trips_validated  (motif de rejet par ligne)  │
  │            ├──► slv_taxi_trips            lignes valides      │
  │            └──► slv_taxi_trips_rejected   quarantaine          │
  └────────────┬─────────────────────────────────────────────────┘
               │  agrégations métier + jointure référentiel
               │  (seed community_areas)
               ▼
  ┌──────────────────────────────────────────────────────────────┐
  │ GOLD   gld_daily_kpis           KPIs par jour                │
  │        gld_pickup_area_ranking  top zones de prise en charge │
  │        gld_hourly_demand        demande jour × heure         │
  │        gld_payment_mix          répartition des paiements    │
  └────────────┬─────────────────────────────────────────────────┘
               ▼
   Exposition : tables DuckDB (SQL)  +  output/gold/*.parquet (BI)
```

### Contenu des couches

| Couche | Modèle | Grain | Rôle |
|---|---|---|---|
| bronze | `brz_taxi_trips` | 1 ligne par ligne du fichier source | copie fidèle et traçable de la source |
| silver | `int_taxi_trips_validated` | 1 ligne par ligne source | typage et attribution d'un motif de rejet |
| silver | `slv_taxi_trips` | 1 ligne par course (`trip_id` unique) | données propres et enrichies (date, heure, jour de semaine, minutes, vitesse) |
| silver | `slv_taxi_trips_rejected` | 1 ligne rejetée | quarantaine auditable |
| ref | `community_areas` (seed) | 1 ligne par zone | libellés des 77 zones de Chicago |
| gold | `gld_daily_kpis` | 1 ligne par jour | courses, taxis actifs, revenus, durée moyenne et médiane, distance, taux de pourboire carte |
| gold | `gld_pickup_area_ranking` | 1 ligne par zone | rang par volume et par revenu, parts de marché |
| gold | `gld_hourly_demand` | jour de semaine × heure | profil de la demande (heatmap) |
| gold | `gld_payment_mix` | 1 ligne par moyen de paiement | volumes, revenus, pourboire moyen |

### Règles qualité (silver)

Chaque ligne reçoit au plus **un** motif de rejet. Le premier qui s'applique, dans cet ordre :

| Motif | Règle |
|---|---|
| `missing_trip_id` | identifiant absent |
| `duplicate_trip_id` | `trip_id` déjà vu ; on garde l'occurrence du fichier dont le nom est le plus grand (cf. convention de nommage ci-dessous) |
| `invalid_start_timestamp` | date de début illisible |
| `end_before_start` | fin antérieure au début |
| `invalid_duration` | durée ≤ 0 s ou > 24 h |
| `invalid_distance` | distance < 0 ou > 500 miles |
| `invalid_amount` | total absent, négatif ou > 2 000 $, ou composante de prix négative |

Les seuils sont des variables dbt modifiables dans `dbt_project.yml`.

### Tests

- **Tests unitaires dbt** (sur des données en ligne, sans dépendre du fichier source) :
  - les deux formats d'export (site et API) sont typés de façon identique ;
  - chaque cas invalide reçoit le bon motif de rejet.
- **Tests de données** : unicité et non-nullité des clés, bornes de valeurs, intégrité référentielle vers les zones,
  unicité de la clé composite de `gld_hourly_demand`.
- **Garde-fous** :
  - **réconciliation** gold ↔ silver (même nombre de courses, même revenu) ;
  - **alerte** si le taux de rejet dépasse 10 % ;
  - **alerte** si le total d'une course est inférieur à la somme de ses composantes.

---

## 4. Choix techniques et arbitrages

**dbt + DuckDB plutôt qu'un entrepôt ou un cluster.**
Le besoin est un pipeline reproductible en local sur quelques millions de lignes. DuckDB traite ce volume en
quelques secondes sur un portable, sans serveur à installer ni à maintenir. dbt apporte :

- la structure en couches et le lignage ;
- les tests et la documentation générée.

Le même projet pourrait passer sur Snowflake, BigQuery ou Databricks en changeant d'adaptateur dbt. Seules quelques
fonctions spécifiques à DuckDB seraient à adapter (`try_strptime`, `read_csv`, `copy … to parquet`).

**Bronze en texte brut.**
Tout est lu en `varchar` (`all_varchar`), sans aucune transformation. Une valeur mal formée ne peut donc pas faire
échouer le chargement ni être perdue silencieusement : le typage, et ses éventuels échecs, se font en silver, où ils
sont visibles et testés.

**Parsing tolérant aux deux formats d'export.**
Selon l'écran utilisé, le portail produit :

- des en-têtes « Trip ID » ou « trip_id » ;
- des dates « 01/31/2019 11:45:00 PM » ou ISO ;
- des montants « $1,234.50 » ou « 1234.5 ».

Les noms de colonnes sont normalisés à la lecture et des macros (`macros/parsing.sql`) gèrent les deux formats.
Un test unitaire le garantit.

**Quarantaine plutôt que suppression.**
Les lignes invalides ne sont pas filtrées silencieusement : elles sont conservées dans `slv_taxi_trips_rejected`
avec leur motif. Cela permet de :

- mesurer la qualité de la source ;
- détecter un changement de format (alerte au-delà de 10 % de rejet) ;
- ajuster les règles sans recharger les données.

**Déduplication déterministe.**
Plusieurs exports peuvent se chevaucher. On garde une seule occurrence par `trip_id`, choisie selon le nom du fichier.
Convention : nommer les fichiers de façon à ce que l'ordre alphabétique suive l'ordre des exports
(`taxi_trips_2019Q1_20261105.csv`).

**Durées calculées depuis `trip_seconds`.**
Pour l'anonymisation, la source arrondit les horodatages au quart d'heure. La différence fin − début est donc
imprécise ; `trip_seconds` est la mesure fiable.

**Taux de pourboire calculé sur la carte uniquement.**
Les pourboires en espèces ne sont pas enregistrés dans la source. Les inclure ferait baisser artificiellement le taux.

**Gold exposée deux fois.**
Les tables gold existent dans DuckDB (interrogeables en SQL) et sont aussi exportées en Parquet par un post-hook.
Le Parquet est un format ouvert, lisible par n'importe quel outil BI ou moteur, sans dépendre de DuckDB.

**Tables plutôt qu'incrémental.**
À ce volume, une reconstruction complète prend quelques secondes et reste plus simple à raisonner (idempotente).
Le passage en incrémental est listé ci-dessous.

**Pas de package externe (dbt_utils…).**
Les deux tests génériques nécessaires (`accepted_range`, `unique_combination`) sont écrits dans `tests/generic/`.
Le projet s'installe donc avec un simple `pip install`, sans `dbt deps` ni accès au hub dbt.

---

## 5. Ce que j'aurais fait avec plus de temps

- **Ingestion automatisée** : un script d'extraction via l'API SODA (filtre sur `trip_start_timestamp`,
  pagination), pour ne plus dépendre d'un export manuel.
- **Orchestration** : planifier `dbt build` (Airflow, Dagster ou dbt Cloud), avec alerting sur les tests en échec.
- **Modèles incrémentaux** en silver et gold (`unique_key = trip_id`, partition par date) pour absorber plusieurs
  années de données sans tout recalculer.
- **Stockage objet** : écrire bronze, silver et gold en Parquet partitionné (par date) sur S3 ou MinIO,
  avec un format de table ouvert (Iceberg / Delta) pour le versionnement et le time travel.
- **Modélisation dimensionnelle complète** : table de faits des courses et dimensions date, zone, compagnie, taxi.
  Ajouter des flux origine → destination et un indicateur sur les aéroports (O'Hare, Midway).
- **Qualité plus poussée** :
  - contrats de modèle dbt (types imposés) ;
  - tests de fraîcheur des sources ;
  - détection d'anomalies sur les KPIs quotidiens (variation anormale du volume) ;
  - tests de distribution.
- **CI** : `dbt build` sur un échantillon à chaque pull request (GitHub Actions), plus du linting SQL (sqlfluff).
- **Couche d'exposition** : un petit tableau de bord (Evidence, Streamlit ou Metabase) branché sur les tables gold.

---

## Arborescence

```
chicago-taxi-dbt/
├── dbt_project.yml          configuration du projet, variables (chemins, seuils qualité)
├── profiles.yml             connexion DuckDB locale (warehouse/chicago_taxi.duckdb)
├── requirements.txt         dépendances Python figées
├── data/raw/                CSV exportés du portail (non versionnés)
├── seeds/                   référentiel des 77 community areas
├── macros/                  parsing tolérant, nommage des schémas, export Parquet
├── models/
│   ├── bronze/              source + copie brute
│   ├── silver/              typage, qualité, quarantaine (+ tests unitaires)
│   └── gold/                agrégats métier pour la BI
├── tests/                   tests génériques et tests de réconciliation / qualité
├── warehouse/               base DuckDB générée (non versionnée)
└── output/gold/             exports Parquet de la couche gold (non versionnés)
```
