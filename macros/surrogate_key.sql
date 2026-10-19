{#- md5 hash of the given columns, separated by '|'. NULLs become a placeholder first, because
    concat_ws skips them: ('a', null, 'b') and ('a', 'b', null) would otherwise hash the same. -#}
{% macro surrogate_key(columns) -%}
    md5(concat_ws('|'
    {%- for column in columns %},
        coalesce(cast({{ column }} as varchar), '_null_')
    {%- endfor %}
    ))
{%- endmacro %}
