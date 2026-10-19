-- The report must have exactly one row per month and funnel step.
select
    month,
    funnel_step,
    count(*) as row_count
from {{ ref('rep_sales_funnel_monthly') }}
group by month, funnel_step
having count(*) > 1
