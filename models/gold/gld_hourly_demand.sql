{#
  GOLD — profil de la demande par jour de semaine et heure de départ
  (base d'une heatmap, utile pour dimensionner l'offre).
  Grain : une ligne par (jour de semaine, heure).
#}
with per_day_hour as (

    select
        trip_date,
        trip_day_of_week,
        trip_start_hour,
        count(*)            as nb_trips,
        sum(trip_total)     as total_revenue,
        avg(trip_minutes)   as avg_trip_minutes
    from {{ ref('slv_taxi_trips') }}
    group by 1, 2, 3

)

select
    trip_day_of_week,                                  -- 1 = lundi … 7 = dimanche
    trip_start_hour,
    count(distinct trip_date)                          as nb_days_observed,
    sum(nb_trips)                                      as nb_trips,
    round(avg(nb_trips), 1)                            as avg_trips_per_day,
    round(avg(total_revenue), 2)                       as avg_revenue_per_day,
    round(sum(avg_trip_minutes * nb_trips) / sum(nb_trips), 2) as avg_trip_minutes
from per_day_hour
group by 1, 2
order by 1, 2
