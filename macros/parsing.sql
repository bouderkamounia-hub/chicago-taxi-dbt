{# Fonctions de parsing tolérantes : les exports du portail Socrata varient selon
   l'écran utilisé et la langue du navigateur.

   Formats rencontrés :
     - export du site, navigateur anglais : "$1,234.50", "1,140", "41.879"
     - export du site, navigateur français : "$1 234,50", "1 140", "41,879"
       (séparateur de milliers = espace insécable fine U+202F)
     - API / export de requête             : "1234.5", "1140", "41.879"
   Le fichier peut aussi avoir été ré-encodé (ex. par PowerShell), ce qui transforme
   l'espace fine en caractères parasites ("1â€¯140"). #}

{% macro clean_text(col) -%}
    nullif(trim({{ col }}), '')
{%- endmacro %}

{# Normalise un nombre en texte au format "1234.5" :
   1. on ne garde que chiffres, signe, virgule et point (supprime "$", espaces, U+202F...) ;
   2. s'il y a un point, c'est le séparateur décimal -> les virgules sont des milliers ;
      sinon, une virgule éventuelle est le séparateur décimal (format français). #}
{% macro normalize_number(col) -%}
    case
        when regexp_replace({{ col }}, '[^0-9.,-]', '', 'g') like '%.%'
            then replace(regexp_replace({{ col }}, '[^0-9.,-]', '', 'g'), ',', '')
        else replace(regexp_replace({{ col }}, '[^0-9.,-]', '', 'g'), ',', '.')
    end
{%- endmacro %}

{% macro parse_amount(col) -%}
    try_cast(nullif({{ normalize_number(col) }}, '') as decimal(10, 2))
{%- endmacro %}

{% macro parse_double(col) -%}
    try_cast(nullif({{ normalize_number(col) }}, '') as double)
{%- endmacro %}

{# Entiers : tout séparateur (milliers) est retiré. #}
{% macro parse_int(col) -%}
    try_cast(nullif(regexp_replace({{ col }}, '[^0-9-]', '', 'g'), '') as bigint)
{%- endmacro %}

{# Dates : "03/31/2023 10:30:00 AM" (export du site) ou ISO "2023-03-31T10:30:00.000" (API). #}
{% macro parse_ts(col) -%}
    coalesce(
        try_strptime({{ clean_text(col) }}, '%m/%d/%Y %I:%M:%S %p'),
        try_cast({{ clean_text(col) }} as timestamp)
    )
{%- endmacro %}
