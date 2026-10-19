-- Grain: one row per deal_id. Pivots the deal_changes event log into the current deal state
-- with a single scan and one aggregation.
with deal_changes as (

    select * from {{ ref('stg_pipedrive__deal_changes') }}

),

stages as (

    select * from {{ ref('stg_pipedrive__stages') }}

),

field_options as (

    select * from {{ ref('stg_pipedrive__field_options') }}

),

funnel_steps as (

    select * from {{ ref('funnel_steps') }}

),

deals as (

    -- latest value of a field = first element of its values ordered newest first
    select
        deal_id,
        min(changed_at) filter (where field_key = 'add_time')                           as created_at,
        count(*) filter (where field_key = 'add_time')                                  as creation_event_count,
        (array_agg(new_value order by changed_at desc) filter (where field_key = 'stage_id'))[1]::int
                                                                                        as current_stage_id,
        max(new_value::int) filter (where field_key = 'stage_id')                       as furthest_stage_id,
        max(changed_at) filter (where field_key = 'stage_id')                           as last_stage_change_at,
        (array_agg(new_value order by changed_at desc) filter (where field_key = 'user_id'))[1]::int
                                                                                        as current_owner_user_id,
        (array_agg(new_value order by changed_at desc) filter (where field_key = 'lost_reason'))[1]
                                                                                        as lost_reason_id,
        max(changed_at) filter (where field_key = 'lost_reason')                        as lost_at
    from deal_changes
    group by deal_id

)

select
    deals.deal_id,
    deals.created_at,
    deals.current_stage_id,
    current_stage.stage_name                as current_stage_name,
    deals.furthest_stage_id,
    deals.last_stage_change_at,
    deals.current_owner_user_id,
    deals.lost_reason_id::int               as lost_reason_id,
    lost_reason.option_label                as lost_reason,
    deals.lost_at,
    lost_stage.source_key::int              as lost_stage_id,
    -- lost after signature = cancellation (withdrawal, failed site survey or financing check);
    -- lost in post_sale can also be a lost upsell rather than a lost customer
    lost_stage.funnel_phase                 as lost_phase,
    -- 5 deal_ids carry two creation events with interleaved histories: two generated deals sharing
    -- one id (each history has its own time of day, see DQ-1)
    deals.creation_event_count > 1          as has_multiple_creation_events
from deals
left join stages as current_stage
    on deals.current_stage_id = current_stage.stage_id
left join field_options as lost_reason
    on lost_reason.field_key = 'lost_reason'
    and deals.lost_reason_id = lost_reason.option_id
-- stage at the time of loss: the current stage, unless the stage changed after the loss
left join funnel_steps as lost_stage
    on lost_stage.source_type = 'stage'
    and lost_stage.source_key = deals.current_stage_id::varchar
    and deals.last_stage_change_at <= deals.lost_at
