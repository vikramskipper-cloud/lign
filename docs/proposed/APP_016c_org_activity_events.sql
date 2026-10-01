-- APP 016c — organisation-scoped activity events.
--
-- activity_events.workspace_id was NOT NULL, so an action on an organisation
-- had nowhere to be recorded. APP 015 therefore shipped create_organization,
-- add_org_member, change_org_member_role and remove_org_member writing no
-- event at all — the one part of that slice that was simply missing rather
-- than deferred. In a product whose whole purpose is that decisions are
-- reconstructable two years later, a membership change with no trace is the
-- wrong kind of gap to leave.
--
-- WHAT MAKES THIS SAFE TO LOOSEN. Dropping NOT NULL cannot invalidate an
-- existing row, and the scope CHECK below is satisfied by every row already
-- in the table: all of them have workspace_id set and organization_id null.
-- The risk is the opposite direction — a NULL workspace_id reaching code that
-- assumes otherwise — so the policy is rewritten to test each scope
-- explicitly rather than relying on lign_is_workspace_admin(null) happening
-- to return false.

alter table public.activity_events
  alter column workspace_id drop not null;

alter table public.activity_events
  add column organization_id uuid references public.organizations (id) on delete restrict;

comment on column public.activity_events.organization_id is
  'Set for organisation-scoped events; null for workspace and project events. Exactly one of workspace_id / organization_id is set.';

-- Exactly one scope. Both set would make "which log is this in" ambiguous;
-- neither set would orphan the row.
alter table public.activity_events
  add constraint activity_events_scope_check
  check ((workspace_id is not null) <> (organization_id is not null));

-- Matches the read: an organisation's log, newest first.
create index activity_events_organization_id_idx
  on public.activity_events (organization_id, occurred_at desc)
  where organization_id is not null;

-- The previous policy was:
--   lign_is_workspace_admin(workspace_id)
--   OR (project_id IS NOT NULL AND lign_has_capability(project_id, workspace_id, 'activity.view'))
--
-- Org rows would have been rejected by it, which is safe but useless. Each arm
-- is now guarded by the scope it reads, so no arm is ever handed a NULL it did
-- not expect. Workspace rows need no new clause: lign_is_workspace_admin
-- already answers true for org admins, since APP 015 widened it.
drop policy if exists activity_events_select on public.activity_events;
create policy activity_events_select on public.activity_events
  for select to authenticated
  using (
    (workspace_id is not null and public.lign_is_workspace_admin(workspace_id))
    or (workspace_id is not null and project_id is not null
        and public.lign_has_capability(project_id, workspace_id, 'activity.view'))
    or (organization_id is not null and public.lign_is_org_admin(organization_id))
  );

-- ------------------------------------------- the four RPCs gain their events --
-- Bodies are otherwise byte-for-byte the APP 015 versions.

create or replace function public.create_organization(
  p_name text,
  p_slug text default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_caller uuid;
  v_name   text;
  v_base   text;
  v_slug   text;
  v_n      integer := 1;
  v_org    uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'create_organization: authentication required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles where id = v_caller) then
    raise exception 'create_organization: caller profile % not found', v_caller using errcode = '23503';
  end if;

  v_name := trim(coalesce(p_name, ''));
  if length(v_name) = 0 then
    raise exception 'create_organization: name required' using errcode = '22004';
  end if;
  if length(v_name) > 120 then
    raise exception 'create_organization: name exceeds 120 characters' using errcode = '22001';
  end if;

  v_base := regexp_replace(lower(coalesce(nullif(trim(coalesce(p_slug, '')), ''), v_name)),
                           '[^a-z0-9]+', '-', 'g');
  v_base := trim(both '-' from v_base);
  v_base := left(nullif(v_base, ''), 56);
  if v_base is null then
    v_base := 'org';
  end if;
  v_slug := v_base;
  while exists (
    select 1 from public.organizations where lower(slug::text) = v_slug
  ) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n::text;
  end loop;

  insert into public.organizations (name, slug, status)
  values (v_name, v_slug::extensions.citext, 'active')
  returning id into v_org;

  insert into public.organization_members (
    organization_id, user_id, role, status, invited_at, activated_at
  )
  values (v_org, v_caller, 'owner', 'active', now(), now());

  insert into public.activity_events (
    workspace_id, organization_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    null, v_org, null, now(), 'organization.created',
    v_caller, 'user',
    'organization', v_org, v_name,
    jsonb_build_object('name', v_name, 'slug', v_slug),
    jsonb_build_object('actor_capacity', 'internal')
  );

  return v_org;
end;
$function$;

create or replace function public.add_org_member(
  p_organization_id uuid,
  p_user_id         uuid,
  p_role            text default 'member'
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_caller uuid;
  v_id     uuid;
  v_label  text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'add_org_member: authentication required' using errcode = '42501';
  end if;
  if p_role not in ('owner', 'admin', 'member') then
    raise exception 'add_org_member: invalid role %', p_role using errcode = '23514';
  end if;
  if not public.lign_is_org_admin(p_organization_id) then
    raise exception 'add_org_member: forbidden' using errcode = '42501';
  end if;
  if p_role = 'owner' and not exists (
    select 1 from public.organization_members
     where organization_id = p_organization_id and user_id = v_caller
       and status = 'active' and role = 'owner'
  ) then
    raise exception 'add_org_member: only an owner may grant the owner role' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles where id = p_user_id) then
    raise exception 'add_org_member: profile % not found', p_user_id using errcode = '23503';
  end if;

  insert into public.organization_members (
    organization_id, user_id, role, status, invited_at, activated_at
  )
  values (p_organization_id, p_user_id, p_role, 'active', now(), now())
  on conflict (organization_id, user_id) do update
    set role         = excluded.role,
        status       = 'active',
        activated_at = coalesce(organization_members.activated_at, now()),
        removed_at   = null
  returning id into v_id;

  select email::text into v_label from public.profiles where id = p_user_id;

  insert into public.activity_events (
    workspace_id, organization_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label,
    subject_snapshot, payload
  )
  values (
    null, p_organization_id, null, now(), 'organization.member.added',
    v_caller, 'user', 'organization_member', v_id, coalesce(v_label, ''),
    jsonb_build_object('role', p_role),
    jsonb_build_object('actor_capacity', 'internal')
  );

  return v_id;
end;
$function$;

create or replace function public.change_org_member_role(
  p_organization_member_id uuid,
  p_role                   text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_caller      uuid;
  v_m           public.organization_members%rowtype;
  v_caller_role text;
  v_owners      integer;
  v_label       text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'change_org_member_role: authentication required' using errcode = '42501';
  end if;
  if p_role not in ('owner', 'admin', 'member') then
    raise exception 'change_org_member_role: invalid role %', p_role using errcode = '23514';
  end if;

  select * into v_m from public.organization_members where id = p_organization_member_id;
  if not found then
    raise exception 'change_org_member_role: member % not found', p_organization_member_id
      using errcode = '23503';
  end if;
  if not public.lign_is_org_admin(v_m.organization_id) then
    raise exception 'change_org_member_role: forbidden' using errcode = '42501';
  end if;
  if v_m.user_id = v_caller then
    raise exception 'change_org_member_role: cannot change your own role' using errcode = '42501';
  end if;

  select role into v_caller_role from public.organization_members
   where organization_id = v_m.organization_id and user_id = v_caller and status = 'active';

  if (p_role = 'owner' or v_m.role = 'owner') and v_caller_role is distinct from 'owner' then
    raise exception 'change_org_member_role: only an owner may grant or revoke the owner role'
      using errcode = '42501';
  end if;
  if v_m.role = p_role then return; end if;

  if v_m.role = 'owner' then
    select count(*) into v_owners from public.organization_members
     where organization_id = v_m.organization_id and role = 'owner' and status = 'active';
    if v_owners <= 1 then
      raise exception 'change_org_member_role: cannot demote the last owner of the organisation'
        using errcode = '23514';
    end if;
  end if;

  update public.organization_members set role = p_role where id = p_organization_member_id;

  select email::text into v_label from public.profiles where id = v_m.user_id;

  insert into public.activity_events (
    workspace_id, organization_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label,
    subject_snapshot, payload
  )
  values (
    null, v_m.organization_id, null, now(), 'organization.member.role_changed',
    v_caller, 'user', 'organization_member', v_m.id, coalesce(v_label, ''),
    jsonb_build_object('from_role', v_m.role, 'to_role', p_role),
    jsonb_build_object('actor_capacity', 'internal')
  );
end;
$function$;

create or replace function public.remove_org_member(
  p_organization_member_id uuid
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_caller      uuid;
  v_m           public.organization_members%rowtype;
  v_caller_role text;
  v_owners      integer;
  v_label       text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'remove_org_member: authentication required' using errcode = '42501';
  end if;

  select * into v_m from public.organization_members where id = p_organization_member_id;
  if not found then
    raise exception 'remove_org_member: member % not found', p_organization_member_id
      using errcode = '23503';
  end if;
  if not public.lign_is_org_admin(v_m.organization_id) then
    raise exception 'remove_org_member: forbidden' using errcode = '42501';
  end if;
  if v_m.user_id = v_caller then
    raise exception 'remove_org_member: cannot remove yourself from the organisation'
      using errcode = '42501';
  end if;
  if v_m.status = 'removed' then return; end if;

  select role into v_caller_role from public.organization_members
   where organization_id = v_m.organization_id and user_id = v_caller and status = 'active';
  if v_m.role = 'owner' and v_caller_role is distinct from 'owner' then
    raise exception 'remove_org_member: only an owner may remove an owner' using errcode = '42501';
  end if;
  if v_m.role = 'owner' then
    select count(*) into v_owners from public.organization_members
     where organization_id = v_m.organization_id and role = 'owner' and status = 'active';
    if v_owners <= 1 then
      raise exception 'remove_org_member: cannot remove the last owner of the organisation'
        using errcode = '23514';
    end if;
  end if;

  -- Deliberately does NOT touch workspace_members. Losing org-wide oversight
  -- and losing the workspaces you were individually added to are different
  -- events, and cascading them would silently strip access nobody asked to
  -- revoke.
  update public.organization_members
     set status = 'removed', removed_at = now()
   where id = p_organization_member_id;

  select email::text into v_label from public.profiles where id = v_m.user_id;

  insert into public.activity_events (
    workspace_id, organization_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind, subject_kind, subject_id, subject_label,
    subject_snapshot, payload
  )
  values (
    null, v_m.organization_id, null, now(), 'organization.member.removed',
    v_caller, 'user', 'organization_member', v_m.id, coalesce(v_label, ''),
    jsonb_build_object('previous_role', v_m.role),
    jsonb_build_object('actor_capacity', 'internal')
  );
end;
$function$;