-- AUTH 005: collaboration_rls
--
-- RLS + RPCs for §7 Group F (reviews, review_participants, comments,
-- comment_edits, annotations).
--
-- Contents:
--   1. Helper: lign_resolve_comment_target_project
--   2. Triggers:
--        enforce_comment_write_gate       (body via RPC + immutable identity)
--        enforce_annotation_meta_immutable (author + wsid + anchor tables)
--   3. RPCs (SECURITY DEFINER, search_path=''):
--        create_review        — draft (+ optional open + roster) atomically
--        respond_to_review    — reviewer submits response (auto in_progress)
--        complete_review      — draft/open/in_progress → completed | cancelled
--        edit_own_comment     — body edit + append comment_edits row atomically
--   4. Policies:
--        reviews:              SELECT
--        review_participants:  SELECT (via review)
--        comments:             SELECT, INSERT, UPDATE (body gated by trigger)
--        comment_edits:        SELECT (via parent comment)
--        annotations:          SELECT, INSERT, UPDATE
--
-- Frozen event vocabulary from EVENT_MODEL.md used verbatim:
--   review.created, review.opened, review.reviewer_responded,
--   review.completed, review.cancelled,
--   comment.created (deferred: emitted only by future comment.create RPC —
--       direct RLS INSERT does not emit, matches AUTH 004 precedent),
--   comment.edited (emitted by edit_own_comment).
--
-- Not touched:
--   - Frozen architecture docs.
--   - Storage / notifications / cron / realtime / AI / nuesync.
--   - Comment on decision-targeted rows (project resolution deferred to
--     AUTH 006 — decisions has no project_id column).
--
-- Preserved invariants:
--   - Member/stakeholder role parity: lign_has_capability is identity-path
--     agnostic; respond_to_review looks up participant via either FK.
--   - Impersonation: author_profile_id = (select auth.uid()) in INSERT WITH
--     CHECK; author immutability enforced by trigger post-insert.
--   - Project/workspace isolation: composite FKs + capability check with
--     workspace_id-parameterized helpers.
--   - Comment target integrity: existing 7-way XOR CHECK; targets immutable
--     via trigger.
--   - Annotation version/file integrity: existing position-immutability
--     trigger + this migration's meta-immutability trigger.
--   - Comment edit history: edit_own_comment writes comments.body AND
--     comment_edits row in one transaction; append-only trigger protects
--     history from tampering.
--   - Review-completion edit gate: edit_own_comment rejects when the
--     comment's target_review_id points to a review in status
--     completed|cancelled.
--   - Admin creative separation: workspace admins have review.view /
--     comment.view / annotation.view via override but NOT review.create /
--     review.complete / comment.create / comment.resolve / comment.edit_own /
--     annotation.create / annotation.resolve.

------------------------------------------------------------------------------
-- 1. lign_resolve_comment_target_project — DEFINER
------------------------------------------------------------------------------
-- Given the 7 target columns from a comment row, returns the project_id of
-- the target. Decisions have no project_id (workspace-scoped only) — returns
-- NULL for that case; AUTH 006 will introduce full decision handling.

create or replace function public.lign_resolve_comment_target_project(
  p_target_version_id          uuid,
  p_target_review_id           uuid,
  p_target_annotation_id       uuid,
  p_target_change_id           uuid,
  p_target_decision_id         uuid,
  p_target_design_asset_id     uuid,
  p_target_approval_request_id uuid
)
returns uuid
language sql
stable
parallel safe
security definer
set search_path = ''
as $$
  select case
    when p_target_version_id is not null then
      (select project_id from public.asset_versions where id = p_target_version_id)
    when p_target_review_id is not null then
      (select project_id from public.reviews where id = p_target_review_id)
    when p_target_annotation_id is not null then
      (select av.project_id
         from public.annotations a
         join public.asset_versions av on av.id = a.asset_version_id
        where a.id = p_target_annotation_id)
    when p_target_change_id is not null then
      (select project_id from public.changes where id = p_target_change_id)
    when p_target_design_asset_id is not null then
      (select project_id from public.design_assets where id = p_target_design_asset_id)
    when p_target_approval_request_id is not null then
      (select project_id from public.approval_requests where id = p_target_approval_request_id)
    else null
  end;
$$;

comment on function public.lign_resolve_comment_target_project(uuid,uuid,uuid,uuid,uuid,uuid,uuid) is
  'Returns the project_id for the target of a comment. Handles 6 project-scoped targets (version, review, annotation, change, design_asset, approval_request). Returns NULL for decision-targeted comments (decisions are workspace-scoped; AUTH 006 will handle). SECURITY DEFINER bypasses target-table RLS.';

revoke all on function public.lign_resolve_comment_target_project(uuid,uuid,uuid,uuid,uuid,uuid,uuid) from public;
revoke all on function public.lign_resolve_comment_target_project(uuid,uuid,uuid,uuid,uuid,uuid,uuid) from anon;
grant execute on function public.lign_resolve_comment_target_project(uuid,uuid,uuid,uuid,uuid,uuid,uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 2a. enforce_comment_write_gate — trigger
------------------------------------------------------------------------------
-- Blocks changes to immutable identity/target columns. Blocks body mutations
-- unless the session GUC lign.allow_comment_body_write is set (only
-- edit_own_comment RPC sets it).

create or replace function public.enforce_comment_write_gate()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id is distinct from old.id then
    raise exception 'comments.id is immutable' using errcode = '23514';
  end if;
  if new.workspace_id is distinct from old.workspace_id then
    raise exception 'comments.workspace_id is immutable' using errcode = '23514';
  end if;
  if new.author_profile_id is distinct from old.author_profile_id then
    raise exception 'comments.author_profile_id is immutable' using errcode = '23514';
  end if;
  if new.parent_comment_id is distinct from old.parent_comment_id then
    raise exception 'comments.parent_comment_id is immutable' using errcode = '23514';
  end if;
  if new.target_version_id          is distinct from old.target_version_id
     or new.target_review_id        is distinct from old.target_review_id
     or new.target_annotation_id    is distinct from old.target_annotation_id
     or new.target_change_id        is distinct from old.target_change_id
     or new.target_decision_id      is distinct from old.target_decision_id
     or new.target_design_asset_id  is distinct from old.target_design_asset_id
     or new.target_approval_request_id is distinct from old.target_approval_request_id
  then
    raise exception 'comments.target is immutable' using errcode = '23514';
  end if;
  if new.created_at is distinct from old.created_at then
    raise exception 'comments.created_at is immutable' using errcode = '23514';
  end if;

  if new.body is distinct from old.body then
    if coalesce(current_setting('lign.allow_comment_body_write', true), '') <> 'true' then
      raise exception 'comments.body may only be modified via edit_own_comment RPC (id=%)', old.id
        using errcode = '42501';
    end if;
  end if;

  return new;
end $$;

comment on function public.enforce_comment_write_gate() is
  'DB-boundary trigger: enforces comment immutability of identity/target columns; body mutations only via edit_own_comment RPC (GUC-gated).';

drop trigger if exists comments_write_gate on public.comments;
create trigger comments_write_gate
  before update on public.comments
  for each row execute function public.enforce_comment_write_gate();

------------------------------------------------------------------------------
-- 2b. enforce_annotation_meta_immutable — trigger
------------------------------------------------------------------------------
-- Blocks author_profile_id and workspace_id changes; the existing
-- enforce_annotation_position_immutable trigger already blocks
-- anchor_kind, position, page_number, asset_version_id, version_file_id.

create or replace function public.enforce_annotation_meta_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id is distinct from old.id then
    raise exception 'annotations.id is immutable' using errcode = '23514';
  end if;
  if new.workspace_id is distinct from old.workspace_id then
    raise exception 'annotations.workspace_id is immutable' using errcode = '23514';
  end if;
  if new.author_profile_id is distinct from old.author_profile_id then
    raise exception 'annotations.author_profile_id is immutable' using errcode = '23514';
  end if;
  return new;
end $$;

drop trigger if exists annotations_meta_immutable on public.annotations;
create trigger annotations_meta_immutable
  before update on public.annotations
  for each row execute function public.enforce_annotation_meta_immutable();

------------------------------------------------------------------------------
-- 3a. create_review
------------------------------------------------------------------------------

create or replace function public.create_review(
  p_project_id        uuid,
  p_design_asset_id   uuid,
  p_version_id        uuid,
  p_title             text,
  p_description       text default null,
  p_reviewer_wm_ids   uuid[] default '{}'::uuid[],
  p_reviewer_sh_ids   uuid[] default '{}'::uuid[],
  p_due_at            timestamptz default null,
  p_open              boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller       uuid;
  v_workspace_id uuid;
  v_v_asset      uuid;
  v_v_status     text;
  v_da_project   uuid;
  v_review_id    uuid;
  v_wm_id        uuid;
  v_sh_id        uuid;
  v_reviewer_ct  int := 0;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'create_review: authentication required' using errcode='42501';
  end if;
  if p_project_id is null or p_design_asset_id is null or p_version_id is null then
    raise exception 'create_review: ids required' using errcode='22004';
  end if;
  if p_title is null or length(trim(p_title))=0 then
    raise exception 'create_review: title required' using errcode='22004';
  end if;

  select project_id, workspace_id into v_da_project, v_workspace_id
    from public.design_assets where id = p_design_asset_id;
  if v_workspace_id is null then
    raise exception 'create_review: design_asset % not found', p_design_asset_id using errcode='23503';
  end if;
  if v_da_project <> p_project_id then
    raise exception 'create_review: asset does not belong to project %', p_project_id using errcode='23514';
  end if;

  select design_asset_id, status into v_v_asset, v_v_status
    from public.asset_versions where id = p_version_id;
  if v_v_asset is null then
    raise exception 'create_review: version % not found', p_version_id using errcode='23503';
  end if;
  if v_v_asset <> p_design_asset_id then
    raise exception 'create_review: version does not belong to asset' using errcode='23514';
  end if;
  if v_v_status <> 'published' then
    raise exception 'create_review: version must be published (is %)', v_v_status using errcode='23514';
  end if;

  if not public.lign_has_capability(p_project_id, v_workspace_id, 'review.create') then
    raise exception 'create_review: forbidden (review.create)' using errcode='42501';
  end if;

  insert into public.reviews (
    workspace_id, project_id, design_asset_id, version_id,
    title, description, status, due_at, created_by_profile_id
  ) values (
    v_workspace_id, p_project_id, p_design_asset_id, p_version_id,
    p_title, p_description, 'draft', p_due_at, v_caller
  )
  returning id into v_review_id;

  -- Add roster: workspace_member reviewers
  foreach v_wm_id in array coalesce(p_reviewer_wm_ids, '{}'::uuid[]) loop
    if not exists (
      select 1 from public.workspace_members
       where id = v_wm_id and workspace_id = v_workspace_id and status = 'active'
    ) then
      raise exception 'create_review: workspace_member % not found in workspace (active)', v_wm_id using errcode='23503';
    end if;
    insert into public.review_participants (workspace_id, review_id, workspace_member_id, status, assigned_at)
    values (v_workspace_id, v_review_id, v_wm_id, 'pending', now());
    v_reviewer_ct := v_reviewer_ct + 1;
  end loop;

  -- Add roster: stakeholder reviewers
  foreach v_sh_id in array coalesce(p_reviewer_sh_ids, '{}'::uuid[]) loop
    if not exists (
      select 1 from public.stakeholders
       where id = v_sh_id and workspace_id = v_workspace_id and status in ('active','invited')
    ) then
      raise exception 'create_review: stakeholder % not found in workspace', v_sh_id using errcode='23503';
    end if;
    insert into public.review_participants (workspace_id, review_id, stakeholder_id, status, assigned_at)
    values (v_workspace_id, v_review_id, v_sh_id, 'pending', now());
    v_reviewer_ct := v_reviewer_ct + 1;
  end loop;

  -- Emit review.created (feed-only per EVENT_MODEL §4.7)
  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_workspace_id, p_project_id, now(), 'review.created',
    v_caller, 'user',
    'review', v_review_id, p_title,
    jsonb_build_object('title', p_title, 'version_id', p_version_id),
    '{}'::jsonb
  );

  -- Optional open transition (requires >=1 reviewer per STATE_MACHINES.md)
  if p_open then
    if v_reviewer_ct < 1 then
      raise exception 'create_review: cannot open with zero reviewers' using errcode='23514';
    end if;
    update public.reviews set status = 'open' where id = v_review_id;

    insert into public.activity_events (
      workspace_id, project_id, occurred_at, event_type,
      actor_profile_id, actor_kind,
      subject_kind, subject_id, subject_label, subject_snapshot, payload
    ) values (
      v_workspace_id, p_project_id, now(), 'review.opened',
      v_caller, 'user',
      'review', v_review_id, p_title,
      jsonb_build_object('title', p_title, 'reviewer_count', v_reviewer_ct),
      '{}'::jsonb
    );
  end if;

  return v_review_id;
end $$;

revoke all on function public.create_review(uuid, uuid, uuid, text, text, uuid[], uuid[], timestamptz, boolean) from public;
revoke all on function public.create_review(uuid, uuid, uuid, text, text, uuid[], uuid[], timestamptz, boolean) from anon;
grant execute on function public.create_review(uuid, uuid, uuid, text, text, uuid[], uuid[], timestamptz, boolean) to authenticated, service_role;

------------------------------------------------------------------------------
-- 3b. respond_to_review
------------------------------------------------------------------------------

create or replace function public.respond_to_review(
  p_review_id uuid,
  p_response  text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller       uuid;
  v_workspace_id uuid;
  v_project_id   uuid;
  v_r_status     text;
  v_pp_id        uuid;
  v_pp_status    text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'respond_to_review: authentication required' using errcode='42501';
  end if;
  if p_response not in ('commented','signed_off','declined') then
    raise exception 'respond_to_review: invalid response %', p_response using errcode='22023';
  end if;

  select workspace_id, project_id, status
    into v_workspace_id, v_project_id, v_r_status
    from public.reviews
   where id = p_review_id
   for update;
  if v_workspace_id is null then
    raise exception 'respond_to_review: review % not found', p_review_id using errcode='23503';
  end if;
  if v_r_status not in ('open','in_progress') then
    raise exception 'respond_to_review: review is % (must be open or in_progress)', v_r_status
      using errcode='23514';
  end if;

  -- Locate CALLER's participant slot (own identity only, either path)
  select rp.id, rp.status
    into v_pp_id, v_pp_status
    from public.review_participants rp
    left join public.workspace_members wm on wm.id = rp.workspace_member_id and wm.status = 'active'
    left join public.stakeholders sh on sh.id = rp.stakeholder_id and sh.status = 'active'
   where rp.review_id = p_review_id
     and (wm.user_id = v_caller or sh.user_id = v_caller);
  if v_pp_id is null then
    raise exception 'respond_to_review: caller is not an assigned reviewer'
      using errcode='42501';
  end if;
  if v_pp_status <> 'pending' then
    raise exception 'respond_to_review: reviewer slot already responded (%)', v_pp_status
      using errcode='23514';
  end if;

  update public.review_participants
     set status = p_response, responded_at = now()
   where id = v_pp_id;

  if v_r_status = 'open' then
    update public.reviews set status = 'in_progress' where id = p_review_id;
  end if;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_workspace_id, v_project_id, now(), 'review.reviewer_responded',
    v_caller, 'user',
    'review_participant', v_pp_id, p_response,
    jsonb_build_object('review_id', p_review_id, 'reviewer_status', p_response),
    '{}'::jsonb
  );

  return v_pp_id;
end $$;

revoke all on function public.respond_to_review(uuid, text) from public;
revoke all on function public.respond_to_review(uuid, text) from anon;
grant execute on function public.respond_to_review(uuid, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 3c. complete_review
------------------------------------------------------------------------------

create or replace function public.complete_review(
  p_review_id uuid,
  p_terminal  text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller       uuid;
  v_workspace_id uuid;
  v_project_id   uuid;
  v_r_status     text;
  v_title        text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'complete_review: authentication required' using errcode='42501';
  end if;
  if p_terminal not in ('completed','cancelled') then
    raise exception 'complete_review: invalid terminal %', p_terminal using errcode='22023';
  end if;

  select workspace_id, project_id, status, title
    into v_workspace_id, v_project_id, v_r_status, v_title
    from public.reviews
   where id = p_review_id
   for update;
  if v_workspace_id is null then
    raise exception 'complete_review: review not found' using errcode='23503';
  end if;
  if v_r_status not in ('draft','open','in_progress') then
    raise exception 'complete_review: review is % (already terminal)', v_r_status
      using errcode='23514';
  end if;

  if not public.lign_has_capability(v_project_id, v_workspace_id, 'review.complete') then
    raise exception 'complete_review: forbidden (review.complete)' using errcode='42501';
  end if;

  if p_terminal = 'completed' then
    update public.reviews set status='completed', completed_at=now() where id = p_review_id;
  else
    update public.reviews set status='cancelled', cancelled_at=now() where id = p_review_id;
  end if;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_workspace_id, v_project_id, now(),
    case when p_terminal='completed' then 'review.completed' else 'review.cancelled' end,
    v_caller, 'user',
    'review', p_review_id, v_title,
    jsonb_build_object('title', v_title, 'terminal', p_terminal),
    '{}'::jsonb
  );

  return p_review_id;
end $$;

revoke all on function public.complete_review(uuid, text) from public;
revoke all on function public.complete_review(uuid, text) from anon;
grant execute on function public.complete_review(uuid, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 3d. edit_own_comment
------------------------------------------------------------------------------

create or replace function public.edit_own_comment(
  p_comment_id uuid,
  p_new_body   text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller           uuid;
  v_workspace_id     uuid;
  v_author           uuid;
  v_old_body         text;
  v_deleted_at       timestamptz;
  v_target_review_id uuid;
  v_target_v_id      uuid;
  v_target_a_id      uuid;
  v_target_c_id      uuid;
  v_target_d_id      uuid;
  v_target_da_id     uuid;
  v_target_ar_id     uuid;
  v_project_id       uuid;
  v_review_status    text;
  v_next_revision    int;
  v_edit_id          uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'edit_own_comment: authentication required' using errcode='42501';
  end if;
  if p_new_body is null or length(p_new_body) = 0 then
    raise exception 'edit_own_comment: body required' using errcode='22004';
  end if;

  select workspace_id, author_profile_id, body, deleted_at,
         target_version_id, target_review_id, target_annotation_id,
         target_change_id, target_decision_id, target_design_asset_id, target_approval_request_id
    into v_workspace_id, v_author, v_old_body, v_deleted_at,
         v_target_v_id, v_target_review_id, v_target_a_id,
         v_target_c_id, v_target_d_id, v_target_da_id, v_target_ar_id
    from public.comments
   where id = p_comment_id
   for update;
  if v_workspace_id is null then
    raise exception 'edit_own_comment: comment not found' using errcode='23503';
  end if;
  if v_author <> v_caller then
    raise exception 'edit_own_comment: not the author' using errcode='42501';
  end if;
  if v_deleted_at is not null then
    raise exception 'edit_own_comment: comment is soft-deleted' using errcode='23514';
  end if;

  v_project_id := public.lign_resolve_comment_target_project(
    v_target_v_id, v_target_review_id, v_target_a_id,
    v_target_c_id, v_target_d_id, v_target_da_id, v_target_ar_id);

  if v_project_id is null then
    raise exception 'edit_own_comment: comment target has no project scope (decision-targeted comments deferred)' using errcode='42501';
  end if;

  if not public.lign_has_capability(v_project_id, v_workspace_id, 'comment.edit_own') then
    raise exception 'edit_own_comment: forbidden (comment.edit_own)' using errcode='42501';
  end if;

  -- Review-completion edit gate: if comment targets a review, that review
  -- must not be completed/cancelled (per PERMISSIONS.md §8 Group G).
  if v_target_review_id is not null then
    select status into v_review_status
      from public.reviews where id = v_target_review_id;
    if v_review_status in ('completed','cancelled') then
      raise exception 'edit_own_comment: containing review is % (edits denied)', v_review_status
        using errcode='42501';
    end if;
  end if;

  if v_old_body = p_new_body then
    -- No-op; do not create empty edit history row.
    return p_comment_id;
  end if;

  select coalesce(max(revision), 0) + 1
    into v_next_revision
    from public.comment_edits
   where comment_id = p_comment_id;

  insert into public.comment_edits (
    workspace_id, comment_id, revision, previous_body, edited_by_profile_id, edited_at
  ) values (
    v_workspace_id, p_comment_id, v_next_revision, v_old_body, v_caller, now()
  )
  returning id into v_edit_id;

  perform set_config('lign.allow_comment_body_write', 'true', true);
  update public.comments set body = p_new_body where id = p_comment_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_workspace_id, v_project_id, now(), 'comment.edited',
    v_caller, 'user',
    'comment', p_comment_id, 'rev '||v_next_revision,
    jsonb_build_object('revision', v_next_revision),
    '{}'::jsonb
  );

  return p_comment_id;
end $$;

revoke all on function public.edit_own_comment(uuid, text) from public;
revoke all on function public.edit_own_comment(uuid, text) from anon;
grant execute on function public.edit_own_comment(uuid, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 4. Policies
------------------------------------------------------------------------------

-- reviews: SELECT only (writes RPC-only)
drop policy if exists reviews_select on public.reviews;
create policy reviews_select on public.reviews
  as permissive for select to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'review.view'));

-- review_participants: SELECT via review
drop policy if exists review_participants_select on public.review_participants;
create policy review_participants_select on public.review_participants
  as permissive for select to authenticated
  using (
    exists (
      select 1 from public.reviews r
       where r.id = review_participants.review_id
         and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
    )
  );

-- comments: SELECT
drop policy if exists comments_select on public.comments;
create policy comments_select on public.comments
  as permissive for select to authenticated
  using (
    public.lign_has_capability(
      public.lign_resolve_comment_target_project(
        target_version_id, target_review_id, target_annotation_id,
        target_change_id, target_decision_id, target_design_asset_id, target_approval_request_id),
      workspace_id,
      'comment.view'
    )
  );

-- comments: INSERT (direct RLS with impersonation guard)
drop policy if exists comments_insert on public.comments;
create policy comments_insert on public.comments
  as permissive for insert to authenticated
  with check (
    author_profile_id = (select auth.uid())
    and public.lign_has_capability(
      public.lign_resolve_comment_target_project(
        target_version_id, target_review_id, target_annotation_id,
        target_change_id, target_decision_id, target_design_asset_id, target_approval_request_id),
      workspace_id,
      'comment.create'
    )
  );

-- comments: UPDATE — permits resolve toggle (comment.resolve) OR own soft-delete
-- (comment.edit_own on own row). Body changes are separately blocked by trigger
-- unless the edit_own_comment RPC's GUC is set.
drop policy if exists comments_update on public.comments;
create policy comments_update on public.comments
  as permissive for update to authenticated
  using (
    public.lign_has_capability(
      public.lign_resolve_comment_target_project(
        target_version_id, target_review_id, target_annotation_id,
        target_change_id, target_decision_id, target_design_asset_id, target_approval_request_id),
      workspace_id,
      'comment.view'
    )
  )
  with check (
    public.lign_has_capability(
      public.lign_resolve_comment_target_project(
        target_version_id, target_review_id, target_annotation_id,
        target_change_id, target_decision_id, target_design_asset_id, target_approval_request_id),
      workspace_id,
      'comment.resolve'
    )
    or (
      author_profile_id = (select auth.uid())
      and public.lign_has_capability(
        public.lign_resolve_comment_target_project(
          target_version_id, target_review_id, target_annotation_id,
          target_change_id, target_decision_id, target_design_asset_id, target_approval_request_id),
        workspace_id,
        'comment.edit_own'
      )
    )
  );

-- comment_edits: SELECT via parent comment access
drop policy if exists comment_edits_select on public.comment_edits;
create policy comment_edits_select on public.comment_edits
  as permissive for select to authenticated
  using (
    exists (
      select 1 from public.comments c
       where c.id = comment_edits.comment_id
         and public.lign_has_capability(
           public.lign_resolve_comment_target_project(
             c.target_version_id, c.target_review_id, c.target_annotation_id,
             c.target_change_id, c.target_decision_id, c.target_design_asset_id, c.target_approval_request_id),
           c.workspace_id,
           'comment.view'
         )
    )
  );

-- annotations: SELECT
drop policy if exists annotations_select on public.annotations;
create policy annotations_select on public.annotations
  as permissive for select to authenticated
  using (
    public.lign_has_capability(
      (select project_id from public.asset_versions where id = annotations.asset_version_id),
      workspace_id,
      'annotation.view'
    )
  );

-- annotations: INSERT (direct RLS with impersonation guard; existing position
-- immutability trigger + this migration's meta trigger protect content)
drop policy if exists annotations_insert on public.annotations;
create policy annotations_insert on public.annotations
  as permissive for insert to authenticated
  with check (
    author_profile_id = (select auth.uid())
    and public.lign_has_capability(
      (select project_id from public.asset_versions where id = asset_version_id),
      workspace_id,
      'annotation.create'
    )
  );

-- annotations: UPDATE — status transitions only (position/anchor blocked by trigger)
drop policy if exists annotations_update on public.annotations;
create policy annotations_update on public.annotations
  as permissive for update to authenticated
  using (
    public.lign_has_capability(
      (select project_id from public.asset_versions where id = annotations.asset_version_id),
      workspace_id,
      'annotation.resolve'
    )
  )
  with check (
    public.lign_has_capability(
      (select project_id from public.asset_versions where id = annotations.asset_version_id),
      workspace_id,
      'annotation.resolve'
    )
  );
