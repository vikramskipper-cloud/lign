-- APP 026: project leads invite external reviewers and approvers in their own project.
-- Workspace leadership retains existing invitation authority. Workspace-scoped
-- capabilities and existing customer records are unchanged.

create or replace function public.invite_stakeholder(
  p_workspace_id uuid,
  p_email text,
  p_project_id uuid,
  p_role text default 'reviewer',
  p_display_name text default null,
  p_expires_in_days integer default 14
)
returns table (out_invitation_id uuid, out_stakeholder_id uuid, out_token text, out_expires_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid; v_email extensions.citext; v_token text; v_hash text;
  v_expires timestamptz; v_inv uuid; v_sh uuid; v_proj_ws uuid;
  v_workspace_admin boolean; v_stakeholder_status text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'invite_stakeholder: authentication required' using errcode='42501';
  end if;
  if p_workspace_id is null or p_email is null or p_project_id is null then
    raise exception 'invite_stakeholder: workspace_id, email and project_id required' using errcode='22004';
  end if;
  if p_role is null or p_role not in ('lead','contributor','reviewer','approver','observer') then
    raise exception 'invite_stakeholder: invalid project role %', p_role using errcode='23514';
  end if;
  v_workspace_admin := public.lign_is_workspace_admin(p_workspace_id);
  if not v_workspace_admin then
    if not public.lign_has_capability(p_project_id, p_workspace_id, 'project.manage_access') then
      raise exception 'Only workspace leadership or this project lead can invite external participants' using errcode='42501';
    end if;
    if p_role not in ('reviewer','approver') then
      raise exception 'Project leads can invite external reviewers and approvers only' using errcode='42501';
    end if;
  end if;

  select workspace_id into v_proj_ws from public.projects where id = p_project_id;
  if v_proj_ws is distinct from p_workspace_id then
    raise exception 'invite_stakeholder: project % is not in workspace %', p_project_id, p_workspace_id
      using errcode='23503';
  end if;

  v_email := trim(p_email)::extensions.citext;

  select id,status into v_sh,v_stakeholder_status from public.stakeholders
   where workspace_id = p_workspace_id and email = v_email for update;
  if v_sh is null then
    insert into public.stakeholders (workspace_id, email, display_name, status)
    values (p_workspace_id, v_email, nullif(trim(coalesce(p_display_name,'')),''), 'invited')
    returning id into v_sh;
  else
    -- The stakeholder identity is shared within a workspace. A project lead
    -- must not restore a workspace-wide revocation or edit another project's
    -- existing consultant/client identity while inviting them to this project.
    if not v_workspace_admin and v_stakeholder_status='revoked' then
      raise exception 'Ask workspace leadership to restore this external participant' using errcode='42501';
    end if;
    if v_workspace_admin then
    update public.stakeholders
       set status = case when status = 'revoked' then 'invited' else status end,
           revoked_at = case when status = 'revoked' then null else revoked_at end,
           display_name = coalesce(nullif(trim(coalesce(p_display_name,'')),''), display_name)
     where id = v_sh;
    end if;
  end if;

  if not exists (
    select 1 from public.project_participants
     where project_id = p_project_id and stakeholder_id = v_sh and status = 'active'
  ) then
    perform public.add_project_participant(p_project_id, null, v_sh, p_role);
  end if;

  if exists (
    select 1 from public.invitations
     where workspace_id = p_workspace_id and email = v_email
       and kind = 'stakeholder' and status = 'sent' and expires_at > now()
  ) then
    raise exception 'invite_stakeholder: an invitation for % is already pending', v_email
      using errcode='23505';
  end if;

  v_token   := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
  v_hash    := encode(extensions.digest(v_token::bytea, 'sha256'), 'hex');
  v_expires := now() + make_interval(days => greatest(1, coalesce(p_expires_in_days, 14)));

  insert into public.invitations (workspace_id, email, kind, role, invited_by_profile_id,
                                  status, token_hash, expires_at)
  values (p_workspace_id, v_email, 'stakeholder', p_role, v_caller, 'sent', v_hash, v_expires)
  returning id into v_inv;

  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (p_workspace_id, p_project_id, now(), 'stakeholder.invited', v_caller, 'user',
    'stakeholder', v_sh, v_email::text,
    jsonb_build_object('email', v_email::text, 'project_id', p_project_id, 'role', p_role,
                       'invitation_id', v_inv), '{}'::jsonb);

  return query select v_inv, v_sh, v_token, v_expires;
end $$;

revoke all on function public.invite_stakeholder(uuid,text,uuid,text,text,integer) from public,anon;
grant execute on function public.invite_stakeholder(uuid,text,uuid,text,text,integer) to authenticated,service_role;
