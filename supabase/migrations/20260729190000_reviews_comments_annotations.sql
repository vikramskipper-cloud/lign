-- Migration 005: reviews_comments_annotations
--
-- LIGN's contextual design-review and collaboration layer.
--
-- Contents:
--   0. Migration 004 FK-index hardening (eight unindexed_foreign_keys findings).
--   1. public.reviews             — first-class review of a specific version.
--   2. public.review_participants — reviewer roster (member XOR stakeholder).
--   3. public.annotations         — spatial/positional feedback on a version.
--   4. public.comments            — threaded textual feedback with typed targets.
--   5. public.comment_edits       — append-only relational edit history.
--   6. Structural immutability triggers:
--        - annotations: position / anchor_kind / page_number immutable after
--          insert.
--        - comment_edits: append-only (no UPDATE, no DELETE).
--   7. RLS enabled on all five tables with NO policies.
--
-- Explicit non-goals:
--   - No changes / decisions / approval_requests / releases / activity_events.
--   - No RPCs (create_review, complete_review, edit_own_comment, etc.).
--   - No mention parsing or notification emission.
--   - No completed-review comment-editing gate (deferred to the RPC layer;
--     DATABASE_SCHEMA.md does not require a structural trigger for it).
--   - No storage buckets, pg_cron, pg_net.
--   - No RLS policies.
--
-- Preserved invariants (verified pre-application):
--   A. Every Review is scoped to workspace + project via composite FKs.
--   B. review.version_id belongs to review.design_asset_id (composite FK).
--   C. Review participants share the review's workspace (composite FK).
--   D. review_participants XOR: exactly one of workspace_member_id /
--      stakeholder_id must be set.
--   E. Comment author uses profile attribution (author_profile_id → profiles).
--   F. Comment has exactly one target of the seven typed target columns.
--   G. Comment target FKs are composite with workspace_id — cross-workspace
--      targeting is structurally impossible for the four target tables that
--      exist today (asset_versions, reviews, annotations, design_assets).
--   H. Comment parent_comment_id references another comment — thread
--      integrity preserved via FK RESTRICT.
--   I. Comment edits form a relational, append-only history (no JSONB).
--   J. Annotation author uses profile attribution.
--   K. Annotation asset_version_id belongs to the correct workspace via
--      composite FK; optional version_file_id belongs to the same version.
--   L. Annotation geometry (anchor_kind, position, page_number) is
--      industry-neutral — no PDF/CAD/BIM-specific fields.
--   M. Annotation position immutable after insert (trigger).
--   N. No generic-chat architecture (no channels, DMs, rooms).
--   O. No professional / vertical terminology.
--   P. No RLS policies / RPCs / notifications introduced.
--
-- Deferred target FKs on comments (added by later migrations):
--   - target_change_id           → changes(id, workspace_id)          — Migration 006
--   - target_decision_id         → decisions(id, workspace_id)        — Migration 006
--   - target_approval_request_id → approval_requests(id, workspace_id) — Migration 007
-- All seven target columns and the XOR check exist from this migration so
-- future ALTERs add only the FK constraints, not columns. The XOR check is
-- protective even in the absence of the three deferred FKs because direct
-- writes are blocked by RLS (no policies yet).

------------------------------------------------------------------------------
-- 0. Migration 004 FK-index hardening
------------------------------------------------------------------------------

-- asset_versions.design_asset_fk: (design_asset_id, project_id, workspace_id)
create index if not exists asset_versions_design_asset_project_workspace_idx
  on public.asset_versions (design_asset_id, project_id, workspace_id);

-- asset_versions.published_by_profile_id_fkey (nullable)
create index if not exists asset_versions_published_by_profile_id_idx
  on public.asset_versions (published_by_profile_id)
  where published_by_profile_id is not null;

-- design_assets.collection_fk: (collection_id, project_id, workspace_id), nullable collection_id
create index if not exists design_assets_collection_project_workspace_idx
  on public.design_assets (collection_id, project_id, workspace_id)
  where collection_id is not null;

-- design_assets.created_by_profile_id_fkey (nullable)
create index if not exists design_assets_created_by_profile_id_idx
  on public.design_assets (created_by_profile_id)
  where created_by_profile_id is not null;

-- design_assets.current_version_fk: (current_version_id, id), nullable current_version_id
create index if not exists design_assets_current_version_idx
  on public.design_assets (current_version_id, id)
  where current_version_id is not null;

-- design_assets.project_fk: (project_id, workspace_id)
create index if not exists design_assets_project_workspace_idx
  on public.design_assets (project_id, workspace_id);

-- version_files.file_fk: (file_id, workspace_id)
create index if not exists version_files_file_workspace_idx
  on public.version_files (file_id, workspace_id);

-- version_files.version_fk: (asset_version_id, workspace_id)
create index if not exists version_files_version_workspace_idx
  on public.version_files (asset_version_id, workspace_id);

------------------------------------------------------------------------------
-- 1. reviews (DATABASE_SCHEMA.md v0.3 §3.13)
------------------------------------------------------------------------------

create table public.reviews (
  id                      uuid                    primary key default gen_random_uuid(),
  workspace_id            uuid                    not null,
  project_id              uuid                    not null,
  design_asset_id         uuid                    not null,
  version_id              uuid                    not null,
  title                   text                    not null,
  description             text                    null,
  status                  text                    not null default 'draft',
  due_at                  timestamptz             null,
  completed_at            timestamptz             null,
  cancelled_at            timestamptz             null,
  created_by_profile_id   uuid                    null references public.profiles (id) on delete set null,
  created_at              timestamptz             not null default now(),
  updated_at              timestamptz             not null default now(),

  constraint reviews_status_check
    check (status in ('draft','open','in_progress','completed','cancelled')),

  -- Composite tenant/scope FK: asset lives in the review's project+workspace.
  constraint reviews_design_asset_fk
    foreign key (design_asset_id, project_id, workspace_id)
    references public.design_assets (id, project_id, workspace_id)
    on delete restrict,

  -- Composite scope FK: version belongs to THIS asset (structurally).
  constraint reviews_version_fk
    foreign key (version_id, design_asset_id)
    references public.asset_versions (id, design_asset_id)
    on delete restrict,

  -- Composite unique targets consumed by comments/decisions/etc.
  constraint reviews_id_workspace_key         unique (id, workspace_id),
  constraint reviews_id_project_workspace_key unique (id, project_id, workspace_id)
);

comment on table public.reviews is
  'First-class request to evaluate a specific asset_version. Version must belong to the reviewed design_asset (composite FK). MVP lifecycle draft → open → in_progress → completed | cancelled per STATE_MACHINES.md v1 §9. DATABASE_SCHEMA.md v0.3 §3.13.';
comment on constraint reviews_version_fk on public.reviews is
  'Composite FK: the reviewed version is structurally required to belong to the reviewed design_asset. Cross-asset review targeting is impossible.';

create index reviews_version_status_idx    on public.reviews (version_id, status);
create index reviews_asset_status_idx      on public.reviews (design_asset_id, status);
create index reviews_open_due_idx
  on public.reviews (workspace_id, status, due_at)
  where status in ('open','in_progress');
create index reviews_created_by_profile_id_idx
  on public.reviews (created_by_profile_id)
  where created_by_profile_id is not null;

drop trigger if exists reviews_set_updated_at on public.reviews;
create trigger reviews_set_updated_at
  before update on public.reviews
  for each row execute function public.set_updated_at();

alter table public.reviews enable row level security;

------------------------------------------------------------------------------
-- 2. review_participants (DATABASE_SCHEMA.md v0.3 §3.14)
------------------------------------------------------------------------------

create table public.review_participants (
  id                     uuid                    primary key default gen_random_uuid(),
  workspace_id           uuid                    not null,
  review_id              uuid                    not null,
  workspace_member_id    uuid                    null,
  stakeholder_id         uuid                    null,
  status                 text                    not null default 'pending',
  assigned_at            timestamptz             not null default now(),
  responded_at           timestamptz             null,
  created_at             timestamptz             not null default now(),
  updated_at             timestamptz             not null default now(),

  constraint review_participants_status_check
    check (status in ('pending','commented','signed_off','declined')),

  constraint review_participants_actor_xor_check
    check ((workspace_member_id is not null) <> (stakeholder_id is not null)),

  -- Composite tenant FKs.
  constraint review_participants_review_fk
    foreign key (review_id, workspace_id)
    references public.reviews (id, workspace_id)
    on delete restrict,

  constraint review_participants_workspace_member_fk
    foreign key (workspace_member_id, workspace_id)
    references public.workspace_members (id, workspace_id)
    on delete restrict,

  constraint review_participants_stakeholder_fk
    foreign key (stakeholder_id, workspace_id)
    references public.stakeholders (id, workspace_id)
    on delete restrict
);

comment on table public.review_participants is
  'Reviewer slot on a review. Slot exists at invitation time; the invitee may not yet have authenticated. XOR (workspace_member_id | stakeholder_id) matches PERMISSIONS.md roster-XOR pattern. DATABASE_SCHEMA.md v0.3 §3.14.';
comment on constraint review_participants_actor_xor_check on public.review_participants is
  'Exactly one identity path per slot. Same profile appearing via both paths on the same review is prevented at the RPC layer.';

-- Partial uniques prevent duplicate assignment per path.
create unique index review_participants_review_member_key
  on public.review_participants (review_id, workspace_member_id)
  where workspace_member_id is not null;

create unique index review_participants_review_stakeholder_key
  on public.review_participants (review_id, stakeholder_id)
  where stakeholder_id is not null;

create index review_participants_stakeholder_status_idx
  on public.review_participants (stakeholder_id, status)
  where stakeholder_id is not null;

create index review_participants_workspace_member_status_idx
  on public.review_participants (workspace_member_id, status)
  where workspace_member_id is not null;

drop trigger if exists review_participants_set_updated_at on public.review_participants;
create trigger review_participants_set_updated_at
  before update on public.review_participants
  for each row execute function public.set_updated_at();

alter table public.review_participants enable row level security;

------------------------------------------------------------------------------
-- 3. annotations (DATABASE_SCHEMA.md v0.3 §3.17)
--    Created before comments because comments may target annotations.
------------------------------------------------------------------------------

create table public.annotations (
  id                     uuid                    primary key default gen_random_uuid(),
  workspace_id           uuid                    not null,
  asset_version_id       uuid                    not null,
  version_file_id        uuid                    null,
  author_profile_id      uuid                    null references public.profiles (id) on delete set null,
  anchor_kind            text                    not null,
  page_number            integer                 null,
  position               jsonb                   not null,
  status                 text                    not null default 'active',
  resolved_at            timestamptz             null,
  archived_at            timestamptz             null,
  created_at             timestamptz             not null default now(),
  updated_at             timestamptz             not null default now(),

  -- Universal, industry-neutral anchor vocabulary. Nothing PDF/CAD/BIM-
  -- specific in the enum; per-media geometry lives in the position JSONB.
  constraint annotations_anchor_kind_check
    check (anchor_kind in ('point','region','page_point','page_region','time','three_d_node','document')),

  -- page_number only meaningful for paginated anchor kinds.
  constraint annotations_page_number_check
    check (page_number is null or anchor_kind in ('page_point','page_region')),

  constraint annotations_status_check
    check (status in ('active','resolved','archived')),

  -- Composite tenant FK: annotation lives in the same workspace as its
  -- origin version. Permanent anchoring per DOMAIN_MODEL.md §1.3.
  constraint annotations_asset_version_fk
    foreign key (asset_version_id, workspace_id)
    references public.asset_versions (id, workspace_id)
    on delete restrict,

  -- Optional file anchor: file must belong to the same asset_version.
  constraint annotations_version_file_fk
    foreign key (version_file_id, asset_version_id)
    references public.version_files (id, asset_version_id)
    on delete restrict,

  -- Composite unique target for comments.target_annotation_id.
  constraint annotations_id_workspace_key unique (id, workspace_id)
);

comment on table public.annotations is
  'Spatial/positional mark on a file (or the version as a whole) inside a specific asset_version. Permanently anchored to origin version. Geometry stored as JSONB shaped by anchor_kind. Position immutable after insert (trigger). DATABASE_SCHEMA.md v0.3 §3.17.';
comment on column public.annotations.position is
  'Normalized geometry per anchor_kind. JSONB shape is variable across kinds — deliberate. Never stores media-specific identifiers (no CAD entity IDs, no BIM GUIDs, no PDF native objects).';

create index annotations_version_status_idx
  on public.annotations (asset_version_id, status);
create index annotations_version_file_page_idx
  on public.annotations (version_file_id, page_number)
  where version_file_id is not null;
create index annotations_workspace_active_idx
  on public.annotations (workspace_id, status)
  where status = 'active';
create index annotations_author_profile_id_idx
  on public.annotations (author_profile_id)
  where author_profile_id is not null;

drop trigger if exists annotations_set_updated_at on public.annotations;
create trigger annotations_set_updated_at
  before update on public.annotations
  for each row execute function public.set_updated_at();

-- Position immutability trigger.
create or replace function public.enforce_annotation_position_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.anchor_kind is distinct from old.anchor_kind
    or new.page_number is distinct from old.page_number
    or new.position    is distinct from old.position
    or new.asset_version_id is distinct from old.asset_version_id
    or new.version_file_id  is distinct from old.version_file_id
  then
    raise exception 'annotations position/anchor is immutable after insert (row id=%)', old.id
      using errcode = '23514';
  end if;
  return new;
end;
$$;

comment on function public.enforce_annotation_position_immutable() is
  'DB-boundary trigger: annotation anchor_kind, page_number, position, asset_version_id, version_file_id are immutable after insert. Moving a pin creates a new annotation per DOMAIN_MODEL.md §1.3.';

drop trigger if exists annotations_position_immutable on public.annotations;
create trigger annotations_position_immutable
  before update on public.annotations
  for each row execute function public.enforce_annotation_position_immutable();

alter table public.annotations enable row level security;

------------------------------------------------------------------------------
-- 4. comments (DATABASE_SCHEMA.md v0.3 §3.15)
--
--    Comments carry seven typed target columns (one nullable FK per
--    possible target type) with a strict XOR CHECK: exactly one target
--    is non-null. Cross-workspace targeting is structurally prevented by
--    composite (target_x_id, workspace_id) FKs.
--
--    FKs for target_change_id, target_decision_id, target_approval_request_id
--    are DEFERRED to Migrations 006 and 007. The columns and the XOR check
--    exist from this migration so the invariant is expressed once and
--    downstream migrations only ADD CONSTRAINT.
------------------------------------------------------------------------------

create table public.comments (
  id                             uuid                    primary key default gen_random_uuid(),
  workspace_id                   uuid                    not null,
  parent_comment_id              uuid                    null,
  body                           text                    not null,
  author_profile_id              uuid                    null references public.profiles (id) on delete set null,
  resolved_at                    timestamptz             null,
  deleted_at                     timestamptz             null,

  target_version_id              uuid                    null,
  target_review_id               uuid                    null,
  target_annotation_id           uuid                    null,
  target_change_id               uuid                    null,
  target_decision_id             uuid                    null,
  target_design_asset_id         uuid                    null,
  target_approval_request_id     uuid                    null,

  created_at                     timestamptz             not null default now(),
  updated_at                     timestamptz             not null default now(),

  -- Exactly one target column is non-null.
  constraint comments_target_xor_check check (
    (target_version_id is not null)::int
    + (target_review_id is not null)::int
    + (target_annotation_id is not null)::int
    + (target_change_id is not null)::int
    + (target_decision_id is not null)::int
    + (target_design_asset_id is not null)::int
    + (target_approval_request_id is not null)::int
    = 1
  ),

  -- Self-reference for threading. Composite with workspace_id so a reply
  -- cannot cross workspace boundaries (invariant H). RESTRICT preserves
  -- thread structure — comment deletion is soft (deleted_at) rather than
  -- physical. Schema §3.15 describes the parent FK as single-column; the
  -- composite form is a defensive strengthening that satisfies the
  -- cross-scope invariant without weakening any spec behavior.
  constraint comments_parent_fk
    foreign key (parent_comment_id, workspace_id)
    references public.comments (id, workspace_id)
    on delete restrict,

  -- Composite typed-target FKs, per DATABASE_SCHEMA.md v0.3 §3.15. Each is
  -- composite with workspace_id and ON DELETE RESTRICT. Cross-workspace
  -- targeting is structurally impossible.
  constraint comments_target_version_fk
    foreign key (target_version_id, workspace_id)
    references public.asset_versions (id, workspace_id)
    on delete restrict,

  constraint comments_target_review_fk
    foreign key (target_review_id, workspace_id)
    references public.reviews (id, workspace_id)
    on delete restrict,

  constraint comments_target_annotation_fk
    foreign key (target_annotation_id, workspace_id)
    references public.annotations (id, workspace_id)
    on delete restrict,

  constraint comments_target_design_asset_fk
    foreign key (target_design_asset_id, workspace_id)
    references public.design_assets (id, workspace_id)
    on delete restrict,

  -- Deferred: target_change_id, target_decision_id, target_approval_request_id
  -- FKs added in Migrations 006 and 007 when the target tables land.

  -- Composite unique target for comment_edits.
  constraint comments_id_workspace_key unique (id, workspace_id)
);

comment on table public.comments is
  'Threaded textual feedback with typed targets. Exactly one of seven target_* columns is set (XOR CHECK). Cross-workspace targeting structurally impossible via composite FKs. Author attribution via profiles. DATABASE_SCHEMA.md v0.3 §3.15.';
comment on constraint comments_target_xor_check on public.comments is
  'Sum-of-non-null pattern: exactly one target is set. The seven target columns are declared here even though three of their FK constraints (change, decision, approval_request) are added by later migrations when the target tables exist.';
comment on column public.comments.parent_comment_id is
  'Threading self-reference. ON DELETE RESTRICT preserves thread structure — comment deletion is soft (deleted_at) rather than physical.';
comment on column public.comments.author_profile_id is
  'Profile-level attribution. Impersonation guard (author_profile_id = auth.uid()) is enforced in RLS INSERT policies added by the authorization stage.';

-- Common query indexes: per-target activity feeds + workspace-scoped unresolved.
create index comments_parent_idx
  on public.comments (parent_comment_id)
  where parent_comment_id is not null;

create index comments_target_version_idx
  on public.comments (target_version_id, created_at desc)
  where target_version_id is not null;

create index comments_target_review_idx
  on public.comments (target_review_id, created_at desc)
  where target_review_id is not null;

create index comments_target_annotation_idx
  on public.comments (target_annotation_id, created_at desc)
  where target_annotation_id is not null;

create index comments_target_design_asset_idx
  on public.comments (target_design_asset_id, created_at desc)
  where target_design_asset_id is not null;

-- Partial indexes for the deferred targets: kept lightweight so they exist
-- from day one and continue working when the FKs land.
create index comments_target_change_idx
  on public.comments (target_change_id, created_at desc)
  where target_change_id is not null;

create index comments_target_decision_idx
  on public.comments (target_decision_id, created_at desc)
  where target_decision_id is not null;

create index comments_target_approval_request_idx
  on public.comments (target_approval_request_id, created_at desc)
  where target_approval_request_id is not null;

create index comments_workspace_unresolved_idx
  on public.comments (workspace_id, resolved_at)
  where resolved_at is null and deleted_at is null;

create index comments_author_profile_id_idx
  on public.comments (author_profile_id)
  where author_profile_id is not null;

drop trigger if exists comments_set_updated_at on public.comments;
create trigger comments_set_updated_at
  before update on public.comments
  for each row execute function public.set_updated_at();

alter table public.comments enable row level security;

------------------------------------------------------------------------------
-- 5. comment_edits (DATABASE_SCHEMA.md v0.3 §3.16)
--    Append-only relational edit history. No updated_at column; row is
--    immutable after insert. Trigger blocks UPDATE and DELETE.
------------------------------------------------------------------------------

create table public.comment_edits (
  id                     uuid                    primary key default gen_random_uuid(),
  workspace_id           uuid                    not null,
  comment_id             uuid                    not null,
  revision               integer                 not null,
  previous_body          text                    not null,
  edited_by_profile_id   uuid                    null references public.profiles (id) on delete set null,
  edited_at              timestamptz             not null default now(),

  constraint comment_edits_revision_positive_check check (revision > 0),

  -- Composite tenant FK to comments.
  constraint comment_edits_comment_fk
    foreign key (comment_id, workspace_id)
    references public.comments (id, workspace_id)
    on delete restrict,

  -- One revision number per comment.
  constraint comment_edits_comment_revision_key unique (comment_id, revision)
);

comment on table public.comment_edits is
  'Append-only relational history of comment body revisions. Each row captures the previous_body at the moment of an edit. Never updated, never deleted (trigger). DATABASE_SCHEMA.md v0.3 §3.16.';

create index comment_edits_comment_edited_idx on public.comment_edits (comment_id, edited_at desc);
create index comment_edits_edited_by_profile_id_idx
  on public.comment_edits (edited_by_profile_id)
  where edited_by_profile_id is not null;

-- Append-only trigger: reject UPDATE and DELETE.
create or replace function public.enforce_comment_edits_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'comment_edits is append-only; % operation is not permitted', tg_op
    using errcode = '23514';
end;
$$;

comment on function public.enforce_comment_edits_append_only() is
  'DB-boundary trigger: comment_edits rows are immutable after insert. Both UPDATE and DELETE are rejected.';

drop trigger if exists comment_edits_no_update on public.comment_edits;
create trigger comment_edits_no_update
  before update on public.comment_edits
  for each row execute function public.enforce_comment_edits_append_only();

drop trigger if exists comment_edits_no_delete on public.comment_edits;
create trigger comment_edits_no_delete
  before delete on public.comment_edits
  for each row execute function public.enforce_comment_edits_append_only();

alter table public.comment_edits enable row level security;
