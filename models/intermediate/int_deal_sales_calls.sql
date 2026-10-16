-- Grain: one row per deal and sales call type with at least one completed call.
-- Only completed (is_done) calls count; open or cancelled calls are not a funnel step reached.
-- The call types come from the funnel_steps seed (source_type = 'activity').
with activities as (

    select * from {{ ref('stg_pipedrive__activities') }}

),

funnel_steps as (

    select * from {{ ref('funnel_steps') }}

)

select
    activities.deal_id,
    activities.activity_type,
    min(activities.due_at)                  as first_completed_at
from activities
inner join funnel_steps
    on funnel_steps.source_type = 'activity'
    and activities.activity_type = funnel_steps.source_key
where activities.is_done
group by
    activities.deal_id,
    activities.activity_type
