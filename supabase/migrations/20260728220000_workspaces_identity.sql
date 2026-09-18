-- Migration 002: workspaces_identity
-- Identity/tenancy foundation. See supabase/migrations/20260728220000_workspaces_identity.sql
-- for full documentation and rationale.

------------------------------------------------------------------------------
-- 1. Migration 001 hardening: pin set_updated_at search_path
------------------------------------------------------------------------------

alter function public.set_updated_at() set search_path = '';

------------------------------------------------------------------------------
-- 2. workspaces (DATABASE_SCHEMA.md v0.3 §3.2)
------------------------------------------------------------------------------

create table public.workspaces (
  id          uuid                    primary key default gen_random_uuid(),
  name        text                    not null,
  slug        extensions.citext       not null,
  status      text                    not null default 'active',
  settings    jsonb                   not null default '{}'::jsonb,
  archived_at timestamptz             null,
  created_at  timestamptz             not null default now(),
  updated_at  timestamptz             not null default now(),

  constraint workspaces_slug_key     unique (slug),
  constraint workspaces_status_check check (status in ('active','suspended','archived'))
);

comment on table public.workspaces is
  'Tenant boundary. Every LIGN row (except profiles) chains back to a workspace via workspace_id. DATABASE_SCHEMA.md v0.3 §3.2.';
comment on column public.workspaces.slug is
  'Human-facing URL slug. Never a substitute for the UUID identity.';
comment on column public.workspaces.settings is
  'Open-ended workspace config (branding, features). The only JSONB entry point on this table.';

drop trigger if exists workspaces_set_updated_at on public.workspaces;
create trigger workspaces_set_updated_at
  before update on public.workspaces
  for each row execute function public.set_updated_at();

alter table public.workspaces enable row level security;

------------------------------------------------------------------------------
-- 3. workspace_members (DATABASE_SCHEMA.md v0.3 §3.3)
------------------------------------------------------------------------------

create table public.workspace_members (
  id             uuid        primary key default gen_random_uuid(),
  workspace_id   uuid        not null references public.workspaces (id) on delete restrict,
  user_id        uuid        not null references public.profiles (id)   on delete restrict,
  role           text        not null,
  status         text        not null default 'invited',
  invited_at     timestamptz not null default now(),
  activated_at   timestamptz null,
  removed_at     timestamptz null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint workspace_members_role_check   check (role in ('owner','admin','member')),
  constraint workspace_members_status_check check (status in ('invited','active','suspended','removed')),

  constraint workspace_members_workspace_user_key unique (workspace_id, user_id),
  constraint workspace_members_id_workspace_key   unique (id, workspace_id)
);

comment on table public.workspace_members is
  'Organizational membership of a Profile in a Workspace, with a workspace role. Distinct from project participation. DATABASE_SCHEMA.md v0.3 §3.3.';
comment on column public.workspace_members.user_id is
  'FK to profiles(id). Immutable after insert (trigger-enforced). Role and status remain mutable.';

create index workspace_members_user_id_idx           on public.workspace_members (user_id);
create index workspace_members_workspace_status_idx  on public.workspace_members (workspace_id, status);

drop trigger if exists workspace_members_set_updated_at on public.workspace_members;
create trigger workspace_members_set_updated_at
  before update on public.workspace_members
  for each row execute function public.set_updated_at();

create or replace function public.enforce_workspace_members_user_id_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.user_id is distinct from old.user_id then
    raise exception 'workspace_members.user_id is immutable after insert (row id=%)', old.id
      using errcode = '23514';
  end if;
  return new;
end;
$$;

comment on function public.enforce_workspace_members_user_id_immutable() is
  'DB-boundary trigger: rejects UPDATE that changes workspace_members.user_id. Identity behind a membership row cannot be reassigned. PERMISSIONS.md §13 rule 9.';

drop trigger if exists workspace_members_user_id_immutable on public.workspace_members;
create trigger workspace_members_user_id_immutable
  before update on public.workspace_members
  for each row execute function public.enforce_workspace_members_user_id_immutable();

alter table public.workspace_members enable row level security;

------------------------------------------------------------------------------
-- 4. stakeholders (DATABASE_SCHEMA.md v0.3 §3.4)
------------------------------------------------------------------------------

create table public.stakeholders (
  id             uuid                    primary key default gen_random_uuid(),
  workspace_id   uuid                    not null references public.workspaces (id) on delete restrict,
  email          extensions.citext       not null,
  display_name   text                    null,
  user_id        uuid                    null references public.profiles (id) on delete restrict,
  status         text                    not null default 'invited',
  invited_at     timestamptz             not null default now(),
  revoked_at     timestamptz             null,
  created_at     timestamptz             not null default now(),
  updated_at     timestamptz             not null default now(),

  constraint stakeholders_status_check         check (status in ('invited','active','revoked')),

  constraint stakeholders_workspace_email_key  unique (workspace_id, email),
  constraint stakeholders_id_workspace_key     unique (id, workspace_id)
);

create unique index stakeholders_workspace_user_key
  on public.stakeholders (workspace_id, user_id)
  where user_id is not null;

create index stakeholders_user_id_idx
  on public.stakeholders (user_id)
  where user_id is not null;

comment on table public.stakeholders is
  'Workspace-scoped external identity, deduped by (workspace_id, email). May later link to a profiles row via user_id (invitation-scoped claim). Coexists with — never merges into — workspace_members. DATABASE_SCHEMA.md v0.3 §3.4.';
comment on column public.stakeholders.user_id is
  'Optional FK to profiles(id). Populated on invitation-scoped claim. Never implies workspace membership.';

drop trigger if exists stakeholders_set_updated_at on public.stakeholders;
create trigger stakeholders_set_updated_at
  before update on public.stakeholders
  for each row execute function public.set_updated_at();

alter table public.stakeholders enable row level security;

------------------------------------------------------------------------------
-- 5. invitations (DATABASE_SCHEMA.md v0.3 §3.5)
------------------------------------------------------------------------------

create table public.invitations (
  id                       uuid                    primary key default gen_random_uuid(),
  workspace_id             uuid                    not null references public.workspaces (id) on delete cascade,
  email                    extensions.citext       not null,
  kind                     text                    not null,
  role                     text                    null,
  invited_by_profile_id    uuid                    null references public.profiles (id) on delete set null,
  status                   text                    not null default 'sent',
  token_hash               text                    not null,
  expires_at               timestamptz             not null,
  accepted_at              timestamptz             null,
  created_at               timestamptz             not null default now(),
  updated_at               timestamptz             not null default now(),

  constraint invitations_kind_check   check (kind in ('workspace_member','stakeholder')),
  constraint invitations_status_check check (status in ('sent','accepted','expired','revoked'))
);

comment on table public.invitations is
  'Pending email invites to become a workspace_members row or a stakeholders row. workspace_id CASCADE: invitations are not history. Tokens stored as hashes only. DATABASE_SCHEMA.md v0.3 §3.5.';
comment on column public.invitations.token_hash is
  'Opaque hash of the invitation token. The plaintext token is never stored in the database.';
comment on column public.invitations.role is
  'Workspace role for workspace_member invites; expected null for stakeholder invites. No CHECK constraint per DATABASE_SCHEMA.md — enforced at application layer.';

create unique index invitations_active_key
  on public.invitations (workspace_id, email, kind)
  where status = 'sent';

create index invitations_workspace_status_idx on public.invitations (workspace_id, status);
create index invitations_token_hash_idx       on public.invitations (token_hash);

drop trigger if exists invitations_set_updated_at on public.invitations;
create trigger invitations_set_updated_at
  before update on public.invitations
  for each row execute function public.set_updated_at();

alter table public.invitations enable row level security;