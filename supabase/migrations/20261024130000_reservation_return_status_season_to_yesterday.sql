-- Limit the reservation return status views to reservations that are due a return:
-- in the trout season (year_param target_start_date to target_end_date, 1 April to
-- 30 September) and dated no later than yesterday. Members are not expected to enter
-- a return until the day after they fish, so today's and future reservations, and any
-- returns for them, are left out. This removes the 'upcoming' status, so the v2
-- summary loses its upcoming column (dropped and recreated; nothing else uses it yet).
-- Statuses are now: member_return, dnf, guest_only, missing.

DROP VIEW IF EXISTS private.view_secrep_membername_catchreturns_count_operational_v2;

CREATE OR REPLACE VIEW private.view_reservation_return_status_staging AS
SELECT vrcs.id   AS reservation_id,
       vrcs.date,
       vrcs.cr_name,
       vrcs.name AS booking_name,
       vrcs.beat_id,
       vrcs.beat,
       vrcs.river_order,
       mr.id     AS member_return_id,
       g.guest_returns,
       CASE
           WHEN mr.id IS NOT NULL AND mr.dnf IS TRUE THEN 'dnf'
           WHEN mr.id IS NOT NULL                    THEN 'member_return'
           WHEN g.guest_returns > 0                  THEN 'guest_only'
           ELSE 'missing'
       END AS return_status
FROM private.view_reservations_confirmed_staging vrcs
CROSS JOIN (SELECT target_start_date, target_end_date FROM private.year_param WHERE id = 1) yp
LEFT JOIN private.catch_returns_staging_table mr
       ON mr.guest = false
      AND mr.rod_name   = vrcs.cr_name
      AND mr.catch_date = vrcs.date
      AND mr.beat       = vrcs.beat
CROSS JOIN LATERAL (
    SELECT count(*) AS guest_returns
    FROM private.catch_returns_staging_table gr
    WHERE gr.guest = true
      AND gr.rod_name   = vrcs.cr_name
      AND gr.catch_date = vrcs.date
      AND gr.beat       = vrcs.beat
) g
WHERE vrcs.date >= yp.target_start_date
  AND vrcs.date <= LEAST(yp.target_end_date, CURRENT_DATE - 1);

CREATE VIEW private.view_secrep_membername_catchreturns_count_operational_v2 AS
SELECT s.cr_name,
       count(*)                                                             AS reservations_count,
       count(*) FILTER (WHERE s.return_status = 'member_return')            AS member_returns,
       count(*) FILTER (WHERE s.return_status = 'dnf')                      AS dnf,
       count(*) FILTER (WHERE s.return_status = 'guest_only')               AS guest_only,
       count(*) FILTER (WHERE s.return_status = 'missing')                  AS missing,
       count(*) FILTER (WHERE s.return_status IN ('guest_only', 'missing')) AS member_returns_missing
FROM private.view_reservation_return_status_staging s
GROUP BY s.cr_name
ORDER BY member_returns_missing DESC, reservations_count DESC, s.cr_name;
