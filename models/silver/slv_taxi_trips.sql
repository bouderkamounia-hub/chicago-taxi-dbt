{#
  SILVER — courses nettoyées, typées, dédupliquées, enrichies de colonnes dérivées.
  Grain : une ligne par course (trip_id unique).
#}
select
    trip_id,
    taxi_id,
    trip_start_ts,
    trip_end_ts,
    cast(trip_start_ts as date)                           as trip_date,
    extract(hour from trip_start_ts)::integer             as trip_start_hour,
    extract(isodow from trip_start_ts)::integer           as trip_day_of_week,   -- 1 = lundi
    trip_seconds,
    round(trip_seconds / 60.0, 2)                         as trip_minutes,
    trip_miles,
    case
        when trip_miles > 0 then round(trip_miles / (trip_seconds / 3600.0), 2)
    end                                                   as avg_speed_mph,
    pickup_community_area,
    dropoff_community_area,
    pickup_census_tract,
    dropoff_census_tract,
    fare,
    tips,
    tolls,
    extras,
    trip_total,
    payment_type,
    company,
    pickup_latitude,
    pickup_longitude,
    dropoff_latitude,
    dropoff_longitude,
    _source_file,
    _loaded_at
from {{ ref('int_taxi_trips_validated') }}
where rejection_reason is null
