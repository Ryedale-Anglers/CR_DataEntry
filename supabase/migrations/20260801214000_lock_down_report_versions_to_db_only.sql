-- public.report_versions is only ever read/written by ETL scripts connecting
-- directly with the database password (see etl_reload_beats_members_cr_from_sqlite.py
-- and generate_in_season_catchreturn_compliance_report.py). It has no PostgREST/API
-- consumer, so the anon/authenticated/service_role grants it picked up from a dashboard
-- change on 2026-07-13 are unintended — service_role in particular bypasses RLS, so it
-- had working API access despite RLS being enabled on this table.
REVOKE ALL PRIVILEGES ON TABLE public.report_versions FROM anon, authenticated, service_role;
