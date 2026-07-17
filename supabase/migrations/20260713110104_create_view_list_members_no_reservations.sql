create view private.view_members_without_reservations_current_year as
SELECT *
FROM private.members m
WHERE m.year_of_membership = (
    SELECT value_hash::integer 
    FROM private.club_settings 
    WHERE key = 'current_member_year' 
    LIMIT 1
)
AND NOT EXISTS (
    SELECT 1
    FROM private.reservations_confirmed_staging r
    WHERE r.cr_name iLike m.cr_name
);