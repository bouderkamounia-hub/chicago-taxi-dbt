{#
  Aucune perte au typage : une valeur non vide en bronze doit rester non nulle
  une fois convertie en silver. Un échec ici signale un format de source non prévu
  (nouvelle langue d'export, nouveau format de date...) : le pipeline doit s'arrêter.
#}
select
    v.trip_id,
    v._source_file
from {{ ref('brz_taxi_trips') }} as b
join {{ ref('int_taxi_trips_validated') }} as v
    on b.trip_id = v.trip_id
   and b.filename = v._source_file
where (nullif(trim(b.trip_start_timestamp), '') is not null and v.trip_start_ts is null)
   or (nullif(trim(b.trip_seconds), '')         is not null and v.trip_seconds  is null)
   or (nullif(trim(b.trip_miles), '')           is not null and v.trip_miles    is null)
   or (nullif(trim(b.fare), '')                 is not null and v.fare          is null)
   or (nullif(trim(b.tips), '')                 is not null and v.tips          is null)
   or (nullif(trim(b.trip_total), '')           is not null and v.trip_total    is null)
   or (nullif(trim(b.pickup_centroid_latitude), '') is not null and v.pickup_latitude is null)
