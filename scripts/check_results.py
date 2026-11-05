"""
Contrôle des résultats après un `dbt build`.

Affiche, à partir de la base DuckDB locale :
  1. la volumétrie par couche et le bilan bronze = silver + rejets ;
  2. la période couverte ;
  3. le détail des rejets ;
  4. un aperçu de chaque table gold ;
  5. la présence des exports Parquet.

Usage :
    python scripts/check_results.py
    python scripts/check_results.py --db warehouse/chicago_taxi.duckdb
"""
import argparse
import sys
from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
GOLD_TABLES = ["gld_daily_kpis", "gld_pickup_area_ranking", "gld_hourly_demand", "gld_payment_mix"]


def first_row(con, query: str) -> tuple:
    """Première ligne d'une requête (compatible DuckDB 1.x et 2.x)."""
    return con.sql(query).fetchall()[0]


def print_table(con, query: str, max_cols: int = 7) -> None:
    """Affiche un résultat en texte simple (lisible dans PowerShell comme dans un terminal)."""
    rel = con.sql(query)
    cols = rel.columns[:max_cols]
    rows = [[("" if v is None else str(v)) for v in r[:max_cols]] for r in rel.fetchall()]
    widths = [max(len(c), *(len(r[i]) for r in rows)) if rows else len(c) for i, c in enumerate(cols)]
    print("  " + " | ".join(c.ljust(w) for c, w in zip(cols, widths)))
    print("  " + "-+-".join("-" * w for w in widths))
    for r in rows:
        print("  " + " | ".join(v.ljust(w) for v, w in zip(r, widths)))


def title(text: str) -> None:
    print(f"\n=== {text} " + "=" * max(0, 70 - len(text)))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--db", default=str(ROOT / "warehouse" / "chicago_taxi.duckdb"))
    parser.add_argument("--parquet-dir", default=str(ROOT / "output" / "gold"))
    args = parser.parse_args()

    if not Path(args.db).exists():
        print(f"Base introuvable : {args.db}. Lancez d'abord : dbt build --profiles-dir .")
        return 1

    con = duckdb.connect(args.db, read_only=True)
    ok = True

    title("1. Volumétrie par couche")
    bronze, silver, rejected = first_row(con, """
        select (select count(*) from bronze.brz_taxi_trips),
               (select count(*) from silver.slv_taxi_trips),
               (select count(*) from silver.slv_taxi_trips_rejected)
    """)
    print(f"  bronze (lignes brutes)   : {bronze:>12,}")
    print(f"  silver (courses valides) : {silver:>12,}")
    print(f"  silver (rejets)          : {rejected:>12,}")
    rate = rejected / bronze if bronze else 0
    print(f"  taux de rejet            : {rate:>12.2%}")
    balanced = bronze == silver + rejected
    print(f"  bronze = valides + rejets : {'OK' if balanced else 'ÉCART'}")
    ok &= balanced

    title("2. Période couverte (silver)")
    first, last, days = first_row(con, """
        select min(trip_start_ts), max(trip_start_ts), count(distinct trip_date)
        from silver.slv_taxi_trips
    """)
    print(f"  du {first} au {last} ({days} jours)")

    title("3. Rejets par motif")
    print_table(con, """
        select rejection_reason as motif, count(*) as nb_lignes
        from silver.slv_taxi_trips_rejected group by 1 order by 2 desc
    """)

    title("4. Couche gold")
    for table in GOLD_TABLES:
        n = first_row(con, f"select count(*) from gold.{table}")[0]
        print(f"\n  gold.{table} : {n:,} lignes")
        print_table(con, f"select * from gold.{table} limit 5")

    gold_trips = first_row(con, "select sum(nb_trips) from gold.gld_daily_kpis")[0]
    reconciled = gold_trips == silver
    print(f"  Réconciliation gold/silver (nb de courses) : {'OK' if reconciled else 'ÉCART'}")
    ok &= reconciled

    title("5. Exports Parquet")
    for table in GOLD_TABLES:
        path = Path(args.parquet_dir) / f"{table}.parquet"
        present = path.exists()
        print(f"  {path.name:<32} {'présent' if present else 'ABSENT'}")
        ok &= present

    print("\nRÉSULTAT GLOBAL :", "OK" if ok else "ÉCHEC")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
