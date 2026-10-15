with source as (

    select * from {{ source('pipedrive', 'deal_changes') }}

)

select
    deal_id,
    change_time                             as changed_at,
    changed_field_key                       as field_key,
    new_value
from source
