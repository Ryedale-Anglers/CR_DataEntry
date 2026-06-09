CREATE OR REPLACE VIEW private.view_missing_cr_age_report5
AS WITH reservation_stats AS (
         SELECT vrcs.cr_name,
            count(*) AS total_reservations
           FROM view_reservations_confirmed_staging vrcs
             LEFT JOIN catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name AND vrcs.beat = crst.beat
          WHERE crst.guest IS DISTINCT FROM true AND crst.dnf IS DISTINCT FROM true
          GROUP BY vrcs.cr_name
        ), catch_returns_stats AS (
         SELECT vrcs.cr_name,
            CURRENT_DATE - vrcs.date AS days_old,
                CASE
                    WHEN crst.rod_name IS NOT NULL THEN 1
                    ELSE 0
                END AS was_submitted
           FROM view_reservations_confirmed_staging vrcs
             LEFT JOIN catch_returns_staging_table crst ON vrcs.date = crst.catch_date AND vrcs.cr_name = crst.rod_name AND vrcs.beat = crst.beat
          WHERE crst.guest IS DISTINCT FROM true AND crst.dnf IS DISTINCT FROM true
        )
 SELECT m.member_name,
    COALESCE(res.total_reservations, 0::bigint) AS "Reservations",
    COALESCE(sum(crs.was_submitted), 0::bigint) AS "Catch Returns",
    COALESCE(res.total_reservations, 0::bigint) - COALESCE(sum(crs.was_submitted), 0::bigint) AS "CRs Due",
    COALESCE(round(sum(crs.was_submitted)::numeric / NULLIF(res.total_reservations, 0)::numeric * 100::numeric, 1), 0::numeric) AS pct_compliance,
    count(*) FILTER (WHERE crs.was_submitted = 0 AND crs.days_old >= 1 AND crs.days_old <= 7) AS "1-7 Days",
    count(*) FILTER (WHERE crs.was_submitted = 0 AND crs.days_old >= 8 AND crs.days_old <= 14) AS "8-14 Days",
    count(*) FILTER (WHERE crs.was_submitted = 0 AND crs.days_old >= 15 AND crs.days_old <= 21) AS "15-21 Days",
    count(*) FILTER (WHERE crs.was_submitted = 0 AND crs.days_old >= 22 AND crs.days_old <= 28) AS "22-28 Days",
    count(*) FILTER (WHERE crs.was_submitted = 0 AND crs.days_old > 28) AS "28+ Days"
   FROM view_member_names m
     LEFT JOIN reservation_stats res ON m.cr_name = res.cr_name
     LEFT JOIN catch_returns_stats crs ON m.cr_name = crs.cr_name
  GROUP BY m.member_name, res.total_reservations
 HAVING (COALESCE(res.total_reservations, 0::bigint) - COALESCE(sum(crs.was_submitted), 0::bigint)) > 0
  ORDER BY (COALESCE(res.total_reservations, 0::bigint) - COALESCE(sum(crs.was_submitted), 0::bigint)) DESC;