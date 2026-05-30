create view public.report_2_4_members_zero_reservations_scd as
WITH date_series AS (
    SELECT generate_series(
        '2026-04-01'::date,
        CURRENT_DATE,
        '1 day'::interval
    )::date AS dt
),
first_reservation AS (
    SELECT
        r.members_id,
        MIN(r.date) AS first_booked_on
    FROM reservations_confirmed r
    INNER JOIN private.members m ON m.id = r.members_id
    WHERE r.date <= CURRENT_DATE
      AND m.year_of_membership = EXTRACT(YEAR FROM CURRENT_DATE)::int
    GROUP BY r.members_id
),
total_members AS (
    SELECT COUNT(*) AS total FROM private.members
    where year_of_membership = EXTRACT(YEAR FROM CURRENT_DATE)::int
),
members_with_reservation_by_date AS (
    -- How many members had made at least one booking by each date
    SELECT
        d.dt,
        COUNT(fr.members_id) AS has_booked
    FROM date_series d
    LEFT JOIN first_reservation fr ON fr.first_booked_on <= d.dt
    GROUP BY d.dt
)
SELECT
    m.dt AS date,
    tm.total - m.has_booked AS members_without_reservation
FROM members_with_reservation_by_date m
CROSS JOIN total_members tm
ORDER BY m.dt;

-- public.view_missing_cr_age_report2 source
CREATE OR REPLACE VIEW public.view_missing_cr_age_report3 AS 
WITH reservation_stats AS (
         SELECT vrcs.cr_name,
            count(*) AS total_reservations
           FROM view_reservations_confirmed_staging vrcs
          WHERE vrcs.date < CURRENT_DATE AND NOT (EXISTS ( SELECT 1
                   FROM catch_returns_staging_table disqualified
                  WHERE disqualified.catch_date = vrcs.date AND disqualified.rod_name = vrcs.cr_name AND (disqualified.dnf = true OR disqualified.guest = true)))
          GROUP BY vrcs.cr_name
        ), return_stats AS (
         SELECT vrcs.cr_name,
            CURRENT_DATE - vrcs.date AS days_old,
                CASE
                    WHEN crst.rod_name IS NOT NULL THEN 1
                    ELSE 0
                END AS was_submitted
           FROM view_reservations_confirmed_staging vrcs
             LEFT JOIN ( SELECT catch_returns_staging_table.id,
                    catch_returns_staging_table."timestamp",
                    catch_returns_staging_table.rod_name,
                    catch_returns_staging_table.catch_date,
                    catch_returns_staging_table.beat,
                    catch_returns_staging_table.guest,
                    catch_returns_staging_table.dnf,
                    row_number() OVER (PARTITION BY catch_returns_staging_table.catch_date, catch_returns_staging_table.rod_name ORDER BY catch_returns_staging_table."timestamp" DESC) AS rn
                   FROM catch_returns_staging_table
                  WHERE catch_returns_staging_table.dnf = false AND catch_returns_staging_table.guest = false) crst ON vrcs.cr_name = crst.rod_name AND vrcs.date = crst.catch_date AND crst.rn = 1
          WHERE vrcs.date < CURRENT_DATE AND NOT (EXISTS ( SELECT 1
                   FROM catch_returns_staging_table disqualified
                  WHERE disqualified.catch_date = vrcs.date AND disqualified.rod_name = vrcs.cr_name AND (disqualified.dnf = true OR disqualified.guest = true)))
        )
 SELECT m.member_name,
    res.total_reservations AS "Total Reservations",
    sum(rs.was_submitted) AS "Returns Submitted",
	COALESCE(
	    ROUND(sum(rs.was_submitted)::numeric / NULLIF(res.total_reservations, 0) * 100, 1),
	    0
	) AS pct_compliance,
    count(
        CASE
            WHEN rs.was_submitted = 0 AND rs.days_old <= 7 THEN 1
            ELSE NULL::integer
        END) AS "1-7 Days",
    count(
        CASE
            WHEN rs.was_submitted = 0 AND rs.days_old > 7 AND rs.days_old <= 14 THEN 1
            ELSE NULL::integer
        END) AS "8-14 Days",
    count(
        CASE
            WHEN rs.was_submitted = 0 AND rs.days_old > 14 AND rs.days_old <= 21 THEN 1
            ELSE NULL::integer
        END) AS "15-21 Days",
    count(
        CASE
            WHEN rs.was_submitted = 0 AND rs.days_old > 21 AND rs.days_old <= 28 THEN 1
            ELSE NULL::integer
        END) AS "21-28 Days",
    count(
        CASE
            WHEN rs.was_submitted = 0 AND rs.days_old > 28 THEN 1
            ELSE NULL::integer
        END) AS "28+ Days",
    count(
        CASE
            WHEN rs.was_submitted = 0 THEN 1
            ELSE NULL::integer
        END) AS "Total Missing"
   FROM view_member_names m
     JOIN return_stats rs ON m.cr_name = rs.cr_name
     LEFT JOIN reservation_stats res ON m.cr_name = res.cr_name
  GROUP BY m.member_name, res.total_reservations
 HAVING count(
        CASE
            WHEN rs.was_submitted = 0 THEN 1
            ELSE NULL::integer
        END) > 0
  ORDER BY (count(
        CASE
            WHEN rs.was_submitted = 0 THEN 1
            ELSE NULL::integer
        END)) DESC;
        