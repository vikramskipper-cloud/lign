-- APP 008: Requirements product-surface additive schema.
--
-- Frozen sources: REQUIREMENTS 001–005 (byte-identical baseline preserved),
-- APP 002 workspaces_identity (workspace_members composite unique key).
--
-- Delivers the additive schema delta enumerated in APP_008_BACKEND_PROPOSAL §3–§6:
--   * 6 nullable columns on public.requirements
--       (priority, source_kind, category_kind, owner_profile_id,
--        verification_method, due_at)
--   * 1 nullable column on public.comments (target_requirement_id) + XOR widening
--   * 4 NULL-permissive CHECK constraints on requirements
--   * 2 composite FKs (owner_profile_id → workspace_members(user_id, workspace_id);
--                     comments.target_requirement_id → requirements(id, workspace_id))
--   * 7 additive indexes (I-1 … I-7) + 2 covering composite FK indexes
--   * 1 optional convenience trigger (requirements_default_owner_on_insert)
--
-- All additions are additive-only per APP 008 §24 backwards-compat guarantees.
-- No frozen surface renamed, dropped, or narrowed.

------------------------------------------------------------------------------
-- 1. requirements: additive nullable columns
------------------------------------------------------------------------------

alter table public.requirements
  add column if not exists priority             text        null default 'medium',
  add column if not exists source_kind          text        null,
  add column if not exists category_kind        text        null,
  add column if not exists owner_profile_id     uuid        null,
  add column if not exists verification_method  text        null,
  add column if not exists due_at               timestamptz null;

comment on column public.requirements.priority is
  'APP 008 §3.1: ordinal priority tier (critical|high|medium|low|informational). NULL for pre-APP-008 rows; new rows default to ''medium'' per G-34.';
comment on column public.requirements.source_kind is
  'APP 008 §3.2: enum-backed source dimension (client|consultant|regulatory|internal_team|qa|procurement|manufacturing|safety|contractual|other). Free-text ''source'' preserved for human label.';
comment on column public.requirements.category_kind is
  'APP 008 §3.3: enum-backed category dimension (functional|non_functional|regulatory|contractual|technical|aesthetic|sustainability|safety|operational|other). Free-text ''category'' preserved for human label.';
comment on column public.requirements.owner_profile_id is
  'APP 008 §3.4 / G-24: mutable owner distinct from created_by_profile_id. Composite FK to workspace_members(user_id, workspace_id) enforces active workspace membership (G-33). Falls back to created_by_profile_id in the read layer when NULL.';
comment on column public.requirements.verification_method is
  'APP 008 §3.5 / §23.11: systems-engineering verification taxonomy (inspection|test|analysis|demonstration). Reserved; not surfaced in v1 UX.';
comment on column public.requirements.due_at is
  'APP 008 §3.6 / §12.1: first-assessment deadline for overdue_critical dashboard view and reserved requirement.due_soon / requirement.overdue cron emitters.';

------------------------------------------------------------------------------
-- 2. requirements: NULL-permissive CHECK constraints
------------------------------------------------------------------------------

alter table public.requirements
  add constraint requirements_priority_check
    check (priority is null or priority in ('critical','high','medium','low','informational'));

alter table public.requirements
  add constraint requirements_source_kind_check
    check (source_kind is null or source_kind in (
      'client','consultant','regulatory','internal_team','qa',
      'procurement','manufacturing','safety','contractual','other'
    ));

alter table public.requirements
  add constraint requirements_category_kind_check
    check (category_kind is null or category_kind in (
      'functional','non_functional','regulatory','contractual','technical',
      'aesthetic','sustainability','safety','operational','other'
    ));

alter table public.requirements
  add constraint requirements_verification_method_check
    check (verification_method is null or verification_method in (
      'inspection','test','analysis','demonstration'
    ));

------------------------------------------------------------------------------
-- 3. requirements: composite FK on owner_profile_id
------------------------------------------------------------------------------
-- Enforces G-33: owner must be an active workspace_member of the requirement's
-- workspace. workspace_members.user_id is the FK to public.profiles(id) per
-- 20260728220000_workspaces_identity.sql L90; the composite UNIQUE
-- workspace_members_workspace_user_key on (workspace_id, user_id) satisfies
-- this FK. ON DELETE SET NULL preserves the requirement row when a member
-- leaves; the read layer falls back to created_by_profile_id.

alter table public.requirements
  add constraint requirements_owner_workspace_fk
    foreign key (owner_profile_id, workspace_id)
    references public.workspace_members (user_id, workspace_id)
    on delete set null;

------------------------------------------------------------------------------
-- 4. requirements: additive indexes (I-1, I-2, I-3, I-4, I-5, I-6)
------------------------------------------------------------------------------
-- I-1 Priority-sorted dashboard scans (Freeze Index §8.2, §12.1 by_priority).
create index if not exists requirements_project_priority_idx
  on public.requirements (project_id, priority)
  where status in ('draft','active');

-- I-2 assigned_to_me + owner filter (Freeze Index §12.1, §13.2).
create index if not exists requirements_project_owner_idx
  on public.requirements (project_id, owner_profile_id)
  where owner_profile_id is not null;

-- I-3 by_source view + ?source= filter.
create index if not exists requirements_project_source_idx
  on public.requirements (project_id, source_kind)
  where source_kind is not null;

-- I-4 ?category= filter + compliance breakdown.
create index if not exists requirements_project_category_idx
  on public.requirements (project_id, category_kind)
  where category_kind is not null;

-- I-5 overdue_critical view + reserved cron scan.
create index if not exists requirements_due_at_partial_idx
  on public.requirements (due_at)
  where due_at is not null and status in ('draft','active');

-- I-6 GIN trigram on title + description for ?search= (Freeze Index §13.1).
-- Extension installed in the `extensions` schema (project convention);
-- operator classes are qualified accordingly to keep public.requirements clean.
create extension if not exists pg_trgm with schema extensions;
create index if not exists requirements_title_desc_trgm_idx
  on public.requirements
  using gin (title extensions.gin_trgm_ops, description extensions.gin_trgm_ops);

-- Covering composite index so the unindexed_foreign_keys linter recognizes
-- requirements_owner_workspace_fk. Partial (nullable leading column) to stay small.
create index if not exists requirements_owner_workspace_covering_idx
  on public.requirements (owner_profile_id, workspace_id)
  where owner_profile_id is not null;

------------------------------------------------------------------------------
-- 5. comments: additive nullable column + composite FK
------------------------------------------------------------------------------
-- 8th XOR target arm for requirement-scoped discussions (Freeze Index §10.3, G-7).

alter table public.comments
  add column if not exists target_requirement_id uuid null;

comment on column public.comments.target_requirement_id is
  'APP 008 §3.7 / G-7: 8th XOR-target arm for requirement-scoped discussions. Composite FK to requirements(id, workspace_id) for tenant coherence; ON DELETE SET NULL preserves the comment row.';

alter table public.comments
  add constraint comments_target_requirement_workspace_fk
    foreign key (target_requirement_id, workspace_id)
    references public.requirements (id, workspace_id)
    on delete set null;

------------------------------------------------------------------------------
-- 6. comments: widen XOR-target CHECK from 7 arms to 8 arms
------------------------------------------------------------------------------
-- Frozen predicate shape (= 1) preserved; only arm count changes (§6.1).
-- Drop-and-recreate under the same constraint name; existing rows all satisfy
-- the widened predicate because each has exactly one target set.

alter table public.comments
  drop constraint if exists comments_target_xor_check;

alter table public.comments
  add constraint comments_target_xor_check check ((
    (target_version_id           is not null)::int
    + (target_review_id          is not null)::int
    + (target_annotation_id      is not null)::int
    + (target_change_id          is not null)::int
    + (target_decision_id        is not null)::int
    + (target_design_asset_id    is not null)::int
    + (target_approval_request_id is not null)::int
    + (target_requirement_id     is not null)::int
  ) = 1);

------------------------------------------------------------------------------
-- 7. comments: partial + covering indexes on the new target column (I-7)
------------------------------------------------------------------------------
create index if not exists comments_target_requirement_partial_idx
  on public.comments (target_requirement_id)
  where target_requirement_id is not null;

-- Covering composite index so the unindexed_foreign_keys linter recognizes
-- comments_target_requirement_workspace_fk.
create index if not exists comments_target_requirement_workspace_covering_idx
  on public.comments (target_requirement_id, workspace_id)
  where target_requirement_id is not null;

------------------------------------------------------------------------------
-- 8. Optional convenience trigger: default owner_profile_id on INSERT
------------------------------------------------------------------------------
-- Populates owner_profile_id from created_by_profile_id when unset so the
-- assigned_to_me dashboard view is coherent for requirements authored via the
-- frozen create_requirement RPC (which sets created_by_profile_id from
-- auth.uid() per REQUIREMENTS 003 L235–L236). Silent no-op path when
-- created_by_profile_id is NULL (raw service-role bypass).

create or replace function public.requirements_default_owner_on_insert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.owner_profile_id is null and new.created_by_profile_id is not null then
    new.owner_profile_id := new.created_by_profile_id;
  end if;
  return new;
end $$;

comment on function public.requirements_default_owner_on_insert() is
  'APP 008 §11.1: BEFORE INSERT convenience — defaults owner_profile_id to created_by_profile_id when unset. Not an invariant; the read layer already falls back. Silent no-op when created_by_profile_id is NULL.';

drop trigger if exists requirements_default_owner_on_insert on public.requirements;
create trigger requirements_default_owner_on_insert
  before insert on public.requirements
  for each row execute function public.requirements_default_owner_on_insert();

revoke all on function public.requirements_default_owner_on_insert() from public, anon, authenticated;

-- No GRANT to authenticated — trigger functions fire under the row-writer's
-- transaction context. Matches the frozen REQUIREMENTS 002 REVOKE block at
-- L494–L497.
