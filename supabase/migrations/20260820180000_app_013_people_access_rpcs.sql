-- APP 013 wave 1b — People & Access write RPCs.
--
-- 8 SECURITY DEFINER RPCs, each with search_path='', an inline capability
-- check, and exactly one canonical past-tense event from EVENT_MODEL.md.
--
-- Invariants enforced here rather than in the schema, because they are
-- row-relative and a CHECK cannot express them:
--   I-1  a workspace always retains at least one ACTIVE owner
--   I-2  no self-lockout: nobody removes or demotes themselves
--   I-3  only an owner may grant or revoke the owner role
--   I-4  removing workspace access cascades to project participation
--   I-5  removal is soft; authored history keeps its attribution
--
-- Token handling matches the frozen accept_invitation /
-- claim_stakeholder_invitation verifiers exactly:
--   encode(extensions.digest(token::bytea, 'sha256'), 'hex')
-- The plaintext token is returned ONCE and never stored.

create or replace function public.invite_workspace_member(
  p_workspace_id uuid,
  p_email text,
  p_role text default 'member',
  p_expires_in_days integer default 14
)
returns table (out_invitation_id uuid, out_token text, out_expires_at timestamptz)
language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid; v_email extensions.citext; v_token text; v_hash text;
  v_expires timestamptz; v_id uuid; v_caller_role text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'invite_workspace_member: authentication required' using errcode='42501';
  end if;
  if p_workspace_id is null or p_email is null or length(trim(p_email)) = 0 then
    raise exception 'invite_workspace_member: workspace_id and email required' using errcode='22004';
  end if;
  if p_role not in ('owner','admin','member') then
    raise exception 'invite_workspace_member: invalid role %', p_role using errcode='23514';
  end if;
  if not public.lign_has_capability(null, p_workspace_id, 'member.invite') then
    raise exception 'invite_workspace_member: forbidden (member.invite)' using errcode='42501';
  end if;

  select role into v_caller_role from public.workspace_members
   where workspace_id = p_workspace_id and user_id = v_caller and status = 'active';
  if p_role = 'owner' and v_caller_role is distinct from 'owner' then
    raise exception 'invite_workspace_member: only an owner may invite an owner' using errcode='42501';
  end if;

  v_email := trim(p_email)::extensions.citext;

  if exists (
    select 1 from public.workspace_members wm
      join public.profiles pr on pr.id = wm.user_id
     where wm.workspace_id = p_workspace_id and pr.email = v_email and wm.status = 'active'
  ) then
    raise exception 'invite_workspace_member: % is already an active member', v_email using errcode='23505';
  end if;

  if exists (
    select 1 from public.invitations
     where workspace_id = p_workspace_id and email = v_email
       and kind = 'workspace_member' and status = 'sent' and expires_at > now()
  ) then
    raise exception 'invite_workspace_member: an invitation for % is already pending', v_email
      using errcode='23505';
  end if;

  v_token   := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
  v_hash    := encode(extensions.digest(v_token::bytea, 'sha256'), 'hex');
  v_expires := now() + make_interval(days => greatest(1, coalesce(p_expires_in_days, 14)));

  insert into public.invitations (workspace_id, email, kind, role, invited_by_profile_id,
                                  status, token_hash, expires_at)
  values (p_workspace_id, v_email, 'workspace_member', p_role, v_caller, 'sent', v_hash, v_expires)
  returning id into v_id;

  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (p_workspace_id, null, now(), 'workspace.member.invited', v_caller, 'user',
    'workspace_member', v_id, v_email::text,
    jsonb_build_object('email', v_email::text, 'role', p_role, 'invitation_id', v_id), '{}'::jsonb);

  return query select v_id, v_token, v_expires;
end $$;

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
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'invite_stakeholder: authentication required' using errcode='42501';
  end if;
  if p_workspace_id is null or p_email is null or p_project_id is null then
    raise exception 'invite_stakeholder: workspace_id, email and project_id required' using errcode='22004';
  end if;
  if p_role not in ('lead','contributor','reviewer','approver','observer') then
    raise exception 'invite_stakeholder: invalid project role %', p_role using errcode='23514';
  end if;
  if not public.lign_has_capability(null, p_workspace_id, 'stakeholder.invite') then
    raise exception 'invite_stakeholder: forbidden (stakeholder.invite)' using errcode='42501';
  end if;

  select workspace_id into v_proj_ws from public.projects where id = p_project_id;
  if v_proj_ws is distinct from p_workspace_id then
    raise exception 'invite_stakeholder: project % is not in workspace %', p_project_id, p_workspace_id
      using errcode='23503';
  end if;

  v_email := trim(p_email)::extensions.citext;

  select id into v_sh from public.stakeholders
   where workspace_id = p_workspace_id and email = v_email;
  if v_sh is null then
    insert into public.stakeholders (workspace_id, email, display_name, status)
    values (p_workspace_id, v_email, nullif(trim(coalesce(p_display_name,'')),''), 'invited')
    returning id into v_sh;
  else
    update public.stakeholders
       set status = case when status = 'revoked' then 'invited' else status end,
           revoked_at = case when status = 'revoked' then null else revoked_at end,
           display_name = coalesce(nullif(trim(coalesce(p_display_name,'')),''), display_name)
     where id = v_sh;
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

create or replace function public.revoke_invitation(p_invitation_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_inv public.invitations%rowtype; v_key text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'revoke_invitation: authentication required' using errcode='42501';
  end if;
  select * into v_inv from public.invitations where id = p_invitation_id;
  if not found then
    raise exception 'revoke_invitation: invitation % not found', p_invitation_id using errcode='23503';
  end if;
  v_key := case when v_inv.kind = 'stakeholder' then 'stakeholder.invite' else 'member.invite' end;
  if not public.lign_has_capability(null, v_inv.workspace_id, v_key) then
    raise exception 'revoke_invitation: forbidden (%)', v_key using errcode='42501';
  end if;
  if v_inv.status <> 'sent' then
    raise exception 'revoke_invitation: invitation is % and cannot be revoked', v_inv.status
      using errcode='23514';
  end if;

  update public.invitations set status = 'revoked' where id = p_invitation_id;

  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_inv.workspace_id, null, now(), 'invitation.revoked', v_caller, 'user',
    'invitation', v_inv.id, v_inv.email::text,
    jsonb_build_object('kind', v_inv.kind, 'email', v_inv.email::text), '{}'::jsonb);
end $$;

create or replace function public.change_workspace_member_role(
  p_workspace_member_id uuid,
  p_role text
)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid; v_m public.workspace_members%rowtype;
  v_caller_role text; v_owner_count integer; v_label text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'change_workspace_member_role: authentication required' using errcode='42501';
  end if;
  if p_role not in ('owner','admin','member') then
    raise exception 'change_workspace_member_role: invalid role %', p_role using errcode='23514';
  end if;

  select * into v_m from public.workspace_members where id = p_workspace_member_id;
  if not found then
    raise exception 'change_workspace_member_role: member % not found', p_workspace_member_id
      using errcode='23503';
  end if;
  if not public.lign_has_capability(null, v_m.workspace_id, 'member.change_role') then
    raise exception 'change_workspace_member_role: forbidden (member.change_role)' using errcode='42501';
  end if;

  if v_m.user_id = v_caller then
    raise exception 'change_workspace_member_role: cannot change your own role'
      using errcode='42501';
  end if;

  select role into v_caller_role from public.workspace_members
   where workspace_id = v_m.workspace_id and user_id = v_caller and status = 'active';

  if (p_role = 'owner' or v_m.role = 'owner') and v_caller_role is distinct from 'owner' then
    raise exception 'change_workspace_member_role: only an owner may grant or revoke the owner role'
      using errcode='42501';
  end if;

  if v_m.role = p_role then return; end if;

  if v_m.role = 'owner' and p_role <> 'owner' then
    select count(*) into v_owner_count from public.workspace_members
     where workspace_id = v_m.workspace_id and role = 'owner' and status = 'active';
    if v_owner_count <= 1 then
      raise exception 'change_workspace_member_role: cannot demote the last owner of the workspace'
        using errcode='23514';
    end if;
  end if;

  update public.workspace_members set role = p_role where id = p_workspace_member_id;

  select email::text into v_label from public.profiles where id = v_m.user_id;

  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_m.workspace_id, null, now(), 'workspace.member.role_changed', v_caller, 'user',
    'workspace_member', v_m.id, coalesce(v_label,''),
    jsonb_build_object('from_role', v_m.role, 'to_role', p_role), '{}'::jsonb);
end $$;

create or replace function public.remove_workspace_member(p_workspace_member_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_caller uuid; v_m public.workspace_members%rowtype;
  v_caller_role text; v_owner_count integer; v_label text; v_dropped integer;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'remove_workspace_member: authentication required' using errcode='42501';
  end if;

  select * into v_m from public.workspace_members where id = p_workspace_member_id;
  if not found then
    raise exception 'remove_workspace_member: member % not found', p_workspace_member_id
      using errcode='23503';
  end if;
  if not public.lign_has_capability(null, v_m.workspace_id, 'member.remove') then
    raise exception 'remove_workspace_member: forbidden (member.remove)' using errcode='42501';
  end if;

  if v_m.user_id = v_caller then
    raise exception 'remove_workspace_member: cannot remove yourself from the workspace'
      using errcode='42501';
  end if;
  if v_m.status = 'removed' then return; end if;

  select role into v_caller_role from public.workspace_members
   where workspace_id = v_m.workspace_id and user_id = v_caller and status = 'active';
  if v_m.role = 'owner' and v_caller_role is distinct from 'owner' then
    raise exception 'remove_workspace_member: only an owner may remove an owner' using errcode='42501';
  end if;

  if v_m.role = 'owner' then
    select count(*) into v_owner_count from public.workspace_members
     where workspace_id = v_m.workspace_id and role = 'owner' and status = 'active';
    if v_owner_count <= 1 then
      raise exception 'remove_workspace_member: cannot remove the last owner of the workspace'
        using errcode='23514';
    end if;
  end if;

  update public.project_participants
     set status = 'removed', removed_at = now()
   where workspace_member_id = p_workspace_member_id and status = 'active';
  get diagnostics v_dropped = row_count;

  update public.workspace_members
     set status = 'removed', removed_at = now()
   where id = p_workspace_member_id;

  select email::text into v_label from public.profiles where id = v_m.user_id;

  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_m.workspace_id, null, now(), 'workspace.member.removed', v_caller, 'user',
    'workspace_member', v_m.id, coalesce(v_label,''),
    jsonb_build_object('previous_role', v_m.role, 'participations_removed', v_dropped), '{}'::jsonb);
end $$;

create or replace function public.revoke_stakeholder(p_stakeholder_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_s public.stakeholders%rowtype; v_dropped integer;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'revoke_stakeholder: authentication required' using errcode='42501';
  end if;
  select * into v_s from public.stakeholders where id = p_stakeholder_id;
  if not found then
    raise exception 'revoke_stakeholder: stakeholder % not found', p_stakeholder_id using errcode='23503';
  end if;
  if not public.lign_has_capability(null, v_s.workspace_id, 'stakeholder.revoke') then
    raise exception 'revoke_stakeholder: forbidden (stakeholder.revoke)' using errcode='42501';
  end if;
  if v_s.status = 'revoked' then return; end if;

  update public.project_participants
     set status = 'removed', removed_at = now()
   where stakeholder_id = p_stakeholder_id and status = 'active';
  get diagnostics v_dropped = row_count;

  update public.stakeholders
     set status = 'revoked', revoked_at = now()
   where id = p_stakeholder_id;

  update public.invitations
     set status = 'revoked'
   where workspace_id = v_s.workspace_id and email = v_s.email
     and kind = 'stakeholder' and status = 'sent';

  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_s.workspace_id, null, now(), 'stakeholder.revoked', v_caller, 'user',
    'stakeholder', v_s.id, v_s.email::text,
    jsonb_build_object('participations_removed', v_dropped), '{}'::jsonb);
end $$;

create or replace function public.change_project_participant_role(
  p_participant_id uuid,
  p_role text
)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_p public.project_participants%rowtype; v_label text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'change_project_participant_role: authentication required' using errcode='42501';
  end if;
  if p_role not in ('lead','contributor','reviewer','approver','observer') then
    raise exception 'change_project_participant_role: invalid role %', p_role using errcode='23514';
  end if;
  select * into v_p from public.project_participants where id = p_participant_id;
  if not found then
    raise exception 'change_project_participant_role: participant % not found', p_participant_id
      using errcode='23503';
  end if;
  if not (
    public.lign_is_workspace_admin(v_p.workspace_id)
    or public.lign_has_capability(v_p.project_id, v_p.workspace_id, 'project.manage_access')
  ) then
    raise exception 'change_project_participant_role: forbidden (project.manage_access)'
      using errcode='42501';
  end if;
  if v_p.status <> 'active' then
    raise exception 'change_project_participant_role: participant is %', v_p.status using errcode='23514';
  end if;
  if v_p.role = p_role then return; end if;

  update public.project_participants set role = p_role where id = p_participant_id;

  v_label := coalesce(
    (select pr.email::text from public.profiles pr
       join public.workspace_members wm on wm.user_id = pr.id
      where wm.id = v_p.workspace_member_id),
    (select sh.email::text from public.stakeholders sh where sh.id = v_p.stakeholder_id),
    '');

  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_p.workspace_id, v_p.project_id, now(), 'project.participant.role_changed', v_caller, 'user',
    'project_participant', v_p.id, v_label,
    jsonb_build_object('from_role', v_p.role, 'to_role', p_role), '{}'::jsonb);
end $$;

create or replace function public.remove_project_participant(p_participant_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_caller uuid; v_p public.project_participants%rowtype; v_label text; v_self uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'remove_project_participant: authentication required' using errcode='42501';
  end if;
  select * into v_p from public.project_participants where id = p_participant_id;
  if not found then
    raise exception 'remove_project_participant: participant % not found', p_participant_id
      using errcode='23503';
  end if;
  if not (
    public.lign_is_workspace_admin(v_p.workspace_id)
    or public.lign_has_capability(v_p.project_id, v_p.workspace_id, 'project.manage_access')
  ) then
    raise exception 'remove_project_participant: forbidden (project.manage_access)' using errcode='42501';
  end if;
  if v_p.status <> 'active' then return; end if;

  select wm.user_id into v_self from public.workspace_members wm where wm.id = v_p.workspace_member_id;
  if v_self = v_caller then
    raise exception 'remove_project_participant: cannot remove yourself from the project'
      using errcode='42501';
  end if;

  update public.project_participants
     set status = 'removed', removed_at = now()
   where id = p_participant_id;

  v_label := coalesce(
    (select pr.email::text from public.profiles pr
       join public.workspace_members wm on wm.user_id = pr.id
      where wm.id = v_p.workspace_member_id),
    (select sh.email::text from public.stakeholders sh where sh.id = v_p.stakeholder_id),
    '');

  insert into public.activity_events (workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label, subject_snapshot, payload)
  values (v_p.workspace_id, v_p.project_id, now(), 'project.participant.removed', v_caller, 'user',
    'project_participant', v_p.id, v_label,
    jsonb_build_object('previous_role', v_p.role), '{}'::jsonb);
end $$;

do $$
declare v_sig text;
begin
  foreach v_sig in array array[
    'public.invite_workspace_member(uuid, text, text, integer)',
    'public.invite_stakeholder(uuid, text, uuid, text, text, integer)',
    'public.revoke_invitation(uuid)',
    'public.change_workspace_member_role(uuid, text)',
    'public.remove_workspace_member(uuid)',
    'public.revoke_stakeholder(uuid)',
    'public.change_project_participant_role(uuid, text)',
    'public.remove_project_participant(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', v_sig);
    execute format('grant execute on function %s to authenticated, service_role', v_sig);
  end loop;
end $$;
