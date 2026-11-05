{#
  Cohérence des montants : le total ne doit pas être inférieur à la somme
  tarif + pourboire + péages + extras (tolérance de 1 $ pour les arrondis).
  Sévérité "warn" : la source contient des écarts connus, on les mesure sans bloquer.
#}
{{ config(severity = 'warn') }}

select trip_id, fare, tips, tolls, extras, trip_total
from {{ ref('slv_taxi_trips') }}
where trip_total + 1 < coalesce(fare, 0) + coalesce(tips, 0) + coalesce(tolls, 0) + coalesce(extras, 0)
