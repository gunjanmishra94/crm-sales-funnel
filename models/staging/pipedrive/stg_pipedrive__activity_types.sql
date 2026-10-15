with source as (

    select * from {{ source('pipedrive', 'activity_types') }}

)

select
    id                                      as activity_type_id,
    type                                    as activity_type,
    name                                    as activity_type_name,
    active = 'Yes'                          as is_active
from source
