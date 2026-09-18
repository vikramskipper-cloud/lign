-- Migration 004: design_assets_versions_files
--
-- Core LIGN Design Asset → Version → File model. The most consequential
-- structural migration to date.
--
-- Contents:
--   0. Migration 003 FK-index hardening (six unindexed_foreign_keys findings).
--   1. public.design_assets  — persistent identity of a piece of design work.
--   2. public.asset_versions — immutable iteration of a design asset.
--   3. ALTER design_assets to add the circular current_version_id FK.
--   4. public.files          — content-addressed workspace-owned artifact metadata.
--   5. public.version_files  — attachment of a file to a version.
--   6. Structural immutability triggers:
--        - asset_versions content is immutable once past 'draft'
--        - version_files rows only mutable while parent is 'draft'
--   7. RLS enabled on all four new tables with NO policies.
--
-- Core preserved invariants (documented for reviewers):
--   A. A Design Asset belongs to exactly one Project/Workspace.
--   B. A Version belongs to exactly one Design Asset.
--   C. A Version cannot belong to a different Workspace/Project than its
--      Design Asset (composite FK enforces).
--   D. Version sequence is unique within the Design Asset.
--   E. Multiple published Versions may coexist (no auto-supersede).
--   F. current_version_id can be NULL.
--   G. current_version_id can only point to a Version of the SAME asset
--      (composite FK enforces).
--   H. Publishing/creating a Version does not change current_version_id
--      (no trigger).
--   I. A File belongs to exactly one Workspace.
--   J. File checksum deduplication is Workspace-scoped only.
--   K. A File cannot be attached across Workspace boundaries (composite FK).
--   L. Version/File composite unique targets are declared for the downstream
--      review/comment/approval/release/annotation FKs (Migrations 005+).
--   M. No professional/vertical terminology.
--   N. No Storage buckets or storage.objects policies created here.
--   O. No RLS policies or workflow RPCs created here.
--
-- Circular FK handled deliberately:
--   design_assets.current_version_id → asset_versions(id, design_asset_id)
--   asset_versions.design_asset_id   → design_assets(id, project_id, workspace_id)
--   Resolution: create design_assets without the current_version FK first,
--   create asset_versions (declares the required composite UNIQUE target),
--   then ALTER design_assets to add the FK.
--
-- Immutability triggers:
--   - enforce_asset_version_publish_immutability: allows draft rows to be
--     fully mutable, then locks content columns once past draft. Allows
--     status transitions, deprecated_at, deprecation_note, updated_at
--     (though updated_at is separately gated by a WHEN clause below).
--   - enforce_version_files_parent_draft_mutation: version_files may only
--     be inserted/updated/deleted while parent asset_version.status='draft'.
--     SECURITY DEFINER so the internal parent-status lookup bypasses RLS.
--
-- updated_at behavior:
--   Per DATABASE_SCHEMA.md v0.3 §3 (Standard columns), immutable-once-
--   published tables do not advance updated_at after they lock. The
--   asset_versions updated_at trigger fires only WHEN (OLD.status='draft'),
--   freezing updated_at once the row leaves draft. version_files relies
--   on the immutability trigger to block mutations post-draft, so its
--   updated_at cannot advance either.
--
-- No destructive cascades. Every FK from these four tables to a parent is
-- RESTRICT, with the exceptions the schema explicitly requires:
--   - design_assets.collection_id → collections ON DELETE SET NULL
--   - design_assets.current_version_id → asset_versions ON DELETE SET NULL
--   - files.uploaded_by_profile_id / asset_versions.published_by_profile_id
--     / design_assets.created_by_profile_id → profiles ON DELETE SET NULL
--
-- Explicit non-goals:
--   - No reviews/comments/annotations/changes/decisions/approvals/releases.
--   - No RPCs (upload_and_attach_version_file, publish_version,
--     set_current_version, discard_draft_version, etc.).
--   - No storage buckets, no pg_cron, no pg_net.
--   - No RLS policies.

------------------------------------------------------------------------------
-- 0. Migration 003 FK-index hardening
------------------------------------------------------------------------------
-- Covers the six unindexed_foreign_keys advisor findings.

create index if not exists projects_created_by_profile_id_idx
  on public.projects (created_by_profile_id)
  where created_by_profile_id is not null;

create index if not exists collections_created_by_profile_id_idx
  on public.collections (created_by_profile_id)
  where created_by_profile_id is not null;

create index if not exists collections_project_workspace_idx
  on public.collections (project_id, workspace_id);

create index if not exists project_participants_project_workspace_idx
  on public.project_participants (project_id, workspace_id);

create index if not exists project_participants_workspace_member_workspace_idx
  on public.project_participants (workspace_member_id, workspace_id)
  where workspace_member_id is not null;

create index if not exists project_participants_stakeholder_workspace_idx
  on public.project_participants (stakeholder_id, workspace_id)
  where stakeholder_id is not null;

------------------------------------------------------------------------------
-- 1. design_assets (DATABASE_SCHEMA.md v0.3 §3.9)
--    current_version_id column is present but its FK is added later, after
--    asset_versions exists.
------------------------------------------------------------------------------

create table public.design_assets (
  id                     uuid                    primary key default gen_random_uuid(),
  workspace_id           uuid                    not null,
  project_id             uuid                    not null,
  collection_id          uuid                    null,
  name                   text                    not null,
  description            text                    null,
  code                   text                    null,
  current_version_id     uuid                    null,
  status                 text                    not null default 'draft',
  created_by_profile_id  uuid                    null references public.profiles (id) on delete set null,
  archived_at            timestamptz             null,
  created_at             timestamptz             not null default now(),
  updated_at             timestamptz             not null default now(),

  constraint design_assets_status_check
    check (status in ('draft','active','deprecated','archived')),

  -- Composite tenant/scope FK: same project + workspace as this row.
  constraint design_assets_project_fk
    foreign key (project_id, workspace_id)
    references public.projects (id, workspace_id)
    on delete restrict,

  -- Optional collection membership; SET NULL if the collection is deleted
  -- (per DATABASE_SCHEMA.md v0.3 §3.9). Composite ensures same project.
  constraint design_assets_collection_fk
    foreign key (collection_id, project_id, workspace_id)
    references public.collections (id, project_id, workspace_id)
    on delete set null,

  -- Composite unique targets for downstream (asset_versions, reviews, etc.).
  constraint design_assets_id_workspace_key         unique (id, workspace_id),
  constraint design_assets_id_project_workspace_key unique (id, project_id, workspace_id)
);

comment on table public.design_assets is
  'Persistent identity of a piece of design work. Belongs to exactly one project. current_version_id is set ONLY by the future asset.set_current RPC — never auto-set by version creation, publish, approval, or release. Preserved on archive. DATABASE_SCHEMA.md v0.3 §3.9.';
comment on column public.design_assets.current_version_id is
  'Nullable FK to an asset_version OF THIS asset (composite FK enforces same-asset). Preserved on archive.';
comment on column public.design_assets.code is
  'Optional human-facing product code. Nullable, not unique.';

create index design_assets_project_status_idx on public.design_assets (project_id, status);
create index design_assets_collection_idx
  on public.design_assets (collection_id)
  where collection_id is not null;
create index design_assets_workspace_project_idx on public.design_assets (workspace_id, project_id);

drop trigger if exists design_assets_set_updated_at on public.design_assets;
create trigger design_assets_set_updated_at
  before update on public.design_assets
  for each row execute function public.set_updated_at();

alter table public.design_assets enable row level security;

------------------------------------------------------------------------------
-- 2. asset_versions (DATABASE_SCHEMA.md v0.3 §3.10)
------------------------------------------------------------------------------

create table public.asset_versions (
  id                          uuid                    primary key default gen_random_uuid(),
  workspace_id                uuid                    not null,
  project_id                  uuid                    not null,
  design_asset_id             uuid                    not null,
  sequence                    integer                 not null,
  label                       text                    null,
  notes                       text                    null,
  status                      text                    not null default 'draft',
  published_at                timestamptz             null,
  published_by_profile_id     uuid                    null references public.profiles (id) on delete set null,
  deprecated_at               timestamptz             null,
  deprecation_note            text                    null,
  created_at                  timestamptz             not null default now(),
  updated_at                  timestamptz             not null default now(),

  constraint asset_versions_status_check
    check (status in ('draft','published','superseded','deprecated')),

  constraint asset_versions_sequence_positive_check
    check (sequence > 0),

  -- Non-draft versions must carry publish metadata.
  constraint asset_versions_publish_metadata_check
    check ((status = 'draft')
           or (published_at is not null and published_by_profile_id is not null)),

  -- Composite tenant/project FK to design_assets: same asset within same
  -- project within same workspace. Structural cross-scope prevention.
  constraint asset_versions_design_asset_fk
    foreign key (design_asset_id, project_id, workspace_id)
    references public.design_assets (id, project_id, workspace_id)
    on delete restrict,

  -- Version-ordering integrity + concurrency backstop.
  constraint asset_versions_asset_sequence_key    unique (design_asset_id, sequence),

  -- Composite unique targets:
  --   - (id, design_asset_id) is the target of design_assets.current_version_id
  --     and future changes/reviews/approval_requests composite FKs.
  --   - (id, project_id) is the target of future release_items composite FKs.
  --   - (id, workspace_id) is the target of future annotations/comments/
  --     decisions composite FKs.
  constraint asset_versions_id_design_asset_key   unique (id, design_asset_id),
  constraint asset_versions_id_project_key        unique (id, project_id),
  constraint asset_versions_id_workspace_key      unique (id, workspace_id)
);

comment on table public.asset_versions is
  'Immutable iteration of a design_asset. Sequence-scoped per asset (UNIQUE design_asset_id, sequence). Publishing does NOT auto-supersede prior published versions — multiple published versions may coexist. DATABASE_SCHEMA.md v0.3 §3.10.';
comment on column public.asset_versions.sequence is
  'Strictly increasing per design_asset. Uniqueness structurally enforced. Concurrency backstop: simultaneous inserts of the same sequence fail with UNIQUE violation; RPC layer retries.';

create index asset_versions_asset_sequence_desc_idx
  on public.asset_versions (design_asset_id, sequence desc);

create index asset_versions_asset_status_idx
  on public.asset_versions (design_asset_id, status);

create index asset_versions_published_recent_idx
  on public.asset_versions (workspace_id, project_id, published_at desc)
  where status = 'published';

-- updated_at trigger fires ONLY while row is still draft. Once past draft,
-- the row is immutable-once-published per DATABASE_SCHEMA.md v0.3 §3
-- (Standard columns).
drop trigger if exists asset_versions_set_updated_at on public.asset_versions;
create trigger asset_versions_set_updated_at
  before update on public.asset_versions
  for each row
  when (old.status = 'draft')
  execute function public.set_updated_at();

-- Content immutability trigger.
create or replace function public.enforce_asset_version_publish_immutability()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Draft rows remain fully mutable.
  if old.status = 'draft' then
    return new;
  end if;

  -- Post-draft: block content-column changes. Allowed changes on published+:
  -- status (lifecycle), deprecated_at, deprecation_note, updated_at.
  if new.workspace_id            is distinct from old.workspace_id
    or new.project_id             is distinct from old.project_id
    or new.design_asset_id        is distinct from old.design_asset_id
    or new.sequence               is distinct from old.sequence
    or new.label                  is distinct from old.label
    or new.notes                  is distinct from old.notes
    or new.published_at           is distinct from old.published_at
    or new.published_by_profile_id is distinct from old.published_by_profile_id
    or new.created_at             is distinct from old.created_at
  then
    raise exception 'asset_versions content is immutable after publish (row id=%, status=%)', old.id, old.status
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function public.enforce_asset_version_publish_immutability() is
  'DB-boundary trigger: once asset_versions.status leaves draft, content columns become immutable. Allows status transitions, deprecated_at, deprecation_note. Does not block legitimate RPC-driven lifecycle transitions.';

drop trigger if exists asset_versions_publish_immutability on public.asset_versions;
create trigger asset_versions_publish_immutability
  before update on public.asset_versions
  for each row
  execute function public.enforce_asset_version_publish_immutability();

alter table public.asset_versions enable row level security;

------------------------------------------------------------------------------
-- 3. Complete the design_assets circular FK.
--    (current_version_id, id) → asset_versions(id, design_asset_id)
--    ensures the referenced version belongs to THIS asset. Order of FK
--    columns is reversed to match the target UNIQUE (id, design_asset_id).
------------------------------------------------------------------------------

alter table public.design_assets
  add constraint design_assets_current_version_fk
    foreign key (current_version_id, id)
    references public.asset_versions (id, design_asset_id)
    on delete set null;

comment on constraint design_assets_current_version_fk on public.design_assets is
  'Composite FK: current_version_id, when non-null, references an asset_version of the SAME design_asset. Cross-asset current designation is structurally impossible.';

------------------------------------------------------------------------------
-- 4. files (DATABASE_SCHEMA.md v0.3 §3.11)
------------------------------------------------------------------------------

create table public.files (
  id                       uuid                    primary key default gen_random_uuid(),
  workspace_id             uuid                    not null references public.workspaces (id) on delete restrict,
  checksum_sha256          bytea                   not null,
  mime_type                text                    not null,
  size_bytes               bigint                  not null,
  storage_ref              text                    not null,
  uploaded_by_profile_id   uuid                    null references public.profiles (id) on delete set null,
  status                   text                    not null default 'active',
  orphaned_at              timestamptz             null,
  purged_at                timestamptz             null,
  created_at               timestamptz             not null default now(),
  updated_at               timestamptz             not null default now(),

  constraint files_status_check check (status in ('uploaded','active','orphaned','purged')),
  constraint files_size_check   check (size_bytes >= 0),

  -- Workspace-scoped dedup. NEVER global. Workspace A cannot infer
  -- workspace B's files through checksum collision.
  constraint files_workspace_checksum_key unique (workspace_id, checksum_sha256),

  -- Composite unique target for version_files.
  constraint files_id_workspace_key       unique (id, workspace_id)
);

comment on table public.files is
  'Content-addressed workspace-owned artifact metadata. Dedup is workspace-scoped only. Content immutable per checksum (a new upload with different bytes is a new files row). Actual storage bytes live in Supabase Storage (STORAGE_ARCHITECTURE.md, future). DATABASE_SCHEMA.md v0.3 §3.11.';
comment on column public.files.checksum_sha256 is
  'sha256 of file bytes. UNIQUE (workspace_id, checksum_sha256) enforces workspace-scoped dedup only.';

create index files_workspace_status_idx on public.files (workspace_id, status);
create index files_storage_ref_idx      on public.files (storage_ref);
create index files_uploaded_by_profile_id_idx
  on public.files (uploaded_by_profile_id)
  where uploaded_by_profile_id is not null;

drop trigger if exists files_set_updated_at on public.files;
create trigger files_set_updated_at
  before update on public.files
  for each row execute function public.set_updated_at();

alter table public.files enable row level security;

------------------------------------------------------------------------------
-- 5. version_files (DATABASE_SCHEMA.md v0.3 §3.12)
------------------------------------------------------------------------------

create table public.version_files (
  id                   uuid                    primary key default gen_random_uuid(),
  workspace_id         uuid                    not null,
  asset_version_id     uuid                    not null,
  file_id              uuid                    not null,
  display_name         text                    null,
  role                 text                    not null default 'primary',
  sort_order           integer                 not null default 0,
  created_at           timestamptz             not null default now(),
  updated_at           timestamptz             not null default now(),

  constraint version_files_role_check
    check (role in ('primary','reference','spec','source','export','other')),
  constraint version_files_sort_order_check
    check (sort_order >= 0),

  -- Composite tenant FKs: version and file must live in the same workspace
  -- as this row. Cross-workspace attachment is structurally impossible.
  constraint version_files_version_fk
    foreign key (asset_version_id, workspace_id)
    references public.asset_versions (id, workspace_id)
    on delete restrict,

  constraint version_files_file_fk
    foreign key (file_id, workspace_id)
    references public.files (id, workspace_id)
    on delete restrict,

  -- A file is attached to a given version at most once.
  constraint version_files_version_file_key       unique (asset_version_id, file_id),

  -- Deterministic ordering per version.
  constraint version_files_version_sort_order_key unique (asset_version_id, sort_order),

  -- Composite unique target for future annotations composite FK.
  constraint version_files_id_asset_version_key   unique (id, asset_version_id)
);

comment on table public.version_files is
  'Attachment of a file to a specific asset_version, with per-attachment metadata. Rows are only mutable while parent asset_version.status = draft (trigger). Composite FKs prevent cross-workspace attachment. DATABASE_SCHEMA.md v0.3 §3.12.';

create index version_files_file_idx on public.version_files (file_id);

drop trigger if exists version_files_set_updated_at on public.version_files;
create trigger version_files_set_updated_at
  before update on public.version_files
  for each row execute function public.set_updated_at();

-- Draft-only mutation trigger.
create or replace function public.enforce_version_files_parent_draft_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_parent_id     uuid;
  v_parent_status text;
begin
  if tg_op = 'DELETE' then
    v_parent_id := old.asset_version_id;
  else
    v_parent_id := new.asset_version_id;
  end if;

  select status into v_parent_status
    from public.asset_versions where id = v_parent_id;

  if v_parent_status is null then
    raise exception 'enforce_version_files_parent_draft_mutation: parent asset_version % not found', v_parent_id
      using errcode = '23503';
  end if;

  if v_parent_status is distinct from 'draft' then
    raise exception 'version_files may only be mutated while parent asset_version.status = ''draft'' (parent status=%)', v_parent_status
      using errcode = '23514';
  end if;

  if tg_op = 'DELETE' then
    return old;
  else
    return new;
  end if;
end;
$$;

comment on function public.enforce_version_files_parent_draft_mutation() is
  'DB-boundary trigger: version_files rows may only be inserted/updated/deleted while the parent asset_version is in draft status. SECURITY DEFINER so the internal parent-status lookup bypasses RLS on asset_versions.';

revoke all on function public.enforce_version_files_parent_draft_mutation() from public;
revoke all on function public.enforce_version_files_parent_draft_mutation() from anon;
revoke all on function public.enforce_version_files_parent_draft_mutation() from authenticated;

drop trigger if exists version_files_parent_draft_mutation on public.version_files;
create trigger version_files_parent_draft_mutation
  before insert or update or delete on public.version_files
  for each row execute function public.enforce_version_files_parent_draft_mutation();

alter table public.version_files enable row level security;
