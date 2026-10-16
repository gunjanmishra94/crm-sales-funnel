-- Grain: one row per deal and pipeline stage the deal reached.
-- A deal reached a stage when it was recorded in that stage or any later one. In Enpal's sales
-- process a signed contract implies a quote and a site or building assessment, and an installation
-- implies a signed contract, so skipped stages are CRM logging gaps, not steps that never happened.
-- Skipped stages take the time the deal first got past them.
-- Assumes stage_id follows the pipeline order (1 = Lead Generation ... 9 = Renewal/Expansion).
with deal_changes as (

    select * from {{ ref('stg_pipedrive__deal_changes') }}

),

stages as (

    select * from {{ ref('stg_pipedrive__stages') }}

),

stage_changes as (

    select
        deal_id,
        new_value::int                      as stage_id,
        changed_at
    from deal_changes
    where field_key = 'stage_id'

),

recorded_stages as (

    select
        deal_id,
        stage_id,
        min(changed_at)                     as first_recorded_at
    from stage_changes
    group by deal_id, stage_id

)

-- fan out each recorded stage to itself and every earlier stage: the first time the deal was at a
-- stage or beyond is the earliest of those recordings
select
    recorded_stages.deal_id,
    stages.stage_id,
    min(recorded_stages.first_recorded_at)  as first_reached_at,
    bool_or(recorded_stages.stage_id = stages.stage_id) as is_recorded
from recorded_stages
inner join stages
    on stages.stage_id <= recorded_stages.stage_id
group by recorded_stages.deal_id, stages.stage_id
