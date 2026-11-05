{# Test générique : la combinaison de colonnes doit être unique (clé composite). #}
{% test unique_combination(model, columns) %}
select {{ columns | join(', ') }}, count(*) as nb
from {{ model }}
group by {{ columns | join(', ') }}
having count(*) > 1
{% endtest %}
