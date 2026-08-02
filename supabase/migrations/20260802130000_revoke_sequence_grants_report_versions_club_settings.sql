-- REVOKE ON TABLE (20260801214000, 20260801215500) didn't cover the identity
-- sequences backing these tables - sequences are separate grantable objects
-- with their own privileges, left over from the same 2026-07-13 dashboard
-- session as the table grants. Currently inert (table INSERT is already
-- revoked, and RLS blocks anon/authenticated on club_settings regardless),
-- but same landmine reasoning as before: don't leave API-role privileges
-- sitting on objects that are only meant to be reachable via a direct DB
-- connection.
REVOKE ALL PRIVILEGES ON SEQUENCE private.club_settings_id_seq FROM anon, authenticated, service_role;
REVOKE ALL PRIVILEGES ON SEQUENCE public.report_versions_id_seq FROM anon, authenticated, service_role;
