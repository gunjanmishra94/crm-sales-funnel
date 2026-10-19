{% macro to_reporting_timezone(column) -%}
    ({{ column }} at time zone '{{ var("source_timezone") }}' at time zone '{{ var("reporting_timezone") }}')
{%- endmacro %}
