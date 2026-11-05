{# Fonctions de parsing tolérantes : les exports du portail Socrata varient selon
   l'écran utilisé (noms de colonnes, format des dates, "$" et séparateurs de milliers). #}

{% macro clean_text(col) -%}
    nullif(trim({{ col }}), '')
{%- endmacro %}

{% macro parse_amount(col) -%}
    try_cast(replace(replace({{ clean_text(col) }}, '$', ''), ',', '') as decimal(10, 2))
{%- endmacro %}

{% macro parse_double(col) -%}
    try_cast(replace({{ clean_text(col) }}, ',', '') as double)
{%- endmacro %}

{% macro parse_int(col) -%}
    try_cast(try_cast(replace({{ clean_text(col) }}, ',', '') as double) as bigint)
{%- endmacro %}

{# Formats rencontrés : "01/31/2019 11:45:00 PM" (export CSV du site)
   et "2019-01-31T23:45:00.000" (API / export de requête). #}
{% macro parse_ts(col) -%}
    coalesce(
        try_strptime({{ clean_text(col) }}, '%m/%d/%Y %I:%M:%S %p'),
        try_cast({{ clean_text(col) }} as timestamp)
    )
{%- endmacro %}
