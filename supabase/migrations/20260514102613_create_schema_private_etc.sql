CREATE SCHEMA private;
ALTER TABLE public.club_settings SET SCHEMA private;
ALTER TABLE public.members SET SCHEMA private;

-- Allow the service_role (and authenticated users) to see the schema
GRANT USAGE ON SCHEMA private TO service_role;
GRANT USAGE ON SCHEMA private TO authenticated;

-- Allow the service_role to do everything inside this schema
GRANT ALL ON ALL TABLES IN SCHEMA private TO service_role;
GRANT ALL ON ALL SEQUENCES IN SCHEMA private TO service_role;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA private TO service_role;

GRANT USAGE ON SCHEMA private TO postgres;
GRANT SELECT ON private.club_settings TO postgres;

-- Allow the Edge Function's role to run the function
GRANT EXECUTE ON FUNCTION verify_club_password(TEXT) TO service_role;


create or replace view public.view_member_names 
WITH (security_invoker = false) 
as 
select id, cr_name, member_name, year_of_membership
from private.members;

-- 2. Grant access so the public API can see the names
GRANT SELECT ON public.view_member_names TO anon;