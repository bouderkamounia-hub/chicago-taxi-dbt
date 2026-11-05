{# Utilise directement le nom de schéma configuré (bronze, silver, gold, ref)
   au lieu du préfixe par défaut "<target_schema>_<custom_schema>". #}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}{{ target.schema }}{%- else -%}{{ custom_schema_name | trim }}{%- endif -%}
{%- endmacro %}
