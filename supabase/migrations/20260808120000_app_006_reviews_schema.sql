-- Migration 012 (APP 006): Reviews schema
--
-- Backend re-freeze for APP 006 — Reviews. Implements the frozen
-- APP_006_BACKEND_PROPOSAL.md schema surface:
--
--   1. New columns on reviews (round chain, coordinator, policy, quorum,
--      require-comments-resolved, cancellation reason)
--   2. New columns on review_participants (required, sequence_index,
--      removed_at, removed_reason)
--   3. Status enum expansion: adds ready_for_review + waiting
--   4. Composite tenancy FKs for chain (parent_review_id, root_review_id)
--   5. Chain integrity CHECK constraints
--   6. Policy consistency CHECK
--   7. Chain-immutability trigger (defense-in-depth over RPC-side enforcement)
--   8. New indexes covering every new FK/predicate/sort
--   9. New tables: user_bookmarks, user_saved_views
--   10. RLS policies for new tables (roster mutation stays RPC-only)
--
-- Non-goals of this migration:
--   * No new capability keys (Migration 013 extends lign_has_capability)
--   * No new RPCs (Migration 013)
--   * No emitter for the RESERVED event types (review.deadline_approached
--     / review.deadline_passed) — types are name-only frozen in the event
--     vocabulary; emitters are a later cron slice
--   * No changes to any APP 001–005 frozen table's existing structure
--
-- Transaction control: none inline. Supabase migration runner wraps.

------------------------------------------------------------------------------
-- 1. reviews.status enum expansion
------------------------------------------------------------------------------
-- Existing:  draft | open | in_progress | completed | cancelled
-- Adds:      ready_for_review | waiting

alter table public.reviews
  drop constraint if exists reviews_status_check;

alter table public.reviews
  add constraint reviews_status_check
    check (status in ('draft','ready_for_review','open','in_progress','waiting','completed','cancelled'));

------------------------------------------------------------------------------
-- 2. reviews — new columns
------------------------------------------------------------------------------

alter table public.reviews
  add column if not exists round_number integer not null default 1,
  add column if not exists parent_review_id uuid null,
  add column if not exists root_review_id uuid null,
  add column if not exists coordinator_profile_id uuid null,
  add column if not exists policy text not null default 'parallel',
  add column if not exists quorum_min integer null,
  add column if not exists require_comments_resolved boolean not null default false,
  add column if not exists cancellation_reason text null;

-- Coordinator FK (author-style pattern: ON DELETE SET NULL)
alter table public.reviews
  drop constraint if exists reviews_coordinator_profile_fk;
alter table public.reviews
  add constraint reviews_coordinator_profile_fk
    foreign key (coordinator_profile_id)
    references public.profiles (id)
    on delete set null;

-- Composite tenancy FKs for chain
alter table public.reviews
  drop constraint if exists reviews_parent_review_fk;
alter table public.reviews
  add constraint reviews_parent_review_fk
    foreign key (parent_review_id, workspace_id)
    references public.reviews (id, workspace_id)
    on delete restrict;

alter table public.reviews
  drop constraint if exists reviews_root_review_fk;
alter table public.reviews
  add constraint reviews_root_review_fk
    foreign key (root_review_id, workspace_id)
    references public.reviews (id, workspace_id)
    on delete restrict;

-- Chain integrity CHECK constraints
alter table public.reviews
  drop constraint if exists reviews_chain_self_consistency_check;
alter table public.reviews
  add constraint reviews_chain_self_consistency_check
    check (
      (round_number = 1 and parent_review_id is null) or
      (round_number > 1 and parent_review_id is not null)
    );

alter table public.reviews
  drop constraint if exists reviews_root_self_reference_check;
alter table public.reviews
  add constraint reviews_root_self_reference_check
    check (
      (round_number = 1 and (root_review_id is null or root_review_id = id)) or
      (round_number > 1 and root_review_id is not null)
    );

-- Policy CHECK
alter table public.reviews
  drop constraint if exists reviews_policy_check;
alter table public.reviews
  add constraint reviews_policy_check
    check (policy in ('parallel','sequential','quorum'));

alter table public.reviews
  drop constraint if exists reviews_quorum_min_check;
alter table public.reviews
  add constraint reviews_quorum_min_check
    check ((policy <> 'quorum') or (quorum_min is not null and quorum_min > 0));

-- Cancellation-reason mandatory when cancelled
alter table public.reviews
  drop constraint if exists reviews_cancellation_reason_check;
alter table public.reviews
  add constraint reviews_cancellation_reason_check
    check (
      (status <> 'cancelled') or
      (cancellation_reason is not null and length(cancellation_reason) between 3 and 500)
    );

comment on column public.reviews.round_number is
  'APP 006: chain round number, starts at 1. Immutable after insert (trigger).';
comment on column public.reviews.parent_review_id is
  'APP 006: immediate predecessor round in a review chain. Composite FK enforces same workspace.';
comment on column public.reviews.root_review_id is
  'APP 006: root of the review chain (self on Round 1; propagated on reopen). Dashboard groups on this column.';
comment on column public.reviews.coordinator_profile_id is
  'APP 006: day-to-day driver, distinct from created_by_profile_id (owner). Falls back to owner if null.';
comment on column public.reviews.policy is
  'APP 006: reviewer completion policy — parallel (default) | sequential | quorum.';
comment on column public.reviews.quorum_min is
  'APP 006: quorum threshold (used only when policy = quorum).';
comment on column public.reviews.require_comments_resolved is
  'APP 006: opt-in completion gate — when true, complete_review refuses while any review-scoped root comment is unresolved.';
comment on column public.reviews.cancellation_reason is
  'APP 006: mandatory reason on cancel (D-8). Enforced by check constraint.';

------------------------------------------------------------------------------
-- 3. review_participants — new columns
------------------------------------------------------------------------------

alter table public.review_participants
  add column if not exists required boolean not null default true,
  add column if not exists sequence_index integer not null default 0,
  add column if not exists removed_at timestamptz null,
  add column if not exists removed_reason text null;

alter table public.review_participants
  drop constraint if exists review_participants_sequence_index_check;
alter table public.review_participants
  add constraint review_participants_sequence_index_check
    check (sequence_index >= 0);

-- Tight-form CHECK: soft-removal is fully audit-traceable to a reason
-- (matches reviews.cancellation_reason mandatory posture, D-8).
alter table public.review_participants
  drop constraint if exists review_participants_removal_pair_check;
alter table public.review_participants
  add constraint review_participants_removal_pair_check
    check (
      (removed_at is null and removed_reason is null) or
      (removed_at is not null and removed_reason is not null
       and length(removed_reason) between 3 and 500)
    );

comment on column public.review_participants.required is
  'APP 006: required vs optional reviewer. Required reviewers block completion; optional are courtesy notifications only.';
comment on column public.review_participants.sequence_index is
  'APP 006: unlock order under policy=sequential. Ignored for parallel/quorum.';
comment on column public.review_participants.removed_at is
  'APP 006: soft-removal timestamp. Used when a reviewer has already responded — hard-delete would break the audit trail.';
comment on column public.review_participants.removed_reason is
  'APP 006: mandatory reason accompanying removed_at (paired via CHECK).';

------------------------------------------------------------------------------
-- 4. reviews — indexes
------------------------------------------------------------------------------

create index if not exists reviews_root_review_id_idx
  on public.reviews (root_review_id)
  where root_review_id is not null;

create index if not exists reviews_parent_review_id_idx
  on public.reviews (parent_review_id)
  where parent_review_id is not null;

create index if not exists reviews_project_status_round_idx
  on public.reviews (project_id, status, round_number desc);

create index if not exists reviews_workspace_status_updated_idx
  on public.reviews (workspace_id, status, updated_at desc);

create index if not exists reviews_due_at_partial_idx
  on public.reviews (due_at)
  where status in ('open','in_progress','waiting') and due_at is not null;

create index if not exists reviews_coordinator_profile_id_idx
  on public.reviews (coordinator_profile_id)
  where coordinator_profile_id is not null;

------------------------------------------------------------------------------
-- 5. review_participants — indexes
------------------------------------------------------------------------------

create index if not exists review_participants_review_required_status_idx
  on public.review_participants (review_id, required, status);

-- Refine frozen wm_status and stakeholder_status indexes (already partial).
-- The frozen catalog has:
--   review_participants_workspace_member_status_idx (wm_id, status)
--   review_participants_stakeholder_status_idx (sh_id, status)
-- Both already suit "assigned to me" inbox queries. No changes required.

------------------------------------------------------------------------------
-- 6. reviews — chain-immutability trigger (defense-in-depth)
------------------------------------------------------------------------------
-- RPCs are the primary enforcement path; this trigger provides DB-boundary
-- defense against direct SQL edits, matching the frozen precedent set by
-- annotations_position_immutable and enforce_version_files_parent_draft_mutation.

create or replace function public.enforce_reviews_chain_immutable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.round_number is distinct from old.round_number then
    raise exception 'reviews.round_number is immutable after insert (chain integrity)'
      using errcode = '23514';
  end if;
  if new.parent_review_id is distinct from old.parent_review_id then
    raise exception 'reviews.parent_review_id is immutable after insert (chain integrity)'
      using errcode = '23514';
  end if;
  if new.root_review_id is distinct from old.root_review_id then
    raise exception 'reviews.root_review_id is immutable after insert (chain integrity)'
      using errcode = '23514';
  end if;
  return new;
end $$;

revoke all on function public.enforce_reviews_chain_immutable() from public;
revoke all on function public.enforce_reviews_chain_immutable() from anon;
revoke all on function public.enforce_reviews_chain_immutable() from authenticated;

drop trigger if exists reviews_chain_immutable on public.reviews;
create trigger reviews_chain_immutable
  before update on public.reviews
  for each row execute function public.enforce_reviews_chain_immutable();

comment on function public.enforce_reviews_chain_immutable() is
  'APP 006: defense-in-depth trigger enforcing chain immutability after insert. RPC layer is primary; this catches direct SQL. Matches annotations_position_immutable precedent.';

------------------------------------------------------------------------------
-- 7. user_bookmarks (generalized bookmark table)
------------------------------------------------------------------------------

create table if not exists public.user_bookmarks (
  id                  uuid                  primary key default gen_random_uuid(),
  user_id             uuid                  not null references auth.users (id) on delete cascade,
  workspace_id        uuid                  not null references public.workspaces (id) on delete restrict,
  subject_kind        text                  not null,
  subject_id          uuid                  not null,
  created_at          timestamptz           not null default now(),

  constraint user_bookmarks_subject_kind_len_check check (length(subject_kind) between 1 and 40),
  constraint user_bookmarks_user_subject_unique unique (user_id, subject_kind, subject_id)
);

comment on table public.user_bookmarks is
  'APP 006: per-user bookmarks. subject_kind is open vocabulary (application-side): review, asset, version, approval, release, etc. RLS: user_id = auth.uid().';

create index if not exists user_bookmarks_user_subject_idx
  on public.user_bookmarks (user_id, subject_kind, subject_id);

create index if not exists user_bookmarks_workspace_user_idx
  on public.user_bookmarks (workspace_id, user_id);

alter table public.user_bookmarks enable row level security;

drop policy if exists user_bookmarks_select on public.user_bookmarks;
create policy user_bookmarks_select on public.user_bookmarks
  as permissive for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists user_bookmarks_insert on public.user_bookmarks;
create policy user_bookmarks_insert on public.user_bookmarks
  as permissive for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and public.lign_is_workspace_member(workspace_id)
  );

drop policy if exists user_bookmarks_delete on public.user_bookmarks;
create policy user_bookmarks_delete on public.user_bookmarks
  as permissive for delete to authenticated
  using (user_id = (select auth.uid()));

------------------------------------------------------------------------------
-- 8. user_saved_views (dashboard filter + column set persistence)
------------------------------------------------------------------------------

create table if not exists public.user_saved_views (
  id                  uuid                  primary key default gen_random_uuid(),
  user_id             uuid                  not null references auth.users (id) on delete cascade,
  workspace_id        uuid                  not null references public.workspaces (id) on delete restrict,
  scope               text                  not null,
  name                text                  not null,
  definition          jsonb                 not null default '{}'::jsonb,
  visibility          text                  not null default 'private',
  created_at          timestamptz           not null default now(),
  updated_at          timestamptz           not null default now(),

  constraint user_saved_views_scope_len_check check (length(scope) between 1 and 40),
  constraint user_saved_views_name_len_check  check (length(name) between 1 and 120),
  constraint user_saved_views_visibility_check check (visibility in ('private','workspace')),
  constraint user_saved_views_user_scope_name_unique unique (user_id, workspace_id, scope, name)
);

comment on table public.user_saved_views is
  'APP 006: per-user saved dashboard views (filter + column set). scope is app-side vocabulary (reviews for APP 006; extensible). visibility=workspace reserved for v2 (v1 enforces private).';

create index if not exists user_saved_views_user_scope_idx
  on public.user_saved_views (user_id, workspace_id, scope);

drop trigger if exists user_saved_views_set_updated_at on public.user_saved_views;
create trigger user_saved_views_set_updated_at
  before update on public.user_saved_views
  for each row execute function public.set_updated_at();

alter table public.user_saved_views enable row level security;

drop policy if exists user_saved_views_select on public.user_saved_views;
create policy user_saved_views_select on public.user_saved_views
  as permissive for select to authenticated
  using (
    user_id = (select auth.uid())
    and public.lign_is_workspace_member(workspace_id)
  );

drop policy if exists user_saved_views_insert on public.user_saved_views;
create policy user_saved_views_insert on public.user_saved_views
  as permissive for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and public.lign_is_workspace_member(workspace_id)
    and visibility = 'private'  -- v1 hardcodes private per §5.4
  );

drop policy if exists user_saved_views_update on public.user_saved_views;
create policy user_saved_views_update on public.user_saved_views
  as permissive for update to authenticated
  using      (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()) and visibility = 'private');

drop policy if exists user_saved_views_delete on public.user_saved_views;
create policy user_saved_views_delete on public.user_saved_views
  as permissive for delete to authenticated
  using (user_id = (select auth.uid()));
