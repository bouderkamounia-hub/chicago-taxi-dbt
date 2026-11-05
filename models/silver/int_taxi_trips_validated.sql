{#
  SILVER (étape intermédiaire) — typage, normalisation et contrôle qualité.
  Chaque ligne reçoit un motif de rejet (ou null si elle est valide). Les deux modèles
  suivants répartissent ensuite les lignes : slv_taxi_trips (valides) et
  slv_taxi_trips_rejected (quarantaine), pour qu'aucune ligne ne disparaisse sans trace.
#}
with typed as (

    select
        {{ clean_text('trip_id') }}                          as trip_id,
        {{ clean_text('taxi_id') }}                          as taxi_id,
        {{ parse_ts('trip_start_timestamp') }}               as trip_start_ts,
        {{ parse_ts('trip_end_timestamp') }}                 as trip_end_ts,
        {{ parse_int('trip_seconds') }}                      as trip_seconds,
        {{ parse_double('trip_miles') }}                     as trip_miles,
        {{ clean_text('pickup_census_tract') }}              as pickup_census_tract,
        {{ clean_text('dropoff_census_tract') }}             as dropoff_census_tract,
        {{ parse_int('pickup_community_area') }}::integer    as pickup_community_area,
        {{ parse_int('dropoff_community_area') }}::integer   as dropoff_community_area,
        {{ parse_amount('fare') }}                           as fare,
        {{ parse_amount('tips') }}                           as tips,
        {{ parse_amount('tolls') }}                          as tolls,
        {{ parse_amount('extras') }}                         as extras,
        {{ parse_amount('trip_total') }}                     as trip_total,
        coalesce({{ clean_text('payment_type') }}, 'Unknown') as payment_type,
        coalesce({{ clean_text('company') }}, 'Unknown')      as company,
        {{ parse_double('pickup_centroid_latitude') }}       as pickup_latitude,
        {{ parse_double('pickup_centroid_longitude') }}      as pickup_longitude,
        {{ parse_double('dropoff_centroid_latitude') }}      as dropoff_latitude,
        {{ parse_double('dropoff_centroid_longitude') }}     as dropoff_longitude,
        filename                                             as _source_file,
        _loaded_at
    from {{ ref('brz_taxi_trips') }}

),

ranked as (

    select
        *,
        -- Déduplication : une course peut apparaître dans plusieurs exports qui se chevauchent
        row_number() over (
            partition by trip_id
            order by _source_file desc, trip_end_ts desc nulls last
        ) as _dup_rank
    from typed

)

select
    *,
    case
        when trip_id is null                                   then 'missing_trip_id'
        when _dup_rank > 1                                     then 'duplicate_trip_id'
        when trip_start_ts is null                             then 'invalid_start_timestamp'
        when trip_end_ts < trip_start_ts                       then 'end_before_start'
        when trip_seconds is null
          or trip_seconds <= 0
          or trip_seconds > {{ var('max_trip_seconds') }}      then 'invalid_duration'
        when trip_miles < 0
          or trip_miles > {{ var('max_trip_miles') }}          then 'invalid_distance'
        when trip_total is null
          or trip_total < 0
          or trip_total > {{ var('max_trip_total') }}
          or fare < 0 or tips < 0 or tolls < 0 or extras < 0   then 'invalid_amount'
    end as rejection_reason
from ranked
