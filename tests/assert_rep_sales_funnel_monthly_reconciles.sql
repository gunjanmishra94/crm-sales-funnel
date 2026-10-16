-- Total deals per step in the report must equal the distinct deals that reached that step.
with report as (

    select funnel_step, sum(deals_count) as report_deals
    from {{ ref('rep_sales_funnel_monthly') }}
    group by funnel_step

),

facts as (

    select funnel_step, count(*) as fact_deals
    from {{ ref('fct_deal_funnel_events') }}
    group by funnel_step

)

select *
from report
full outer join facts using (funnel_step)
where coalesce(report.report_deals, 0) <> coalesce(facts.fact_deals, 0)
