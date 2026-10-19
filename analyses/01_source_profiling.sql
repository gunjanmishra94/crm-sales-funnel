/*
    01 Source profiling: volumes, coverage, keys, nulls and duplicates of the six raw tables.

    Run: `dbt compile -s 01_source_profiling`, then execute
    target/compiled/enpal_assessment_project/analyses/01_source_profiling.sql. Dates are raw UTC.

    Findings
    - deal_changes: 15,406 rows, 1,995 deals, 2024-01-01 to 2025-03-11. activity: 4,579 rows,
      2024-01-01 to 2024-09-13. users: 1,787. Lookups: 9 stages, 4 fields, 4 activity types.
    - No nulls in any key, timestamp or value column. No fully duplicated rows.
    - Only the lookup tables have a declared primary key; deal_changes and activity have none (DQ-11).
    - There is no deals table: a deal exists only as events in deal_changes.
    - New deals: 205-262 per full month from January to August 2024, 92 in September, then none.
      Stage changes go on until February 2025, lost reasons until March 2025 (DQ-6).

    Decisions
    - Source tests: unique + not_null on lookup ids. Derived keys are tested in the models.
    - The deal entity is rebuilt from the event log (dim_deals).
*/

{% set deal_changes = source('pipedrive', 'deal_changes') %}
{% set activity = source('pipedrive', 'activity') %}

-- row counts per table
select 'deal_changes' as table_name, count(*) as row_count from {{ deal_changes }}
union all select 'activity', count(*) from {{ activity }}
union all select 'activity_types', count(*) from {{ source('pipedrive', 'activity_types') }}
union all select 'fields', count(*) from {{ source('pipedrive', 'fields') }}
union all select 'stages', count(*) from {{ source('pipedrive', 'stages') }}
union all select 'users', count(*) from {{ source('pipedrive', 'users') }};

-- coverage of the two event tables
select count(distinct deal_id) as deals, min(change_time), max(change_time)
from {{ deal_changes }};

select count(distinct activity_id) as activity_ids, count(distinct deal_id) as deal_ids, min(due_to), max(due_to)
from {{ activity }};

-- nulls
select
    count(*) filter (where deal_id is null)                 as null_deal_id,
    count(*) filter (where change_time is null)             as null_change_time,
    count(*) filter (where changed_field_key is null)       as null_field_key,
    count(*) filter (where new_value is null)               as null_new_value
from {{ deal_changes }};

select
    count(*) filter (where activity_id is null)             as null_activity_id,
    count(*) filter (where deal_id is null)                 as null_deal_id,
    count(*) filter (where due_to is null)                  as null_due_to,
    count(*) filter (where done is null)                    as null_done,
    count(*) filter (where assigned_to_user is null)        as null_user
from {{ activity }};

-- fully duplicated rows
select count(*) - count(distinct (deal_id, change_time, changed_field_key, new_value)) as duplicate_rows
from {{ deal_changes }};

select count(*) - count(distinct (activity_id, type, assigned_to_user, deal_id, done, due_to)) as duplicate_rows
from {{ activity }};

-- events per field key
select changed_field_key, count(*) as events, count(distinct deal_id) as deals
from {{ deal_changes }}
group by 1
order by 2 desc;

-- DQ-6: new deals, stage events and lost reasons per month
select
    date_trunc('month', change_time)::date                              as month,
    count(*) filter (where changed_field_key = 'add_time')              as deals_created,
    count(*) filter (where changed_field_key = 'stage_id')              as stage_events,
    count(*) filter (where changed_field_key = 'lost_reason')           as lost_reasons
from {{ deal_changes }}
group by 1
order by 1;
