
------------------------------------------------------------------------------
-- 5. cancel_approval — extended (Option A additive tail)
------------------------------------------------------------------------------
-- Frozen 2-arg overload preserved (dispatches to extended body). Mandatory
-- cancellation reason enforced via the schema CHECK when status → cancelled.

create or replace function public.cancel_approval(
  p_approval_request_id uuid,
  p_reason              text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Backwards-compat path: use p_reason as both outcome_note AND cancellation_reason
  return public.cancel_approval(p_approval_request_id, p_reason, p_reason);
end $$;

revoke all on function public.cancel_approval(uuid, text) from public;
revoke all on function public.cancel_approval(uuid, text) from anon;
revoke all on function public.cancel_approval(uuid, text) from authenticated;
grant execute on function public.cancel_approval(uuid, text) to authenticated, service_role;

create or replace function public.cancel_approval(
  p_approval_request_id uuid,
  p_reason              text,
  p_cancellation_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_proj uuid; v_status text;
  v_admin_override boolean := false;
  v_effective_reason text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'cancel_approval: authentication required' using errcode='42501';
  end if;

  v_effective_reason := coalesce(p_cancellation_reason, p_reason);
  if v_effective_reason is null or length(trim(v_effective_reason)) < 3 or length(v_effective_reason) > 500 then
    raise exception 'cancel_approval: cancellation_reason required (3-500 chars)' using errcode='22004';
  end if;

  select workspace_id, project_id, status
    into v_ws, v_proj, v_status
    from public.approval_requests
   where id = p_approval_request_id
   for update;
  if v_ws is null then
    raise exception 'cancel_approval: request not found' using errcode='23503';
  end if;
  if v_status not in ('draft','pending','in_progress') then
    raise exception 'cancel_approval: request is % (must be non-terminal)', v_status using errcode='23514';
  end if;

  if not public.lign_has_capability(v_proj, v_ws, 'approval.cancel') then
    raise exception 'cancel_approval: forbidden (approval.cancel)' using errcode='42501';
  end if;
  if public.lign_is_workspace_admin(v_ws) then
    v_admin_override := true;
  end if;

  update public.approval_requests
     set status                   = 'cancelled',
         outcome_at               = now(),
         outcome_actor_profile_id = v_caller,
         outcome_note             = p_reason,
         cancellation_reason      = v_effective_reason
   where id = p_approval_request_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_proj, now(), 'approval.cancelled',
    v_caller, 'user',
    'approval_request', p_approval_request_id, 'cancelled',
    jsonb_build_object('reason', p_reason),
    jsonb_build_object(
      'cancellation_reason', v_effective_reason,
      'admin_override',      v_admin_override
    )
  );

  return p_approval_request_id;
end $$;

revoke all on function public.cancel_approval(uuid, text, text) from public;
revoke all on function public.cancel_approval(uuid, text, text) from anon;
revoke all on function public.cancel_approval(uuid, text, text) from authenticated;
grant execute on function public.cancel_approval(uuid, text, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 6. expire_approval — admin/lead force-expire
------------------------------------------------------------------------------

create or replace function public.expire_approval(
  p_approval_request_id uuid,
  p_reason              text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_proj uuid; v_status text; v_expires_at timestamptz;
  v_admin_override boolean := false;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'expire_approval: authentication required' using errcode='42501';
  end if;

  select workspace_id, project_id, status, expires_at
    into v_ws, v_proj, v_status, v_expires_at
    from public.approval_requests
   where id = p_approval_request_id
   for update;
  if v_ws is null then
    raise exception 'expire_approval: request not found' using errcode='23503';
  end if;
  if v_status not in ('pending','in_progress') then
    raise exception 'expire_approval: request is % (must be pending|in_progress)', v_status using errcode='23514';
  end if;

  if not public.lign_has_capability(v_proj, v_ws, 'approval.expire') then
    raise exception 'expire_approval: forbidden (approval.expire)' using errcode='42501';
  end if;
  if public.lign_is_workspace_admin(v_ws) then
    v_admin_override := true;
  end if;

  update public.approval_requests
     set status                   = 'expired',
         outcome_at               = now(),
         outcome_actor_profile_id = v_caller,
         outcome_note             = p_reason
   where id = p_approval_request_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  ) values (
    v_ws, v_proj, now(), 'approval.expired',
    v_caller, 'user',
    'approval_request', p_approval_request_id, 'expired',
    jsonb_build_object('reason', p_reason),
    jsonb_build_object(
      'approval_request_id', p_approval_request_id,
      'admin_override', v_admin_override,
      'expires_at', v_expires_at
    )
  );

  return p_approval_request_id;
end $$;

revoke all on function public.expire_approval(uuid, text) from public;
revoke all on function public.expire_approval(uuid, text) from anon;
revoke all on function public.expire_approval(uuid, text) from authenticated;
grant execute on function public.expire_approval(uuid, text) to authenticated, service_role;

------------------------------------------------------------------------------
-- 7. Roster mutation RPCs: add / remove / reassign / set_required / set_veto_power
------------------------------------------------------------------------------

create or replace function public.add_approver(
  p_approval_request_id uuid,
  p_wm_id               uuid    default null,
  p_sh_id               uuid    default null,
  p_required            boolean default true,
  p_veto_power          boolean default false,
  p_sort_order          integer default 0
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_proj uuid; v_status text; v_new_id uuid;
  v_identity text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'add_approver: authentication required' using errcode='42501';
  end if;
  if p_approval_request_id is null then
    raise exception 'add_approver: id required' using errcode='22004';
  end if;
  if (p_wm_id is null and p_sh_id is null) or (p_wm_id is not null and p_sh_id is not null) then
    raise exception 'add_approver: exactly one of wm_id / sh_id required (XOR)' using errcode='22023';
  end if;

  select workspace_id, project_id, status into v_ws, v_proj, v_status
    from public.approval_requests where id = p_approval_request_id;
  if v_ws is null then
    raise exception 'add_approver: request not found' using errcode='23503';
  end if;
  if v_status not in ('draft','pending','in_progress') then
    raise exception 'add_approver: cannot modify terminal request (%)', v_status using errcode='23514';
  end if;

  if not public.lign_has_capability(v_proj, v_ws, 'approval.request') then
    raise exception 'add_approver: forbidden (approval.request)' using errcode='42501';
  end if;
  if p_veto_power and not public.lign_has_capability(v_proj, v_ws, 'approval.veto') then
    raise exception 'add_approver: forbidden (approval.veto)' using errcode='42501';
  end if;

  if p_wm_id is not null then
    if not exists (
      select 1 from public.workspace_members
       where id = p_wm_id and workspace_id = v_ws and status = 'active'
    ) then
      raise exception 'add_approver: workspace_member % not active', p_wm_id using errcode='23503';
    end if;
    v_identity := 'member';
  else
    if not exists (
      select 1 from public.stakeholders
       where id = p_sh_id and workspace_id = v_ws and status in ('active','invited')
    ) then
      raise exception 'add_approver: stakeholder % not in workspace', p_sh_id using errcode='23503';
    end if;
    v_identity := 'stakeholder';
  end if;

  insert into public.approval_request_approvers (
    workspace_id, approval_request_id, workspace_member_id, stakeholder_id,
    required, veto_power, sort_order
  ) values (
    v_ws, p_approval_request_id, p_wm_id, p_sh_id,
    p_required, p_veto_power, p_sort_order
  )
  returning id into v_new_id;

  return v_new_id;
end $$;

revoke all on function public.add_approver(uuid, uuid, uuid, boolean, boolean, integer) from public;
revoke all on function public.add_approver(uuid, uuid, uuid, boolean, boolean, integer) from anon;
revoke all on function public.add_approver(uuid, uuid, uuid, boolean, boolean, integer) from authenticated;
grant execute on function public.add_approver(uuid, uuid, uuid, boolean, boolean, integer) to authenticated, service_role;

create or replace function public.remove_approver(
  p_approver_slot_id uuid,
  p_reason           text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_req_id uuid; v_proj uuid; v_r_status text;
  v_has_response boolean;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'remove_approver: authentication required' using errcode='42501';
  end if;
  if p_reason is null or length(trim(p_reason)) < 3 then
    raise exception 'remove_approver: reason required (min 3 chars)' using errcode='22004';
  end if;

  select workspace_id, approval_request_id into v_ws, v_req_id
    from public.approval_request_approvers where id = p_approver_slot_id;
  if v_ws is null then
    raise exception 'remove_approver: slot not found' using errcode='23503';
  end if;

  select project_id, status into v_proj, v_r_status
    from public.approval_requests where id = v_req_id;
  if v_r_status not in ('draft','pending','in_progress') then
    raise exception 'remove_approver: cannot modify terminal request (%)', v_r_status using errcode='23514';
  end if;

  if not public.lign_has_capability(v_proj, v_ws, 'approval.request') then
    raise exception 'remove_approver: forbidden (approval.request)' using errcode='42501';
  end if;

  select exists (
    select 1 from public.approval_responses where approver_slot_id = p_approver_slot_id
  ) into v_has_response;

  if v_has_response then
    -- Soft remove
    update public.approval_request_approvers
       set removed_at = now(), removed_reason = p_reason
     where id = p_approver_slot_id;
  else
    delete from public.approval_request_approvers where id = p_approver_slot_id;
  end if;

  return p_approver_slot_id;
end $$;

revoke all on function public.remove_approver(uuid, text) from public;
revoke all on function public.remove_approver(uuid, text) from anon;
revoke all on function public.remove_approver(uuid, text) from authenticated;
grant execute on function public.remove_approver(uuid, text) to authenticated, service_role;

create or replace function public.set_approver_required(
  p_approver_slot_id uuid,
  p_required         boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_req_id uuid; v_proj uuid; v_r_status text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'set_approver_required: authentication required' using errcode='42501';
  end if;
  if p_approver_slot_id is null or p_required is null then
    raise exception 'set_approver_required: slot_id and required required' using errcode='22004';
  end if;

  select workspace_id, approval_request_id into v_ws, v_req_id
    from public.approval_request_approvers where id = p_approver_slot_id;
  if v_ws is null then
    raise exception 'set_approver_required: slot not found' using errcode='23503';
  end if;
  select project_id, status into v_proj, v_r_status
    from public.approval_requests where id = v_req_id;
  if v_r_status not in ('draft','pending','in_progress') then
    raise exception 'set_approver_required: cannot modify terminal request' using errcode='23514';
  end if;
  if not public.lign_has_capability(v_proj, v_ws, 'approval.request') then
    raise exception 'set_approver_required: forbidden (approval.request)' using errcode='42501';
  end if;

  update public.approval_request_approvers set required = p_required where id = p_approver_slot_id;
  return p_approver_slot_id;
end $$;

revoke all on function public.set_approver_required(uuid, boolean) from public;
revoke all on function public.set_approver_required(uuid, boolean) from anon;
revoke all on function public.set_approver_required(uuid, boolean) from authenticated;
grant execute on function public.set_approver_required(uuid, boolean) to authenticated, service_role;

create or replace function public.set_approver_veto_power(
  p_approver_slot_id uuid,
  p_veto_power       boolean
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid; v_ws uuid; v_req_id uuid; v_proj uuid; v_r_status text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'set_approver_veto_power: authentication required' using errcode='42501';
  end if;
  if p_approver_slot_id is null or p_veto_power is null then
    raise exception 'set_approver_veto_power: slot_id and veto_power required' using errcode='22004';
  end if;

  select workspace_id, approval_request_id into v_ws, v_req_id
    from public.approval_request_approvers where id = p_approver_slot_id;
  if v_ws is null then
    raise exception 'set_approver_veto_power: slot not found' using errcode='23503';
  end if;
  select project_id, status into v_proj, v_r_status
    from public.approval_requests where id = v_req_id;
  if v_r_status not in ('draft','pending','in_progress') then
    raise exception 'set_approver_veto_power: cannot modify terminal request' using errcode='23514';
  end if;
  if not public.lign_has_capability(v_proj, v_ws, 'approval.request') then
    raise exception 'set_approver_veto_power: forbidden (approval.request)' using errcode='42501';
  end if;
  if p_veto_power and not public.lign_has_capability(v_proj, v_ws, 'approval.veto') then
    raise exception 'set_approver_veto_power: forbidden (approval.veto)' using errcode='42501';
  end if;

  update public.approval_request_approvers set veto_power = p_veto_power where id = p_approver_slot_id;
  return p_approver_slot_id;
end $$;

revoke all on function public.set_approver_veto_power(uuid, boolean) from public;
revoke all on function public.set_approver_veto_power(uuid, boolean) from anon;
revoke all on function public.set_approver_veto_power(uuid, boolean) from authenticated;
grant execute on function public.set_approver_veto_power(uuid, boolean) to authenticated, service_role;
