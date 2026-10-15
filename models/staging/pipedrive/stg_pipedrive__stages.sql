with source as (

    select * from {{ source('pipedrive', 'stages') }}

)

select
    stage_id,
    stage_name
from source
