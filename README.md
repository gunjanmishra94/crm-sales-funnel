# Pipedrive Sales Funnel – dbt Solution

## Quick start

```bash
docker compose up -d                 # Postgres + raw data load
python3 -m venv .venv && source .venv/bin/activate
pip install dbt-core dbt-postgres    # tested with dbt-core 1.12 / dbt-postgres 1.11
dbt build --profiles-dir .           # seeds, models and tests
```

All objects are built in schema `public_pipedrive_analytics`. The final output is
`rep_sales_funnel_monthly` (`month`, `kpi_name`, `funnel_step`, `deals_count`).

## Project structure

```
seeds/funnel_steps.csv            business definition of the funnel (step -> stage_id or activity type)
models/
  staging/pipedrive/              1:1 with sources: rename, cast, surrogate keys (views)
    stg_pipedrive__deal_changes, stg_pipedrive__activities, stg_pipedrive__activity_types,
    stg_pipedrive__stages, stg_pipedrive__users, stg_pipedrive__field_options
  intermediate/                   reusable building blocks (views)
    int_deal_stage_entries        deal x stage, first time entered
    int_deal_sales_calls          deal x sales call type, first completed call
  marts/                          business entities (tables)
    dim_deals                     current state of each deal (stage, owner, lost reason)
    fct_deal_funnel_events        deal x funnel step, first time reached
  reporting/
    rep_sales_funnel_monthly      month x funnel step, deals_count (zero-filled)
tests/                            singular tests (report grain, reconciliation with the fact)
```

Data flow: `sources -> staging -> intermediate -> marts -> reporting`.

## Metric definition

`deals_count` = number of distinct deals that reached a funnel step **for the first time** in that month.

| Step | KPI | Source |
|---|---|---|
| 1–9 (except 2.1, 3.1) | Pipeline stages | `deal_changes` where `changed_field_key = 'stage_id'`, first entry per deal and stage |
| 2.1 | Sales Call 1 | `activity` of type `meeting` with `done = true`, first completed call per deal (`due_to`) |
| 3.1 | Sales Call 2 | `activity` of type `sc_2` with `done = true`, first completed call per deal (`due_to`) |

The step-to-source mapping is in `seeds/funnel_steps.csv`, so you can change the funnel there without touching SQL.
Every month × step combination is present, so empty months show `0` instead of a missing row.

## Exploratory findings

| Finding | Impact / handling |
|---|---|
| `deal_changes` is an EAV event log with 4 field keys (`add_time`, `user_id`, `stage_id`, `lost_reason`). 15,406 rows, 1,995 deals, Jan 2024 – Feb 2025. | Pivoted into `dim_deals` with one scan + one window function. |
| 28% of stage transitions skip stages (e.g. 5 → 8), and 8 go backwards. | Funnel counts the stages a deal was actually recorded in. Deals that skip a stage aren't counted for it. Re-entries count once (first entry). |
| 5 deal_ids have **two** `add_time` events with interleaved histories, which looks like two deals sharing one id. | Flagged in `dim_deals.has_multiple_creation_events`. The funnel counts each deal_id once per step. |
| `activity.activity_id` is not unique (11 ids are reused by unrelated activities). | Surrogate `activity_key` in staging, tested for uniqueness. |
| Only **8 of 4,579** activities reference a deal_id that exists in `deal_changes`. | Sales Call steps can't be tied to pipeline deals, so they are counted from activities on their own. Surfaced as a `warn` relationship test. |
| Every deal ends with a `lost_reason` event, including deals in Renewal/Expansion. | `lost_reason` is exposed in `dim_deals` but not used to filter the funnel. |
| `stages.stage_name` says "Qualified lead" but `fields` says "Qualified Lead". | KPI names come from the seed, which matches the task spec. |
| Activity type mapping: `meeting` = Sales Call 1, `sc_2` = Sales Call 2. `follow_up` is inactive. | Joined on `activity_types.type`. |
| Timestamps have no timezone. | Assumed to be one consistent timezone. Months are calendar months. |

## Design choices

- **Staging as views, marts/reporting as tables.** Staging is cheap renaming. Tables are materialized where they get queried.
- **Filter and aggregate early.** Intermediate models reduce to the funnel grain (one row per deal × step) before the
  union/join, so the report is a plain `count(*)` over a small fact.
- **No package dependencies.** Surrogate keys use `md5(concat_ws(...))`, so `dbt deps` isn't needed.
- **Tests at every layer**: source PKs, staging keys and accepted values, referential integrity, fact uniqueness,
  plus singular tests that the report has one row per month × step and reconciles exactly to the fact table.

## Possible extensions

- Cohort view of the funnel (deals grouped by creation month), as an alternative to the event-month view.
- An "at least reached" funnel that fills in skipped stages, if the business treats skipped stages as passed.
- Incremental materialization of `fct_deal_funnel_events` on `reached_at` once volumes grow.

---

# Original assignment
## Setup

1. Download Docker Desktop (if you don’t have installed) using the official website, install and launch.
2. Fork this Github project to you Github account. Clone the forked repo to your device.
3. Open your Command Prompt or Terminal, navigate to that folder, and run the command `docker compose up`.
4. Now you have launched a local Postgres database with the following credentials:
 ```
    Host: localhost
    User: admin
    Password: admin
    Port: 5432 
```
5. Connect to the db via a preferred tool (e.g. DataGrip, Dbeaver etc)
6. Install dbt-core and dbt-postgres using pip (if you don’t have) on your preferred environment.
7. Now you can run `dbt run` with the test model and check public_pipedrive_analytics schema to see the dbt result (with one test model)

## Project
1. Remove the test model once you make sure it works
2. Dive deep into the Pipedrive CRM source data to gain a thorough understanding of all its details. (You may also research the Pipedrive CRM tool terms).
3. Define DBT sources and build the necessary layers organizing the data flow for optimal relevance and maintainability.
4. Build a reporting model (rep_sales_funnel_monthly) with monthly intervals, incorporating the following funnel steps (KPIs):  
  &nbsp;&nbsp;&nbsp;Step 1: Lead Generation  
  &nbsp;&nbsp;&nbsp;Step 2: Qualified Lead  
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Step 2.1: Sales Call 1  
  &nbsp;&nbsp;&nbsp;Step 3: Needs Assessment  
  &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;Step 3.1: Sales Call 2  
  &nbsp;&nbsp;&nbsp;Step 4: Proposal/Quote Preparation  
  &nbsp;&nbsp;&nbsp;Step 5: Negotiation  
  &nbsp;&nbsp;&nbsp;Step 6: Closing  
  &nbsp;&nbsp;&nbsp;Step 7: Implementation/Onboarding  
  &nbsp;&nbsp;&nbsp;Step 8: Follow-up/Customer Success  
  &nbsp;&nbsp;&nbsp;Step 9: Renewal/Expansion
5. Column names of the reporting model: `month`, `kpi_name`, `funnel_step`, `deals_count`
6. “Git commit” all the changes and create a PR to your forked repo (not the original one). Send your repo link to us.
