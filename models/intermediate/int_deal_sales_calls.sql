-- Grain: one row per deal and sales call type with at least one completed call.
-- Only completed (is_done) calls count; open or cancelled calls are not a funnel step reached.
select
    activity.deal_id,
    activity.activity_type,
    activity_types.activity_type_name,
    min(activity.due_at)                    as first_completed_at,
    count(*)                                as completed_calls
from {{ ref('stg_pipedrive__activities') }} as activity
inner join {{ ref('stg_pipedrive__activity_types') }} as activity_types
    on activity.activity_type = activity_types.activity_type
where activity.is_done
    and activity.activity_type in ('meeting', 'sc_2')
group by
    activity.deal_id,
    activity.activity_type,
    activity_types.activity_type_name
