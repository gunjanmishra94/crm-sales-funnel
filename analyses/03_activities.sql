/*
    03 Activities: sales calls, their types and how they link to deals.

    Findings
    - Four activity types joined on activity.type = activity_types.type (activity_types.id is not used):
      meeting = Sales Call 1 (1,145 rows, 568 done), sc_2 = Sales Call 2 (1,124, 560 done),
      follow_up (inactive, but 1,133 rows) and after_close_call (1,177) (DQ-9).
    - activity_id is not unique: 4,579 rows, 4,568 ids. The 11 reused ids sit on unrelated rows (DQ-3).
    - Only 8 of 4,579 activities have a deal_id that exists in deal_changes, although both use six-digit
      ids in the same range (DQ-2).
    - None of the 560 deals with a completed Sales Call 2 has a completed Sales Call 1 (DQ-7).
    - There is no completion timestamp; due_to is a due date (DQ-15).

    Decisions
    - Surrogate activity_key in staging, tested unique.
    - Sales Call 1 and 2 are counted from completed activities on their own, not inside the stage funnel.
      The link to deals is a warning test, so the gap shows up in every build without blocking it.
    - due_to is used as the date of a completed call.
*/

{% set activity = source('pipedrive', 'activity') %}

-- activity types and their usage
select activity_types.id, activity_types.name, activity_types.active, activity_types.type,
       count(activity.*) as activities,
       count(activity.*) filter (where activity.done) as done
from {{ source('pipedrive', 'activity_types') }} as activity_types
left join {{ activity }} as activity
    on activity.type = activity_types.type
group by 1, 2, 3, 4
order by 1;

-- DQ-3: reused activity_ids
select *
from {{ activity }}
where activity_id in (select activity_id from {{ activity }} group by 1 having count(*) > 1)
order by activity_id;

-- DQ-2: activities whose deal_id exists in deal_changes, and the id ranges of both tables
select count(*) as linked_activities
from {{ activity }}
where deal_id in (select deal_id from {{ source('pipedrive', 'deal_changes') }});

select 'deal_changes' as table_name, min(deal_id), max(deal_id) from {{ source('pipedrive', 'deal_changes') }}
union all
select 'activity', min(deal_id), max(deal_id) from {{ activity }};

-- activities per deal_id, and deals with two completed calls of the same type
select activities, count(*) as deal_ids
from (select deal_id, count(*) as activities from {{ activity }} group by 1) as per_deal
group by 1;

select type, count(*) as deal_ids
from (select deal_id, type from {{ activity }} where done group by 1, 2 having count(*) > 1) as repeated
group by 1;

-- DQ-7: completed Sales Call 2 without a completed Sales Call 1
select count(distinct deal_id) as sc2_without_sc1
from {{ activity }} as sc2
where sc2.type = 'sc_2'
    and sc2.done
    and not exists (
        select 1
        from {{ activity }} as sc1
        where sc1.deal_id = sc2.deal_id
            and sc1.type = 'meeting'
            and sc1.done
    );

-- assignees missing from users
select count(*) as unknown_assignees
from {{ activity }}
where assigned_to_user not in (select id from {{ source('pipedrive', 'users') }});
