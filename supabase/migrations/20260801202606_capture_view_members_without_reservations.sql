create or replace view "private"."view_members_without_reservations_current_year" as  SELECT id,
    cr_name,
    email_address,
    member_name,
    year_of_membership
   FROM private.members m
  WHERE ((year_of_membership = ( SELECT (club_settings.value_hash)::integer AS value_hash
           FROM private.club_settings
          WHERE (club_settings.key = 'current_member_year'::text)
         LIMIT 1)) AND (NOT (EXISTS ( SELECT 1
           FROM private.reservations_confirmed_staging r
          WHERE (r.cr_name ~~* m.cr_name)))));
