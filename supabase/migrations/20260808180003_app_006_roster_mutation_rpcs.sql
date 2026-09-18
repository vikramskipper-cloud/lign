-- APP 006 RPCs part 4: roster mutation (add/remove/reassign/set_required)

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
    delete from public.review_participants where id = p_participant_id;
    v_hard_deleted := true;
  else
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
