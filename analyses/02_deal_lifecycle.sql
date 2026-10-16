/*
    02 Deal lifecycle: how deals move through the pipeline in deal_changes.

    Findings
    - Every deal starts with add_time, then user_id, then stage_id = 1 (1,995 deals start at stage 1).
      The stage 1 event comes a median 35 days after creation (min 2, max 83) (DQ-14).
    - Stage moves: 4,399 to the next stage, 2,502 skip one or more stages (36% of moves after the first),
      8 go backwards, 2 repeat a stage. 1,684 deals (84%) skip at least once (DQ-4).
    - Recorded vs reached: 1,479 deals are recorded in Qualified Lead, but 1,990 reached it or a later stage.
    - 5 deal_ids have two add_time events. Every other deal has all events at one time of day; these five
      have exactly two, one per deal, and hold all 8 backward moves and both repeats (DQ-1).
    - Every deal's last event is a lost_reason, including the 324 that reached Renewal/Expansion. The five
      reasons are spread evenly at every final stage (DQ-5).
    - Owners: 1,494 deals have one owner event, 497 two, 4 three. All owner ids exist in users.

    Decisions
    - A stage counts as reached when the deal was recorded in it or any later stage (int_deal_stage_entries).
    - Each deal_id counts once per step; the 5 shared ids are flagged in dim_deals.
    - Step 1 counts entry into stage 1, not creation; creation month is used only for cohorts.
    - lost_reason is not a funnel filter; dim_deals exposes the stage and phase at loss.
*/

{% set deal_changes = source('pipedrive', 'deal_changes') %}

-- DQ-14: order of each deal's first three events
select first_events, count(*) as deals
from (
    select deal_id, string_agg(changed_field_key, ' > ' order by change_time) as first_events
    from (
        select *, row_number() over (partition by deal_id order by change_time) as event_number
        from {{ deal_changes }}
    ) as numbered
    where event_number <= 3
    group by deal_id
) as sequences
group by 1
order by 2 desc;

-- DQ-14: days from deal creation to the first stage event
select
    percentile_cont(0.5) within group (order by days) as median_days,
    min(days)                                         as min_days,
    max(days)                                         as max_days
from (
    select
        deal_id,
        extract(epoch from (
            min(change_time) filter (where changed_field_key = 'stage_id')
          - min(change_time) filter (where changed_field_key = 'add_time')
        )) / 86400 as days
    from {{ deal_changes }}
    group by deal_id
) as gaps;

-- DQ-4: stage transitions compared with the deal's previous stage event
with stage_events as (
    select
        deal_id,
        new_value::int as stage_id,
        lag(new_value::int) over (partition by deal_id order by change_time) as previous_stage_id
    from {{ deal_changes }}
    where changed_field_key = 'stage_id'
)
select
    case
        when previous_stage_id is null then 'first'
        when stage_id = previous_stage_id + 1 then 'next'
        when stage_id > previous_stage_id + 1 then 'skip'
        when stage_id < previous_stage_id then 'backward'
        else 'same'
    end                     as transition,
    count(*)                as moves,
    count(distinct deal_id) as deals
from stage_events
group by 1
order by 1;

-- DQ-4: deals recorded in each stage vs deals that reached it (recorded in it or a later stage)
with recorded as (
    select distinct deal_id, new_value::int as stage_id
    from {{ deal_changes }}
    where changed_field_key = 'stage_id'
),
furthest as (
    select deal_id, max(stage_id) as furthest_stage_id
    from recorded
    group by deal_id
)
select
    stages.stage_id,
    stages.stage_name,
    (select count(*) from recorded where recorded.stage_id = stages.stage_id)          as recorded_deals,
    (select count(*) from furthest where furthest.furthest_stage_id >= stages.stage_id) as reached_deals
from {{ source('pipedrive', 'stages') }} as stages
order by stages.stage_id;

-- DQ-1: deal_ids with two creation events, and distinct times of day per deal
select deal_id, count(*) as creation_events
from {{ deal_changes }}
where changed_field_key = 'add_time'
group by 1
having count(*) > 1;

select times_of_day, count(*) as deals
from (
    select deal_id, count(distinct change_time::time) as times_of_day
    from {{ deal_changes }}
    group by deal_id
) as per_deal
group by 1
order by 1;

-- DQ-1: backward and repeated stage moves (all belong to the five shared deal_ids)
select deal_id, change_time, stage_id, previous_stage_id
from (
    select
        deal_id,
        change_time,
        new_value::int as stage_id,
        lag(new_value::int) over (partition by deal_id order by change_time) as previous_stage_id
    from {{ deal_changes }}
    where changed_field_key = 'stage_id'
) as stage_events
where stage_id <= previous_stage_id;

-- DQ-5: last event of every deal
select changed_field_key as last_event, count(*) as deals
from (
    select distinct on (deal_id) deal_id, changed_field_key
    from {{ deal_changes }}
    order by deal_id, change_time desc
) as last_events
group by 1;

-- DQ-5: final stage before the loss, by lost reason
with final_stage as (
    select distinct on (deal_id) deal_id, new_value::int as stage_id
    from {{ deal_changes }}
    where changed_field_key = 'stage_id'
    order by deal_id, change_time desc
),
final_lost_reason as (
    select distinct on (deal_id) deal_id, new_value as lost_reason_id
    from {{ deal_changes }}
    where changed_field_key = 'lost_reason'
    order by deal_id, change_time desc
)
select final_stage.stage_id, final_lost_reason.lost_reason_id, count(*) as deals
from final_stage
inner join final_lost_reason using (deal_id)
group by 1, 2
order by 1, 2;

-- owner events per deal, and owner ids missing from users
select owner_events, count(*) as deals
from (
    select deal_id, count(*) as owner_events
    from {{ deal_changes }}
    where changed_field_key = 'user_id'
    group by 1
) as per_deal
group by 1
order by 1;

select count(*) as unknown_owner_events
from {{ deal_changes }}
where changed_field_key = 'user_id'
    and new_value::int not in (select id from {{ source('pipedrive', 'users') }});
