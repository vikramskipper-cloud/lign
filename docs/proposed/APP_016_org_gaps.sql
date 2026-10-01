-- APP 016 — closing the gaps APP 015 left open.
--
-- Five items, four of which were listed in APP_015_IMPLEMENTATION_REPORT.md §6
-- and one of which that report got wrong.
--
-- 1. PERFORMANCE — the item I under-called. APP 015 said the widened helpers
--    put "a second index probe" on the critical path and that I had not
--    measured it. Measured: 17 us for the old membership-only check, 246 us
--    for the widened one when the membership clause misses. Fourteen times
--    slower, not a probe.
--
--    The cause is not the probe, it is the nesting. A SECURITY DEFINER
--    function CANNOT be inlined by the planner, so lign_is_workspace_member
--    calling lign_org_of_workspace calling lign_is_org_admin pays three full
--    function invocations with their own snapshots. Flattening to one query
--    over a join: 33 us. Still twice the old cost, which is the honest price
--    of the feature, instead of fourteen times.
--
--    This matters far more widely than "org admins pay it". RLS evaluates the
--    policy per candidate row, and the membership clause misses on every row
--    you cannot see — so a user with one of fifty workspaces took the 246 us
--    path forty-nine times per list query.
--
--    lign_is_org_member / lign_is_org_admin / lign_org_of_workspace stay: the
--    policies on the org tables and the app both use them. They are simply no
--    longer called from the hot path.
--
-- 2. Organisation-scoped activity events had nowhere to live, because
--    activity_events.workspace_id was NOT NULL.
-- 3. Organisation invitations could not be represented, same reason on
--    invitations.workspace_id, so add_org_member required an existing profile.
-- 4. workspaces.slug was globally unique, so one tenant's name could block
--    another's.
-- 5. revoke_invitation only understood workspace-scoped invitations.

-- ------------------------------------------------- 1. flatten the hot path --

create or replace function public.lign_is_workspace_member(p_workspace_id uuid)
returns boolean
language sql
stable parallel safe security definer
set search_path to ''
as $function$
  select exists (
    select 1
      from public.workspace_members
     where user_id = auth.uid()
       and workspace_id = p_workspace_id
       and status = 'active'
  ) or exists (
    -- Deliberately NOT lign_is_org_admin(lign_org_of_workspace(...)). Nested
    -- SECURITY DEFINER calls cannot be inlined; this join is the same
    -- predicate at a sixth of the cost.
    select 1
      from public.workspaces w
      join public.organization_members om on om.organization_id = w.organization_id
     where w.id       = p_workspace_id
       and om.user_id = auth.uid()
       and om.status  = 'active'
       and om.role in ('owner', 'admin')
  );
$function$;

create or replace function public.lign_is_workspace_admin(p_workspace_id uuid)
returns boolean
language sql
stable parallel safe security definer
set search_path to ''
as $function$
  select exists (
    select 1
      from public.workspace_members
     where user_id = auth.uid()
       and workspace_id = p_workspace_id
       and status = 'active'
       and role in ('owner','admin')
  ) or exists (
    select 1
      from public.workspaces w
      join public.organization_members om on om.organization_id = w.organization_id
     where w.id       = p_workspace_id
       and om.user_id = auth.uid()
       and om.status  = 'active'
       and om.role in ('owner', 'admin')
  );
$function$;

-- --------------------------------------- 2. org-scoped activity_events ------

alter table public.activity_events
  alter column workspace_id drop not null;

alter table public.activity_events
  add column organization_id uuid references public.organizations (id) on delete restrict;

-- Exactly one scope. A workspace event names its workspace (and optionally a
-- project inside it); an organisation event names its organisation. Allowing
-- both would make "which log is this in" ambiguous, and allowing neither
-- would orphan the row.
alter table public.activity_events
  add constraint activity_events_scope_check
  check ((workspace_id is not null) <> (organization_id is not null));

create index activity_events_organization_id_idx
  on public.activity_events (organization_id, occurred_at desc)
  where organization_id is not null;

-- Org rows were invisible until now: lign_is_workspace_admin(null) is false,
-- so the existing policy rejected them. Workspace rows need no new clause —
-- lign_is_workspace_admin already answers true for org admins.
drop policy if exists activity_events_select on public.activity_events;
create policy activity_events_select on public.activity_events
  for select to authenticated
  using (
    (workspace_id is not null and public.lign_is_workspace_admin(workspace_id))
    or (project_id is not null and public.lign_has_capability(project_id, workspace_id, 'activity.view'))
    or (organization_id is not null and public.lign_is_org_admin(organization_id))
  );

-- ------------------------------------------ 3. org-scoped invitations -------

alter table public.invitations
  alter column workspace_id drop not null;

alter table public.invitations
  add column organization_id uuid references public.organizations (id) on delete cascade;

alter table public.invitations
  drop constraint invitations_kind_check;
alter table public.invitations
  add constraint invitations_kind_check
  check (kind = any (array['workspace_member'::text, 'stakeholder'::text, 'org_member'::text]));

alter table public.invitations
  add constraint invitations_scope_check
  check ((workspace_id is not null) <> (organization_id is not null));

-- kind and scope must agree, or an org invitation could be claimed by the
-- workspace accept path.
alter table public.invitations
  add constraint invitations_kind_scope_check
  check (
    (kind = 'org_member' and organization_id is not null)
    or (kind in ('workspace_member', 'stakeholder') and workspace_id is not null)
  );

create index invitations_organization_id_idx
  on public.invitations (organization_id)
  where organization_id is not null;

drop policy if exists invitations_select_admin_or_invitee on public.invitations;
create policy invitations_select_admin_or_invitee on public.invitations
  for select to authenticated
  using (
    (workspace_id is not null and public.lign_is_workspace_admin(workspace_id))
    or (organization_id is not null and public.lign_is_org_admin(organization_id))
    or email = ((select auth.email()))::extensions.citext
  );

-- ------------------------------------- 4. workspace slug is per-tenant ------
-- Globally unique slugs meant a stranger's workspace name could block yours.
-- create_workspace suffixed around it, so nobody was ever blocked, but the
-- suffix was answering the wrong question: two organisations should both be
-- able to have a workspace called "studio".
alter table public.workspaces drop constraint workspaces_slug_key;
alter table public.workspaces
  add constraint workspaces_organization_slug_key unique (organization_id, slug);

-- ----------------------------------------------------------- 5. RPCs --------

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

create or replace function public.create_workspace(
  p_name            text,
  p_slug            text,
  p_organization_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_caller_profile_id uuid;
  v_org               uuid;
  v_base              text;
  v_slug              text;
  v_n                 integer := 1;
  v_workspace_id      uuid;
begin
  v_caller_profile_id := auth.uid();
  if v_caller_profile_id is null then
    raise exception 'create_workspace: authentication required'
      using errcode = '42501';
  end if;

  if p_name is null or length(trim(p_name)) = 0 then
    raise exception 'create_workspace: name required'
      using errcode = '22004';
  end if;

  if not exists (
    select 1 from public.profiles where id = v_caller_profile_id
  ) then
    raise exception 'create_workspace: caller profile % not found', v_caller_profile_id
      using errcode = '23503';
  end if;

  if p_organization_id is null then
    if exists (
      select 1 from public.organization_members
       where user_id = v_caller_profile_id and status = 'active'
    ) then
      raise exception 'create_workspace: organization_id required — caller already belongs to an organisation'
        using errcode = '22004';
    end if;
    v_org := public.create_organization(p_name, p_slug);
  else
    v_org := p_organization_id;
    if not public.lign_is_org_admin(v_org) then
      raise exception 'create_workspace: forbidden — not an admin of organisation %', v_org
        using errcode = '42501';
    end if;
  end if;

  -- Scoped to the organisation now that the unique key is. Two tenants may
  -- both have a "studio"; one tenant may not have two.
  v_base := regexp_replace(lower(coalesce(nullif(trim(coalesce(p_slug, '')), ''), trim(p_name))),
                           '[^a-z0-9]+', '-', 'g');
  v_base := trim(both '-' from v_base);
  v_base := left(nullif(v_base, ''), 56);
  if v_base is null then
    v_base := 'workspace';
  end if;
  v_slug := v_base;
  while exists (
    select 1 from public.workspaces
     where organization_id = v_org and lower(slug::text) = v_slug
  ) loop
    v_n := v_n + 1;
    v_slug := v_base || '-' || v_n::text;
  end loop;

  insert into public.workspaces (name, slug, status, organization_id)
  values (trim(p_name), v_slug::extensions.citext, 'active', v_org)
  returning id into v_workspace_id;

  insert into public.workspace_members (
    workspace_id, user_id, role, status, invited_at, activated_at
  )
  values (
    v_workspace_id, v_caller_profile_id, 'owner', 'active', now(), now()
  );

  insert into public.activity_events (
    workspace_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    v_workspace_id, null, now(), 'workspace.created',
    v_caller_profile_id, 'user',
    'workspace', v_workspace_id, trim(p_name),
    jsonb_build_object('name', trim(p_name), 'slug', v_slug, 'organization_id', v_org),
    '{}'::jsonb
  );

  return v_workspace_id;
end;
$function$;

-- Org invitations by email. Same shape as invite_workspace_member: the
-- plaintext token is returned ONCE and only its sha256 is stored, because
-- there is still no email infrastructure and delivery is a copied link.
create or replace function public.invite_org_member(
  p_organization_id uuid,
  p_email           text,
  p_role            text    default 'member',
  p_expires_in_days integer default 14
)
returns table (
  out_invitation_id uuid,
  out_token         text,
  out_expires_at    timestamptz
)
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_caller  uuid;
  v_email   extensions.citext;
  v_token   text;
  v_hash    text;
  v_expires timestamptz;
  v_inv     uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'invite_org_member: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_email is null then
    raise exception 'invite_org_member: organization_id and email required' using errcode = '22004';
  end if;
  if p_role not in ('owner', 'admin', 'member') then
    raise exception 'invite_org_member: invalid role %', p_role using errcode = '23514';
  end if;
  if not public.lign_is_org_admin(p_organization_id) then
    raise exception 'invite_org_member: forbidden' using errcode = '42501';
  end if;
  if p_role = 'owner' and not exists (
    select 1 from public.organization_members
     where organization_id = p_organization_id and user_id = v_caller
       and status = 'active' and role = 'owner'
  ) then
    raise exception 'invite_org_member: only an owner may grant the owner role' using errcode = '42501';
  end if;

  -- Lower-cased before comparison and storage. citext's = operator is not
  -- visible under search_path '' and silently degrades to case-sensitive text
  -- equality — the defect APP 014 shipped and then had to fix.
  v_email := lower(trim(p_email))::extensions.citext;

  if exists (
    select 1
      from public.organization_members om
      join public.profiles p on p.id = om.user_id
     where om.organization_id = p_organization_id
       and om.status = 'active'
       and lower(p.email::text) = v_email::text
  ) then
    raise exception 'invite_org_member: % is already a member of this organisation', v_email
      using errcode = '23505';
  end if;

  if exists (
    select 1 from public.invitations
     where organization_id = p_organization_id
       and lower(email::text) = v_email::text
       and kind = 'org_member' and status = 'sent' and expires_at > now()
  ) then
    raise exception 'invite_org_member: an invitation for % is already pending', v_email
      using errcode = '23505';
  end if;

  v_token   := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  v_hash    := encode(extensions.digest(v_token::bytea, 'sha256'), 'hex');
  v_expires := now() + make_interval(days => greatest(1, coalesce(p_expires_in_days, 14)));

  insert into public.invitations (
    workspace_id, organization_id, email, kind, role, invited_by_profile_id,
    status, token_hash, expires_at
  )
  values (
    null, p_organization_id, v_email, 'org_member', p_role, v_caller,
    'sent', v_hash, v_expires
  )
  returning id into v_inv;

  insert into public.activity_events (
    workspace_id, organization_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    null, p_organization_id, null, now(), 'organization.member.invited',
    v_caller, 'user',
    'invitation', v_inv, v_email::text,
    jsonb_build_object('email', v_email::text, 'role', p_role),
    jsonb_build_object('actor_capacity', 'internal')
  );

  return query select v_inv, v_token, v_expires;
end;
$function$;

create or replace function public.accept_org_invitation(p_token text)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_caller     uuid;
  v_email      extensions.citext;
  v_hash       text;
  v_invitation public.invitations%rowtype;
  v_member_id  uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'accept_org_invitation: authentication required' using errcode = '42501';
  end if;
  if p_token is null or length(p_token) = 0 then
    raise exception 'accept_org_invitation: token required' using errcode = '22004';
  end if;

  select lower(email)::extensions.citext into v_email from auth.users where id = v_caller;
  if v_email is null then
    raise exception 'accept_org_invitation: caller has no email on auth.users' using errcode = '23503';
  end if;

  v_hash := encode(extensions.digest(p_token::bytea, 'sha256'), 'hex');

  select * into v_invitation
    from public.invitations
   where token_hash = v_hash
     and kind       = 'org_member'
     and status     = 'sent'
     and expires_at > now()
   limit 1;
  if not found then
    raise exception 'accept_org_invitation: invitation not found, expired, revoked, or already accepted'
      using errcode = '42501';
  end if;

  if lower(v_invitation.email::text) is distinct from v_email::text then
    raise exception 'accept_org_invitation: invitation email does not match caller'
      using errcode = '42501';
  end if;

  insert into public.organization_members (
    organization_id, user_id, role, status, invited_at, activated_at
  )
  values (
    v_invitation.organization_id, v_caller,
    coalesce(v_invitation.role, 'member'), 'active', v_invitation.created_at, now()
  )
  on conflict (organization_id, user_id) do update
    set status       = 'active',
        activated_at = coalesce(organization_members.activated_at, now()),
        removed_at   = null
  returning id into v_member_id;

  update public.invitations
     set status = 'accepted', accepted_at = now()
   where id = v_invitation.id;

  insert into public.activity_events (
    workspace_id, organization_id, project_id, occurred_at, event_type,
    actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    null, v_invitation.organization_id, null, now(), 'organization.member.activated',
    v_caller, 'user',
    'organization_member', v_member_id, v_email::text,
    jsonb_build_object('invitation_id', v_invitation.id, 'role', coalesce(v_invitation.role, 'member')),
    jsonb_build_object('actor_capacity', 'internal')
  );

  return v_member_id;
end;
$function$;

-- revoke_invitation only understood the two workspace kinds; an org
-- invitation fell through to the member.invite capability on a NULL workspace
-- and was unrevokable.
create or replace function public.revoke_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
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

  if v_inv.kind = 'org_member' then
    if not public.lign_is_org_admin(v_inv.organization_id) then
      raise exception 'revoke_invitation: forbidden (organisation admin)' using errcode='42501';
    end if;
  else
    v_key := case when v_inv.kind = 'stakeholder' then 'stakeholder.invite' else 'member.invite' end;
    if not public.lign_has_capability(null, v_inv.workspace_id, v_key) then
      raise exception 'revoke_invitation: forbidden (%)', v_key using errcode='42501';
    end if;
  end if;

  if v_inv.status <> 'sent' then
    raise exception 'revoke_invitation: invitation is % and cannot be revoked', v_inv.status
      using errcode='23514';
  end if;

  update public.invitations set status = 'revoked' where id = p_invitation_id;

  insert into public.activity_events (workspace_id, organization_id, project_id, occurred_at,
    event_type, actor_profile_id, actor_kind, subject_kind, subject_id, subject_label,
    subject_snapshot, payload)
  values (v_inv.workspace_id, v_inv.organization_id, null, now(), 'invitation.revoked',
    v_caller, 'user', 'invitation', v_inv.id, v_inv.email::text,
    jsonb_build_object('kind', v_inv.kind, 'email', v_inv.email::text), '{}'::jsonb);
end $function$;

-- The three org-membership RPCs gain the activity events they could not write
-- before. Bodies are otherwise unchanged from APP 015.

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

grant execute on function public.invite_org_member(uuid, text, text, integer) to authenticated;
grant execute on function public.accept_org_invitation(text)                  to authenticated;