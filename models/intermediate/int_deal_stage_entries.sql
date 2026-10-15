-- Grain: one row per deal and stage the deal has entered.
-- A deal can re-enter a stage (backward moves, or the 5 deal_ids that hold two deal histories);
-- only the first entry counts toward the funnel.
with stage_changes as (

    select
        deal_id,
        new_value::int                      as stage_id,
        changed_at
    from {{ ref('stg_pipedrive__deal_changes') }}
    where field_key = 'stage_id'

)

select
    deal_id,
    stage_id,
    min(changed_at)                         as first_entered_at,
    count(*)                                as times_entered
from stage_changes
group by deal_id, stage_id
