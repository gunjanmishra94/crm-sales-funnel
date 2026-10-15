-- Grain: one row per deal_id. Pivots the deal_changes event log into the current deal state
-- with a single scan and one window function.
with changes as (

    select
        deal_id,
        field_key,
        new_value,
        changed_at,
        row_number() over (
            partition by deal_id, field_key
            order by changed_at desc
        )                                   as recency_rank
    from {{ ref('stg_pipedrive__deal_changes') }}

),

deals as (

    select
        deal_id,
        min(changed_at) filter (where field_key = 'add_time')                           as created_at,
        count(*) filter (where field_key = 'add_time')                                  as creation_event_count,
        max(case when field_key = 'stage_id' and recency_rank = 1 then new_value::int end) as current_stage_id,
        max(case when field_key = 'stage_id' then new_value::int end)                   as furthest_stage_id,
        max(case when field_key = 'stage_id' then changed_at end)                       as last_stage_change_at,
        max(case when field_key = 'user_id' and recency_rank = 1 then new_value::int end) as current_owner_user_id,
        max(case when field_key = 'lost_reason' and recency_rank = 1 then new_value end) as lost_reason_id,
        max(case when field_key = 'lost_reason' then changed_at end)                    as lost_at
    from changes
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
    -- 5 deal_ids carry two creation events with interleaved histories (likely an id collision)
    deals.creation_event_count > 1          as has_multiple_creation_events
from deals
left join {{ ref('stg_pipedrive__stages') }} as current_stage
    on deals.current_stage_id = current_stage.stage_id
left join {{ ref('stg_pipedrive__field_options') }} as lost_reason
    on lost_reason.field_key = 'lost_reason'
    and deals.lost_reason_id = lost_reason.option_id
