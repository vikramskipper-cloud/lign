-- Local-only harness setup for tests/realtime/*.mjs. NEVER run against production.
--
-- Compensates for two things the migration set does not carry, because they are
-- Supabase platform state applied at project creation rather than by migrations:
--
--  1. DML GRANTs to anon/authenticated/service_role. Production has
--     SELECT/INSERT/UPDATE/DELETE on every public table for `authenticated`;
--     a fresh replay has only REFERENCES/TRIGGER/TRUNCATE, so every request
--     fails with 42501 before RLS is ever consulted.
--  2. A usable password on a fixture auth user (storage_003_test_fixtures
--     creates them with an empty encrypted_password).
--
-- See docs/APP_011_IMPLEMENTATION_REPORT.md for the grants gap this exposed.

grant usage on schema public to anon, authenticated, service_role;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on all tables in schema public to anon;
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to anon, authenticated, service_role;
grant execute on all functions in schema public to anon, authenticated, service_role;

create extension if not exists pgcrypto with schema extensions;
update auth.users
   set encrypted_password     = extensions.crypt('LignProbe!2026', extensions.gen_salt('bf')),
       email_confirmed_at     = coalesce(email_confirmed_at, now()),
       confirmation_token     = coalesce(confirmation_token, ''),
       recovery_token         = coalesce(recovery_token, ''),
       email_change_token_new = coalesce(email_change_token_new, ''),
       email_change           = coalesce(email_change, ''),
       raw_app_meta_data      = coalesce(raw_app_meta_data, '{}'::jsonb)
                                || '{"provider":"email","providers":["email"]}'::jsonb
 where email = 'p_lead@lign.test';
