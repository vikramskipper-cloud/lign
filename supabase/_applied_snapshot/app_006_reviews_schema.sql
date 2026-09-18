-- Migration 012 (APP 006): Reviews schema
-- Full documentation: supabase/migrations/20260808120000_app_006_reviews_schema.sql

------------------------------------------------------------------------------
-- 1. reviews.status enum expansion
------------------------------------------------------------------------------

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

alter table public.reviews
  drop constraint if exists reviews_coordinator_profile_fk;
alter table public.reviews
  add constraint reviews_coordinator_profile_fk
    foreign key (coordinator_profile_id)
    references public.profiles (id)
    on delete set null;

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

alter table public.reviews
  drop constraint if exists reviews_cancellation_reason_check;
alter table public.reviews
  add constraint reviews_cancellation_reason_check
    check (
      (status <> 'cancelled') or
      (cancellation_reason is not null and length(cancellation_reason) between 3 and 500)
    );

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

alter table public.review_participants
  drop constraint if exists review_participants_removal_pair_check;
alter table public.review_participants
  add constraint review_participants_removal_pair_check
    check (
      (removed_at is null and removed_reason is null) or
      (removed_at is not null and removed_reason is not null
       and length(removed_reason) between 3 and 500)
    );

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

------------------------------------------------------------------------------
-- 6. reviews — chain-immutability trigger (defense-in-depth)
------------------------------------------------------------------------------

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

------------------------------------------------------------------------------
-- 7. user_bookmarks
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
-- 8. user_saved_views
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
    and visibility = 'private'
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
