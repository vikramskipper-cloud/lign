-- PLATFORM 001: codify the table privileges the application depends on.
--
-- WHY THIS EXISTS
--
-- Until now these GRANTs were Supabase platform state, applied at project
-- creation and never emitted by a migration. Discovered 2026-09-18 during APP
-- 011 behavioural testing: a pristine replay of the full migration set grants
-- anon / authenticated / service_role NO SELECT, INSERT, UPDATE or DELETE on
-- any of the 32 public tables (96 grant pairs, zero holding SELECT). Every
-- request against such a rebuild fails with SQLSTATE 42501 *before RLS is ever
-- consulted* -- the application is completely non-functional.
--
-- That made the migration set unable to rebuild the system: disaster recovery,
-- a staging environment, or onboarding a second developer would all have
-- produced a dead database. See docs/APP_011_IMPLEMENTATION_REPORT.md §3.
--
-- APPLYING THIS TO PRODUCTION CHANGES NOTHING. Production already holds every
-- privilege below; this is a no-op there and the fix everywhere else.
--
-- WHAT THIS DELIBERATELY DOES NOT DO
--
-- It does NOT grant EXECUTE on functions. 27 of the 160 functions in `public`
-- deliberately withhold EXECUTE from anon/authenticated -- SECURITY DEFINER
-- trigger functions and service_role-only operators such as
-- enforce_requirement_hierarchy, resolve_notification_router_targets,
-- handle_new_auth_user and list_purgeable_files, each hardened by an explicit
-- REVOKE in its own migration. A blanket
-- `grant execute on all functions ... to authenticated` would re-grant all 27
-- and silently undo that hardening across AUTH, STORAGE, REQUIREMENTS and
-- APP 006-010. Function privileges already replay correctly, because every
-- migration grants or revokes per function at the point of creation.
--
-- ALTER DEFAULT PRIVILEGES below is safe for the same reason it is useful: it
-- applies only to objects created AFTER it runs, so it cannot affect an
-- existing REVOKE. It mirrors the default privileges production already
-- carries, so a future migration's tables inherit the same grants there and in
-- a rebuild alike.
--
-- SCOPE NOTE (not a change, an observation)
--
-- This replicates production exactly rather than improving on it. That
-- includes `anon` holding full DML and TRUNCATE on every table. RLS is the
-- authorization boundary in Supabase's model and every table has RLS enabled
-- with policies, so DML is governed -- but TRUNCATE is NOT subject to RLS, and
-- is blocked only by PostgREST exposing no TRUNCATE verb. Tightening that is a
-- deliberate security decision, out of scope for a migration whose purpose is
-- to make replay faithful. Recorded for the architect.

grant usage on schema public to anon, authenticated, service_role;

grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;

alter default privileges in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public
  grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public
  grant execute on functions to anon, authenticated, service_role;
