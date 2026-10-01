-- APP 016f — the RPCs that write the organisation audit trail, plus email
-- invitations to an organisation.
--
-- Pairs with APP 016e, which created organization_events and
-- organization_invitations. Every function here is either CREATE OR REPLACE of
-- an APP 015 function (mine, not frozen V1) or a new one. No frozen RPC is
-- touched: in particular revoke_invitation is left exactly as it is, and org
-- invitations get their own revoke_org_invitation, because org invitations now
-- live in their own table and never reach the old one.
--
-- WHAT THIS CLOSES. Until now create_organization, add_org_member,
-- change_org_member_role and remove_org_member wrote no audit record at all —
-- the last unclosed gap from APP 015 — and there was no way to invite someone
-- to an organisation who did not already hold a LIGN account.

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

  insert into public.organization_events (
    organization_id, occurred_at, event_type, actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    v_org, now(), 'organization.created', v_caller, 'user',
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

  insert into public.organization_events (
    organization_id, occurred_at, event_type, actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    p_organization_id, now(), 'organization.member.added', v_caller, 'user',
    'organization_member', v_id, coalesce(v_label, ''),
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

  insert into public.organization_events (
    organization_id, occurred_at, event_type, actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    v_m.organization_id, now(), 'organization.member.role_changed', v_caller, 'user',
    'organization_member', v_m.id, coalesce(v_label, ''),
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

  insert into public.organization_events (
    organization_id, occurred_at, event_type, actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    v_m.organization_id, now(), 'organization.member.removed', v_caller, 'user',
    'organization_member', v_m.id, coalesce(v_label, ''),
    jsonb_build_object('previous_role', v_m.role),
    jsonb_build_object('actor_capacity', 'internal')
  );
end;
$function$;

-- Invite someone who has no LIGN account yet. The plaintext token is returned
-- ONCE and only its sha256 is stored; there is still no email infrastructure,
-- so delivery is a copied link, exactly as APP 013 settled for workspaces.
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
  v_email   text;
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

  -- Compared and stored lower-cased as plain text. citext's = operator is not
  -- visible under search_path '' and silently degrades to case-sensitive text
  -- equality — the defect APP 014 shipped and then had to fix.
  v_email := nullif(lower(trim(p_email)), '');
  if v_email is null then
    raise exception 'invite_org_member: email required' using errcode = '22004';
  end if;

  if exists (
    select 1
      from public.organization_members om
      join public.profiles p on p.id = om.user_id
     where om.organization_id = p_organization_id
       and om.status = 'active'
       and lower(p.email::text) = v_email
  ) then
    raise exception 'ORG_MEMBER_EXISTS' using errcode = '23505', detail = v_email;
  end if;

  if exists (
    select 1 from public.organization_invitations
     where organization_id = p_organization_id
       and lower(email::text) = v_email
       and status = 'sent' and expires_at > now()
  ) then
    raise exception 'ORG_INVITE_PENDING' using errcode = '23505', detail = v_email;
  end if;

  v_token   := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  v_hash    := encode(extensions.digest(v_token::bytea, 'sha256'), 'hex');
  v_expires := now() + make_interval(days => greatest(1, coalesce(p_expires_in_days, 14)));

  insert into public.organization_invitations (
    organization_id, email, role, invited_by_profile_id, status, token_hash, expires_at
  )
  values (
    p_organization_id, v_email::extensions.citext, p_role, v_caller, 'sent', v_hash, v_expires
  )
  returning id into v_inv;

  insert into public.organization_events (
    organization_id, occurred_at, event_type, actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    p_organization_id, now(), 'organization.member.invited', v_caller, 'user',
    'organization_invitation', v_inv, v_email,
    jsonb_build_object('email', v_email, 'role', p_role),
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
  v_email      text;
  v_hash       text;
  v_invitation public.organization_invitations%rowtype;
  v_member_id  uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'accept_org_invitation: authentication required' using errcode = '42501';
  end if;
  if p_token is null or length(p_token) = 0 then
    raise exception 'accept_org_invitation: token required' using errcode = '22004';
  end if;

  select lower(email) into v_email from auth.users where id = v_caller;
  if v_email is null then
    raise exception 'accept_org_invitation: caller has no email on auth.users' using errcode = '23503';
  end if;

  v_hash := encode(extensions.digest(p_token::bytea, 'sha256'), 'hex');

  select * into v_invitation
    from public.organization_invitations
   where token_hash = v_hash
     and status     = 'sent'
     and expires_at > now()
   limit 1;
  if not found then
    raise exception 'accept_org_invitation: invitation not found, expired, revoked, or already accepted'
      using errcode = '42501';
  end if;

  -- The invitation is for an address, not a person. Binding it to whoever
  -- happens to hold the link would let a forwarded email hand over access.
  if lower(v_invitation.email::text) is distinct from v_email then
    raise exception 'accept_org_invitation: invitation email does not match caller'
      using errcode = '42501';
  end if;

  insert into public.organization_members (
    organization_id, user_id, role, status, invited_at, activated_at
  )
  values (
    v_invitation.organization_id, v_caller, v_invitation.role, 'active',
    v_invitation.created_at, now()
  )
  on conflict (organization_id, user_id) do update
    set status       = 'active',
        activated_at = coalesce(organization_members.activated_at, now()),
        removed_at   = null
  returning id into v_member_id;

  update public.organization_invitations
     set status = 'accepted', accepted_at = now()
   where id = v_invitation.id;

  insert into public.organization_events (
    organization_id, occurred_at, event_type, actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    v_invitation.organization_id, now(), 'organization.member.activated', v_caller, 'user',
    'organization_member', v_member_id, v_email,
    jsonb_build_object('invitation_id', v_invitation.id, 'role', v_invitation.role),
    jsonb_build_object('actor_capacity', 'internal')
  );

  return v_member_id;
end;
$function$;

-- Separate from revoke_invitation, which is frozen and only knows the
-- workspace table. Org invitations never reach it.
create or replace function public.revoke_org_invitation(p_invitation_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare v_caller uuid; v_inv public.organization_invitations%rowtype;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'revoke_org_invitation: authentication required' using errcode = '42501';
  end if;
  select * into v_inv from public.organization_invitations where id = p_invitation_id;
  if not found then
    raise exception 'revoke_org_invitation: invitation % not found', p_invitation_id
      using errcode = '23503';
  end if;
  if not public.lign_is_org_admin(v_inv.organization_id) then
    raise exception 'revoke_org_invitation: forbidden' using errcode = '42501';
  end if;
  if v_inv.status <> 'sent' then
    raise exception 'revoke_org_invitation: invitation is % and cannot be revoked', v_inv.status
      using errcode = '23514';
  end if;

  update public.organization_invitations set status = 'revoked' where id = p_invitation_id;

  insert into public.organization_events (
    organization_id, occurred_at, event_type, actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    v_inv.organization_id, now(), 'organization.invitation.revoked', v_caller, 'user',
    'organization_invitation', v_inv.id, v_inv.email::text,
    jsonb_build_object('email', v_inv.email::text, 'role', v_inv.role),
    jsonb_build_object('actor_capacity', 'internal')
  );
end;
$function$;

grant execute on function public.invite_org_member(uuid, text, text, integer) to authenticated;
grant execute on function public.accept_org_invitation(text)                  to authenticated;
grant execute on function public.revoke_org_invitation(uuid)                  to authenticated;