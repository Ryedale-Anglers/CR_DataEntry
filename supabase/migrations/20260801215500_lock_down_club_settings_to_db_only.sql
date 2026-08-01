-- private.club_settings holds the shared club password hash and the current
-- season year. RLS is enabled with zero policies, so anon/authenticated are
-- already blocked, and the private schema isn't exposed via PostgREST, so
-- service_role (which bypasses RLS) has no route to the table either. All
-- legitimate read access goes through SECURITY DEFINER RPCs (verify_club_password,
-- get_member_info_for_email, etc.) owned by postgres, which bypass RLS via table
-- ownership regardless of these grants. The grants are leftover from a dashboard
-- change on 2026-07-13 and are not required by any code path.
REVOKE ALL PRIVILEGES ON TABLE private.club_settings FROM anon, authenticated, service_role;
