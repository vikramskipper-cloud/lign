-- Migration 001: foundation_profiles
--
-- Foundational infrastructure required before any LIGN domain table can be
-- created. Scope is intentionally minimal.
--
-- Contents:
--   1. citext extension (schema: extensions). Required by profiles.email and
--      by many downstream tables per DATABASE_SCHEMA.md v0.3.
--   2. public.set_updated_at() trigger function. Reused by every LIGN table
--      that carries an updated_at column.
--   3. public.profiles table. DATABASE_SCHEMA.md v0.3 §3.1.
--   4. public.handle_new_auth_user() trigger function + on_auth_user_created
--      trigger on auth.users. Creates the LIGN profile on Supabase Auth
--      signup. SECURITY DEFINER with pinned empty search_path.
--   5. RLS enabled on public.profiles as the secure baseline. No policies
--      are created here; policies land in the dedicated authorization stage.
--
-- Explicit non-goals (deferred per implementation plan):
--   - No workspaces / memberships / stakeholders / projects / etc.
--   - No capability functions, RPCs, or business triggers.
--   - No storage buckets, cron jobs, or notification infrastructure.
--   - No RLS policies on profiles (RLS is enabled without policies; direct
--     client access is intentionally unavailable until the auth stage lands).
--
-- Historical-retention note:
--   profiles.id references auth.users(id) with ON DELETE RESTRICT — a
--   deliberate deviation from the standard Supabase quickstart's ON DELETE
--   CASCADE. Per DOMAIN_MODEL.md §0 (Historical attribution) and
--   DATABASE_SCHEMA.md v0.3 §3.1, deletion of an auth.users row is blocked
--   while a LIGN profile exists. Profile purge is a deliberate admin
--   operation, not a cascade.
--
-- Transaction control:
--   No explicit BEGIN/COMMIT here. The Supabase migration runner (CLI and
--   MCP apply_migration) wraps each migration in its own transaction.

------------------------------------------------------------------------------
-- 1. Extensions
------------------------------------------------------------------------------

create extension if not exists citext with schema extensions;

------------------------------------------------------------------------------
-- 2. Reusable updated_at trigger function
------------------------------------------------------------------------------

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function public.set_updated_at() is
  'Sets NEW.updated_at = now() on UPDATE. Reusable trigger function for every LIGN table carrying an updated_at column.';

------------------------------------------------------------------------------
-- 3. profiles table (DATABASE_SCHEMA.md v0.3 §3.1)
------------------------------------------------------------------------------

create table public.profiles (
  id             uuid                    primary key
                                         references auth.users (id)
                                         on delete restrict,
  email          extensions.citext       not null,
  display_name   text                    not null,
  avatar_url     text                    null,
  status         text                    not null default 'active',
  deactivated_at timestamptz             null,
  created_at     timestamptz             not null default now(),
  updated_at     timestamptz             not null default now(),

  constraint profiles_email_key    unique (email),
  constraint profiles_status_check check (status in ('provisioned','active','deactivated'))
);

comment on table  public.profiles is
  'LIGN identity record, 1:1 with auth.users. Primary attribution anchor for every authored row. DATABASE_SCHEMA.md v0.3 §3.1.';
comment on column public.profiles.id is
  'auth.users(id). ON DELETE RESTRICT — auth deletion is blocked while a LIGN profile exists. Deliberate deviation from Supabase quickstart CASCADE, per historical-retention rule in DOMAIN_MODEL.md §0.';
comment on column public.profiles.email is
  'Denormalized from auth.users.email. Kept in sync by the auth-signup trigger; profile updates do not currently propagate to auth.';
comment on column public.profiles.status is
  'Lifecycle: provisioned -> active -> deactivated. Never hard-deleted while authored history exists.';

-- updated_at trigger
drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row
  execute function public.set_updated_at();

------------------------------------------------------------------------------
-- 4. Auth signup -> profile creation
------------------------------------------------------------------------------
--
-- Creates one public.profiles row per new auth.users row.
--
-- SECURITY DEFINER because auth.users INSERTs are performed by the
-- supabase_auth_admin role, which does not have INSERT on public.profiles.
-- Every schema object is fully qualified and search_path is pinned to ''
-- to prevent schema-hijack against the elevated privilege.
--
-- Identity fields (id, email) come from the auth.users NEW row and are never
-- taken from client-supplied metadata. Display name is derived from optional
-- metadata with a safe fallback and can be edited later by the profile owner.
--
-- MVP requires an email on the auth.users row. Phone-only signups are out
-- of scope for MVP; the trigger raises rather than silently creating a
-- malformed profile.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_email        extensions.citext;
  v_display_name text;
  v_avatar_url   text;
begin
  if new.email is null then
    raise exception 'handle_new_auth_user: auth.users.email is null; LIGN requires an email-based identity'
      using errcode = '22004';
  end if;

  v_email := new.email::extensions.citext;

  v_display_name := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
    split_part(new.email, '@', 1)
  );

  v_avatar_url := nullif(trim(new.raw_user_meta_data ->> 'avatar_url'), '');

  insert into public.profiles (id, email, display_name, avatar_url, status)
  values (new.id, v_email, v_display_name, v_avatar_url, 'active');

  return new;
end;
$$;

comment on function public.handle_new_auth_user() is
  'Creates a public.profiles row on auth.users INSERT. SECURITY DEFINER with pinned empty search_path. Establishes LIGN identity only; does not create workspaces or memberships. Rejects phone-only signups (email required for MVP).';

-- Harden the SECURITY DEFINER function: it should only ever run via the
-- trigger, not by direct call from application roles.
revoke all on function public.handle_new_auth_user() from public;
revoke all on function public.handle_new_auth_user() from anon;
revoke all on function public.handle_new_auth_user() from authenticated;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row
  execute function public.handle_new_auth_user();

------------------------------------------------------------------------------
-- 5. RLS baseline
------------------------------------------------------------------------------
--
-- RLS is enabled here as the secure baseline. No policies are created; the
-- dedicated authorization migration stage will introduce them per
-- PERMISSIONS.md §8 Group A. Direct client SELECT/UPDATE on public.profiles
-- is intentionally unavailable during the intervening stages.

alter table public.profiles enable row level security;
