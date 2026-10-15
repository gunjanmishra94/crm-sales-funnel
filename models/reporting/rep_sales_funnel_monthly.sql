-- Grain: one row per month and funnel step.
-- deals_count = distinct deals that reached the step for the first time in that month.
-- Every month x step combination is present (zero-filled) so the report has no gaps.
with funnel_events as (

    select * from {{ ref('fct_deal_funnel_events') }}

),

funnel_steps as (

    select * from {{ ref('funnel_steps') }}

),

months as (

    select generate_series(
        min(reached_month),
        max(reached_month),
        interval '1 month'
    )::date                                 as month
    from funnel_events

),

monthly_counts as (

    select
        reached_month                       as month,
        funnel_step,
        count(*)                            as deals_count  -- fct grain is one row per deal and step
    from funnel_events
    group by reached_month, funnel_step

)

select
    months.month,
    funnel_steps.kpi_name,
    funnel_steps.funnel_step,
    coalesce(monthly_counts.deals_count, 0) as deals_count
from months
cross join funnel_steps
left join monthly_counts
    on months.month = monthly_counts.month
    and funnel_steps.funnel_step = monthly_counts.funnel_step
order by months.month, funnel_steps.funnel_step
