-- New section for the in-season compliance report: members who have made no
-- reservation at all during the current season, so the secretary can follow
-- up on members who haven't engaged yet (as distinct from members who have
-- reservations but haven't submitted a catch return, which the other two
-- report sections already cover).
--
-- Deliberately a new view rather than reusing private.view_members_without_
-- reservations_current_year (created 2026-08-01, unreferenced anywhere): that
-- one keys off club_settings.current_member_year and has no season-date
-- bound at all, just "ever has a reservations_confirmed_staging row". This
-- one uses year_param for both the membership year and the season's
-- start/end dates, matching every other report view's convention.
--
-- A member with only a Synthetic reservation (e.g. from a self-attested
-- catch return with no real booking) still counts as "has a reservation" -
-- consistent with how the rest of the app treats Synthetic and real
-- reservations identically (no distinction exposed anywhere else either).
CREATE OR REPLACE VIEW private.view_members_without_season_reservations
AS SELECT m.member_name
   FROM private.members m
   CROSS JOIN private.year_param yp
   WHERE m.year_of_membership = yp.target_year
     AND NOT EXISTS (
         SELECT 1
         FROM private.reservations_confirmed_staging rcs
         WHERE rcs.cr_name = m.cr_name
           AND rcs.date BETWEEN yp.target_start_date AND yp.target_end_date
     )
   ORDER BY m.member_name;
