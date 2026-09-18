-- Local-only harness setup for tests/realtime/*.mjs. NEVER run against production.
--
-- As of migration 20260818180000_platform_001_role_grants the DML GRANTs this
-- file used to apply are carried by the migration set itself, so only the auth
-- fixture remains: storage_003_test_fixtures creates its users with an empty
-- encrypted_password, which GoTrue cannot authenticate against.
--
-- Two identities are needed: the notification router excludes the actor, so
-- observing a notification payload requires a writer (p_lead) and a distinct
-- recipient (p_reviewer).
--
-- If a probe starts failing with SQLSTATE 42501 again, that means PLATFORM 001
-- stopped being applied -- fix the migration, do not re-add grants here.

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
 where email in ('p_lead@lign.test', 'p_reviewer@lign.test');
