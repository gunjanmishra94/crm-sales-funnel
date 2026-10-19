-- Grain: one row per cohort month and pipeline stage step. Extension beyond the brief.
-- Cohort = the month a deal was created (Berlin time). For each cohort and stage: how many deals
-- reached the stage, the share of the cohort and of the previous stage, and the median days it took
-- from the previous stage.
-- Stage steps only: Sales Call 1/2 can't be tied to pipeline deals (DQ-2), so they have no cohort.
-- Days are measured only where the deal was recorded in both stages; a skipped stage takes the
-- time of the next recorded one (DQ-4), which would otherwise show up as 0 days.
with funnel_events as (

    select * from {{ ref('fct_deal_funnel_events') }}

),

deals as (

    select * from {{ ref('dim_deals') }}

),

deal_cohorts as (

    select
        deal_id,
        date_trunc('month', created_at)::date as cohort_month
    from deals

),

funnel_steps as (

    select * from {{ ref('funnel_steps') }}

),

stage_events as (

    select
        funnel_events.deal_id,
        deal_cohorts.cohort_month,
        funnel_events.funnel_step,
        funnel_events.step_order,
        funnel_events.reached_at,
        funnel_events.is_recorded,
        lag(funnel_events.reached_at) over deal_steps   as previous_reached_at,
        lag(funnel_events.is_recorded) over deal_steps  as previous_is_recorded
    from funnel_events
    inner join deal_cohorts
        on funnel_events.deal_id = deal_cohorts.deal_id
    where funnel_events.source_type = 'stage'
    window deal_steps as (partition by funnel_events.deal_id order by funnel_events.step_order)

),

cohorts as (

    select
        cohort_month,
        count(*)                            as cohort_deals
    from deal_cohorts
    group by cohort_month

),

cohort_steps as (

    -- every cohort x stage step, so stages nobody in a cohort reached show 0
    select
        cohorts.cohort_month,
        cohorts.cohort_deals,
        funnel_steps.funnel_step,
        funnel_steps.step_order,
        funnel_steps.kpi_name
    from cohorts
    cross join funnel_steps
    where funnel_steps.source_type = 'stage'

),

step_counts as (

    select
        cohort_month,
        funnel_step,
        count(*)                            as deals_reached,
        percentile_cont(0.5) within group (
            order by extract(epoch from reached_at - previous_reached_at) / 86400
        ) filter (where is_recorded and previous_is_recorded) as median_days_from_previous_step
    from stage_events
    group by cohort_month, funnel_step

),

joined as (

    select
        cohort_steps.cohort_month,
        cohort_steps.kpi_name,
        cohort_steps.funnel_step,
        cohort_steps.step_order,
        cohort_steps.cohort_deals,
        coalesce(step_counts.deals_reached, 0) as deals_reached,
        step_counts.median_days_from_previous_step
    from cohort_steps
    left join step_counts
        on cohort_steps.cohort_month = step_counts.cohort_month
        and cohort_steps.funnel_step = step_counts.funnel_step

)

select
    cohort_month,
    kpi_name,
    funnel_step,
    step_order,
    cohort_deals,
    deals_reached,
    round(deals_reached::numeric / cohort_deals, 4) as share_of_cohort,
    round(deals_reached::numeric / nullif(lag(deals_reached) over cohort, 0), 4)
                                            as share_of_previous_step,
    round(median_days_from_previous_step::numeric, 1) as median_days_from_previous_step
from joined
window cohort as (partition by cohort_month order by step_order)
