-- Unnests the JSON option list of enum fields (stage_id, lost_reason) into one row per option.
with source as (

    select * from {{ source('pipedrive', 'fields') }}

)

select
    source.field_key,
    source.name                             as field_name,
    option ->> 'id'                         as option_id,
    option ->> 'label'                      as option_label
from source
cross join lateral jsonb_array_elements(source.field_value_options) as option
where source.field_value_options is not null
