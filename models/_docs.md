{% docs __overview__ %}
# Pipedrive sales funnel

Monthly sales funnel for Enpal, built from a Pipedrive CRM export. The output the brief asks for is
`rep_sales_funnel_monthly`: for each month and each of the 11 funnel steps, the number of deals that
reached the step for the first time.

**Layers**

| Layer | Models | Materialization |
|---|---|---|
| staging | `stg_pipedrive__*`: one per raw table, renamed, cast, UTC converted to Europe/Berlin | view |
| intermediate | `int_deal_stage_entries`, `int_deal_sales_calls`: first time per deal and step | view |
| marts | `dim_deals` (deal state), `fct_deal_funnel_events` (deal x funnel step) | table |
| reporting | `rep_sales_funnel_monthly` (the brief), `extensions/rep_sales_funnel_cohort` | table |

**Key definitions**

- A pipeline stage counts as reached when the deal was recorded in it or any later stage. Deals often
  skip stages in the CRM, but a signed contract implies a quote and a site assessment.
- Sales Call 1 and 2 come from completed activities and are counted on their own: activity deal_ids
  almost never match pipeline deals.
- Months are calendar months in Europe/Berlin time.

The funnel definition (steps, sources, sort order, sales phase) lives in the `funnel_steps` seed.
Data exploration is in the `analyses/` folder; the README lists every data quality issue and how it is handled.
{% enddocs %}


{% docs deal_id %}
Pipedrive deal id. There is no deals table in the source: a deal exists only as events in
`deal_changes`. Five ids each hold two separate deals (DQ-1); they are counted once per step.
{% enddocs %}


{% docs funnel_step %}
Funnel step label from the brief, e.g. '1', '2.1'. Text, so it sorts correctly for the current steps;
use `step_order` for a robust sort.
{% enddocs %}


{% docs step_order %}
Numeric sort order of the funnel steps (1 to 11), from the `funnel_steps` seed.
{% enddocs %}


{% docs kpi_name %}
KPI name of the funnel step, exactly as in the brief (from the `funnel_steps` seed).
{% enddocs %}


{% docs reached_at %}
First time the deal reached the step, in Europe/Berlin time. For a pipeline stage: the first time the
deal was recorded in that stage or any later stage. For a sales call: the due date of the first
completed call (there is no completion timestamp).
{% enddocs %}


{% docs is_recorded %}
True when the deal was logged in exactly this stage. False when the stage was skipped in the CRM and is
implied by a later stage; its time is then the time the deal first got past it.
{% enddocs %}


{% docs berlin_timestamp %}
Converted from UTC (Pipedrive's storage zone) to Europe/Berlin by the `to_reporting_timezone` macro.
{% enddocs %}
