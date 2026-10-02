-- view_missing_cr_age_report5 joined private.view_member_names, which is an unfiltered
-- SELECT over private.members (all years). A member present in more than one year with
-- the same cr_name and member_name (e.g. D JOHNSTON, 2025 and 2026) was therefore listed
-- twice and his returns due counted twice. Restrict the member list to the target year.
-- Otherwise unchanged: same columns, season end date, DNF exclusion and date rules.
CREATE OR REPLACE VIEW private.view_missing_cr_age_report5 AS
WITH reservation_stats AS (
    SELECT vrcs.cr_name,
           count(*) AS total_reservations
    FROM private.view_reservations_confirmed_staging vrcs
    CROSS JOIN (SELECT target_year FROM private.year_param WHERE id = 1) yp
    LEFT JOIN private.catch_returns_staging_table crst
           ON vrcs.date = crst.catch_date
          AND vrcs.cr_name = crst.rod_name
          AND vrcs.beat = crst.beat
          AND crst.guest = false
    WHERE crst.dnf IS DISTINCT FROM true
      AND vrcs.date < CURRENT_DATE
      AND vrcs.date <= make_date(yp.target_year, 9, 30)
    GROUP BY vrcs.cr_name
), catch_returns_stats AS (
    SELECT vrcs.cr_name,
           sum(CASE WHEN crst.rod_name IS NOT NULL THEN 1 ELSE 0 END) AS total_submitted,
           count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) >= 1 AND (CURRENT_DATE - vrcs.date) <= 7) AS "1-7 Days",
           count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) >= 8 AND (CURRENT_DATE - vrcs.date) <= 14) AS "8-14 Days",
           count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) >= 15 AND (CURRENT_DATE - vrcs.date) <= 21) AS "15-21 Days",
           count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) >= 22 AND (CURRENT_DATE - vrcs.date) <= 28) AS "22-28 Days",
           count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) > 28) AS "28+ Days"
    FROM private.view_reservations_confirmed_staging vrcs
    CROSS JOIN (SELECT target_year FROM private.year_param WHERE id = 1) yp
    LEFT JOIN private.catch_returns_staging_table crst
           ON vrcs.date = crst.catch_date
          AND vrcs.cr_name = crst.rod_name
          AND vrcs.beat = crst.beat
          AND crst.guest = false
    WHERE crst.dnf IS DISTINCT FROM true
      AND vrcs.date < CURRENT_DATE
      AND vrcs.date <= make_date(yp.target_year, 9, 30)
    GROUP BY vrcs.cr_name
)
SELECT m.member_name,
       COALESCE(res.total_reservations, 0::bigint) AS "Reservations",
       COALESCE(crs.total_submitted, 0::bigint) AS "Catch Returns",
       COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint) AS "CRs Due",
       COALESCE(round(crs.total_submitted::numeric / NULLIF(res.total_reservations, 0)::numeric * 100::numeric, 1), 0::numeric) AS pct_compliance,
       COALESCE(crs."1-7 Days", 0::bigint) AS "1-7 Days",
       COALESCE(crs."8-14 Days", 0::bigint) AS "8-14 Days",
       COALESCE(crs."15-21 Days", 0::bigint) AS "15-21 Days",
       COALESCE(crs."22-28 Days", 0::bigint) AS "22-28 Days",
       COALESCE(crs."28+ Days", 0::bigint) AS "28+ Days"
FROM private.view_member_names m
LEFT JOIN reservation_stats res ON m.cr_name = res.cr_name
LEFT JOIN catch_returns_stats crs ON m.cr_name = crs.cr_name
WHERE m.year_of_membership = (SELECT target_year FROM private.year_param WHERE id = 1)
  AND (COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint)) > 0
ORDER BY (COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint)) DESC;
