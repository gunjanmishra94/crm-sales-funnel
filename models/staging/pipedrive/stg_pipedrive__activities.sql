with source as (

    select * from {{ source('pipedrive', 'activity') }}

)

select
    -- activity_id is reused by unrelated activities, so build a surrogate key
    {{ surrogate_key(['activity_id', 'deal_id', 'type', 'due_to']) }} as activity_key,
    activity_id,
    deal_id,
    assigned_to_user                        as user_id,
    type                                    as activity_type,
    done                                    as is_done,
    {{ to_reporting_timezone("due_to") }}  as due_at
from source
