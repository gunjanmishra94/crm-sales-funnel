-- Grain: one row per deal and funnel step reached (first time only). A pipeline stage counts as
-- reached when the deal was recorded in it or any later stage (see int_deal_stage_entries).
-- Funnel definitions live in the funnel_steps seed: pipeline stages come from deal stage
-- changes, Sales Call 1/2 come from completed activities.
with funnel_steps as (

    select * from {{ ref('funnel_steps') }}

),

stage_entries as (

    select * from {{ ref('int_deal_stage_entries') }}

),

sales_calls as (

    select * from {{ ref('int_deal_sales_calls') }}

),

events as (

    select
        'stage'                             as source_type,
        deal_id,
        stage_id::varchar                   as source_key,
        first_reached_at                    as reached_at,
        is_recorded
    from stage_entries

    union all

    select
        'activity'                          as source_type,
        deal_id,
        activity_type                       as source_key,
        first_completed_at                  as reached_at,
        true                                as is_recorded
    from sales_calls

)

select
    {{ surrogate_key(['events.deal_id', 'funnel_steps.funnel_step']) }} as deal_funnel_event_key,
    events.deal_id,
    funnel_steps.funnel_step,
    funnel_steps.step_order,
    funnel_steps.kpi_name,
    funnel_steps.source_type,
    funnel_steps.funnel_phase,
    events.reached_at,
    events.is_recorded,
    date_trunc('month', events.reached_at)::date as reached_month
from events
inner join funnel_steps
    on events.source_type = funnel_steps.source_type
    and events.source_key = funnel_steps.source_key
