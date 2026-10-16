"""Sales funnel dashboard over the dbt models in public_pipedrive_analytics.

Run `dbt build` first, then: streamlit run dashboard/app.py
"""

import os

import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
import psycopg2
import streamlit as st

SCHEMA = "public_pipedrive_analytics"
NAVY, ORANGE, BLUE, GREY = "#14213D", "#E07A3A", "#2F6FB0", "#B8BFCC"

st.set_page_config(page_title="Enpal sales funnel", layout="wide")


@st.cache_data(ttl=600)
def query(sql: str) -> pd.DataFrame:
    # Same local Postgres as profiles.yml; override with PG* environment variables.
    with psycopg2.connect(
        host=os.getenv("PGHOST", "localhost"),
        port=os.getenv("PGPORT", "5432"),
        user=os.getenv("PGUSER", "admin"),
        password=os.getenv("PGPASSWORD", "admin"),
        dbname=os.getenv("PGDATABASE", "postgres"),
    ) as conn, conn.cursor() as cursor:
        cursor.execute(sql.format(schema=SCHEMA))
        columns = [column.name for column in cursor.description]
        return pd.DataFrame(cursor.fetchall(), columns=columns)


try:
    monthly = query(
        """
        select report.month, report.funnel_step, report.kpi_name, report.deals_count,
               steps.step_order, steps.source_type
        from {schema}.rep_sales_funnel_monthly as report
        join {schema}.funnel_steps as steps using (funnel_step)
        order by report.month, steps.step_order
        """
    )
except psycopg2.Error as error:
    st.error(f"Could not read the dbt models. Start Postgres and run `dbt build` first.\n\n{error}")
    st.stop()

monthly["month"] = pd.to_datetime(monthly["month"])
monthly["step_label"] = monthly["funnel_step"] + " " + monthly["kpi_name"]
step_labels = monthly.drop_duplicates("step_order").sort_values("step_order")["step_label"].tolist()

st.title("Enpal sales funnel")
st.caption("Pipedrive CRM export, modelled with dbt. All months in Europe/Berlin time.")

tab_monthly, tab_cohort, tab_recorded, tab_quality = st.tabs(
    ["Monthly funnel", "Cohorts", "Recorded vs reached", "Data quality"]
)

# --- Monthly funnel: rep_sales_funnel_monthly, the report the assignment asks for -------------------
with tab_monthly:
    months = sorted(monthly["month"].unique())
    start, end = st.select_slider(
        "Months",
        options=months,
        value=(months[0], months[-1]),
        format_func=lambda m: pd.Timestamp(m).strftime("%b %Y"),
    )
    selected = monthly[(monthly["month"] >= start) & (monthly["month"] <= end)]
    totals = (
        selected.groupby(["step_order", "step_label", "source_type"], as_index=False)["deals_count"]
        .sum()
        .sort_values("step_order")
    )

    left, right = st.columns([3, 2])
    with left:
        st.subheader("Deals reaching each step")
        funnel = go.Figure(
            go.Funnel(
                y=totals["step_label"],
                x=totals["deals_count"],
                marker_color=[BLUE if t == "activity" else NAVY for t in totals["source_type"]],
                textinfo="value",
                connector={"fillcolor": "#E4E7EC"},
            )
        )
        funnel.update_layout(margin=dict(l=0, r=0, t=10, b=0), height=480)
        st.plotly_chart(funnel, width="stretch")
    with right:
        st.subheader("How to read it")
        st.markdown(
            "- Each deal is counted in the month it **first** reached a step.\n"
            "- A stage counts once the deal is in it **or any later stage**.\n"
            "- Sales Call 1 and 2 (blue) come from completed activities and are counted on their own: "
            "only 8 of 4,579 activities link to a pipeline deal.\n"
            "- Within one month a later step can be higher than an earlier one, because they are "
            "different deals."
        )

    st.subheader("Month × step")
    grid = selected.pivot_table(
        index=selected["month"].dt.strftime("%Y-%m"),
        columns="step_label",
        values="deals_count",
        aggfunc="sum",
    )[step_labels]
    st.dataframe(grid, width="stretch")

# --- Cohorts: rep_sales_funnel_cohort (extension) ----------------------------------------------------
with tab_cohort:
    cohort = query(
        """
        select cohort_month, funnel_step, kpi_name, step_order, cohort_deals, deals_reached,
               share_of_cohort, share_of_previous_step, median_days_from_previous_step
        from {schema}.rep_sales_funnel_cohort
        order by cohort_month, step_order
        """
    )
    cohort["cohort_month"] = pd.to_datetime(cohort["cohort_month"])
    cohort["step_label"] = cohort["funnel_step"] + " " + cohort["kpi_name"]
    cohort_months = sorted(cohort["cohort_month"].unique())
    chosen = st.selectbox(
        "Deals created in",
        cohort_months,
        index=min(2, len(cohort_months) - 1),
        format_func=lambda m: pd.Timestamp(m).strftime("%B %Y"),
    )
    one = cohort[cohort["cohort_month"] == chosen]

    c1, c2, c3 = st.columns(3)
    c1.metric("Deals in cohort", f"{int(one['cohort_deals'].iloc[0]):,}")
    closing = one.loc[one["funnel_step"] == "6", "share_of_cohort"]
    renewal = one.loc[one["funnel_step"] == "9", "share_of_cohort"]
    c2.metric("Reached Closing", f"{closing.iloc[0]:.0%}" if len(closing) else "n/a")
    c3.metric("Reached Renewal/Expansion", f"{renewal.iloc[0]:.0%}" if len(renewal) else "n/a")

    shares = px.bar(
        one,
        x="step_label",
        y="share_of_cohort",
        text=one["share_of_cohort"].map("{:.0%}".format),
        labels={"step_label": "", "share_of_cohort": "Share of cohort"},
        color_discrete_sequence=[NAVY],
    )
    shares.update_yaxes(tickformat=".0%", range=[0, 1.05])
    shares.update_layout(margin=dict(l=0, r=0, t=10, b=0), height=380)
    st.plotly_chart(shares, width="stretch")

    st.subheader("Share reaching each stage, all cohorts")
    heat = cohort.pivot_table(
        index=cohort["cohort_month"].dt.strftime("%Y-%m"),
        columns="step_label",
        values="share_of_cohort",
    )[one.sort_values("step_order")["step_label"].tolist()]
    st.dataframe(
        heat * 100,
        column_config={col: st.column_config.NumberColumn(format="%d%%") for col in heat.columns},
        width="stretch",
    )
    st.caption(
        "Median days from the previous stage are measured only where the deal was recorded in both "
        "stages. Sales calls are not included: they can't be linked to pipeline deals."
    )
    st.dataframe(
        one[["step_label", "deals_reached", "share_of_previous_step", "median_days_from_previous_step"]]
        .rename(columns={
            "step_label": "Stage",
            "deals_reached": "Deals",
            "share_of_previous_step": "Share of previous stage",
            "median_days_from_previous_step": "Median days from previous stage",
        }),
        hide_index=True,
        width="stretch",
    )

# --- Recorded vs reached: the effect of counting skipped stages --------------------------------------
with tab_recorded:
    recorded = query(
        """
        select funnel_step, kpi_name, step_order,
               count(*) filter (where is_recorded)  as recorded_in_crm,
               count(*)                             as reached
        from {schema}.fct_deal_funnel_events
        where source_type = 'stage'
        group by funnel_step, kpi_name, step_order
        order by step_order
        """
    )
    recorded["step_label"] = recorded["funnel_step"] + " " + recorded["kpi_name"]
    st.markdown(
        "Sales reps often skip stages in the CRM, for example moving a deal straight from Qualified Lead "
        "to Closing. The report counts a stage as **reached** once the deal is in it or any later stage. "
        "Counting only stages **recorded** in the CRM would make the middle of the funnel look much "
        "smaller than it is."
    )
    long = recorded.melt(
        id_vars=["step_label", "step_order"],
        value_vars=["recorded_in_crm", "reached"],
        var_name="count_type",
        value_name="deals",
    )
    long["count_type"] = long["count_type"].map(
        {"recorded_in_crm": "Recorded in the CRM", "reached": "Reached (used in the report)"}
    )
    bars = px.bar(
        long,
        x="step_label",
        y="deals",
        color="count_type",
        barmode="group",
        labels={"step_label": "", "deals": "Deals", "count_type": ""},
        color_discrete_sequence=[GREY, NAVY],
    )
    bars.update_layout(margin=dict(l=0, r=0, t=10, b=0), height=420, legend=dict(orientation="h"))
    st.plotly_chart(bars, width="stretch")
    recorded["filled_in"] = recorded["reached"] - recorded["recorded_in_crm"]
    st.dataframe(
        recorded[["step_label", "recorded_in_crm", "reached", "filled_in"]].rename(columns={
            "step_label": "Stage",
            "recorded_in_crm": "Recorded in CRM",
            "reached": "Reached",
            "filled_in": "Filled in from a later stage",
        }),
        hide_index=True,
        width="stretch",
    )

# --- Data quality: the main findings, computed live from the models ----------------------------------
with tab_quality:
    dq = query(
        """
        with deals as (
            select count(*) as deals, count(*) filter (where has_multiple_creation_events) as shared_ids
            from {schema}.dim_deals
        ),
        skips as (
            select count(*) filter (where skipped) as deals_skipping
            from (
                select deal_id, bool_or(not is_recorded) as skipped
                from {schema}.fct_deal_funnel_events
                where source_type = 'stage'
                group by deal_id
            ) as per_deal
        ),
        activities as (
            select count(*) as activities,
                   count(*) filter (where deal_id in (select deal_id from {schema}.dim_deals)) as linked
            from {schema}.stg_pipedrive__activities
        )
        select * from deals, skips, activities
        """
    ).iloc[0]

    m1, m2, m3, m4 = st.columns(4)
    m1.metric("Deals", f"{dq['deals']:,}")
    m2.metric("Deals skipping a stage", f"{dq['deals_skipping'] / dq['deals']:.0%}")
    m3.metric("Activities linked to a deal", f"{dq['linked']:,} of {dq['activities']:,}")
    m4.metric("Deal ids holding two deals", f"{dq['shared_ids']}")

    lost = query(
        """
        select coalesce(lost_phase, 'stage changed after loss') as lost_phase, count(*) as deals
        from {schema}.dim_deals
        group by 1
        """
    )
    order = ["pre_sale", "closing", "post_sale", "stage changed after loss"]
    lost["lost_phase"] = pd.Categorical(lost["lost_phase"], categories=order, ordered=True)
    lost = lost.sort_values("lost_phase")

    left, right = st.columns([2, 3])
    with left:
        st.subheader("Where deals were lost")
        lost_bars = px.bar(
            lost,
            x="lost_phase",
            y="deals",
            text="deals",
            labels={"lost_phase": "", "deals": "Deals"},
            color_discrete_sequence=[ORANGE],
        )
        lost_bars.update_layout(margin=dict(l=0, r=0, t=10, b=0), height=360)
        st.plotly_chart(lost_bars, width="stretch")
    with right:
        st.subheader("What this means for the funnel")
        st.markdown(
            "- **Every deal ends with a lost reason**, even those that reached Renewal/Expansion. "
            "Lost deals stay in the funnel; post-sale losses read as cancellations or lost upsells.\n"
            "- **Skipped stages** are filled in from later stages (see *Recorded vs reached*).\n"
            "- **Activities almost never match a pipeline deal**, so the two sales call steps are "
            "counted on their own and can't appear in the cohort view.\n"
            "- **A few deal ids hold two deals**; they are counted once per step and flagged in "
            "`dim_deals`.\n\n"
            "The full list (DQ-1 to DQ-15) and the queries behind it are in the README and `analyses/`."
        )
