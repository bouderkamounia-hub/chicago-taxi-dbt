{#
  GOLD — KPIs quotidiens (revenus, volume, durée, distance).
  Grain : une ligne par jour.
#}
select
    trip_date,
    count(*)                                          as nb_trips,
    count(distinct taxi_id)                           as nb_active_taxis,
    sum(trip_total)                                   as total_revenue,
    sum(fare)                                         as fare_revenue,
    sum(tips)                                         as tips_revenue,
    round(avg(trip_total), 2)                         as avg_revenue_per_trip,
    round(avg(trip_minutes), 2)                       as avg_trip_minutes,
    round(median(trip_minutes), 2)                    as median_trip_minutes,
    round(avg(trip_miles), 2)                         as avg_trip_miles,
    -- Taux de pourboire calculé sur les seuls paiements carte :
    -- les pourboires en espèces ne sont pas enregistrés par la source.
    round(
        sum(tips) filter (where payment_type = 'Credit Card')
        / nullif(sum(fare) filter (where payment_type = 'Credit Card'), 0)
    , 4)                                              as card_tip_rate
from {{ ref('slv_taxi_trips') }}
group by trip_date
order by trip_date
