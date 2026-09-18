-- Migration 001: foundation_profiles
-- Foundational infrastructure required before any LIGN domain table can be created.
-- See supabase/migrations/20260728160001_foundation_profiles.sql for full documentation.

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

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row
  execute function public.set_updated_at();

------------------------------------------------------------------------------
-- 4. Auth signup -> profile creation
------------------------------------------------------------------------------

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

alter table public.profiles enable row level security;