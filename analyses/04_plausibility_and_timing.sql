/*
    04 Plausibility and timing: does the data behave like a real sales pipeline, and which clock to use.

    Findings
    - Synthetic-data signals: flat volume (205-262 new deals per full month, no ramp or seasonality),
      stage changes spread evenly over all seven weekdays including Sundays (2,130-2,262 each),
      1,787 users for 1,995 deals, lost reasons spread evenly at every stage.
    - Installation lag: median 15 days from first reaching Closing to first reaching Implementation.
      Closings run until January 2025 and implementations until February 2025, months after the last
      new deal, which fits time for installation and grid registration (DQ-6).
    - Timestamps carry a time of day over all 24 hours. Converting from UTC (Pipedrive's storage zone) to
      Europe/Berlin moves 25 stage events into another month; no completed sales call moves (DQ-13).
    - Lookups: stage 2 is "Qualified lead" in stages but "Qualified Lead" in fields and the brief (DQ-8).
      users has 4 duplicate emails and 21 duplicate names (DQ-12).

    Decisions
    - The business context guides definitions, not data corrections.
    - Timestamps are converted to Europe/Berlin in staging (to_reporting_timezone macro).
    - KPI names come from the funnel_steps seed; users are joined on id only.
*/

{% set deal_changes = source('pipedrive', 'deal_changes') %}

-- events per weekday (1 = Monday)
select extract(isodow from change_time) as weekday, count(*) as events
from {{ deal_changes }}
group by 1
order by 1;

-- DQ-6: closings and implementations per month
select
    date_trunc('month', change_time)::date                                      as month,
    count(*) filter (where changed_field_key = 'add_time')                      as deals_created,
    count(*) filter (where changed_field_key = 'stage_id' and new_value = '6')  as closing_events,
    count(*) filter (where changed_field_key = 'stage_id' and new_value = '7')  as implementation_events
from {{ deal_changes }}
group by 1
order by 1;

-- DQ-6: median days from first reaching Closing to first reaching Implementation
select percentile_cont(0.5) within group (order by days) as median_days_closing_to_implementation
from (
    select extract(epoch from (
               min(change_time) filter (where changed_field_key = 'stage_id' and new_value = '7')
             - min(change_time) filter (where changed_field_key = 'stage_id' and new_value = '6')
           )) / 86400 as days
    from {{ deal_changes }}
    group by deal_id
) as lags
where days is not null;

-- DQ-13: events that change month when converted from UTC to Europe/Berlin
select count(*) as stage_events_moving_month
from {{ deal_changes }}
where changed_field_key = 'stage_id'
    and date_trunc('month', change_time)
     <> date_trunc('month', {{ to_reporting_timezone('change_time') }});

select count(*) as sales_calls_moving_month
from {{ source('pipedrive', 'activity') }}
where type in ('meeting', 'sc_2')
    and done
    and date_trunc('month', due_to)
     <> date_trunc('month', {{ to_reporting_timezone('due_to') }});

-- DQ-8: stage names in stages vs the labels in fields
select stages.stage_id, stages.stage_name, options.option ->> 'label' as field_label
from {{ source('pipedrive', 'stages') }} as stages
left join (
    select jsonb_array_elements(field_value_options) as option
    from {{ source('pipedrive', 'fields') }}
    where field_key = 'stage_id'
) as options
    on (options.option ->> 'id')::int = stages.stage_id
order by stages.stage_id;

-- DQ-12: duplicate user emails and names
select
    count(*) - count(distinct email) as duplicate_emails,
    count(*) - count(distinct name)  as duplicate_names
from {{ source('pipedrive', 'users') }};
