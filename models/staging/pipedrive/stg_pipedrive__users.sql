with source as (

    select * from {{ source('pipedrive', 'users') }}

)

select
    id                                      as user_id,
    name                                    as user_name,
    email,
    {{ to_reporting_timezone("modified") }} as modified_at
from source
