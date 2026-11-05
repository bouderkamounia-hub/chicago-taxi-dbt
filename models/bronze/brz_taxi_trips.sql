{#
  BRONZE — données brutes, non modifiées.
  On conserve toutes les colonnes du fichier (en texte) et on ajoute seulement
  des métadonnées de traçabilité : fichier d'origine et date de chargement.
#}
select
    *,
    current_timestamp as _loaded_at
from {{ source('raw', 'taxi_trips') }}
