-- APP 006 RPCs part 3: complete_review, open_review, set_review_state, reopen_review

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

  insert into public.review_participants (
    workspace_id, review_id, workspace_member_id, stakeholder_id,
    status, assigned_at, required, sequence_index
  )
  select v_ws, v_new_id, workspace_member_id, stakeholder_id,
         'pending', now(), required, sequence_index
    from public.review_participants
   where review_id = p_review_id and removed_at is null;

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
