-- Sort private.view_members_without_season_reservations by surname (the last
-- whitespace-separated word in member_name, e.g. "GILLHAM" in "A J GILLHAM")
-- rather than by the whole member_name string, while still displaying the
-- full member_name. Wrapped in upper() so case differences in how a name
-- happens to be stored (e.g. "Fred Collin" vs "A J GILLHAM") don't affect
-- sort order. Column list is unchanged - member_name only.
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
   ORDER BY upper(regexp_replace(trim(m.member_name), '^.*\s', ''));
