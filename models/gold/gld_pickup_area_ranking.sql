{#
  GOLD — classement des zones de prise en charge (community areas).
  Grain : une ligne par zone (les courses sans zone sont regroupées en "Hors Chicago / inconnue").
#}
with by_area as (

    select
        t.pickup_community_area                                   as community_area_id,
        coalesce(ca.community_area_name, 'Hors Chicago / inconnue') as community_area_name,
        count(*)                                                  as nb_trips,
        sum(t.trip_total)                                         as total_revenue,
        round(avg(t.trip_total), 2)                               as avg_revenue_per_trip,
        round(avg(t.trip_minutes), 2)                             as avg_trip_minutes,
        round(avg(t.trip_miles), 2)                               as avg_trip_miles
    from {{ ref('slv_taxi_trips') }} as t
    left join {{ ref('community_areas') }} as ca
        on t.pickup_community_area = ca.community_area_id
    group by 1, 2

)

select
    rank() over (order by nb_trips desc)                          as rank_by_trips,
    rank() over (order by total_revenue desc)                     as rank_by_revenue,
    *,
    round(nb_trips / sum(nb_trips) over (), 4)                    as share_of_trips,
    round(total_revenue / sum(total_revenue) over (), 4)          as share_of_revenue
from by_area
order by rank_by_trips
