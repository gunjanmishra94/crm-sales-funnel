-- Grain: one row per deal and funnel step reached (first time only).
-- Funnel definitions live in the funnel_steps seed: pipeline stages come from deal stage
-- changes, Sales Call 1/2 come from completed activities.
with funnel_steps as (

    select * from {{ ref('funnel_steps') }}

),

stage_events as (

    select
        deal_id,
        stage_id::varchar                   as source_key,
        first_entered_at                    as reached_at
    from {{ ref('int_deal_stage_entries') }}

),

sales_call_events as (

    select
        deal_id,
        activity_type                       as source_key,
        first_completed_at                  as reached_at
    from {{ ref('int_deal_sales_calls') }}

),

events as (

    select 'stage' as source_type, * from stage_events
    union all
    select 'activity' as source_type, * from sales_call_events

)

select
    md5(concat_ws('|', events.deal_id, funnel_steps.funnel_step)) as deal_funnel_event_key,
    events.deal_id,
    funnel_steps.funnel_step,
    funnel_steps.kpi_name,
    funnel_steps.source_type,
    events.reached_at,
    date_trunc('month', events.reached_at)::date as reached_month
from events
inner join funnel_steps
    on events.source_type = funnel_steps.source_type
    and events.source_key = funnel_steps.source_key
