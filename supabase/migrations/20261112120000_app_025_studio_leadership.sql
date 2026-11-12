-- APP 025: studio ownership, delegated workspace leadership and oversight.
-- Existing role vocabulary is preserved: org owner/admin, workspace admin
-- (displayed as Workspace lead), project lead, and project contributors.
-- No fixture or customer rows are changed by this migration.

create or replace function public.lign_is_org_owner(p_organization_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.organization_members
   where organization_id = p_organization_id and user_id = auth.uid()
     and status = 'active' and role = 'owner');
$$;
revoke all on function public.lign_is_org_owner(uuid) from public, anon;
grant execute on function public.lign_is_org_owner(uuid) to authenticated, service_role;

-- Assign an existing studio architect directly; no second account or invitation.
create or replace function public.assign_workspace_architect(
 p_workspace_id uuid, p_user_id uuid, p_role text default 'member'
)
returns uuid language plpgsql security definer set search_path = ''
as $fn$
declare
 v_org uuid; v_id uuid; v_old_role text; v_old_status text; v_role text;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_role is null or p_role not in ('admin','member') then
  raise exception 'Choose workspace lead or team member' using errcode='22023';
 end if;
 select organization_id into v_org from public.workspaces
  where id=p_workspace_id and status='active' for update;
 if not found then raise exception 'Active workspace not found' using errcode='23503'; end if;
 if not public.lign_is_workspace_admin(p_workspace_id) then
  raise exception 'Workspace leadership required' using errcode='42501';
 end if;
 perform 1 from public.organization_members om join public.profiles p on p.id=om.user_id
  where om.organization_id=v_org and om.user_id=p_user_id and om.status='active' and p.status='active'
  for share of om, p;
 if not found then raise exception 'Choose an active architect from this studio' using errcode='23503'; end if;
 select id,role,status into v_id,v_old_role,v_old_status from public.workspace_members
  where workspace_id=p_workspace_id and user_id=p_user_id for update;
 if (p_role='admin' or v_old_role in ('admin','owner')) and not public.lign_is_org_admin(v_org) then
  raise exception 'Only studio owners or administrators can appoint workspace leads' using errcode='42501';
 end if;
 if v_old_role='owner' and v_old_status <> 'active' and not public.lign_is_org_owner(v_org) then
  raise exception 'Only the studio owner can restore an owner membership' using errcode='42501';
 end if;
 v_role := case when v_old_role='owner' then 'owner' else p_role end;
 if v_id is not null and v_old_status='active' and v_old_role=v_role then return v_id; end if;
 insert into public.workspace_members(workspace_id,user_id,role,status,invited_at,activated_at)
 values(p_workspace_id,p_user_id,v_role,'active',now(),now())
 on conflict(workspace_id,user_id) do update
  set role=excluded.role,status='active',removed_at=null,
      activated_at=coalesce(public.workspace_members.activated_at,now())
 returning id into v_id;
 insert into public.activity_events(workspace_id,occurred_at,event_type,actor_profile_id,actor_kind,
  subject_kind,subject_id,subject_label,subject_snapshot,payload)
 values(p_workspace_id,now(),case when v_old_status='active' then 'workspace.member.role_changed'
                                else 'workspace.member.activated' end,auth.uid(),'user',
  'workspace_member',v_id,(select display_name from public.profiles where id=p_user_id),
  jsonb_build_object('role',v_role,'previous_role',v_old_role),jsonb_build_object('user_id',p_user_id));
 return v_id;
end;
$fn$;
revoke all on function public.assign_workspace_architect(uuid,uuid,text) from public,anon;
grant execute on function public.assign_workspace_architect(uuid,uuid,text) to authenticated;

create or replace function public.create_workspace_team(
 p_organization_id uuid, p_name text, p_lead_user_id uuid default null,
 p_member_user_ids uuid[] default '{}'::uuid[]
)
returns uuid language plpgsql security definer set search_path = ''
as $fn$
declare v_ws uuid; v_user uuid;
begin
 if not public.lign_is_org_admin(p_organization_id) then
  raise exception 'Studio ownership or administration required' using errcode='42501';
 end if;
 if p_name is null or length(trim(p_name)) not between 1 and 120 then
  raise exception 'Workspace name must contain 1 to 120 characters' using errcode='22023';
 end if;
 v_ws := public.create_workspace(trim(p_name),null,p_organization_id);
 if p_lead_user_id is not null and p_lead_user_id<>auth.uid() then
  perform public.assign_workspace_architect(v_ws,p_lead_user_id,'admin');
 end if;
 foreach v_user in array coalesce(p_member_user_ids,'{}'::uuid[]) loop
  if v_user is null then raise exception 'Choose a studio architect' using errcode='22023'; end if;
  if v_user<>auth.uid() and v_user is distinct from p_lead_user_id then
   perform public.assign_workspace_architect(v_ws,v_user,'member');
  end if;
 end loop;
 return v_ws;
end;
$fn$;
revoke all on function public.create_workspace_team(uuid,text,uuid,uuid[]) from public,anon;
grant execute on function public.create_workspace_team(uuid,text,uuid,uuid[]) to authenticated;


create or replace function public.create_project_full(
  p_workspace_id    uuid,
  p_name            text,
  p_code            text    default null,
  p_description     text    default null,
  p_lead_member_id  uuid    default null,
  p_client_emails   text[]  default '{}'::text[],
  p_expires_in_days integer default 14
)
returns table (
  out_project_id uuid,
  out_slug       text,
  out_code       text,
  out_invites    jsonb
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_caller        uuid;
  v_caller_member uuid;
  v_lead_member   uuid;
  v_name          text;
  v_code          text;
  v_desc          text;
  v_base          text;
  v_slug          text;
  v_n             integer := 1;
  v_project_id    uuid;
  v_conflict      text;
  v_email         text;
  v_raw           text;
  v_member        uuid;
  v_member_label  text;
  v_sh            uuid;
  v_participant   uuid;
  v_token         text;
  v_hash          text;
  v_expires       timestamptz;
  v_inv           uuid;
  v_invites       jsonb := '[]'::jsonb;
  v_seen          text[] := '{}';
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'create_project_full: authentication required' using errcode = '42501';
  end if;
  if p_workspace_id is null then
    raise exception 'create_project_full: workspace_id required' using errcode = '22004';
  end if;

  -- The control. The dialog hides its button without this, but hiding a button
  -- is a courtesy, not a permission.
  if not public.lign_has_capability(null, p_workspace_id, 'workspace.manage') then
    raise exception 'create_project_full: forbidden (workspace.manage)' using errcode = '42501';
  end if;

  select id into v_caller_member
    from public.workspace_members
   where workspace_id = p_workspace_id
     and user_id      = v_caller
     and status       = 'active';
  if v_caller_member is null then
    -- An org owner/admin already administers this workspace by inheritance.
    -- Materialise that membership only when creating work, so lead/contributor
    -- participation has a real workspace member identity to reference.
    v_caller_member := public.assign_workspace_architect(p_workspace_id,v_caller,'admin');
  end if;

  ---------------------------------------------------------------- name + code
  v_name := trim(coalesce(p_name, ''));
  if length(v_name) = 0 then
    raise exception 'create_project_full: name required' using errcode = '22004';
  end if;
  if length(v_name) > 120 then
    raise exception 'create_project_full: name exceeds 120 characters' using errcode = '22001';
  end if;

  -- Empty stays null. A code the user did not choose is a code they will never
  -- recognise, so nothing is generated on their behalf.
  v_code := nullif(upper(trim(coalesce(p_code, ''))), '');
  if v_code is not null then
    if v_code !~ '^[A-Z0-9][A-Z0-9-]{0,15}$' then
      raise exception 'create_project_full: invalid code format' using errcode = '22023';
    end if;
    -- Uniqueness is enforced HERE only. projects.code carries no unique index
    -- (projects_workspace_slug_key is on slug), so two simultaneous creations
    -- can still both pass this check. See the gap noted in the task report.
    select name into v_conflict
      from public.projects
     where workspace_id = p_workspace_id
       and upper(code)  = v_code
       and archived_at is null
     limit 1;
    if v_conflict is not null then
      raise exception 'PROJECT_CODE_TAKEN' using errcode = '23505', detail = v_conflict;
    end if;
  end if;

  v_desc := nullif(trim(coalesce(p_description, '')), '');
  if length(coalesce(v_desc, '')) > 280 then
    raise exception 'create_project_full: description exceeds 280 characters' using errcode = '22001';
  end if;

  ---------------------------------------------------------------------- slug
  -- slug is NOT NULL and unique per workspace, but it is not a field in the
  -- dialog: the brief asks for one required input. Derived from the name and
  -- suffixed until free, so two "Northgate Flagship" projects can coexist.
  -- Compared as lower(text) rather than citext for the reason in the header.
  v_base := regexp_replace(lower(v_name), '[^a-z0-9]+', '-', 'g');
  v_base := trim(both '-' from v_base);
  v_base := left(nullif(v_base, ''), 56);
  if v_base is null then
    v_base := 'project';
  end if;
  v_slug := v_base;
  while exists (
    select 1 from public.projects
     where workspace_id = p_workspace_id and lower(slug::text) = v_slug
  ) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n::text;
  end loop;

  ---------------------------------------------------------------------- lead
  v_lead_member := coalesce(p_lead_member_id, v_caller_member);
  if not exists (
    select 1 from public.workspace_members
     where id = v_lead_member and workspace_id = p_workspace_id and status = 'active'
  ) then
    raise exception 'create_project_full: lead % is not an active member of this workspace', v_lead_member
      using errcode = '23503';
  end if;

  ------------------------------------------------------------------- project
  insert into public.projects (
    workspace_id, name, slug, code, description, status, created_by_profile_id
  )
  values (
    p_workspace_id, v_name, v_slug::extensions.citext, v_code, v_desc, 'active', v_caller
  )
  returning id into v_project_id;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    p_workspace_id, v_project_id, now(), 'project.created',
    v_caller, 'user',
    'project', v_project_id, v_name,
    jsonb_build_object('name', v_name, 'slug', v_slug, 'code', v_code),
    jsonb_build_object('actor_capacity', 'internal')
  );

  --------------------------------------------------------------- participants
  insert into public.project_participants (
    workspace_id, project_id, workspace_member_id, stakeholder_id, role, status, added_at
  )
  values (p_workspace_id, v_project_id, v_lead_member, null, 'lead', 'active', now())
  returning id into v_participant;

  select p.display_name into v_member_label
    from public.workspace_members wm join public.profiles p on p.id = wm.user_id
   where wm.id = v_lead_member;

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    p_workspace_id, v_project_id, now(), 'project.participant.added',
    v_caller, 'user',
    'project_participant', v_participant, coalesce(v_member_label, ''),
    jsonb_build_object('role', 'lead', 'workspace_member_id', v_lead_member),
    jsonb_build_object('capacity', 'internal', 'actor_capacity', 'internal')
  );

  -- Handing the lead role to someone else must not lock the creator out. Work
  -- capabilities (version.upload, release.create, approval.respond) resolve
  -- only through project_participants, so a workspace admin who creates a
  -- project and hands it over would otherwise be able to view it and do
  -- nothing in it.
  if v_lead_member <> v_caller_member then
    insert into public.project_participants (
      workspace_id, project_id, workspace_member_id, stakeholder_id, role, status, added_at
    )
    values (p_workspace_id, v_project_id, v_caller_member, null, 'contributor', 'active', now())
    returning id into v_participant;

    select p.display_name into v_member_label from public.profiles p where p.id = v_caller;

    insert into public.activity_events (
      workspace_id, project_id, occurred_at, event_type,
      actor_profile_id, actor_kind,
      subject_kind, subject_id, subject_label, subject_snapshot, payload
    )
    values (
      p_workspace_id, v_project_id, now(), 'project.participant.added',
      v_caller, 'user',
      'project_participant', v_participant, coalesce(v_member_label, ''),
      jsonb_build_object('role', 'contributor', 'workspace_member_id', v_caller_member),
      jsonb_build_object('capacity', 'internal', 'actor_capacity', 'internal',
                         'reason', 'creator retained access after assigning another lead')
    );
  end if;

  ----------------------------------------------------------- client approvers
  foreach v_raw in array coalesce(p_client_emails, '{}'::text[]) loop
    v_email := nullif(lower(trim(coalesce(v_raw, ''))), '');
    continue when v_email is null;
    continue when v_email = any (v_seen);
    v_seen := v_seen || v_email;

    -- An address that already belongs to a member of this workspace is that
    -- person. Creating a stakeholder for them would give one human two
    -- identities in the same workspace and split their audit trail.
    select wm.id, p.display_name into v_member, v_member_label
      from public.workspace_members wm
      join public.profiles p on p.id = wm.user_id
     where wm.workspace_id    = p_workspace_id
       and wm.status          = 'active'
       and lower(p.email::text) = v_email
     limit 1;

    if v_member is not null then
      insert into public.project_participants (
        workspace_id, project_id, workspace_member_id, stakeholder_id, role, status, added_at
      )
      values (p_workspace_id, v_project_id, v_member, null, 'approver', 'active', now())
      returning id into v_participant;

      insert into public.activity_events (
        workspace_id, project_id, occurred_at, event_type,
        actor_profile_id, actor_kind,
        subject_kind, subject_id, subject_label, subject_snapshot, payload
      )
      values (
        p_workspace_id, v_project_id, now(), 'project.participant.added',
        v_caller, 'user',
        'project_participant', v_participant, coalesce(v_member_label, v_email),
        jsonb_build_object('role', 'approver', 'workspace_member_id', v_member),
        jsonb_build_object('capacity', 'internal', 'actor_capacity', 'internal',
                           'resolved_from_email', v_email)
      );

      v_invites := v_invites || jsonb_build_object(
        'email', v_email, 'kind', 'member',
        'display_name', v_member_label, 'token', null
      );
      v_member := null;
      continue;
    end if;

    select id into v_sh
      from public.stakeholders
     where workspace_id = p_workspace_id and lower(email::text) = v_email;
    if v_sh is null then
      insert into public.stakeholders (workspace_id, email, display_name, status)
      values (p_workspace_id, v_email::extensions.citext, null, 'invited')
      returning id into v_sh;
    else
      update public.stakeholders
         set status     = case when status = 'revoked' then 'invited' else status end,
             revoked_at = case when status = 'revoked' then null else revoked_at end
       where id = v_sh;
    end if;

    insert into public.project_participants (
      workspace_id, project_id, workspace_member_id, stakeholder_id, role, status, added_at
    )
    values (p_workspace_id, v_project_id, null, v_sh, 'approver', 'active', now())
    returning id into v_participant;

    insert into public.activity_events (
      workspace_id, project_id, occurred_at, event_type,
      actor_profile_id, actor_kind,
      subject_kind, subject_id, subject_label, subject_snapshot, payload
    )
    values (
      p_workspace_id, v_project_id, now(), 'project.participant.added',
      v_caller, 'user',
      'project_participant', v_participant, v_email,
      jsonb_build_object('role', 'approver', 'stakeholder_id', v_sh),
      jsonb_build_object('capacity', 'external', 'actor_capacity', 'internal')
    );

    v_token   := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
    v_hash    := encode(extensions.digest(v_token::bytea, 'sha256'), 'hex');
    v_expires := now() + make_interval(days => greatest(1, coalesce(p_expires_in_days, 14)));

    insert into public.invitations (
      workspace_id, email, kind, role, invited_by_profile_id, status, token_hash, expires_at
    )
    values (
      p_workspace_id, v_email::extensions.citext, 'stakeholder', 'approver', v_caller,
      'sent', v_hash, v_expires
    )
    returning id into v_inv;

    insert into public.activity_events (
      workspace_id, project_id, occurred_at, event_type,
      actor_profile_id, actor_kind,
      subject_kind, subject_id, subject_label, subject_snapshot, payload
    )
    values (
      p_workspace_id, v_project_id, now(), 'stakeholder.invited',
      v_caller, 'user',
      'stakeholder', v_sh, v_email,
      jsonb_build_object('email', v_email, 'role', 'approver', 'invitation_id', v_inv),
      jsonb_build_object('capacity', 'external', 'actor_capacity', 'internal')
    );

    v_invites := v_invites || jsonb_build_object(
      'email', v_email, 'kind', 'stakeholder',
      'stakeholder_id', v_sh, 'invitation_id', v_inv,
      'token', v_token, 'expires_at', v_expires
    );
  end loop;

  return query select v_project_id, v_slug, v_code, v_invites;
end;
$function$;

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
  if p_role = 'owner' and v_caller_role is distinct from 'owner' and not public.lign_is_org_owner((select organization_id from public.workspaces where id=p_workspace_id)) then
    raise exception 'invite_workspace_member: only an owner may invite an owner' using errcode='42501';
  end if;

  if p_role='admin' and not public.lign_is_org_admin((select organization_id from public.workspaces where id=p_workspace_id)) then
    raise exception 'Only studio owners or administrators can appoint workspace leads' using errcode='42501';
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

  -- Serialize owner/lead changes within the workspace.
  perform 1 from public.workspaces where id=v_m.workspace_id for update;
  select * into v_m from public.workspace_members where id=p_workspace_member_id for update;
  if not public.lign_has_capability(null, v_m.workspace_id, 'member.change_role') then
    raise exception 'Workspace leadership required' using errcode='42501';
  end if;
  if (p_role='admin' or v_m.role='admin') and not public.lign_is_org_admin((select organization_id from public.workspaces where id=v_m.workspace_id)) then
    raise exception 'Only studio owners or administrators can change workspace leads' using errcode='42501';
  end if;
  select role into v_caller_role from public.workspace_members
   where workspace_id = v_m.workspace_id and user_id = v_caller and status = 'active';

  if (p_role = 'owner' or v_m.role = 'owner') and v_caller_role is distinct from 'owner' and not public.lign_is_org_owner((select organization_id from public.workspaces where id=v_m.workspace_id)) then
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

  -- Serialize owner/lead changes within the workspace.
  perform 1 from public.workspaces where id=v_m.workspace_id for update;
  select * into v_m from public.workspace_members where id=p_workspace_member_id for update;
  if not public.lign_has_capability(null, v_m.workspace_id, 'member.remove') then
    raise exception 'Workspace leadership required' using errcode='42501';
  end if;
  if v_m.status='removed' then return; end if;
  if v_m.role='admin' and not public.lign_is_org_admin((select organization_id from public.workspaces where id=v_m.workspace_id)) then
    raise exception 'Only studio owners or administrators can remove workspace leads' using errcode='42501';
  end if;
  select role into v_caller_role from public.workspace_members
   where workspace_id = v_m.workspace_id and user_id = v_caller and status = 'active';
  if v_m.role = 'owner' and v_caller_role is distinct from 'owner' and not public.lign_is_org_owner((select organization_id from public.workspaces where id=v_m.workspace_id)) then
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




-- Applies to every removal path, including workspace removal and stakeholder
-- revocation. Parent row locks serialize concurrent lead removals.
create or replace function public.retain_project_lead()
returns trigger language plpgsql security definer set search_path = ''
as $fn$
begin
 if old.role='lead' and old.status='active' then
  if tg_op='UPDATE' then
   if new.role='lead' and new.status='active' and new.project_id=old.project_id then return new; end if;
  end if;
  perform 1 from public.projects where id=old.project_id and archived_at is null and status<>'archived' for update;
  if found and not exists (select 1 from public.project_participants
    where project_id=old.project_id and id<>old.id and role='lead' and status='active') then
   raise exception 'Assign another project lead before removing or changing the last lead.' using errcode='23514';
  end if;
 end if;
 if tg_op='DELETE' then return old; end if;
 return new;
end;
$fn$;
revoke all on function public.retain_project_lead() from public,anon,authenticated;
create trigger project_participants_retain_lead
 before update of role,status,project_id or delete on public.project_participants
 for each row execute function public.retain_project_lead();

-- A newly activated workspace colleague is also a studio colleague. Preserve
-- existing organisation roles and deliberate org-level removals.
create or replace function public.link_workspace_colleague_to_studio()
returns trigger language plpgsql security definer set search_path = ''
as $fn$
declare v_org uuid;
begin
 if new.status='active' then
  select organization_id into v_org from public.workspaces where id=new.workspace_id;
  insert into public.organization_members(organization_id,user_id,role,status,invited_at,activated_at)
  values(v_org,new.user_id,'member','active',now(),now())
  on conflict(organization_id,user_id) do nothing;
 end if;
 return new;
end;
$fn$;
revoke all on function public.link_workspace_colleague_to_studio() from public,anon,authenticated;
create trigger workspace_members_link_studio
 after insert or update of status on public.workspace_members
 for each row execute function public.link_workspace_colleague_to_studio();

-- Explicit scope and server-side leadership checks are essential: a contributor
-- must not learn about unassigned projects from summary counts or activity.
create or replace function public.get_studio_overview(
 p_organization_id uuid default null, p_workspace_id uuid default null
)
returns jsonb language plpgsql stable security definer set search_path = ''
as $fn$
declare v_org uuid; v_workspaces jsonb; v_activity jsonb;
begin
 if auth.uid() is null then raise exception 'Authentication required' using errcode='42501'; end if;
 if p_workspace_id is not null then
  select organization_id into v_org from public.workspaces where id=p_workspace_id;
  if v_org is null or not public.lign_is_workspace_admin(p_workspace_id)
     or (p_organization_id is not null and p_organization_id<>v_org) then
   raise exception 'Workspace leadership required' using errcode='42501';
  end if;
 else
  v_org := p_organization_id;
  if v_org is null or not public.lign_is_org_admin(v_org) then
   raise exception 'Studio ownership or administration required' using errcode='42501';
  end if;
 end if;

 select coalesce(jsonb_agg(row_data order by workspace_name),'[]'::jsonb) into v_workspaces
 from (
  select w.name workspace_name,jsonb_build_object(
   'id',w.id,'name',w.name,'status',w.status,
   'teamCount',(select count(*) from public.workspace_members wm where wm.workspace_id=w.id and wm.status='active'),
   'leads',(select coalesce(jsonb_agg(jsonb_build_object('userId',wm.user_id,'name',p.display_name,'role',wm.role) order by wm.role,p.display_name),'[]'::jsonb)
      from public.workspace_members wm join public.profiles p on p.id=wm.user_id
     where wm.workspace_id=w.id and wm.status='active' and wm.role in ('owner','admin')),
   'projects',(select coalesce(jsonb_agg(jsonb_build_object(
    'id',pr.id,'name',pr.name,'status',pr.status,'code',pr.code,'updatedAt',pr.updated_at,
    'leads',(select coalesce(jsonb_agg(jsonb_build_object('name',coalesce(p.display_name,sh.display_name,sh.email::text),'userId',coalesce(wm.user_id,sh.user_id))),'[]'::jsonb)
       from public.project_participants pp
       left join public.workspace_members wm on wm.id=pp.workspace_member_id
       left join public.profiles p on p.id=wm.user_id
       left join public.stakeholders sh on sh.id=pp.stakeholder_id
      where pp.project_id=pr.id and pp.status='active' and pp.role='lead'),
    'pendingReviews',(select count(*) from public.reviews r where r.project_id=pr.id and r.status in ('ready_for_review','open','in_progress','waiting')),
    'pendingApprovals',(select count(*) from public.approval_requests a where a.project_id=pr.id and a.status in ('pending','in_progress')),
    'latestActivityAt',coalesce((select max(e.occurred_at) from public.activity_events e where e.workspace_id=w.id and e.project_id=pr.id),pr.updated_at)
   ) order by pr.updated_at desc),'[]'::jsonb)
    from public.projects pr where pr.workspace_id=w.id and pr.archived_at is null)
  ) row_data
  from public.workspaces w where w.organization_id=v_org and w.status='active'
   and (p_workspace_id is null or w.id=p_workspace_id)
 ) ws;

 select coalesce(jsonb_agg(row_data order by occurred_at desc),'[]'::jsonb) into v_activity from (
  select e.occurred_at,jsonb_build_object('id',e.id,'occurredAt',e.occurred_at,'eventType',e.event_type,
   'subject',e.subject_label,'actor',coalesce(p.display_name,'System'),
   'workspaceId',e.workspace_id,'workspaceName',w.name,'projectId',e.project_id) row_data
   from public.activity_events e join public.workspaces w on w.id=e.workspace_id
   left join public.profiles p on p.id=e.actor_profile_id
  where w.organization_id=v_org and w.status='active' and (p_workspace_id is null or w.id=p_workspace_id)
  order by e.occurred_at desc limit 20
 ) events;
 return jsonb_build_object('organizationId',v_org,'organizationName',(select name from public.organizations where id=v_org),
   'workspaces',v_workspaces,'activity',v_activity);
end;
$fn$;
revoke all on function public.get_studio_overview(uuid,uuid) from public,anon;
grant execute on function public.get_studio_overview(uuid,uuid) to authenticated;
