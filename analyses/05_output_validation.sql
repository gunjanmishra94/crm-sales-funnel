/*
    05 Output validation: does the report match what the raw data says?

    The raw counts repeat the step mapping (stage ids, meeting = 2.1, sc_2 = 3.1) on purpose instead of
    reading the seed or the models, so the check is independent of the code it validates.

    Run after `dbt build`. The reconciliation and grain checks are also automated as singular tests in
    tests/; these queries show the numbers side by side.

    Expected
    - Stage steps: report totals equal the "reached" counts from raw data (1,995 / 1,990 / 1,951 / 1,862 /
      1,693 / 1,424 / 1,081 / 723 / 324 for stages 1-9).
    - Sales calls: 568 (Sales Call 1) and 560 (Sales Call 2), the completed activity counts.
    - 154 rows: 14 months (January 2024 to February 2025) x 11 steps.
*/

-- report totals per step next to an independent count from the raw tables
with report as (
    select funnel_step, kpi_name, sum(deals_count) as report_deals
    from {{ ref('rep_sales_funnel_monthly') }}
    group by funnel_step, kpi_name
),

raw_stage_reach as (
    select stages.stage_id::varchar as funnel_step, count(*) as raw_deals
    from (
        select deal_id, max(new_value::int) as furthest_stage_id
        from {{ source('pipedrive', 'deal_changes') }}
        where changed_field_key = 'stage_id'
        group by deal_id
    ) as furthest
    inner join {{ source('pipedrive', 'stages') }} as stages
        on stages.stage_id <= furthest.furthest_stage_id
    group by stages.stage_id
),

raw_sales_calls as (
    select
        case type when 'meeting' then '2.1' when 'sc_2' then '3.1' end as funnel_step,
        count(distinct deal_id) as raw_deals
    from {{ source('pipedrive', 'activity') }}
    where done and type in ('meeting', 'sc_2')
    group by 1
),

raw as (
    select * from raw_stage_reach
    union all
    select * from raw_sales_calls
)

select
    report.funnel_step,
    report.kpi_name,
    report.report_deals,
    raw.raw_deals,
    report.report_deals = raw.raw_deals as matches
from report
left join raw using (funnel_step)
order by report.funnel_step::numeric;

-- report shape: months, steps and rows
select
    count(distinct month)       as months,
    count(distinct funnel_step) as steps,
    count(*)                    as row_count,
    min(month)                  as first_month,
    max(month)                  as last_month
from {{ ref('rep_sales_funnel_monthly') }};
