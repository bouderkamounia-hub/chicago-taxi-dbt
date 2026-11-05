{#
  SILVER — quarantaine : lignes écartées avec leur motif de rejet.
  Permet d'auditer la qualité de la source sans perdre de données.
#}
select
    rejection_reason,
    * exclude (rejection_reason, _dup_rank)
from {{ ref('int_taxi_trips_validated') }}
where rejection_reason is not null
