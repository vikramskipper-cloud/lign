-- ============================================================================
--  TEST FIXTURE ONLY — NEVER RUN THIS AGAINST A REAL WORKSPACE
-- ============================================================================
--
-- Gives every stakeholder in the project a working login with ONE SHARED
-- PASSWORD, so people added through the New project dialog can sign in and be
-- clicked through without an invite link.
--
-- WHY THIS IS A SCRIPT AND NOT A FEATURE
--
-- Provisioning an account with a known shared password, pre-confirmed, is a
-- complete authentication bypass for anyone who can guess the address. It is
-- acceptable here only because every fixture lives on the `.test` TLD, which
-- is reserved by RFC 2606 and can never receive mail or belong to a real
-- person. The moment a real client email is added to a workspace, running this
-- hands that person's account to anyone who knows the password.
--
-- So it lives in ops/, is never imported by the app, and is not a migration.
-- The real path is /invite/:token -> claim_stakeholder_invitation(), which
-- this deliberately imitates rather than replaces.
--
-- WHAT IT DOES, per stakeholder that has no user_id yet:
--   1. reuses an existing auth.users row for that email, or creates one
--   2. sets stakeholders.user_id and status='active'
--   3. marks their pending invitation accepted
--   4. writes the same 'stakeholder.claimed' event the real claim writes
--
-- so the end state is indistinguishable from someone having opened the link.
-- Idempotent: re-run it after adding more emails.
--
-- USAGE
--   psql "$SUPABASE_DB_URL" -v password="'LignTest!2026'" -f ops/provision_test_logins.sql
--   -- or paste it, editing the default below.
--
-- ============================================================================

\set ON_ERROR_STOP on
\if :{?password}
\else
\set password '''LignTest!2026'''
\endif

begin;

-- Refuse to run anywhere that is not obviously a fixture environment. Every
-- stakeholder without a login must be on .test; one real address aborts the
-- whole thing rather than provisioning a bypass for a real person.
do $$
declare v_bad text;
begin
  select string_agg(email::text, ', ') into v_bad
    from public.stakeholders
   where user_id is null
     and status <> 'revoked'
     and email::text not like '%.test';
  if v_bad is not null then
    raise exception
      'provision_test_logins: refusing to run — these are not .test addresses: %', v_bad
      using errcode = '42501';
  end if;
end $$;

with candidates as (
  select s.id as stakeholder_id, s.workspace_id, lower(s.email::text) as email
    from public.stakeholders s
   where s.user_id is null
     and s.status <> 'revoked'
),
-- An auth user may already exist for the address (they were a member once, or
-- a stakeholder in another workspace). Reuse it; never create a second
-- identity for one human.
resolved as (
  select c.*, u.id as existing_user_id
    from candidates c
    left join auth.users u on lower(u.email) = c.email
),
created as (
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    -- GoTrue scans these into non-nullable Go strings: NULL here produces
    -- "Database error querying schema" at sign-in, not a helpful message.
    confirmation_token, recovery_token, email_change, email_change_token_new
  )
  select
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(),
    'authenticated', 'authenticated',
    r.email,
    extensions.crypt(:password, extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('display_name', initcap(replace(split_part(r.email,'@',1), '.', ' '))),
    now(), now(),
    '', '', '', ''
  from (select distinct email from resolved where existing_user_id is null) r
  returning id, lower(email) as email
),
all_users as (
  select email, existing_user_id as user_id from resolved where existing_user_id is not null
  union
  select email, id from created
),
linked as (
  update public.stakeholders s
     set user_id = a.user_id,
         status  = 'active'
    from resolved r join all_users a on a.email = r.email
   where s.id = r.stakeholder_id
  returning s.id as stakeholder_id, s.workspace_id, s.user_id, s.email::text as email
),
accepted as (
  update public.invitations i
     set status = 'accepted', accepted_at = now()
    from linked l
   where i.workspace_id = l.workspace_id
     and lower(i.email::text) = lower(l.email)
     and i.kind = 'stakeholder'
     and i.status = 'sent'
  returning i.id
)
insert into public.activity_events (
  workspace_id, project_id, occurred_at, event_type,
  actor_profile_id, actor_kind,
  subject_kind, subject_id, subject_label, subject_snapshot, payload
)
select l.workspace_id, null, now(), 'stakeholder.claimed',
       l.user_id, 'user',
       'stakeholder', l.stakeholder_id, l.email,
       jsonb_build_object('provisioned_by', 'ops/provision_test_logins.sql'),
       jsonb_build_object('capacity', 'external', 'test_fixture', true)
  from linked l;

commit;

-- Who can now sign in, and as what.
select s.email::text as login,
       w.name        as workspace,
       s.status,
       string_agg(distinct pr.name, ', ') as projects
  from public.stakeholders s
  join public.workspaces w on w.id = s.workspace_id
  left join public.project_participants pp
         on pp.stakeholder_id = s.id and pp.status = 'active'
  left join public.projects pr on pr.id = pp.project_id
 where s.user_id is not null
 group by 1, 2, 3
 order by 1;
