-- Migration 006: changes_decisions
--
-- Contents:
--   0. Migration 005 FK-index hardening (13 unindexed_foreign_keys findings).
--   1. public.changes   — recorded requested/proposed design modifications.
--   2. public.decisions — durable recorded outcomes with typed targets.
--   3. Deferred Comment FKs completed:
--        comments.target_change_id   → changes(id, workspace_id)
--        comments.target_decision_id → decisions(id, workspace_id)
--   4. Structural immutability trigger on decisions (allowing only
--      supersedes_decision_id to change post-insert; DELETE blocked).
--   5. Covering indexes for every new FK introduced by this migration —
--      goal: zero new unindexed_foreign_keys advisor findings.
--   6. RLS enabled on both new tables with NO policies.
--
-- MVP lifecycle notes (STATE_MACHINES.md v1 §12):
--   - changes.status enum retains all six values ('proposed','under_review',
--     'accepted','rejected','implemented','withdrawn') per the frozen
--     schema. MVP transitions exercise only proposed → accepted | rejected
--     | withdrawn. 'under_review' and 'implemented' are reserved.
--
-- Historical-retention posture (DOMAIN_MODEL.md §0):
--   - changes: composite tenant FKs ON DELETE RESTRICT; author SET NULL;
--     optional origin references (review, comment) composite ON DELETE
--     RESTRICT for full history preservation.
--   - decisions: composite tenant FKs ON DELETE RESTRICT; author SET NULL;
--     supersedes self-reference ON DELETE RESTRICT.
--
-- Explicit non-goals:
--   - No approval_requests / releases / activity_events (later migrations).
--   - No RPCs (record_decision, change.resolve, etc.).
--   - No mention parsing / notification emission.
--   - No storage, pg_cron, pg_net.
--
-- Deferred to later migrations:
--   - decisions.target_approval_request_fk (Migration 007)
--   - decisions.resulting_release_fk       (Migration 008)
--   - comments.target_approval_request_fk  (Migration 007)

------------------------------------------------------------------------------
-- 0. Migration 005 FK-index hardening — 13 covering indexes
------------------------------------------------------------------------------

-- annotations.asset_version_fk (asset_version_id, workspace_id)
create index if not exists annotations_asset_version_workspace_idx
  on public.annotations (asset_version_id, workspace_id);

-- annotations.version_file_fk (version_file_id, asset_version_id) partial
create index if not exists annotations_version_file_version_idx
  on public.annotations (version_file_id, asset_version_id)
  where version_file_id is not null;

-- comment_edits.comment_fk (comment_id, workspace_id)
create index if not exists comment_edits_comment_workspace_idx
  on public.comment_edits (comment_id, workspace_id);

-- comments.parent_fk (parent_comment_id, workspace_id) partial
create index if not exists comments_parent_workspace_idx
  on public.comments (parent_comment_id, workspace_id)
  where parent_comment_id is not null;

-- comments target FKs (partial composite)
create index if not exists comments_target_annotation_workspace_idx
  on public.comments (target_annotation_id, workspace_id)
  where target_annotation_id is not null;

create index if not exists comments_target_design_asset_workspace_idx
  on public.comments (target_design_asset_id, workspace_id)
  where target_design_asset_id is not null;

create index if not exists comments_target_review_workspace_idx
  on public.comments (target_review_id, workspace_id)
  where target_review_id is not null;

create index if not exists comments_target_version_workspace_idx
  on public.comments (target_version_id, workspace_id)
  where target_version_id is not null;

-- review_participants FKs
create index if not exists review_participants_review_workspace_idx
  on public.review_participants (review_id, workspace_id);

create index if not exists review_participants_stakeholder_workspace_idx2
  on public.review_participants (stakeholder_id, workspace_id)
  where stakeholder_id is not null;

create index if not exists review_participants_workspace_member_workspace_idx2
  on public.review_participants (workspace_member_id, workspace_id)
  where workspace_member_id is not null;

-- reviews FKs
create index if not exists reviews_asset_project_workspace_idx
  on public.reviews (design_asset_id, project_id, workspace_id);

create index if not exists reviews_version_asset_idx
  on public.reviews (version_id, design_asset_id);

------------------------------------------------------------------------------
-- 1. changes (DATABASE_SCHEMA.md v0.3 §3.18)
------------------------------------------------------------------------------

create table public.changes (
  id                     uuid                    primary key default gen_random_uuid(),
  workspace_id           uuid                    not null,
  project_id             uuid                    not null,
  design_asset_id        uuid                    not null,
  title                  text                    not null,
  description            text                    null,
  from_version_id        uuid                    null,
  to_version_id          uuid                    null,
  origin_review_id       uuid                    null,
  origin_comment_id      uuid                    null,
  status                 text                    not null default 'proposed',
  created_by_profile_id  uuid                    null references public.profiles (id) on delete set null,
  resolved_at            timestamptz             null,
  created_at             timestamptz             not null default now(),
  updated_at             timestamptz             not null default now(),

  -- Full frozen status vocabulary preserved. MVP exercises only
  -- proposed → accepted | rejected | withdrawn per STATE_MACHINES.md v1
  -- §12. 'under_review' and 'implemented' are reserved values.
  constraint changes_status_check
    check (status in ('proposed','under_review','accepted','rejected','implemented','withdrawn')),

  -- from and to must reference different versions (when both are set).
  constraint changes_version_distinct_check
    check (from_version_id is null or to_version_id is null or from_version_id <> to_version_id),

  -- Composite tenant/scope FK: change lives in asset's project + workspace.
  constraint changes_design_asset_fk
    foreign key (design_asset_id, project_id, workspace_id)
    references public.design_assets (id, project_id, workspace_id)
    on delete restrict,

  -- Optional from/to version references must belong to the SAME design_asset.
  constraint changes_from_version_fk
    foreign key (from_version_id, design_asset_id)
    references public.asset_versions (id, design_asset_id)
    on delete restrict,

  constraint changes_to_version_fk
    foreign key (to_version_id, design_asset_id)
    references public.asset_versions (id, design_asset_id)
    on delete restrict,

  -- Optional origin references: same workspace (tenant integrity).
  constraint changes_origin_review_fk
    foreign key (origin_review_id, workspace_id)
    references public.reviews (id, workspace_id)
    on delete restrict,

  constraint changes_origin_comment_fk
    foreign key (origin_comment_id, workspace_id)
    references public.comments (id, workspace_id)
    on delete restrict,

  -- Composite unique target for downstream tables (comments.target_change_id
  -- and decisions.target_change_id both use workspace_id-composite FKs).
  constraint changes_id_workspace_key unique (id, workspace_id)
);

comment on table public.changes is
  'Recorded requested or proposed modification to a design_asset. Universal (no RFI / variation order / change order terminology). MVP lifecycle: proposed → accepted | rejected | withdrawn. Reserved values ''under_review'' and ''implemented'' remain in the enum for future workflows. DATABASE_SCHEMA.md v0.3 §3.18.';
comment on column public.changes.from_version_id is
  'Optional prior version being critiqued. Nullable per DOMAIN_MODEL.md §1.4 — a change may exist without a meaningful comparison source. Composite FK enforces same-asset.';
comment on column public.changes.to_version_id is
  'Optional resolving version. Composite FK enforces same-asset. Linking to_version_id when an accepted change is implemented is a metadata update, not a state transition (MVP has no ''implemented'' transition).';

-- FK covering indexes (goal: zero new unindexed_foreign_keys findings).
create index changes_design_asset_project_workspace_idx
  on public.changes (design_asset_id, project_id, workspace_id);

create index changes_from_version_asset_idx
  on public.changes (from_version_id, design_asset_id)
  where from_version_id is not null;

create index changes_to_version_asset_idx
  on public.changes (to_version_id, design_asset_id)
  where to_version_id is not null;

create index changes_origin_review_workspace_idx
  on public.changes (origin_review_id, workspace_id)
  where origin_review_id is not null;

create index changes_origin_comment_workspace_idx
  on public.changes (origin_comment_id, workspace_id)
  where origin_comment_id is not null;

create index changes_created_by_profile_id_idx
  on public.changes (created_by_profile_id)
  where created_by_profile_id is not null;

-- Spec-required domain query indexes (DATABASE_SCHEMA.md v0.3 §3.18).
create index changes_asset_status_idx     on public.changes (design_asset_id, status);
create index changes_workspace_status_idx on public.changes (workspace_id, status);

drop trigger if exists changes_set_updated_at on public.changes;
create trigger changes_set_updated_at
  before update on public.changes
  for each row execute function public.set_updated_at();

alter table public.changes enable row level security;

------------------------------------------------------------------------------
-- 2. decisions (DATABASE_SCHEMA.md v0.3 §3.19)
--
-- Decisions are workspace-scoped (no project_id column). Project context is
-- resolved through the typed target when needed. Row is immutable-once-
-- written: no created_at/updated_at standard columns; only recorded_at.
-- The immutability trigger permits only supersedes_decision_id to change
-- (the "except supersession linkage" exception in the domain invariant).
------------------------------------------------------------------------------

create table public.decisions (
  id                             uuid                    primary key default gen_random_uuid(),
  workspace_id                   uuid                    not null references public.workspaces (id) on delete restrict,
  title                          text                    not null,
  body                           text                    not null,
  outcome                        text                    null,
  author_profile_id              uuid                    null references public.profiles (id) on delete set null,
  supersedes_decision_id         uuid                    null,
  recorded_at                    timestamptz             not null default now(),

  -- Five typed target columns. Approval FK is deferred to Migration 007.
  target_design_asset_id         uuid                    null,
  target_version_id              uuid                    null,
  target_review_id               uuid                    null,
  target_change_id               uuid                    null,
  target_approval_request_id     uuid                    null,

  -- Resulting cross-references. Release FK is deferred to Migration 008.
  resulting_version_id           uuid                    null,
  resulting_release_id           uuid                    null,

  -- Exactly one primary target column is non-null.
  constraint decisions_target_xor_check check (
    (target_design_asset_id is not null)::int
    + (target_version_id is not null)::int
    + (target_review_id is not null)::int
    + (target_change_id is not null)::int
    + (target_approval_request_id is not null)::int
    = 1
  ),

  -- Composite target FKs (currently addable). Approval FK deferred.
  constraint decisions_target_design_asset_fk
    foreign key (target_design_asset_id, workspace_id)
    references public.design_assets (id, workspace_id)
    on delete restrict,

  constraint decisions_target_version_fk
    foreign key (target_version_id, workspace_id)
    references public.asset_versions (id, workspace_id)
    on delete restrict,

  constraint decisions_target_review_fk
    foreign key (target_review_id, workspace_id)
    references public.reviews (id, workspace_id)
    on delete restrict,

  constraint decisions_target_change_fk
    foreign key (target_change_id, workspace_id)
    references public.changes (id, workspace_id)
    on delete restrict,

  -- Resulting version FK (release FK deferred).
  constraint decisions_resulting_version_fk
    foreign key (resulting_version_id, workspace_id)
    references public.asset_versions (id, workspace_id)
    on delete restrict,

  -- Supersession self-reference (defensive composite with workspace_id).
  constraint decisions_supersedes_fk
    foreign key (supersedes_decision_id, workspace_id)
    references public.decisions (id, workspace_id)
    on delete restrict,

  -- Composite unique target for comments.target_decision_id and for
  -- decisions.supersedes_decision_fk self-reference.
  constraint decisions_id_workspace_key unique (id, workspace_id)
);

comment on table public.decisions is
  'Durable recorded outcome from design collaboration. Broader than approval: direction, scope, priority, technical trade-offs. Immutable after insert except supersedes_decision_id linkage. Never deleted. Not a comment, approval, change, or task. DATABASE_SCHEMA.md v0.3 §3.19.';
comment on constraint decisions_target_xor_check on public.decisions is
  'Exactly one primary target. The approval-request target column exists here (nullable) so downstream Migration 007 can ADD CONSTRAINT for its FK without column-shape changes.';
comment on column public.decisions.supersedes_decision_id is
  'Forward-linked only: a later decision may point at the earlier one it supersedes. Composite FK with workspace_id defensively enforces same-workspace linkage.';
comment on column public.decisions.recorded_at is
  'Immutable timestamp of the decision. No standard created_at/updated_at columns — decisions are immutable-once-written per DATABASE_SCHEMA.md v0.3 §3 Standard columns note.';

-- FK covering indexes (partial for nullable columns).
create index decisions_target_design_asset_workspace_idx
  on public.decisions (target_design_asset_id, workspace_id)
  where target_design_asset_id is not null;

create index decisions_target_version_workspace_idx
  on public.decisions (target_version_id, workspace_id)
  where target_version_id is not null;

create index decisions_target_review_workspace_idx
  on public.decisions (target_review_id, workspace_id)
  where target_review_id is not null;

create index decisions_target_change_workspace_idx
  on public.decisions (target_change_id, workspace_id)
  where target_change_id is not null;

-- Column-only index for the target column whose FK is deferred to M007.
-- Prepares the covering index in advance so Migration 007's ALTER TABLE
-- ADD CONSTRAINT does not introduce a new unindexed_foreign_keys finding.
create index decisions_target_approval_request_workspace_idx
  on public.decisions (target_approval_request_id, workspace_id)
  where target_approval_request_id is not null;

create index decisions_resulting_version_workspace_idx
  on public.decisions (resulting_version_id, workspace_id)
  where resulting_version_id is not null;

-- Column-only index for deferred resulting_release_fk (Migration 008).
create index decisions_resulting_release_workspace_idx
  on public.decisions (resulting_release_id, workspace_id)
  where resulting_release_id is not null;

create index decisions_supersedes_workspace_idx
  on public.decisions (supersedes_decision_id, workspace_id)
  where supersedes_decision_id is not null;

create index decisions_author_profile_id_idx
  on public.decisions (author_profile_id)
  where author_profile_id is not null;

-- Spec-required domain query indexes.
create index decisions_workspace_recorded_idx
  on public.decisions (workspace_id, recorded_at desc);

create index decisions_target_design_asset_recorded_idx
  on public.decisions (target_design_asset_id, recorded_at desc)
  where target_design_asset_id is not null;

alter table public.decisions enable row level security;

-- Immutability trigger. Allow only supersedes_decision_id to change.
create or replace function public.enforce_decisions_immutable_except_supersedes()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.workspace_id                is distinct from old.workspace_id
    or new.title                     is distinct from old.title
    or new.body                      is distinct from old.body
    or new.outcome                   is distinct from old.outcome
    or new.author_profile_id         is distinct from old.author_profile_id
    or new.recorded_at               is distinct from old.recorded_at
    or new.target_design_asset_id    is distinct from old.target_design_asset_id
    or new.target_version_id         is distinct from old.target_version_id
    or new.target_review_id          is distinct from old.target_review_id
    or new.target_change_id          is distinct from old.target_change_id
    or new.target_approval_request_id is distinct from old.target_approval_request_id
    or new.resulting_version_id      is distinct from old.resulting_version_id
    or new.resulting_release_id      is distinct from old.resulting_release_id
  then
    raise exception 'decisions is immutable after insert (except supersedes_decision_id linkage); row id=%', old.id
      using errcode = '23514';
  end if;
  return new;
end;
$$;

comment on function public.enforce_decisions_immutable_except_supersedes() is
  'DB-boundary trigger: decisions rows are immutable after insert except for supersedes_decision_id, which may be updated (forward-linked supersession).';

drop trigger if exists decisions_immutable on public.decisions;
create trigger decisions_immutable
  before update on public.decisions
  for each row execute function public.enforce_decisions_immutable_except_supersedes();

-- Block deletion (decisions never deleted per DOMAIN_MODEL.md §1.5).
create or replace function public.enforce_decisions_no_delete()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'decisions rows may not be deleted (row id=%)', old.id
    using errcode = '23514';
end;
$$;

comment on function public.enforce_decisions_no_delete() is
  'DB-boundary trigger: decisions may not be deleted. Historical record is permanent.';

drop trigger if exists decisions_no_delete on public.decisions;
create trigger decisions_no_delete
  before delete on public.decisions
  for each row execute function public.enforce_decisions_no_delete();

------------------------------------------------------------------------------
-- 3. Complete deferred Comment FKs
--
--    Migration 005 declared target_change_id and target_decision_id
--    columns on comments and included them in the 7-way XOR CHECK. Now
--    that changes and decisions exist, add the composite tenant FKs.
------------------------------------------------------------------------------

alter table public.comments
  add constraint comments_target_change_fk
    foreign key (target_change_id, workspace_id)
    references public.changes (id, workspace_id)
    on delete restrict;

alter table public.comments
  add constraint comments_target_decision_fk
    foreign key (target_decision_id, workspace_id)
    references public.decisions (id, workspace_id)
    on delete restrict;

-- Covering indexes for the newly-added Comment FKs. The existing
-- comments_target_change_idx (target_change_id, created_at DESC) and
-- comments_target_decision_idx (target_decision_id, created_at DESC) from
-- Migration 005 lead with the target column but their second column is
-- created_at (not workspace_id) — Supabase advisor wants an index whose
-- column-list matches the composite FK. Add them.

create index if not exists comments_target_change_workspace_idx
  on public.comments (target_change_id, workspace_id)
  where target_change_id is not null;

create index if not exists comments_target_decision_workspace_idx
  on public.comments (target_decision_id, workspace_id)
  where target_decision_id is not null;

comment on constraint comments_target_change_fk on public.comments is
  'Deferred from Migration 005 — added when the changes table came online.';
comment on constraint comments_target_decision_fk on public.comments is
  'Deferred from Migration 005 — added when the decisions table came online.';
