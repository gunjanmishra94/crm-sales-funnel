-- The cohort report must have one row per cohort month and stage, never more deals at a stage
-- than at the stage before it, shares between 0 and 1, and the same stage totals as the fact.
with report as (

    select * from {{ ref('rep_sales_funnel_cohort') }}

),

duplicates as (

    select 'duplicate cohort x step' as failure, cohort_month, funnel_step
    from report
    group by cohort_month, funnel_step
    having count(*) > 1

),

increases as (

    select 'more deals than previous step' as failure, cohort_month, funnel_step
    from report
    where share_of_previous_step > 1

),

bad_shares as (

    select 'share outside 0-1' as failure, cohort_month, funnel_step
    from report
    where share_of_cohort not between 0 and 1

),

totals_mismatch as (

    select 'stage total differs from fact' as failure, null::date as cohort_month, report_totals.funnel_step
    from (
        select funnel_step, sum(deals_reached) as deals
        from report
        group by funnel_step
    ) as report_totals
    full outer join (
        select funnel_step, count(*) as deals
        from {{ ref('fct_deal_funnel_events') }}
        where source_type = 'stage'
        group by funnel_step
    ) as fact_totals
        on report_totals.funnel_step = fact_totals.funnel_step
    where coalesce(report_totals.deals, 0) <> coalesce(fact_totals.deals, 0)

)

select * from duplicates
union all select * from increases
union all select * from bad_shares
union all select * from totals_mismatch
