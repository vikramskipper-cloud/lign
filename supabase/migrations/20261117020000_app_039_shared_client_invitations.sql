-- APP 039: share one workspace activation invitation across project assignments.
-- Preserve pending token hashes/expiry; accepted stakeholders need no new activation.
create or replace function public.invite_stakeholder(
 p_workspace_id uuid,p_email text,p_project_id uuid,p_role text default 'reviewer',
 p_display_name text default null,p_expires_in_days integer default 14
)
returns table(out_invitation_id uuid,out_stakeholder_id uuid,out_token text,out_expires_at timestamptz)
language plpgsql security definer set search_path=''
as $$
declare
 caller uuid:=auth.uid(); email_text text:=lower(trim(coalesce(p_email,'')));
 sh public.stakeholders%rowtype; invitation public.invitations%rowtype;
 workspace_admin boolean; existing_role text; token text; expiry timestamptz;
begin
 if caller is null then raise exception 'Authentication required' using errcode='42501';end if;
 if p_workspace_id is null or p_project_id is null then raise exception 'Workspace and project are required' using errcode='22004';end if;
 if p_role is null or p_role not in ('lead','contributor','reviewer','approver','observer') then raise exception 'Invalid project role' using errcode='23514';end if;
 workspace_admin:=public.lign_is_workspace_admin(p_workspace_id);
 if not workspace_admin then
  if not public.lign_has_capability(p_project_id,p_workspace_id,'project.manage_access') then raise exception 'Only workspace leadership or this project lead can invite external participants' using errcode='42501';end if;
  if p_role not in ('reviewer','approver') then raise exception 'Project leads can invite external reviewers and approvers only' using errcode='42501';end if;
 end if;
 if not exists(select 1 from public.projects p where p.id=p_project_id and p.workspace_id=p_workspace_id) then raise exception 'Project is not in this workspace' using errcode='23503';end if;
 if length(email_text)>254 or email_text !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$' then raise exception 'Enter a valid email address' using errcode='22023';end if;
 -- Shared with claim_stakeholder_invitation. Serialises creation/reuse/acceptance per identity.
 perform pg_advisory_xact_lock(hashtextextended('lign:stakeholder:'||p_workspace_id||':'||email_text,39));
 select * into sh from public.stakeholders s where s.workspace_id=p_workspace_id and lower(s.email::text)=email_text for update;
 if sh.id is null then
  insert into public.stakeholders(workspace_id,email,display_name,status)
  values(p_workspace_id,email_text::extensions.citext,nullif(trim(coalesce(p_display_name,'')),''),'invited') returning * into sh;
 else
  if not workspace_admin and sh.status='revoked' then raise exception 'Ask workspace leadership to restore this external participant' using errcode='42501';end if;
  if workspace_admin then
   update public.stakeholders s set status=case when s.status='revoked' then 'invited' else s.status end,
    revoked_at=case when s.status='revoked' then null else s.revoked_at end,
    display_name=coalesce(nullif(trim(coalesce(p_display_name,'')),''),s.display_name)
   where s.id=sh.id returning * into sh;
  end if;
 end if;
 select pp.role into existing_role from public.project_participants pp where pp.project_id=p_project_id and pp.stakeholder_id=sh.id and pp.status='active' for update;
 if existing_role is not null and existing_role<>p_role then raise exception 'This person already has a different project role. Update it through Project people.' using errcode='23514';end if;
 if existing_role is null then perform public.add_project_participant(p_project_id,null,sh.id,p_role);end if;
 update public.invitations i set status='expired' where i.workspace_id=p_workspace_id and lower(i.email::text)=email_text and i.kind='stakeholder' and i.status='sent' and i.expires_at<=now();
 if sh.status='active' and sh.user_id is not null then
  return query select null::uuid,sh.id,null::text,null::timestamptz;
  return;
 end if;
 select * into invitation from public.invitations i where i.workspace_id=p_workspace_id and lower(i.email::text)=email_text and i.kind='stakeholder' and i.status='sent' and i.expires_at>now() for update;
 if invitation.id is not null then
  -- Plaintext tokens are deliberately unrecoverable. Do not rotate an earlier link.
  return query select invitation.id,sh.id,null::text,invitation.expires_at;
  return;
 end if;
 token:=replace(gen_random_uuid()::text,'-','')||replace(gen_random_uuid()::text,'-','');
 expiry:=now()+make_interval(days=>greatest(1,coalesce(p_expires_in_days,14)));
 insert into public.invitations(workspace_id,email,kind,role,invited_by_profile_id,status,token_hash,expires_at)
 values(p_workspace_id,email_text::extensions.citext,'stakeholder',p_role,caller,'sent',encode(extensions.digest(token::bytea,'sha256'),'hex'),expiry) returning * into invitation;
 insert into public.activity_events(workspace_id,project_id,occurred_at,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,subject_snapshot,payload)
 values(p_workspace_id,p_project_id,now(),'stakeholder.invited',caller,'user','stakeholder',sh.id,email_text,
  jsonb_build_object('email',email_text,'project_id',p_project_id,'role',p_role,'invitation_id',invitation.id),'{}'::jsonb);
 return query select invitation.id,sh.id,token,expiry;
end; $$;
revoke all on function public.invite_stakeholder(uuid,text,uuid,text,text,integer) from public,anon,authenticated;
grant execute on function public.invite_stakeholder(uuid,text,uuid,text,text,integer) to authenticated,service_role;

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
  v_invited record;
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

  -- Match the client-details wrapper's workspace lock, including direct callers.
  perform pg_advisory_xact_lock(hashtextextended(p_workspace_id::text,30));

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

    -- One checked path owns stakeholder identity, project role and invitation reuse.
    select * into v_invited from public.invite_stakeholder(p_workspace_id,v_email,v_project_id,'approver',null,p_expires_in_days);
    v_invites:=v_invites||jsonb_build_object(
      'email',v_email,'kind','stakeholder','stakeholder_id',v_invited.out_stakeholder_id,
      'invitation_id',v_invited.out_invitation_id,'token',v_invited.out_token,'expires_at',v_invited.out_expires_at,
      'state',case when v_invited.out_token is not null then 'created' when v_invited.out_invitation_id is not null then 'pending' else 'active' end);
  end loop;

  return query select v_project_id, v_slug, v_code, v_invites;
end;
$function$;
revoke all on function public.create_project_full(uuid,text,text,text,uuid,text[],integer) from public,anon,authenticated;
grant execute on function public.create_project_full(uuid,text,text,text,uuid,text[],integer) to authenticated,service_role;

-- Re-check the token under the identity lock so concurrent reuse/claim/revocation stays safe.
create or replace function public.claim_stakeholder_invitation(p_token text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare caller uuid:=auth.uid(); caller_email text; inv public.invitations%rowtype; sh public.stakeholders%rowtype;
begin
 if caller is null then raise exception 'Authentication required' using errcode='42501';end if;
 if p_token is null or length(p_token)=0 then raise exception 'Invitation token required' using errcode='22004';end if;
 select lower(u.email::text) into caller_email from auth.users u where u.id=caller;
 select * into inv from public.invitations i where i.token_hash=encode(extensions.digest(p_token::bytea,'sha256'),'hex') and i.kind='stakeholder' limit 1;
 if inv.id is null or caller_email is null or lower(inv.email::text)<>caller_email then raise exception 'Invitation does not match this account' using errcode='42501';end if;
 perform pg_advisory_xact_lock(hashtextextended('lign:stakeholder:'||inv.workspace_id||':'||lower(inv.email::text),39));
 select * into inv from public.invitations i where i.id=inv.id for update;
 if inv.status<>'sent' or inv.expires_at<=now() then raise exception 'Invitation not found, expired, revoked, or already accepted' using errcode='42501';end if;
 select * into sh from public.stakeholders s where s.workspace_id=inv.workspace_id and lower(s.email::text)=caller_email for update;
 if sh.id is null or sh.status='revoked' or (sh.user_id is not null and sh.user_id<>caller) then raise exception 'This external identity cannot be claimed by this account' using errcode='42501';end if;
 update public.stakeholders set user_id=caller,status='active' where id=sh.id;
 update public.invitations set status='accepted',accepted_at=now() where id=inv.id;
 insert into public.activity_events(workspace_id,project_id,occurred_at,event_type,actor_profile_id,actor_kind,subject_kind,subject_id,subject_label,subject_snapshot,payload)
 values(inv.workspace_id,null,now(),'stakeholder.claimed',caller,'user','stakeholder',sh.id,caller_email,jsonb_build_object('invitation_id',inv.id),'{}'::jsonb);
 return sh.id;
end; $$;
revoke all on function public.claim_stakeholder_invitation(text) from public,anon,authenticated;
grant execute on function public.claim_stakeholder_invitation(text) to authenticated,service_role;
