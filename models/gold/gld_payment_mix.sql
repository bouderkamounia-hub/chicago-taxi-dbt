{#
  GOLD — répartition par moyen de paiement.
  Grain : une ligne par moyen de paiement.
#}
select
    payment_type,
    count(*)                                            as nb_trips,
    round(count(*) / sum(count(*)) over (), 4)          as share_of_trips,
    sum(trip_total)                                     as total_revenue,
    round(avg(trip_total), 2)                           as avg_revenue_per_trip,
    round(avg(tips), 2)                                 as avg_tip
from {{ ref('slv_taxi_trips') }}
group by payment_type
order by nb_trips desc
