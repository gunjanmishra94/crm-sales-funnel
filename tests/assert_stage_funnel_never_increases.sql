-- Over all months, no pipeline stage can have more deals than the stage before it:
-- every deal that reached a stage also reached all earlier stages.
with stage_totals as (

    select
        step_order,
        count(*)                            as deals
    from {{ ref('fct_deal_funnel_events') }}
    where source_type = 'stage'
    group by step_order

)

select *
from (
    select
        step_order,
        deals,
        lag(deals) over (order by step_order) as previous_stage_deals
    from stage_totals
) as compared
where deals > previous_stage_deals
