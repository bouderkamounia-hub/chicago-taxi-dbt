{# Post-hook de la couche gold : matérialise chaque table aussi en Parquet,
   pour qu'elle soit lisible hors DuckDB (BI, notebooks, autre moteur). #}
{% macro export_to_parquet() -%}
    copy {{ this }} to '{{ var("gold_export_dir") }}/{{ this.name }}.parquet' (format parquet)
{%- endmacro %}
