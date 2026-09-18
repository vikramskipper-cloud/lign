-- Migration 003: projects_participants_collections
--
-- Structural database layer for the Project tier of the LIGN domain:
--   0. Migration 002 hardening — adds the covering index on
--      invitations.invited_by_profile_id flagged by the Supabase advisor
--      (unindexed_foreign_keys). Nullable FK, so partial index.
--   1. public.projects (DATABASE_SCHEMA.md v0.3 §3.6).
--   2. public.project_participants (DATABASE_SCHEMA.md v0.3 §3.7). Sole
--      authorization join for project access. XOR (workspace_member_id |
--      stakeholder_id). Composite FKs enforce structural tenant integrity.
--   3. public.collections (DATABASE_SCHEMA.md v0.3 §3.8). Industry-neutral
--      grouping of design assets inside a project; optional (0..1) per
--      DesignAsset in the frozen multiplicity decision.
--   4. RLS enabled on all three new tables with NO policies. Policies land
--      in the dedicated authorization migration stage.
--
-- Explicit non-goals:
--   - No design_assets / asset_versions / files / version_files / etc.
--   - No create_project / add_project_participant / manage_access RPCs.
--   - No capability functions or business RPCs.
--   - No activity_events emission or notification wiring.
--   - No storage buckets, no pg_cron, no pg_net.
--
-- MVP state-machine notes:
--   - projects.status enum retains ('draft','active','on_hold','archived',
--     'closed') per the frozen schema; MVP exercises only 'active' ↔
--     'archived' per STATE_MACHINES.md v1 §6. Reserved values remain
--     structurally available for future workflows.
--   - project_participants.status enum retains ('active','removed'); MVP
--     exercises both.
--   - collections.status enum retains ('active','archived'); MVP
--     exercises both.
--
-- Historical-retention posture (from DOMAIN_MODEL.md §0):
--   - projects.workspace_id → workspaces(id) ON DELETE RESTRICT
--   - projects.created_by_profile_id → profiles(id) ON DELETE SET NULL
--   - project_participants.workspace_member_id / stakeholder_id → …
--     ON DELETE RESTRICT (roster carries authorization context)
--   - collections.created_by_profile_id → profiles(id) ON DELETE SET NULL
--
-- Downstream FK targets set up now (used by Migration 004+):
--   - projects UNIQUE (id, workspace_id)                         — needed by
--     collections, design_assets, releases, project_participants.
--   - collections UNIQUE (id, project_id, workspace_id)          — needed by
--     design_assets to enforce same-project collection membership.
--   - project_participants UNIQUE (id, project_id, workspace_id) — reserved
--     for future roster-referencing tables (per DATABASE_SCHEMA.md v0.3
--     §3.7); currently unused by MVP but declared per spec.
--
-- Dual-path participation (workspace_member + stakeholder for the same
-- profile on the same project) is enforced at the RPC layer per
-- PERMISSIONS.md §6.3 (D1). Not expressed as a static DB constraint.
--
-- Transaction control: none inline. Supabase migration runner wraps.

------------------------------------------------------------------------------
-- 0. Migration 002 hardening: invitations.invited_by_profile_id covering index
------------------------------------------------------------------------------
-- Nullable FK. Partial index avoids indexing NULL rows.

create index if not exists invitations_invited_by_profile_id_idx
  on public.invitations (invited_by_profile_id)
  where invited_by_profile_id is not null;

------------------------------------------------------------------------------
-- 1. projects (DATABASE_SCHEMA.md v0.3 §3.6)
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

  -- Frozen schema retains all five values. MVP transitions only exercise
  -- 'active' ↔ 'archived'. Reserved future values kept structurally.
  constraint projects_status_check    check (status in ('draft','active','on_hold','archived','closed')),

  -- Workspace-scoped slug uniqueness.
  constraint projects_workspace_slug_key unique (workspace_id, slug),

  -- Composite FK target for every child table
  -- (collections, project_participants, design_assets, releases, ...).
  constraint projects_id_workspace_key   unique (id, workspace_id)
);

comment on table public.projects is
  'Bounded body of design work inside a workspace. Belongs to exactly one workspace. Never movable across workspaces (workspace_id is immutable at the application layer; no DB constraint enforces this in MVP). DATABASE_SCHEMA.md v0.3 §3.6.';
comment on column public.projects.slug is
  'Workspace-scoped URL slug. Not an identity substitute.';
comment on column public.projects.code is
  'Optional human-facing code (e.g. KITCHEN-2026). Nullable, not unique.';

create index projects_workspace_status_idx on public.projects (workspace_id, status);

drop trigger if exists projects_set_updated_at on public.projects;
create trigger projects_set_updated_at
  before update on public.projects
  for each row execute function public.set_updated_at();

alter table public.projects enable row level security;

------------------------------------------------------------------------------
-- 2. project_participants (DATABASE_SCHEMA.md v0.3 §3.7)
------------------------------------------------------------------------------
-- Sole authorization join for project access. Each participant is either a
-- workspace_members row (internal) OR a stakeholders row (external), never
-- both in the same row. XOR CHECK enforced structurally.
--
-- Composite FKs ensure:
--   (project_id, workspace_id)         → projects(id, workspace_id)
--   (workspace_member_id, workspace_id) → workspace_members(id, workspace_id)
--   (stakeholder_id, workspace_id)      → stakeholders(id, workspace_id)
-- Together these make it structurally impossible for a project in workspace A
-- to have a participant sourced from workspace B.

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

  -- Universal project-role vocabulary. Intentionally industry-neutral:
  -- no architect / designer / contractor / client / engineer / vendor.
  constraint project_participants_role_check
    check (role in ('lead','contributor','reviewer','approver','observer')),

  constraint project_participants_status_check
    check (status in ('active','removed')),

  -- XOR: exactly one participation identity path per row.
  constraint project_participants_actor_xor_check
    check ((workspace_member_id is not null) <> (stakeholder_id is not null)),

  -- Composite tenant/scope FKs.
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

  -- Composite FK target reserved for future roster-referencing tables
  -- (per DATABASE_SCHEMA.md v0.3 §3.7). Not consumed by any MVP table.
  constraint project_participants_id_project_workspace_key
    unique (id, project_id, workspace_id)
);

comment on table public.project_participants is
  'Sole authorization join for project access. Roster of a workspace_members row OR a stakeholders row on a specific project, with a project role. Composite FKs prevent cross-workspace participation. DATABASE_SCHEMA.md v0.3 §3.7.';
comment on constraint project_participants_actor_xor_check on public.project_participants is
  'Exactly one of workspace_member_id / stakeholder_id must be set. The dual-path invariant (same profile via both paths on the same project) is enforced separately at the project.manage_access RPC per PERMISSIONS.md §6.3.';
comment on constraint project_participants_project_fk on public.project_participants is
  'Composite tenant/scope FK: the participant row lives in the same workspace as its project. Cross-workspace participation is structurally impossible.';
comment on constraint project_participants_workspace_member_fk on public.project_participants is
  'Composite tenant FK: the referenced workspace_member must belong to the participant row''s workspace.';
comment on constraint project_participants_stakeholder_fk on public.project_participants is
  'Composite tenant FK: the referenced stakeholder must belong to the participant row''s workspace.';

-- Partial uniques prevent duplicate participation via either path.
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
-- 3. collections (DATABASE_SCHEMA.md v0.3 §3.8)
------------------------------------------------------------------------------
-- Industry-neutral grouping of design assets within a single project.
-- Not a folder tree. Not a discipline. Names are user-defined vocabulary.
-- Design assets reference at most one collection (cardinality 0..1) —
-- enforced at the design_assets table in Migration 004.

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

  -- Composite tenant/scope FK: collection belongs to a project in the
  -- same workspace as the collection's workspace_id.
  constraint collections_project_fk
    foreign key (project_id, workspace_id)
    references public.projects (id, workspace_id)
    on delete restrict,

  -- Composite FK target for design_assets (Migration 004):
  --   (collection_id, project_id, workspace_id)
  --   → collections(id, project_id, workspace_id) ON DELETE SET NULL
  constraint collections_id_project_workspace_key
    unique (id, project_id, workspace_id)
);

comment on table public.collections is
  'Universal, industry-neutral grouping of design assets inside a single project. DATABASE_SCHEMA.md v0.3 §3.8. Cardinality: DesignAsset → 0..1 Collection (enforced at design_assets in Migration 004).';
comment on constraint collections_project_fk on public.collections is
  'Composite tenant/scope FK: a collection cannot reference a project in a different workspace. Structurally enforced.';

-- Active-name uniqueness within a project (case-insensitive via LOWER
-- expression index; name column stays text per the frozen schema).
create unique index collections_project_name_active_key
  on public.collections (project_id, lower(name))
  where status = 'active';

create index collections_project_sort_idx on public.collections (project_id, sort_order);

drop trigger if exists collections_set_updated_at on public.collections;
create trigger collections_set_updated_at
  before update on public.collections
  for each row execute function public.set_updated_at();

alter table public.collections enable row level security;
