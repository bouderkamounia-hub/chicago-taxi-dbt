{#
  Garde-fou qualité : alerte si la part de lignes rejetées dépasse le seuil
  (var max_rejection_rate). Un taux anormal signale en général un changement
  de format de la source (colonnes renommées, nouveau format de date...).
#}
{{ config(severity = 'warn') }}

with counts as (
    select
        count(*)                                          as total_rows,
        count(*) filter (where rejection_reason is not null) as rejected_rows
    from {{ ref('int_taxi_trips_validated') }}
)
select *, rejected_rows / nullif(total_rows, 0) as rejection_rate
from counts
where rejected_rows / nullif(total_rows, 0) > {{ var('max_rejection_rate') }}
