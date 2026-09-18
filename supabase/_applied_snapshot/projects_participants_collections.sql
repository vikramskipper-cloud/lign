-- Migration 003: projects_participants_collections
-- Project tier (projects, project_participants, collections) + Migration 002 FK-index hardening.
-- See supabase/migrations/20260729140000_projects_participants_collections.sql for documentation.

------------------------------------------------------------------------------
-- 0. Migration 002 hardening
------------------------------------------------------------------------------

create index if not exists invitations_invited_by_profile_id_idx
  on public.invitations (invited_by_profile_id)
  where invited_by_profile_id is not null;

------------------------------------------------------------------------------
-- 1. projects
------------------------------------------------------------------------------

create table public.projects (
  id                     uuid                    primary key default gen_random_uuid(),
  workspace_id           uuid                    not null references public.workspaces (id) on delete restrict,
  name                   text                    not null,
  slug                   extensions.citext       not null,
  description            text                    null,
  status                 text                    not null default 'draft',
  code                   text                    null,
  created_by_profile_id  uuid                    null references public.profiles (id) on delete set null,
  archived_at            timestamptz             null,
  created_at             timestamptz             not null default now(),
  updated_at             timestamptz             not null default now(),

  constraint projects_status_check    check (status in ('draft','active','on_hold','archived','closed')),
  constraint projects_workspace_slug_key unique (workspace_id, slug),
  constraint projects_id_workspace_key   unique (id, workspace_id)
);

comment on table public.projects is
  'Bounded body of design work inside a workspace. Belongs to exactly one workspace. Never movable across workspaces (workspace_id is immutable at the application layer; no DB constraint enforces this in MVP). DATABASE_SCHEMA.md v0.3 §3.6.';
comment on column public.projects.slug is
  'Workspace-scoped URL slug. Not an identity substitute.';
comment on column public.projects.code is
  'Optional human-facing code. Nullable, not unique.';

create index projects_workspace_status_idx on public.projects (workspace_id, status);

drop trigger if exists projects_set_updated_at on public.projects;
create trigger projects_set_updated_at
  before update on public.projects
  for each row execute function public.set_updated_at();

alter table public.projects enable row level security;

------------------------------------------------------------------------------
-- 2. project_participants
------------------------------------------------------------------------------

create table public.project_participants (
  id                     uuid                    primary key default gen_random_uuid(),
  workspace_id           uuid                    not null,
  project_id             uuid                    not null,
  workspace_member_id    uuid                    null,
  stakeholder_id         uuid                    null,
  role                   text                    not null,
  status                 text                    not null default 'active',
  added_at               timestamptz             not null default now(),
  removed_at             timestamptz             null,
  created_at             timestamptz             not null default now(),
  updated_at             timestamptz             not null default now(),

  constraint project_participants_role_check
    check (role in ('lead','contributor','reviewer','approver','observer')),

  constraint project_participants_status_check
    check (status in ('active','removed')),

  constraint project_participants_actor_xor_check
    check ((workspace_member_id is not null) <> (stakeholder_id is not null)),

  constraint project_participants_project_fk
    foreign key (project_id, workspace_id)
    references public.projects (id, workspace_id)
    on delete restrict,

  constraint project_participants_workspace_member_fk
    foreign key (workspace_member_id, workspace_id)
    references public.workspace_members (id, workspace_id)
    on delete restrict,

  constraint project_participants_stakeholder_fk
    foreign key (stakeholder_id, workspace_id)
    references public.stakeholders (id, workspace_id)
    on delete restrict,

  constraint project_participants_id_project_workspace_key
    unique (id, project_id, workspace_id)
);

comment on table public.project_participants is
  'Sole authorization join for project access. Roster of a workspace_members row OR a stakeholders row on a specific project, with a project role. Composite FKs prevent cross-workspace participation. DATABASE_SCHEMA.md v0.3 §3.7.';
comment on constraint project_participants_actor_xor_check on public.project_participants is
  'Exactly one of workspace_member_id / stakeholder_id must be set. The dual-path invariant (same profile via both paths on the same project) is enforced at the project.manage_access RPC per PERMISSIONS.md §6.3.';

create unique index project_participants_project_member_key
  on public.project_participants (project_id, workspace_member_id)
  where workspace_member_id is not null;

create unique index project_participants_project_stakeholder_key
  on public.project_participants (project_id, stakeholder_id)
  where stakeholder_id is not null;

create index project_participants_workspace_project_status_idx
  on public.project_participants (workspace_id, project_id, status);

drop trigger if exists project_participants_set_updated_at on public.project_participants;
create trigger project_participants_set_updated_at
  before update on public.project_participants
  for each row execute function public.set_updated_at();

alter table public.project_participants enable row level security;

------------------------------------------------------------------------------
-- 3. collections
------------------------------------------------------------------------------

create table public.collections (
  id                     uuid                    primary key default gen_random_uuid(),
  workspace_id           uuid                    not null,
  project_id             uuid                    not null,
  name                   text                    not null,
  description            text                    null,
  sort_order             integer                 not null default 0,
  status                 text                    not null default 'active',
  created_by_profile_id  uuid                    null references public.profiles (id) on delete set null,
  archived_at            timestamptz             null,
  created_at             timestamptz             not null default now(),
  updated_at             timestamptz             not null default now(),

  constraint collections_status_check check (status in ('active','archived')),

  constraint collections_project_fk
    foreign key (project_id, workspace_id)
    references public.projects (id, workspace_id)
    on delete restrict,

  constraint collections_id_project_workspace_key
    unique (id, project_id, workspace_id)
);

comment on table public.collections is
  'Universal, industry-neutral grouping of design assets inside a single project. DATABASE_SCHEMA.md v0.3 §3.8. Cardinality: DesignAsset → 0..1 Collection (enforced at design_assets in Migration 004).';

create unique index collections_project_name_active_key
  on public.collections (project_id, lower(name))
  where status = 'active';

create index collections_project_sort_idx on public.collections (project_id, sort_order);

drop trigger if exists collections_set_updated_at on public.collections;
create trigger collections_set_updated_at
  before update on public.collections
  for each row execute function public.set_updated_at();

alter table public.collections enable row level security;