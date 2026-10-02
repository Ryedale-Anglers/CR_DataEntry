-- private.view_missing_cr_age_report5 filtered on crst.guest IS DISTINCT FROM
-- true in the WHERE clause, treating a guest-only match the same way as a
-- dnf=true match: dropping the whole reservation row rather than just
-- excluding it from "satisfied". That's correct for dnf (the host confirmed
-- they didn't fish, so the obligation really is resolved) but wrong for
-- guest (a guest's catch return never satisfies the HOST's own obligation to
-- submit a return). The effect: a reservation whose only matching catch
-- return is a guest's becomes invisible to this report entirely, in both
-- directions - not counted as a reservation, not counted as a return - so
-- the host's outstanding return for it never shows up as due.
--
-- Confirmed against real local data: BROWN has a reservation for Duncombe
-- Park on 2026-06-16 with only a guest catch return logged against it (no
-- catch return of BROWN's own). This view reported 0 rows for BROWN
-- (reservations=5, submitted=5); private.view_secrep_membername_catchreturns_
-- count_operational (fixed in 20261001090000, which already puts guest=false
-- in the join condition rather than the WHERE clause) correctly reports
-- 6 reservations / 5 returns / variance 1 for the same data.
--
-- Fix: move guest=false into the LEFT JOIN's ON clause so a guest-only match
-- leaves crst NULL (counted as outstanding) instead of dropping the row.
-- dnf stays exactly where it was, in the WHERE clause - that part was never
-- wrong.
CREATE OR REPLACE VIEW private.view_missing_cr_age_report5
AS WITH reservation_stats AS (
         SELECT vrcs.cr_name,
            count(*) AS total_reservations
           FROM private.view_reservations_confirmed_staging vrcs
             LEFT JOIN private.catch_returns_staging_table crst
                ON vrcs.date = crst.catch_date
               AND vrcs.cr_name = crst.rod_name
               AND vrcs.beat = crst.beat
               AND crst.guest = false
          WHERE crst.dnf IS DISTINCT FROM true AND vrcs.date < CURRENT_DATE
          GROUP BY vrcs.cr_name
        ), catch_returns_stats AS (
         SELECT vrcs.cr_name,
            sum(
                CASE
                    WHEN crst.rod_name IS NOT NULL THEN 1
                    ELSE 0
                END) AS total_submitted,
            count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) >= 1 AND (CURRENT_DATE - vrcs.date) <= 7) AS "1-7 Days",
            count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) >= 8 AND (CURRENT_DATE - vrcs.date) <= 14) AS "8-14 Days",
            count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) >= 15 AND (CURRENT_DATE - vrcs.date) <= 21) AS "15-21 Days",
            count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) >= 22 AND (CURRENT_DATE - vrcs.date) <= 28) AS "22-28 Days",
            count(*) FILTER (WHERE crst.rod_name IS NULL AND (CURRENT_DATE - vrcs.date) > 28) AS "28+ Days"
           FROM private.view_reservations_confirmed_staging vrcs
             LEFT JOIN private.catch_returns_staging_table crst
                ON vrcs.date = crst.catch_date
               AND vrcs.cr_name = crst.rod_name
               AND vrcs.beat = crst.beat
               AND crst.guest = false
          WHERE crst.dnf IS DISTINCT FROM true AND vrcs.date < CURRENT_DATE
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
  WHERE (COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint)) > 0
  ORDER BY (COALESCE(res.total_reservations, 0::bigint) - COALESCE(crs.total_submitted, 0::bigint)) DESC;
