-- One shared view that gives every staging reservation a catch return status, and a v2
-- of the secretary's member summary that counts each status per member.
--
-- private.view_reservation_return_status_staging: one row per reservation in
-- private.view_reservations_confirmed_staging. A return matches a reservation on
-- member (rod_name = cr_name), date and beat, as in the existing views.
-- return_status is exactly one of:
--   member_return  the member's own return (guest = false, dnf = false)
--   dnf            the member's own return marked Did Not Fish
--   guest_only     no member return, but one or more guest returns
--   missing        no return of any kind, and the reservation date has passed
--   upcoming       no return of any kind, reservation is today or later
-- The statuses cannot overlap: uq_cr_staging_member_date_beat allows only one member
-- return per reservation, a guest return cannot be DNF, and marking the member's
-- return DNF deletes its guest returns (20260929120000). guest_returns counts the
-- guest returns on the reservation whatever its status.
--
-- private.view_secrep_membername_catchreturns_count_operational_v2: per member, for
-- reservations in the year_param season (target_start_date to target_end_date).
-- reservations_count = member_returns + dnf + guest_only + missing + upcoming.
-- member_returns_missing = guest_only + missing (the member has not sent their own).
-- Unlike v1, DNF reservations are counted (in their own column) rather than dropped,
-- and reservations not yet fished are shown as upcoming rather than outstanding.
-- v1 and view_missing_cr_age_report5 are unchanged.

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
           WHEN vrcs.date < CURRENT_DATE             THEN 'missing'
           ELSE 'upcoming'
       END AS return_status
FROM private.view_reservations_confirmed_staging vrcs
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
) g;

CREATE OR REPLACE VIEW private.view_secrep_membername_catchreturns_count_operational_v2 AS
SELECT s.cr_name,
       count(*)                                                          AS reservations_count,
       count(*) FILTER (WHERE s.return_status = 'member_return')         AS member_returns,
       count(*) FILTER (WHERE s.return_status = 'dnf')                   AS dnf,
       count(*) FILTER (WHERE s.return_status = 'guest_only')            AS guest_only,
       count(*) FILTER (WHERE s.return_status = 'missing')               AS missing,
       count(*) FILTER (WHERE s.return_status = 'upcoming')              AS upcoming,
       count(*) FILTER (WHERE s.return_status IN ('guest_only', 'missing')) AS member_returns_missing
FROM private.view_reservation_return_status_staging s
CROSS JOIN (SELECT target_start_date, target_end_date FROM private.year_param WHERE id = 1) yp
WHERE s.date BETWEEN yp.target_start_date AND yp.target_end_date
GROUP BY s.cr_name
ORDER BY member_returns_missing DESC, reservations_count DESC, s.cr_name;
