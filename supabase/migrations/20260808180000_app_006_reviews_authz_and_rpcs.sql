-- Migration 013 (APP 006): Reviews authorization + RPCs
--
-- Implements the frozen APP 006 backend surface:
--   1. Extends lign_has_capability with review.coordinate + review.reopen
--   2. Extends create_review with additive-tail params (Option A of §13)
--   3. Extends complete_review with additive p_cancellation_reason param
--      (required for the reviews_cancellation_reason_check to succeed on
--      cancel; signature unchanged for the terminal='completed' path)
--   4. New RPCs (all SECURITY DEFINER, search_path=''):
--      - open_review, set_review_state, reopen_review
--      - add_reviewer, remove_reviewer, reassign_reviewer,
--        set_reviewer_required
--      - toggle_bookmark, save_dashboard_view, delete_dashboard_view
--      - list_reviews_dashboard, get_review, get_review_chain
--      - get_review_inbox_count, get_project_review_metrics,
--        get_workspace_review_metrics
--
-- All events per EVENT_MODEL.md canonical shape. RESERVED event names
-- (review.deadline_approached, review.deadline_passed) are NOT emitted here.

------------------------------------------------------------------------------
-- 1. Extend lign_has_capability
------------------------------------------------------------------------------

create or replace function public.lign_has_capability(
  p_project_id uuid,
  p_workspace_id uuid,
  p_capability_key text
)
returns boolean
language plpgsql
stable parallel safe security definer
set search_path = ''
as $$
declare
  v_project_ok boolean;
  v_role       text;
begin
  select exists (
    select 1 from public.projects
     where id = p_project_id and workspace_id = p_workspace_id
  ) into v_project_ok;

  if not v_project_ok then
    return false;
  end if;

  if p_capability_key = any (array[
    'project.view','project.edit','project.manage_access','project.archive',
    'collection.view','collection.archive',
    'asset.view','asset.archive',
    'version.view','review.view','comment.view','annotation.view',
    'change.view','decision.view','approval.view','release.view',
    'file.download','activity.view',
    'requirement.view'
  ]) then
    if public.lign_is_workspace_admin(p_workspace_id) then
      return true;
    end if;
  end if;

  v_role := public.lign_project_role(p_project_id);
  if v_role is null then
    return false;
  end if;

  return case v_role
    when 'lead' then p_capability_key = any (array[
      'project.view','project.edit','project.manage_access','project.archive',
      'collection.view','collection.create','collection.edit','collection.archive',
      'asset.view','asset.create','asset.edit','asset.archive','asset.set_current',
      'version.view','version.upload','version.publish','version.discard_draft',
      'review.view','review.create','review.coordinate','review.complete','review.reopen',
      'comment.view','comment.create','comment.edit_own','comment.resolve',
      'annotation.view','annotation.create','annotation.resolve',
      'change.view','change.create','change.resolve',
      'decision.view','decision.create',
      'approval.view','approval.request','approval.cancel',
      'release.view','release.create','release.finalize','release.withdraw',
      'file.upload','file.attach','file.download','file.remove_orphaned',
      'activity.view',
      'requirement.view','requirement.create','requirement.edit',
      'requirement.archive','requirement.assess'
    ])
    when 'contributor' then p_capability_key = any (array[
      'project.view',
      'collection.view','collection.create','collection.edit','collection.archive',
      'asset.view','asset.create','asset.edit','asset.archive','asset.set_current',
      'version.view','version.upload','version.publish','version.discard_draft',
      'review.view','review.create','review.complete','review.reopen',
      'comment.view','comment.create','comment.edit_own','comment.resolve',
      'annotation.view','annotation.create','annotation.resolve',
      'change.view','change.create','change.resolve',
      'decision.view','decision.create',
      'approval.view','approval.request','approval.cancel',
      'release.view','release.create',
      'file.upload','file.attach','file.download',
      'activity.view',
      'requirement.view','requirement.create','requirement.edit','requirement.assess'
    ])
    when 'reviewer' then p_capability_key = any (array[
      'project.view',
      'collection.view','asset.view','version.view',
      'review.view','review.participate',
      'comment.view','comment.create','comment.edit_own',
      'annotation.view','annotation.create',
      'change.view','change.create',
      'decision.view',
      'approval.view',
      'release.view',
      'file.download',
      'activity.view',
      'requirement.view','requirement.assess'
    ])
    when 'approver' then p_capability_key = any (array[
      'project.view',
      'collection.view','asset.view','version.view',
      'review.view','review.participate',
      'comment.view','comment.create','comment.edit_own',
      'annotation.view','annotation.create',
      'change.view','change.create',
      'decision.view',
      'approval.view','approval.respond',
      'release.view',
      'file.download',
      'activity.view',
      'requirement.view','requirement.assess'
    ])
    when 'observer' then p_capability_key = any (array[
      'project.view',
      'collection.view','asset.view','version.view',
      'review.view','comment.view','annotation.view',
      'change.view','decision.view','approval.view','release.view',
      'file.download','activity.view',
      'requirement.view'
    ])
    else false
  end;
end $$;

------------------------------------------------------------------------------
-- 2. create_review (extended)
------------------------------------------------------------------------------
-- Adds additive tail params:
--   p_coordinator_profile_id, p_policy, p_quorum_min,
--   p_require_comments_resolved,
--   p_reviewer_required (bool[]), p_reviewer_sequence_index (int[])
-- Semantics: p_reviewer_required and p_reviewer_sequence_index are aligned
-- position-by-position with the concatenated (wm_ids || sh_ids) roster.

create or replace function public.create_review(
  p_project_id                 uuid,
  p_design_asset_id            uuid,
  p_version_id                 uuid,
  p_title                      text,
  p_description                text        default null,
  p_reviewer_wm_ids            uuid[]      default '{}'::uuid[],
  p_reviewer_sh_ids            uuid[]      default '{}'::uuid[],
  p_due_at                     timestamptz default null,
  p_open                       boolean     default false,
  p_coordinator_profile_id     uuid        default null,
  p_policy                     text        default 'parallel',
  p_quorum_min                 integer     default null,
  p_require_comments_resolved  boolean     default false,
  p_reviewer_required          boolean[]   default '{}'::boolean[],
  p_reviewer_sequence_index    integer[]   default '{}'::integer[]
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
  v_wm_count     int := coalesce(array_length(p_reviewer_wm_ids, 1), 0);
  v_sh_count     int := coalesce(array_length(p_reviewer_sh_ids, 1), 0);
  v_req_count    int := coalesce(array_length(p_reviewer_required, 1), 0);
  v_seq_count    int := coalesce(array_length(p_reviewer_sequence_index, 1), 0);
  v_i            int;
  v_required     boolean;
  v_sequence     int;
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
  if p_policy is null or p_policy not in ('parallel','sequential','quorum') then
    raise exception 'create_review: invalid policy %', coalesce(p_policy,'(null)') using errcode='22023';
  end if;
  if p_policy = 'quorum' and (p_quorum_min is null or p_quorum_min <= 0) then
    raise exception 'create_review: quorum_min required and positive when policy=quorum' using errcode='22004';
  end if;
  if v_req_count > 0 and v_req_count <> v_wm_count + v_sh_count then
    raise exception 'create_review: p_reviewer_required length must match total reviewer count' using errcode='22023';
  end if;
  if v_seq_count > 0 and v_seq_count <> v_wm_count + v_sh_count then
    raise exception 'create_review: p_reviewer_sequence_index length must match total reviewer count' using errcode='22023';
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

  -- Validate coordinator (if provided) is a project participant of the project
  if p_coordinator_profile_id is not null then
    if not exists (
      select 1
        from public.project_participants pp
        left join public.workspace_members wm on wm.id = pp.workspace_member_id
        left join public.stakeholders sh on sh.id = pp.stakeholder_id
       where pp.project_id = p_project_id
         and pp.status = 'active'
         and (wm.user_id = p_coordinator_profile_id or sh.user_id = p_coordinator_profile_id)
    ) then
      raise exception 'create_review: coordinator % is not an active project participant', p_coordinator_profile_id
        using errcode='23514';
    end if;
  end if;

  -- APP 006 T-CRIT-1 fix: pre-compute the review id so root_review_id = self
  -- can be set inline at INSERT time. A post-INSERT UPDATE would trip the
  -- chain-immutability trigger (Migration 012) which — correctly — rejects
  -- any mutation to root_review_id after insert, including NULL → self.
  -- Single-INSERT initialization keeps the trigger, chain model, and RPC API
  -- untouched.
  v_review_id := gen_random_uuid();

  insert into public.reviews (
    id,
    workspace_id, project_id, design_asset_id, version_id,
    title, description, status, due_at, created_by_profile_id,
    round_number, parent_review_id, root_review_id,
    coordinator_profile_id, policy, quorum_min, require_comments_resolved
  ) values (
    v_review_id,
    v_workspace_id, p_project_id, p_design_asset_id, p_version_id,
    p_title, p_description, 'draft', p_due_at, v_caller,
    1, null, v_review_id,   -- Round 1: root_review_id = self, inline
    p_coordinator_profile_id, p_policy, p_quorum_min, p_require_comments_resolved
  );

  -- Add roster: workspace_member reviewers
  for v_i in 1..v_wm_count loop
    v_wm_id := p_reviewer_wm_ids[v_i];
    if not exists (
      select 1 from public.workspace_members
       where id = v_wm_id and workspace_id = v_workspace_id and status = 'active'
    ) then
      raise exception 'create_review: workspace_member % not found in workspace (active)', v_wm_id using errcode='23503';
    end if;
    v_required := coalesce(p_reviewer_required[v_i], true);
    v_sequence := coalesce(p_reviewer_sequence_index[v_i], 0);
    insert into public.review_participants (
      workspace_id, review_id, workspace_member_id, status, assigned_at,
      required, sequence_index
    )
    values (
      v_workspace_id, v_review_id, v_wm_id, 'pending', now(),
      v_required, v_sequence
    );
    v_reviewer_ct := v_reviewer_ct + 1;
  end loop;

  -- Add roster: stakeholder reviewers
  for v_i in 1..v_sh_count loop
    v_sh_id := p_reviewer_sh_ids[v_i];
    if not exists (
      select 1 from public.stakeholders
       where id = v_sh_id and workspace_id = v_workspace_id and status in ('active','invited')
    ) then
      raise exception 'create_review: stakeholder % not found in workspace', v_sh_id using errcode='23503';
    end if;
    v_required := coalesce(p_reviewer_required[v_wm_count + v_i], true);
    v_sequence := coalesce(p_reviewer_sequence_index[v_wm_count + v_i], 0);
    insert into public.review_participants (
      workspace_id, review_id, stakeholder_id, status, assigned_at,
      required, sequence_index
    )
    values (
      v_workspace_id, v_review_id, v_sh_id, 'pending', now(),
      v_required, v_sequence
    );
    v_reviewer_ct := v_reviewer_ct + 1;
  end loop;

  -- Emit review.created with extended payload
  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_workspace_id, p_project_id, now(), 'review.created',
    v_caller, 'user',
    'review', v_review_id, p_title,
    jsonb_build_object('title', p_title, 'version_id', p_version_id),
    jsonb_build_object(
      'round_number', 1,
      'root_review_id', v_review_id,
      'coordinator_profile_id', p_coordinator_profile_id,
      'policy', p_policy,
      'quorum_min', p_quorum_min
    )
  );

  -- Optional open transition
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
      jsonb_build_object(
        'round_number', 1,
        'roster', jsonb_build_object(
          'wm_ids', to_jsonb(coalesce(p_reviewer_wm_ids, '{}'::uuid[])),
          'sh_ids', to_jsonb(coalesce(p_reviewer_sh_ids, '{}'::uuid[]))
        ),
        'due_at', p_due_at
      )
    );
  end if;

  return v_review_id;
end $$;

revoke all on function public.create_review(
  uuid, uuid, uuid, text, text, uuid[], uuid[], timestamptz, boolean,
  uuid, text, integer, boolean, boolean[], integer[]
) from public;
revoke all on function public.create_review(
  uuid, uuid, uuid, text, text, uuid[], uuid[], timestamptz, boolean,
  uuid, text, integer, boolean, boolean[], integer[]
) from anon;
grant execute on function public.create_review(
  uuid, uuid, uuid, text, text, uuid[], uuid[], timestamptz, boolean,
  uuid, text, integer, boolean, boolean[], integer[]
) to authenticated, service_role;

------------------------------------------------------------------------------
-- 3. complete_review (extended with p_cancellation_reason)
------------------------------------------------------------------------------

create or replace function public.complete_review(
  p_review_id            uuid,
  p_terminal             text,
  p_cancellation_reason  text default null,
  p_forced               boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller     uuid;
  v_ws_id      uuid;
  v_proj_id    uuid;
  v_status     text;
  v_title      text;
  v_round      integer;
  v_require_cr boolean;
  v_unresolved int;
  v_summary    jsonb;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'complete_review: authentication required' using errcode='42501';
  end if;
  if p_review_id is null then
    raise exception 'complete_review: review_id required' using errcode='22004';
  end if;
  if p_terminal is null or p_terminal not in ('completed','cancelled') then
    raise exception 'complete_review: invalid terminal %', coalesce(p_terminal,'(null)') using errcode='22023';
  end if;

  select workspace_id, project_id, status, title, round_number, require_comments_resolved
    into v_ws_id, v_proj_id, v_status, v_title, v_round, v_require_cr
    from public.reviews where id = p_review_id for update;

  if v_ws_id is null then
    raise exception 'complete_review: review % not found', p_review_id using errcode='23503';
  end if;
  if v_status in ('completed','cancelled') then
    raise exception 'complete_review: review already terminal (%)', v_status using errcode='23514';
  end if;

  if not public.lign_has_capability(v_proj_id, v_ws_id, 'review.complete') then
    raise exception 'complete_review: forbidden (review.complete)' using errcode='42501';
  end if;

  if p_terminal = 'cancelled' then
    if p_cancellation_reason is null or length(trim(p_cancellation_reason)) < 3 then
      raise exception 'complete_review: cancellation_reason required (min 3 chars)' using errcode='22004';
    end if;

    update public.reviews
       set status = 'cancelled',
           cancelled_at = now(),
           cancellation_reason = p_cancellation_reason
     where id = p_review_id;

    insert into public.activity_events (
      workspace_id, project_id, occurred_at, event_type,
      actor_profile_id, actor_kind,
      subject_kind, subject_id, subject_label, subject_snapshot, payload
    ) values (
      v_ws_id, v_proj_id, now(), 'review.cancelled',
      v_caller, 'user',
      'review', p_review_id, v_title,
      jsonb_build_object('title', v_title),
      jsonb_build_object(
        'round_number', v_round,
        'cancellation_reason', p_cancellation_reason
      )
    );
    return p_review_id;
  end if;

  -- terminal = 'completed'
  if v_require_cr then
    select count(*) into v_unresolved
      from public.comments
     where target_review_id = p_review_id
       and parent_comment_id is null
       and resolved_at is null
       and deleted_at is null;
    if v_unresolved > 0 then
      raise exception 'complete_review: % unresolved review comments block completion (require_comments_resolved=true)', v_unresolved
        using errcode='23514';
    end if;
  end if;

  -- Compute outcome_summary
  select jsonb_build_object(
    'signed_off_count', count(*) filter (where status='signed_off'),
    'declined_count',   count(*) filter (where status='declined'),
    'commented_count',  count(*) filter (where status='commented'),
    'pending_count',    count(*) filter (where status='pending'),
    'unresolved_comment_count', coalesce((
      select count(*) from public.comments
       where target_review_id = p_review_id
         and parent_comment_id is null
         and resolved_at is null
         and deleted_at is null
    ), 0)
  ) into v_summary
  from public.review_participants
  where review_id = p_review_id
    and removed_at is null;

  update public.reviews
     set status = 'completed',
         completed_at = now()
   where id = p_review_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws_id, v_proj_id, now(), 'review.completed',
    v_caller, 'user',
    'review', p_review_id, v_title,
    jsonb_build_object('title', v_title),
    jsonb_build_object(
      'round_number', v_round,
      'forced', p_forced,
      'outcome_summary', v_summary
    )
  );

  return p_review_id;
end $$;

revoke all on function public.complete_review(uuid, text, text, boolean) from public;
revoke all on function public.complete_review(uuid, text, text, boolean) from anon;
grant execute on function public.complete_review(uuid, text, text, boolean) to authenticated, service_role;

------------------------------------------------------------------------------
-- 4. open_review
------------------------------------------------------------------------------

create or replace function public.open_review(p_review_id uuid)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_proj uuid; v_status text; v_title text; v_round int;
  v_reviewer_ct int; v_due timestamptz;
  v_wm_ids jsonb; v_sh_ids jsonb;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'open_review: authentication required' using errcode='42501'; end if;
  if p_review_id is null then raise exception 'open_review: review_id required' using errcode='22004'; end if;

  select workspace_id, project_id, status, title, round_number, due_at
    into v_ws, v_proj, v_status, v_title, v_round, v_due
    from public.reviews where id = p_review_id for update;
  if v_ws is null then raise exception 'open_review: review % not found', p_review_id using errcode='23503'; end if;
  if v_status not in ('draft','ready_for_review') then
    raise exception 'open_review: cannot open review in status %', v_status using errcode='23514';
  end if;

  if not public.lign_has_capability(v_proj, v_ws, 'review.create') then
    raise exception 'open_review: forbidden (review.create)' using errcode='42501';
  end if;

  select count(*) into v_reviewer_ct from public.review_participants
   where review_id = p_review_id and removed_at is null;
  if v_reviewer_ct < 1 then
    raise exception 'open_review: cannot open with zero reviewers' using errcode='23514';
  end if;

  update public.reviews set status = 'open' where id = p_review_id;

  select coalesce(jsonb_agg(workspace_member_id) filter (where workspace_member_id is not null), '[]'::jsonb),
         coalesce(jsonb_agg(stakeholder_id) filter (where stakeholder_id is not null), '[]'::jsonb)
    into v_wm_ids, v_sh_ids
    from public.review_participants
   where review_id = p_review_id and removed_at is null;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_proj, now(), 'review.opened',
    v_caller, 'user',
    'review', p_review_id, v_title,
    jsonb_build_object('title', v_title, 'reviewer_count', v_reviewer_ct),
    jsonb_build_object(
      'round_number', v_round,
      'roster', jsonb_build_object('wm_ids', v_wm_ids, 'sh_ids', v_sh_ids),
      'due_at', v_due
    )
  );
  return p_review_id;
end $$;
revoke all on function public.open_review(uuid) from public;
revoke all on function public.open_review(uuid) from anon;
grant execute on function public.open_review(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 5. set_review_state (waiting <-> in_progress)
------------------------------------------------------------------------------

create or replace function public.set_review_state(p_review_id uuid, p_target text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_proj uuid; v_status text; v_title text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'set_review_state: authentication required' using errcode='42501'; end if;
  if p_review_id is null then raise exception 'set_review_state: review_id required' using errcode='22004'; end if;
  if p_target is null or p_target not in ('waiting','in_progress') then
    raise exception 'set_review_state: invalid target %', coalesce(p_target,'(null)') using errcode='22023';
  end if;

  select workspace_id, project_id, status, title into v_ws, v_proj, v_status, v_title
    from public.reviews where id = p_review_id for update;
  if v_ws is null then raise exception 'set_review_state: review not found' using errcode='23503'; end if;

  if not public.lign_has_capability(v_proj, v_ws, 'review.coordinate') then
    raise exception 'set_review_state: forbidden (review.coordinate)' using errcode='42501';
  end if;

  if p_target = 'waiting' and v_status <> 'in_progress' then
    raise exception 'set_review_state: waiting only valid from in_progress (is %)', v_status using errcode='23514';
  end if;
  if p_target = 'in_progress' and v_status <> 'waiting' then
    raise exception 'set_review_state: in_progress from waiting only (is %)', v_status using errcode='23514';
  end if;

  update public.reviews set status = p_target where id = p_review_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_proj, now(), 'review.state_changed',
    v_caller, 'user',
    'review', p_review_id, v_title,
    jsonb_build_object('title', v_title),
    jsonb_build_object('from', v_status, 'to', p_target)
  );
  return p_review_id;
end $$;
revoke all on function public.set_review_state(uuid, text) from public;
revoke all on function public.set_review_state(uuid, text) from anon;
grant execute on function public.set_review_state(uuid, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 6. reopen_review
------------------------------------------------------------------------------

create or replace function public.reopen_review(
  p_review_id                    uuid,
  p_carry_forward_annotations    boolean default false,
  p_new_version_id               uuid    default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_proj uuid; v_status text; v_title text; v_desc text;
  v_asset uuid; v_version uuid; v_round int; v_root uuid;
  v_coord uuid; v_policy text; v_qmin int; v_rcr boolean;
  v_new_id uuid; v_new_version uuid; v_new_v_status text; v_new_v_asset uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'reopen_review: authentication required' using errcode='42501'; end if;
  if p_review_id is null then raise exception 'reopen_review: review_id required' using errcode='22004'; end if;

  select workspace_id, project_id, status, title, description,
         design_asset_id, version_id, round_number, root_review_id,
         coordinator_profile_id, policy, quorum_min, require_comments_resolved
    into v_ws, v_proj, v_status, v_title, v_desc,
         v_asset, v_version, v_round, v_root,
         v_coord, v_policy, v_qmin, v_rcr
    from public.reviews where id = p_review_id for update;
  if v_ws is null then raise exception 'reopen_review: review not found' using errcode='23503'; end if;

  if not public.lign_has_capability(v_proj, v_ws, 'review.reopen') then
    raise exception 'reopen_review: forbidden (review.reopen)' using errcode='42501';
  end if;
  if v_status <> 'completed' then
    raise exception 'reopen_review: only completed reviews can be reopened (is %)', v_status using errcode='23514';
  end if;

  v_new_version := coalesce(p_new_version_id, v_version);
  if p_new_version_id is not null then
    select design_asset_id, status into v_new_v_asset, v_new_v_status
      from public.asset_versions where id = p_new_version_id;
    if v_new_v_asset is null then
      raise exception 'reopen_review: new_version % not found', p_new_version_id using errcode='23503';
    end if;
    if v_new_v_asset <> v_asset then
      raise exception 'reopen_review: new_version does not belong to same asset' using errcode='23514';
    end if;
    if v_new_v_status <> 'published' then
      raise exception 'reopen_review: new_version must be published (is %)', v_new_v_status using errcode='23514';
    end if;
  end if;

  insert into public.reviews (
    workspace_id, project_id, design_asset_id, version_id,
    title, description, status, created_by_profile_id,
    round_number, parent_review_id, root_review_id,
    coordinator_profile_id, policy, quorum_min, require_comments_resolved
  ) values (
    v_ws, v_proj, v_asset, v_new_version,
    v_title, v_desc, 'draft', v_caller,
    v_round + 1, p_review_id, coalesce(v_root, p_review_id),
    v_coord, v_policy, v_qmin, v_rcr
  )
  returning id into v_new_id;

  -- Inherit roster (only active non-removed participants)
  insert into public.review_participants (
    workspace_id, review_id, workspace_member_id, stakeholder_id,
    status, assigned_at, required, sequence_index
  )
  select v_ws, v_new_id, workspace_member_id, stakeholder_id,
         'pending', now(), required, sequence_index
    from public.review_participants
   where review_id = p_review_id and removed_at is null;

  -- Optional annotation carry-forward
  if p_carry_forward_annotations and p_new_version_id is not null and p_new_version_id <> v_version then
    insert into public.annotations (
      workspace_id, asset_version_id, version_file_id, author_profile_id,
      anchor_kind, page_number, position, status
    )
    select workspace_id, v_new_version, null, v_caller,
           anchor_kind, page_number, position, 'active'
      from public.annotations
     where asset_version_id = v_version
       and status = 'active';
  end if;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_proj, now(), 'review.reopened',
    v_caller, 'user',
    'review', v_new_id, v_title,
    jsonb_build_object('title', v_title),
    jsonb_build_object(
      'old_review_id', p_review_id,
      'new_review_id', v_new_id,
      'new_round_number', v_round + 1,
      'carry_forward_annotations', p_carry_forward_annotations,
      'new_version_id', p_new_version_id
    )
  );

  return v_new_id;
end $$;
revoke all on function public.reopen_review(uuid, boolean, uuid) from public;
revoke all on function public.reopen_review(uuid, boolean, uuid) from anon;
grant execute on function public.reopen_review(uuid, boolean, uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 7. add_reviewer
------------------------------------------------------------------------------

create or replace function public.add_reviewer(
  p_review_id       uuid,
  p_wm_id           uuid    default null,
  p_sh_id           uuid    default null,
  p_required        boolean default true,
  p_sequence_index  integer default 0
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_proj uuid; v_status text; v_pid uuid;
  v_identity text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'add_reviewer: authentication required' using errcode='42501'; end if;
  if p_review_id is null then raise exception 'add_reviewer: review_id required' using errcode='22004'; end if;
  if (p_wm_id is null and p_sh_id is null) or (p_wm_id is not null and p_sh_id is not null) then
    raise exception 'add_reviewer: exactly one of wm_id / sh_id required (XOR)' using errcode='22023';
  end if;

  select workspace_id, project_id, status into v_ws, v_proj, v_status
    from public.reviews where id = p_review_id;
  if v_ws is null then raise exception 'add_reviewer: review not found' using errcode='23503'; end if;
  if v_status in ('completed','cancelled') then
    raise exception 'add_reviewer: cannot add to terminal review (%)', v_status using errcode='23514';
  end if;

  if not public.lign_has_capability(v_proj, v_ws, 'review.coordinate') then
    raise exception 'add_reviewer: forbidden (review.coordinate)' using errcode='42501';
  end if;

  -- Cross-project participant enforcement (G-32)
  if p_wm_id is not null then
    if not exists (
      select 1 from public.project_participants
       where project_id = v_proj and workspace_member_id = p_wm_id and status = 'active'
    ) then
      raise exception 'add_reviewer: workspace_member % is not an active project participant', p_wm_id using errcode='23514';
    end if;
    v_identity := 'member';
  else
    if not exists (
      select 1 from public.project_participants
       where project_id = v_proj and stakeholder_id = p_sh_id and status = 'active'
    ) then
      raise exception 'add_reviewer: stakeholder % is not an active project participant', p_sh_id using errcode='23514';
    end if;
    v_identity := 'stakeholder';
  end if;

  insert into public.review_participants (
    workspace_id, review_id, workspace_member_id, stakeholder_id,
    status, assigned_at, required, sequence_index
  ) values (
    v_ws, p_review_id, p_wm_id, p_sh_id,
    'pending', now(), p_required, p_sequence_index
  )
  returning id into v_pid;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_proj, now(), 'review.reviewer_added',
    v_caller, 'user',
    'review_participant', v_pid, '',
    '{}'::jsonb,
    jsonb_build_object(
      'review_id', p_review_id,
      'participant_id', v_pid,
      'required', p_required,
      'sequence_index', p_sequence_index,
      'identity', v_identity
    )
  );
  return v_pid;
end $$;
revoke all on function public.add_reviewer(uuid, uuid, uuid, boolean, integer) from public;
revoke all on function public.add_reviewer(uuid, uuid, uuid, boolean, integer) from anon;
grant execute on function public.add_reviewer(uuid, uuid, uuid, boolean, integer) to authenticated, service_role;

------------------------------------------------------------------------------
-- 8. remove_reviewer
------------------------------------------------------------------------------

create or replace function public.remove_reviewer(p_participant_id uuid, p_reason text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_proj uuid; v_review uuid; v_status text;
  v_r_status text; v_hard_deleted boolean := false;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'remove_reviewer: authentication required' using errcode='42501'; end if;
  if p_participant_id is null then raise exception 'remove_reviewer: participant_id required' using errcode='22004'; end if;
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'remove_reviewer: reason required (min 3 chars)' using errcode='22004';
  end if;

  select rp.workspace_id, rp.review_id, rp.status
    into v_ws, v_review, v_status
    from public.review_participants rp
   where rp.id = p_participant_id for update;
  if v_ws is null then raise exception 'remove_reviewer: participant not found' using errcode='23503'; end if;

  select project_id, status into v_proj, v_r_status
    from public.reviews where id = v_review;
  if v_r_status in ('completed','cancelled') then
    raise exception 'remove_reviewer: cannot modify roster of terminal review (%)', v_r_status using errcode='23514';
  end if;

  if not public.lign_has_capability(v_proj, v_ws, 'review.coordinate') then
    raise exception 'remove_reviewer: forbidden (review.coordinate)' using errcode='42501';
  end if;

  if v_status = 'pending' then
    -- Hard-delete
    delete from public.review_participants where id = p_participant_id;
    v_hard_deleted := true;
  else
    -- Soft-remove: preserve response history
    update public.review_participants
       set removed_at = now(), removed_reason = p_reason
     where id = p_participant_id;
  end if;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_proj, now(), 'review.reviewer_removed',
    v_caller, 'user',
    'review_participant', p_participant_id, '',
    '{}'::jsonb,
    jsonb_build_object(
      'review_id', v_review,
      'participant_id', p_participant_id,
      'reason', p_reason,
      'hard_deleted', v_hard_deleted
    )
  );
  return p_participant_id;
end $$;
revoke all on function public.remove_reviewer(uuid, text) from public;
revoke all on function public.remove_reviewer(uuid, text) from anon;
grant execute on function public.remove_reviewer(uuid, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 9. reassign_reviewer
------------------------------------------------------------------------------

create or replace function public.reassign_reviewer(
  p_participant_id uuid,
  p_new_wm_id      uuid default null,
  p_new_sh_id      uuid default null
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_proj uuid; v_review uuid; v_status text; v_r_status text;
  v_old_wm uuid; v_old_sh uuid; v_required boolean; v_seq int;
  v_new_pid uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'reassign_reviewer: authentication required' using errcode='42501'; end if;
  if p_participant_id is null then raise exception 'reassign_reviewer: participant_id required' using errcode='22004'; end if;
  if (p_new_wm_id is null and p_new_sh_id is null) or (p_new_wm_id is not null and p_new_sh_id is not null) then
    raise exception 'reassign_reviewer: exactly one of new_wm_id / new_sh_id required (XOR)' using errcode='22023';
  end if;

  select rp.workspace_id, rp.review_id, rp.status,
         rp.workspace_member_id, rp.stakeholder_id, rp.required, rp.sequence_index
    into v_ws, v_review, v_status, v_old_wm, v_old_sh, v_required, v_seq
    from public.review_participants rp
   where rp.id = p_participant_id for update;
  if v_ws is null then raise exception 'reassign_reviewer: participant not found' using errcode='23503'; end if;
  if v_status <> 'pending' then
    raise exception 'reassign_reviewer: cannot reassign a participant who has already responded' using errcode='23514';
  end if;

  select project_id, status into v_proj, v_r_status
    from public.reviews where id = v_review;
  if v_r_status in ('completed','cancelled') then
    raise exception 'reassign_reviewer: cannot modify roster of terminal review (%)', v_r_status using errcode='23514';
  end if;

  if not public.lign_has_capability(v_proj, v_ws, 'review.coordinate') then
    raise exception 'reassign_reviewer: forbidden (review.coordinate)' using errcode='42501';
  end if;

  -- Cross-project participant enforcement (G-32)
  if p_new_wm_id is not null then
    if not exists (
      select 1 from public.project_participants
       where project_id = v_proj and workspace_member_id = p_new_wm_id and status = 'active'
    ) then
      raise exception 'reassign_reviewer: new workspace_member is not an active project participant' using errcode='23514';
    end if;
  else
    if not exists (
      select 1 from public.project_participants
       where project_id = v_proj and stakeholder_id = p_new_sh_id and status = 'active'
    ) then
      raise exception 'reassign_reviewer: new stakeholder is not an active project participant' using errcode='23514';
    end if;
  end if;

  -- Atomic: hard-remove old, insert new preserving required + sequence_index
  delete from public.review_participants where id = p_participant_id;

  insert into public.review_participants (
    workspace_id, review_id, workspace_member_id, stakeholder_id,
    status, assigned_at, required, sequence_index
  ) values (
    v_ws, v_review, p_new_wm_id, p_new_sh_id,
    'pending', now(), v_required, v_seq
  )
  returning id into v_new_pid;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_proj, now(), 'review.reviewer_reassigned',
    v_caller, 'user',
    'review_participant', v_new_pid, '',
    '{}'::jsonb,
    jsonb_build_object(
      'review_id', v_review,
      'participant_id', v_new_pid,
      'from_identity', case when v_old_wm is not null then 'member' else 'stakeholder' end,
      'to_identity',   case when p_new_wm_id is not null then 'member' else 'stakeholder' end
    )
  );
  return v_new_pid;
end $$;
revoke all on function public.reassign_reviewer(uuid, uuid, uuid) from public;
revoke all on function public.reassign_reviewer(uuid, uuid, uuid) from anon;
grant execute on function public.reassign_reviewer(uuid, uuid, uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 10. set_reviewer_required
------------------------------------------------------------------------------

create or replace function public.set_reviewer_required(p_participant_id uuid, p_required boolean)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_ws uuid; v_proj uuid; v_review uuid; v_r_status text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'set_reviewer_required: authentication required' using errcode='42501'; end if;
  if p_participant_id is null or p_required is null then
    raise exception 'set_reviewer_required: participant_id and required required' using errcode='22004';
  end if;

  select rp.workspace_id, rp.review_id into v_ws, v_review
    from public.review_participants rp where rp.id = p_participant_id;
  if v_ws is null then raise exception 'set_reviewer_required: participant not found' using errcode='23503'; end if;

  select project_id, status into v_proj, v_r_status
    from public.reviews where id = v_review;
  if v_r_status in ('completed','cancelled') then
    raise exception 'set_reviewer_required: cannot modify terminal review' using errcode='23514';
  end if;
  if not public.lign_has_capability(v_proj, v_ws, 'review.coordinate') then
    raise exception 'set_reviewer_required: forbidden (review.coordinate)' using errcode='42501';
  end if;

  update public.review_participants set required = p_required where id = p_participant_id;
  return p_participant_id;
end $$;
revoke all on function public.set_reviewer_required(uuid, boolean) from public;
revoke all on function public.set_reviewer_required(uuid, boolean) from anon;
grant execute on function public.set_reviewer_required(uuid, boolean) to authenticated, service_role;

------------------------------------------------------------------------------
-- 11. toggle_bookmark
------------------------------------------------------------------------------

create or replace function public.toggle_bookmark(
  p_subject_kind text,
  p_subject_id   uuid,
  p_workspace_id uuid
)
returns boolean
language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_existing uuid; v_bookmarked boolean;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'toggle_bookmark: authentication required' using errcode='42501'; end if;
  if p_subject_kind is null or p_subject_id is null or p_workspace_id is null then
    raise exception 'toggle_bookmark: all params required' using errcode='22004';
  end if;
  if not public.lign_is_workspace_member(p_workspace_id) then
    raise exception 'toggle_bookmark: not a workspace member' using errcode='42501';
  end if;

  select id into v_existing from public.user_bookmarks
   where user_id = v_caller and subject_kind = p_subject_kind and subject_id = p_subject_id;

  if v_existing is not null then
    delete from public.user_bookmarks where id = v_existing;
    v_bookmarked := false;
  else
    insert into public.user_bookmarks (user_id, workspace_id, subject_kind, subject_id)
    values (v_caller, p_workspace_id, p_subject_kind, p_subject_id);
    v_bookmarked := true;
  end if;
  return v_bookmarked;
end $$;
revoke all on function public.toggle_bookmark(text, uuid, uuid) from public;
revoke all on function public.toggle_bookmark(text, uuid, uuid) from anon;
grant execute on function public.toggle_bookmark(text, uuid, uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 12. save_dashboard_view + delete_dashboard_view
------------------------------------------------------------------------------

create or replace function public.save_dashboard_view(
  p_view_id      uuid,
  p_workspace_id uuid,
  p_scope        text,
  p_name         text,
  p_definition   jsonb,
  p_visibility   text default 'private'
)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_id uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'save_dashboard_view: authentication required' using errcode='42501'; end if;
  if p_workspace_id is null or p_scope is null or p_name is null or p_definition is null then
    raise exception 'save_dashboard_view: workspace_id, scope, name, definition required' using errcode='22004';
  end if;
  if p_visibility is null or p_visibility <> 'private' then
    raise exception 'save_dashboard_view: v1 enforces visibility=private only' using errcode='22023';
  end if;
  if not public.lign_is_workspace_member(p_workspace_id) then
    raise exception 'save_dashboard_view: not a workspace member' using errcode='42501';
  end if;

  if p_view_id is null then
    insert into public.user_saved_views (user_id, workspace_id, scope, name, definition, visibility)
    values (v_caller, p_workspace_id, p_scope, p_name, p_definition, 'private')
    returning id into v_id;
  else
    update public.user_saved_views
       set name = p_name, definition = p_definition
     where id = p_view_id and user_id = v_caller
    returning id into v_id;
    if v_id is null then
      raise exception 'save_dashboard_view: view not found or not owned by caller' using errcode='23503';
    end if;
  end if;
  return v_id;
end $$;
revoke all on function public.save_dashboard_view(uuid, uuid, text, text, jsonb, text) from public;
revoke all on function public.save_dashboard_view(uuid, uuid, text, text, jsonb, text) from anon;
grant execute on function public.save_dashboard_view(uuid, uuid, text, text, jsonb, text) to authenticated, service_role;

create or replace function public.delete_dashboard_view(p_view_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_count int;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'delete_dashboard_view: authentication required' using errcode='42501'; end if;
  delete from public.user_saved_views where id = p_view_id and user_id = v_caller;
  get diagnostics v_count = row_count;
  if v_count = 0 then
    raise exception 'delete_dashboard_view: view not found or not owned by caller' using errcode='23503';
  end if;
end $$;
revoke all on function public.delete_dashboard_view(uuid) from public;
revoke all on function public.delete_dashboard_view(uuid) from anon;
grant execute on function public.delete_dashboard_view(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 13. list_reviews_dashboard (paginated read)
------------------------------------------------------------------------------
-- Returns paginated review rows with precomputed metrics. Server-opaque
-- cursor is a (updated_at, id) tuple; caller passes them back verbatim.

create or replace function public.list_reviews_dashboard(
  p_ws_id                   uuid,
  p_proj_id                 uuid    default null,
  p_view                    text    default 'recent',
  p_status_filter           text[]  default null,
  p_owner_ids               uuid[]  default null,
  p_reviewer_profile_ids    uuid[]  default null,
  p_cursor_updated_at       timestamptz default null,
  p_cursor_id               uuid    default null,
  p_limit                   integer default 30
)
returns table (
  out_id                          uuid,
  out_workspace_id                uuid,
  out_project_id                  uuid,
  out_design_asset_id             uuid,
  out_version_id                  uuid,
  out_title                       text,
  out_description                 text,
  out_status                      text,
  out_round_number                integer,
  out_root_review_id              uuid,
  out_policy                      text,
  out_created_by_profile_id       uuid,
  out_coordinator_profile_id      uuid,
  out_due_at                      timestamptz,
  out_completed_at                timestamptz,
  out_cancelled_at                timestamptz,
  out_created_at                  timestamptz,
  out_updated_at                  timestamptz,
  out_open_reviewer_count         integer,
  out_signed_off_count            integer,
  out_declined_count              integer,
  out_commented_count             integer,
  out_total_reviewer_count        integer,
  out_open_comment_count          integer,
  out_overdue_flag                boolean,
  out_my_slot_status              text
)
language plpgsql security definer set search_path = '' stable
as $$
declare v_caller uuid; v_lim int;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'list_reviews_dashboard: authentication required' using errcode='42501'; end if;
  if p_ws_id is null then raise exception 'list_reviews_dashboard: ws_id required' using errcode='22004'; end if;
  v_lim := greatest(1, least(coalesce(p_limit, 30), 100));

  return query
    with visible as (
      select r.*
        from public.reviews r
       where r.workspace_id = p_ws_id
         and (p_proj_id is null or r.project_id = p_proj_id)
         and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
    ),
    filtered as (
      select v.*
        from visible v
       where (p_status_filter is null or v.status = any(p_status_filter))
         and (p_owner_ids is null or v.created_by_profile_id = any(p_owner_ids))
         and (
           p_reviewer_profile_ids is null
           or exists (
             select 1 from public.review_participants rp
              left join public.workspace_members wm on wm.id = rp.workspace_member_id
              left join public.stakeholders sh on sh.id = rp.stakeholder_id
              where rp.review_id = v.id
                and rp.removed_at is null
                and coalesce(wm.user_id, sh.user_id) = any(p_reviewer_profile_ids)
           )
         )
         and case p_view
           when 'assigned_to_me' then exists (
             select 1 from public.review_participants rp
              left join public.workspace_members wm on wm.id = rp.workspace_member_id
              left join public.stakeholders sh on sh.id = rp.stakeholder_id
              where rp.review_id = v.id
                and rp.removed_at is null
                and rp.status = 'pending'
                and coalesce(wm.user_id, sh.user_id) = v_caller
           ) and v.status in ('open','in_progress','waiting')
           when 'waiting_on_others' then v.created_by_profile_id = v_caller
                                        and v.status in ('open','in_progress','waiting')
           when 'overdue' then v.due_at is not null and v.due_at < now()
                              and v.status in ('open','in_progress','waiting')
           when 'completed' then v.status = 'completed'
                                and (
                                  v.created_by_profile_id = v_caller
                                  or exists (
                                    select 1 from public.review_participants rp
                                     left join public.workspace_members wm on wm.id = rp.workspace_member_id
                                     left join public.stakeholders sh on sh.id = rp.stakeholder_id
                                     where rp.review_id = v.id
                                       and coalesce(wm.user_id, sh.user_id) = v_caller
                                  )
                                )
           when 'bookmarks' then exists (
             select 1 from public.user_bookmarks b
              where b.user_id = v_caller
                and b.subject_kind = 'review'
                and b.subject_id = v.id
           )
           else true  -- 'recent' or unknown
         end
    )
    select
      f.id, f.workspace_id, f.project_id, f.design_asset_id, f.version_id,
      f.title, f.description, f.status, f.round_number, f.root_review_id, f.policy,
      f.created_by_profile_id, f.coordinator_profile_id,
      f.due_at, f.completed_at, f.cancelled_at, f.created_at, f.updated_at,
      (select count(*)::int from public.review_participants
        where review_id = f.id and status = 'pending' and removed_at is null),
      (select count(*)::int from public.review_participants
        where review_id = f.id and status = 'signed_off' and removed_at is null),
      (select count(*)::int from public.review_participants
        where review_id = f.id and status = 'declined' and removed_at is null),
      (select count(*)::int from public.review_participants
        where review_id = f.id and status = 'commented' and removed_at is null),
      (select count(*)::int from public.review_participants
        where review_id = f.id and removed_at is null),
      (select count(*)::int from public.comments
        where target_review_id = f.id
          and parent_comment_id is null
          and resolved_at is null
          and deleted_at is null),
      (f.due_at is not null and f.due_at < now() and f.status in ('open','in_progress','waiting')),
      (select rp.status from public.review_participants rp
        left join public.workspace_members wm on wm.id = rp.workspace_member_id
        left join public.stakeholders sh on sh.id = rp.stakeholder_id
        where rp.review_id = f.id
          and rp.removed_at is null
          and coalesce(wm.user_id, sh.user_id) = v_caller
        limit 1)
    from filtered f
    where (p_cursor_updated_at is null
           or (f.updated_at, f.id) < (p_cursor_updated_at, p_cursor_id))
    order by f.updated_at desc, f.id desc
    limit v_lim;
end $$;
revoke all on function public.list_reviews_dashboard(uuid, uuid, text, text[], uuid[], uuid[], timestamptz, uuid, integer) from public;
revoke all on function public.list_reviews_dashboard(uuid, uuid, text, text[], uuid[], uuid[], timestamptz, uuid, integer) from anon;
grant execute on function public.list_reviews_dashboard(uuid, uuid, text, text[], uuid[], uuid[], timestamptz, uuid, integer) to authenticated, service_role;

------------------------------------------------------------------------------
-- 14. get_review
------------------------------------------------------------------------------

create or replace function public.get_review(p_review_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' stable
as $$
declare v_caller uuid; v_row jsonb; v_participants jsonb; v_metrics jsonb;
        v_ws uuid; v_proj uuid; v_asset uuid; v_version uuid;
        v_opened_at timestamptz; v_first_resp_at timestamptz; v_first_comm_at timestamptz;
        v_newer_exists boolean; v_chain jsonb;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_review: authentication required' using errcode='42501'; end if;

  select r.workspace_id, r.project_id, r.design_asset_id, r.version_id
    into v_ws, v_proj, v_asset, v_version
    from public.reviews r where r.id = p_review_id;
  if v_ws is null then return null; end if;
  if not public.lign_has_capability(v_proj, v_ws, 'review.view') then
    raise exception 'get_review: forbidden (review.view)' using errcode='42501';
  end if;

  -- Row
  select to_jsonb(r) into v_row from public.reviews r where r.id = p_review_id;

  -- Participants with identity resolution
  select coalesce(jsonb_agg(row_to_jsonb(x)), '[]'::jsonb) into v_participants
  from (
    select rp.id, rp.workspace_member_id, rp.stakeholder_id,
           rp.status, rp.assigned_at, rp.responded_at,
           rp.required, rp.sequence_index, rp.removed_at, rp.removed_reason,
           coalesce(wm_p.display_name, sh_p.display_name, sh.display_name) as display_name,
           coalesce(wm_p.avatar_url, sh_p.avatar_url) as avatar_url,
           coalesce(wm.user_id, sh.user_id) as profile_id,
           case when rp.workspace_member_id is not null then 'member' else 'stakeholder' end as identity
      from public.review_participants rp
      left join public.workspace_members wm on wm.id = rp.workspace_member_id
      left join public.stakeholders sh on sh.id = rp.stakeholder_id
      left join public.profiles wm_p on wm_p.id = wm.user_id
      left join public.profiles sh_p on sh_p.id = sh.user_id
     where rp.review_id = p_review_id
     order by rp.sequence_index asc, rp.assigned_at asc
  ) x;

  -- Metrics — derive opened/first-response/first-comment timestamps from events
  select min(ae.occurred_at) into v_opened_at
    from public.activity_events ae
   where ae.subject_kind = 'review' and ae.subject_id = p_review_id
     and ae.event_type = 'review.opened';

  select min(ae.occurred_at) into v_first_resp_at
    from public.activity_events ae
   where ae.subject_kind = 'review_participant'
     and (ae.payload->>'review_id')::uuid = p_review_id
     and ae.event_type = 'review.reviewer_responded';

  select min(c.created_at) into v_first_comm_at
    from public.comments c
   where c.target_review_id = p_review_id and c.deleted_at is null;

  select v_version is not null and exists (
    select 1 from public.asset_versions av2
     where av2.design_asset_id = v_asset
       and av2.status = 'published'
       and av2.published_at > coalesce((select published_at from public.asset_versions where id = v_version), '-infinity'::timestamptz)
  ) into v_newer_exists;

  v_metrics := jsonb_build_object(
    'opened_at', v_opened_at,
    'first_responded_at', v_first_resp_at,
    'first_commented_at', v_first_comm_at,
    'open_comment_count', (
      select count(*) from public.comments
       where target_review_id = p_review_id
         and parent_comment_id is null
         and resolved_at is null
         and deleted_at is null
    ),
    'response_distribution', (
      select jsonb_build_object(
        'signed_off', count(*) filter (where status='signed_off'),
        'commented',  count(*) filter (where status='commented'),
        'declined',   count(*) filter (where status='declined'),
        'pending',    count(*) filter (where status='pending')
      ) from public.review_participants where review_id = p_review_id and removed_at is null
    ),
    'newer_version_exists', v_newer_exists
  );

  -- Chain position: is_latest, prior/next in chain
  select jsonb_build_object(
    'round_number', (v_row->>'round_number')::int,
    'is_latest', not exists (
      select 1 from public.reviews r2
       where r2.parent_review_id = p_review_id
    ),
    'prior_review_id', (v_row->>'parent_review_id')::uuid,
    'next_review_id', (
      select r2.id from public.reviews r2
       where r2.parent_review_id = p_review_id
       limit 1
    )
  ) into v_chain;

  return jsonb_build_object(
    'review', v_row,
    'participants', v_participants,
    'metrics', v_metrics,
    'chain_position', v_chain
  );
end $$;
revoke all on function public.get_review(uuid) from public;
revoke all on function public.get_review(uuid) from anon;
grant execute on function public.get_review(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 15. get_review_chain
------------------------------------------------------------------------------

create or replace function public.get_review_chain(p_root_review_id uuid)
returns table (
  out_id                uuid,
  out_round_number      integer,
  out_status            text,
  out_title             text,
  out_created_at        timestamptz,
  out_completed_at      timestamptz,
  out_cancelled_at      timestamptz,
  out_reviewer_count    integer,
  out_signed_off_count  integer,
  out_declined_count    integer
)
language plpgsql security definer set search_path = '' stable
as $$
declare v_caller uuid; v_ws uuid; v_proj uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_review_chain: authentication required' using errcode='42501'; end if;

  select workspace_id, project_id into v_ws, v_proj
    from public.reviews where id = p_root_review_id;
  if v_ws is null then return; end if;
  if not public.lign_has_capability(v_proj, v_ws, 'review.view') then
    raise exception 'get_review_chain: forbidden (review.view)' using errcode='42501';
  end if;

  return query
    select r.id, r.round_number, r.status, r.title,
           r.created_at, r.completed_at, r.cancelled_at,
           (select count(*)::int from public.review_participants
             where review_id = r.id and removed_at is null),
           (select count(*)::int from public.review_participants
             where review_id = r.id and status='signed_off' and removed_at is null),
           (select count(*)::int from public.review_participants
             where review_id = r.id and status='declined' and removed_at is null)
      from public.reviews r
     where r.root_review_id = p_root_review_id or r.id = p_root_review_id
     order by r.round_number asc;
end $$;
revoke all on function public.get_review_chain(uuid) from public;
revoke all on function public.get_review_chain(uuid) from anon;
grant execute on function public.get_review_chain(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 16. get_review_inbox_count
------------------------------------------------------------------------------

create or replace function public.get_review_inbox_count(p_ws_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' stable
as $$
declare v_caller uuid; v_assigned int; v_overdue int; v_coord int;
begin
  v_caller := auth.uid();
  if v_caller is null then return jsonb_build_object('assigned_to_me',0,'overdue',0,'coordinating',0); end if;
  if p_ws_id is null then return jsonb_build_object('assigned_to_me',0,'overdue',0,'coordinating',0); end if;

  select count(*) into v_assigned
    from public.reviews r
    join public.review_participants rp on rp.review_id = r.id
    left join public.workspace_members wm on wm.id = rp.workspace_member_id
    left join public.stakeholders sh on sh.id = rp.stakeholder_id
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
     and rp.removed_at is null
     and rp.status = 'pending'
     and r.status in ('open','in_progress','waiting')
     and coalesce(wm.user_id, sh.user_id) = v_caller;

  select count(*) into v_overdue
    from public.reviews r
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
     and r.due_at is not null
     and r.due_at < now()
     and r.status in ('open','in_progress','waiting');

  select count(*) into v_coord
    from public.reviews r
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
     and r.status in ('open','in_progress','waiting')
     and (r.coordinator_profile_id = v_caller or (r.coordinator_profile_id is null and r.created_by_profile_id = v_caller));

  return jsonb_build_object(
    'assigned_to_me', v_assigned,
    'overdue', v_overdue,
    'coordinating', v_coord
  );
end $$;
revoke all on function public.get_review_inbox_count(uuid) from public;
revoke all on function public.get_review_inbox_count(uuid) from anon;
grant execute on function public.get_review_inbox_count(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 17. get_project_review_metrics
------------------------------------------------------------------------------

create or replace function public.get_project_review_metrics(p_proj_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' stable
as $$
declare v_ws uuid; v_out int; v_over int;
begin
  select workspace_id into v_ws from public.projects where id = p_proj_id;
  if v_ws is null then return null; end if;
  if not public.lign_has_capability(p_proj_id, v_ws, 'review.view') then
    raise exception 'get_project_review_metrics: forbidden (review.view)' using errcode='42501';
  end if;

  select count(*) into v_out from public.reviews
    where project_id = p_proj_id and status in ('open','in_progress','waiting','ready_for_review');
  select count(*) into v_over from public.reviews
    where project_id = p_proj_id
      and due_at is not null and due_at < now()
      and status in ('open','in_progress','waiting');

  return jsonb_build_object(
    'outstanding_count', v_out,
    'overdue_count', v_over
  );
end $$;
revoke all on function public.get_project_review_metrics(uuid) from public;
revoke all on function public.get_project_review_metrics(uuid) from anon;
grant execute on function public.get_project_review_metrics(uuid) to authenticated, service_role;

------------------------------------------------------------------------------
-- 18. get_workspace_review_metrics
------------------------------------------------------------------------------

create or replace function public.get_workspace_review_metrics(p_ws_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' stable
as $$
declare v_caller uuid; v_out int; v_over int;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'get_workspace_review_metrics: authentication required' using errcode='42501'; end if;
  if p_ws_id is null then return null; end if;

  select count(*) into v_out from public.reviews r
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
     and r.status in ('open','in_progress','waiting','ready_for_review');

  select count(*) into v_over from public.reviews r
   where r.workspace_id = p_ws_id
     and public.lign_has_capability(r.project_id, r.workspace_id, 'review.view')
     and r.due_at is not null and r.due_at < now()
     and r.status in ('open','in_progress','waiting');

  return jsonb_build_object(
    'outstanding_count', v_out,
    'overdue_count', v_over
  );
end $$;
revoke all on function public.get_workspace_review_metrics(uuid) from public;
revoke all on function public.get_workspace_review_metrics(uuid) from anon;
grant execute on function public.get_workspace_review_metrics(uuid) to authenticated, service_role;
