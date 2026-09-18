-- AUTH 007 apply

create or replace function public.request_approval(
  p_project_id uuid, p_design_asset_id uuid, p_version_id uuid, p_policy text,
  p_approver_wm_ids uuid[] default '{}'::uuid[], p_approver_sh_ids uuid[] default '{}'::uuid[],
  p_title text default null, p_description text default null, p_due_at timestamptz default null
) returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_workspace_id uuid; v_da_project uuid; v_v_asset uuid; v_v_status text; v_v_sequence int;
        v_request_id uuid; v_wm_id uuid; v_sh_id uuid; v_sort int := 0;
        v_seen_wm uuid[] := '{}'::uuid[]; v_seen_sh uuid[] := '{}'::uuid[]; v_seen_users uuid[] := '{}'::uuid[];
        v_probe_user uuid; v_approver_count int;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'request_approval: auth required' using errcode='42501'; end if;
  if p_policy not in ('any','all') then raise exception 'request_approval: policy must be any|all' using errcode='22023'; end if;

  select workspace_id, project_id into v_workspace_id, v_da_project from public.design_assets where id = p_design_asset_id;
  if v_workspace_id is null then raise exception 'request_approval: design_asset not found' using errcode='23503'; end if;
  if v_da_project <> p_project_id then raise exception 'request_approval: asset does not belong to project' using errcode='23514'; end if;

  select design_asset_id, status, sequence into v_v_asset, v_v_status, v_v_sequence from public.asset_versions where id = p_version_id;
  if v_v_asset is null then raise exception 'request_approval: version not found' using errcode='23503'; end if;
  if v_v_asset <> p_design_asset_id then raise exception 'request_approval: version does not belong to asset' using errcode='23514'; end if;
  if v_v_status <> 'published' then raise exception 'request_approval: version must be published' using errcode='23514'; end if;

  if not public.lign_has_capability(p_project_id, v_workspace_id, 'approval.request') then
    raise exception 'request_approval: forbidden (approval.request)' using errcode='42501';
  end if;

  if exists (select 1 from public.approval_requests where design_asset_id = p_design_asset_id and version_id = p_version_id and status = 'in_progress') then
    raise exception 'request_approval: another in_progress request already exists for this asset/version' using errcode='23514';
  end if;

  v_approver_count := coalesce(array_length(p_approver_wm_ids, 1), 0) + coalesce(array_length(p_approver_sh_ids, 1), 0);
  if v_approver_count < 1 then raise exception 'request_approval: at least one approver required' using errcode='23514'; end if;

  foreach v_wm_id in array coalesce(p_approver_wm_ids, '{}'::uuid[]) loop
    if v_wm_id = any(v_seen_wm) then raise exception 'request_approval: duplicate workspace_member approver' using errcode='23514'; end if;
    v_seen_wm := v_seen_wm || v_wm_id;
    select user_id into v_probe_user from public.workspace_members where id = v_wm_id and workspace_id = v_workspace_id and status = 'active';
    if not found then raise exception 'request_approval: workspace_member % not active in workspace', v_wm_id using errcode='23503'; end if;
    if v_probe_user is not null then
      if v_probe_user = any(v_seen_users) then raise exception 'request_approval: dual-path duplicate' using errcode='23514'; end if;
      v_seen_users := v_seen_users || v_probe_user;
    end if;
  end loop;

  foreach v_sh_id in array coalesce(p_approver_sh_ids, '{}'::uuid[]) loop
    if v_sh_id = any(v_seen_sh) then raise exception 'request_approval: duplicate stakeholder approver' using errcode='23514'; end if;
    v_seen_sh := v_seen_sh || v_sh_id;
    select user_id into v_probe_user from public.stakeholders where id = v_sh_id and workspace_id = v_workspace_id and status in ('active','invited');
    if not found then raise exception 'request_approval: stakeholder % not in workspace', v_sh_id using errcode='23503'; end if;
    if v_probe_user is not null then
      if v_probe_user = any(v_seen_users) then raise exception 'request_approval: dual-path duplicate' using errcode='23514'; end if;
      v_seen_users := v_seen_users || v_probe_user;
    end if;
  end loop;

  insert into public.approval_requests (workspace_id, project_id, design_asset_id, version_id, policy, status, title, description, due_at, sent_at, created_by_profile_id)
  values (v_workspace_id, p_project_id, p_design_asset_id, p_version_id, p_policy, 'in_progress', p_title, p_description, p_due_at, now(), v_caller)
  returning id into v_request_id;

  foreach v_wm_id in array coalesce(p_approver_wm_ids, '{}'::uuid[]) loop
    insert into public.approval_request_approvers (workspace_id, approval_request_id, workspace_member_id, sort_order)
    values (v_workspace_id, v_request_id, v_wm_id, v_sort);
    v_sort := v_sort + 1;
  end loop;
  foreach v_sh_id in array coalesce(p_approver_sh_ids, '{}'::uuid[]) loop
    insert into public.approval_request_approvers (workspace_id, approval_request_id, stakeholder_id, sort_order)
    values (v_workspace_id, v_request_id, v_sh_id, v_sort);
    v_sort := v_sort + 1;
  end loop;

  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_workspace_id, p_project_id, now(), 'approval.requested', v_caller, 'user', 'approval_request', v_request_id, coalesce(p_title,'approval'),
    jsonb_build_object('asset_id', p_design_asset_id, 'version_id', p_version_id, 'version_sequence', v_v_sequence, 'policy', p_policy, 'approver_count', v_approver_count, 'due_at', to_jsonb(p_due_at)), '{}'::jsonb);
  return v_request_id;
end $$;
revoke all on function public.request_approval(uuid,uuid,uuid,text,uuid[],uuid[],text,text,timestamptz) from public;
revoke all on function public.request_approval(uuid,uuid,uuid,text,uuid[],uuid[],text,text,timestamptz) from anon;
grant execute on function public.request_approval(uuid,uuid,uuid,text,uuid[],uuid[],text,text,timestamptz) to authenticated, service_role;

create or replace function public.respond_to_approval(p_approver_slot_id uuid, p_decision text, p_comment text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_workspace_id uuid; v_project_id uuid; v_request_id uuid; v_request_status text; v_policy text;
        v_wm_id uuid; v_sh_id uuid; v_slot_user_id uuid; v_response_id uuid;
        v_total int; v_responded int; v_approved int; v_non_approved int; v_outcome text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'respond_to_approval: auth required' using errcode='42501'; end if;
  if p_decision not in ('approved','rejected','changes_requested') then raise exception 'respond_to_approval: invalid decision' using errcode='22023'; end if;

  select workspace_id, approval_request_id, workspace_member_id, stakeholder_id into v_workspace_id, v_request_id, v_wm_id, v_sh_id
    from public.approval_request_approvers where id = p_approver_slot_id;
  if v_workspace_id is null then raise exception 'respond_to_approval: slot not found' using errcode='23503'; end if;

  select project_id, status, policy into v_project_id, v_request_status, v_policy
    from public.approval_requests where id = v_request_id and workspace_id = v_workspace_id for update;
  if v_request_status <> 'in_progress' then raise exception 'respond_to_approval: request is % (must be in_progress)', v_request_status using errcode='23514'; end if;

  if not public.lign_has_capability(v_project_id, v_workspace_id, 'approval.respond') then
    raise exception 'respond_to_approval: forbidden (approval.respond)' using errcode='42501';
  end if;

  if v_wm_id is not null then
    select user_id into v_slot_user_id from public.workspace_members where id = v_wm_id;
  else
    select user_id into v_slot_user_id from public.stakeholders where id = v_sh_id;
  end if;
  if v_slot_user_id is null then raise exception 'respond_to_approval: slot identity is unclaimed' using errcode='42501'; end if;
  if v_slot_user_id <> v_caller then raise exception 'respond_to_approval: caller does not own this slot' using errcode='42501'; end if;

  insert into public.approval_responses (workspace_id, approval_request_id, approver_slot_id, responder_profile_id, decision, comment, responded_at)
  values (v_workspace_id, v_request_id, p_approver_slot_id, v_caller, p_decision, p_comment, now())
  returning id into v_response_id;

  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_workspace_id, v_project_id, now(), 'approval.responded', v_caller, 'user', 'approval_response', v_response_id, p_decision,
    jsonb_build_object('request_id', v_request_id, 'decision', p_decision), '{}'::jsonb);

  select count(*) into v_total from public.approval_request_approvers where approval_request_id = v_request_id;
  select count(*), count(*) filter (where decision='approved'), count(*) filter (where decision in ('rejected','changes_requested'))
    into v_responded, v_approved, v_non_approved
    from public.approval_responses where approval_request_id = v_request_id;

  v_outcome := null;
  if v_policy = 'any' then
    if v_approved >= 1 then v_outcome := 'approved';
    elsif v_responded = v_total and v_approved = 0 then v_outcome := 'rejected';
    end if;
  elsif v_policy = 'all' then
    if v_non_approved >= 1 then v_outcome := 'rejected';
    elsif v_approved = v_total then v_outcome := 'approved';
    end if;
  end if;

  if v_outcome is not null then
    update public.approval_requests set status = v_outcome, outcome_at = now(), outcome_actor_profile_id = null where id = v_request_id;
    insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
    values (v_workspace_id, v_project_id, now(), case when v_outcome='approved' then 'approval.approved' else 'approval.rejected' end,
      null, 'system', 'approval_request', v_request_id, v_outcome, jsonb_build_object('policy', v_policy), '{}'::jsonb);
  end if;
  return v_response_id;
end $$;
revoke all on function public.respond_to_approval(uuid, text, text) from public;
revoke all on function public.respond_to_approval(uuid, text, text) from anon;
grant execute on function public.respond_to_approval(uuid, text, text) to authenticated, service_role;

create or replace function public.cancel_approval(p_approval_request_id uuid, p_reason text default null)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_workspace_id uuid; v_project_id uuid; v_status text;
begin
  v_caller := auth.uid();
  if v_caller is null then raise exception 'cancel_approval: auth required' using errcode='42501'; end if;
  select workspace_id, project_id, status into v_workspace_id, v_project_id, v_status
    from public.approval_requests where id = p_approval_request_id for update;
  if v_workspace_id is null then raise exception 'cancel_approval: request not found' using errcode='23503'; end if;
  if v_status <> 'in_progress' then raise exception 'cancel_approval: request is % (must be in_progress)', v_status using errcode='23514'; end if;
  if not public.lign_has_capability(v_project_id, v_workspace_id, 'approval.cancel') then
    raise exception 'cancel_approval: forbidden (approval.cancel)' using errcode='42501';
  end if;
  update public.approval_requests set status='cancelled', outcome_at=now(), outcome_actor_profile_id=v_caller, outcome_note=p_reason
   where id = p_approval_request_id;
  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_workspace_id, v_project_id, now(), 'approval.cancelled', v_caller, 'user', 'approval_request', p_approval_request_id, 'cancelled',
    jsonb_build_object('reason', p_reason), '{}'::jsonb);
  return p_approval_request_id;
end $$;
revoke all on function public.cancel_approval(uuid, text) from public;
revoke all on function public.cancel_approval(uuid, text) from anon;
grant execute on function public.cancel_approval(uuid, text) to authenticated, service_role;

drop policy if exists approval_requests_select on public.approval_requests;
create policy approval_requests_select on public.approval_requests as permissive for select to authenticated
  using (public.lign_has_capability(project_id, workspace_id, 'approval.view'));

drop policy if exists approval_request_approvers_select on public.approval_request_approvers;
create policy approval_request_approvers_select on public.approval_request_approvers as permissive for select to authenticated
  using (
    exists (select 1 from public.approval_requests ar
      where ar.id = approval_request_approvers.approval_request_id
        and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view'))
  );

drop policy if exists approval_responses_select on public.approval_responses;
create policy approval_responses_select on public.approval_responses as permissive for select to authenticated
  using (
    exists (select 1 from public.approval_requests ar
      where ar.id = approval_responses.approval_request_id
        and public.lign_has_capability(ar.project_id, ar.workspace_id, 'approval.view'))
  );