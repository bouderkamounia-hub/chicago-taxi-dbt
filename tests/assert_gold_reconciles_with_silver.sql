{# Réconciliation : le total des KPIs quotidiens doit égaler celui de la couche silver. #}
with gold as (select sum(nb_trips) as n, sum(total_revenue) as rev from {{ ref('gld_daily_kpis') }}),
     silver as (select count(*) as n, sum(trip_total) as rev from {{ ref('slv_taxi_trips') }})
select *
from gold, silver
where gold.n <> silver.n or abs(gold.rev - silver.rev) > 0.01
