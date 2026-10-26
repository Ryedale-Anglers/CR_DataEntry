-- Members of the year_param target_year with no reservation from 1 April to
-- 30 September of that year, for the in-season compliance report v2
-- (generate_in_season_compliance_report_v2.py). v1
-- (view_members_without_season_reservations) is unchanged.
--
-- Sorted by surname. member_name is "initials surname" (e.g. "M A CHARLTON - WEEDY"),
-- so the surname is the name with its leading single-letter initials removed. A
-- name with no initials (e.g. "Frank Collin") uses its last word.

CREATE OR REPLACE VIEW private.view_members_without_season_reservations_v2 AS
SELECT m.member_name,
       m.cr_name,
       m.email_address
FROM private.members m
CROSS JOIN (SELECT target_year FROM private.year_param WHERE id = 1) yp
WHERE m.year_of_membership = yp.target_year
  AND NOT EXISTS (
      SELECT 1
      FROM private.reservations_confirmed_staging rcs
      WHERE rcs.cr_name = m.cr_name
        AND rcs.date BETWEEN make_date(yp.target_year, 4, 1)
                         AND make_date(yp.target_year, 9, 30))
ORDER BY upper(CASE
                   WHEN trim(m.member_name) ~ '^\S\.?\s'
                       THEN regexp_replace(trim(m.member_name), '^(\S\.?\s+)+', '')
                   ELSE regexp_replace(trim(m.member_name), '^.*\s', '')
               END),
         m.member_name;
