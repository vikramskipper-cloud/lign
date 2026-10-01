-- APP 015 — Organisations above workspaces.
--
-- Approved re-freeze of the V1 structural schema: two new tables, one new
-- column, no table dropped or retyped. See docs/APP_015_BACKEND_PROPOSAL.md.
--
-- THE PROBLEM. `owner` was a per-workspace role meaning "can hand over the keys
-- to THIS workspace". There was no role that could see across workspaces, and
-- no tenant above them, so "the owner can view all the workspaces" had nothing
-- to map to.
--
-- THE MECHANISM. Authorization in this database is funnelled through four
-- helper functions; measured against the deployed policies, 69 of 69 resolve
-- through them and ZERO hand-roll a workspace_members check. So org authority
-- is introduced by widening two of those helpers, and all 69 policies inherit
-- it without being touched. lign_has_capability and lign_project_role are NOT
-- modified.
--
-- THE LINE, decided deliberately. Org owners and admins get the nineteen
-- project READ keys and the six workspace member-management keys, exactly what
-- a workspace admin gets, on every workspace in the org. They do NOT get work
-- capabilities: version.upload, version.publish, approval.respond,
-- release.create and review.create still require a project_participants row.
-- An approval recorded against someone who was never a participant is a
-- signature with no basis, and approval_responses is immutable, so that
-- mistake cannot be walked back. Seeing everything and signing anything are
-- different powers; only the first scales upward.
--
-- organization_members.role = 'member' grants NO implicit workspace access. It
-- records that a person belongs to the company; workspace access still comes
-- from workspace_members.
--
-- THE BACKFILL. I wrote this expecting zero workspaces, having just cleared
-- the database, and the NOT NULL add failed: a workspace had been created
-- through the first-run flow in the meantime. So the column is added nullable,
-- every existing workspace is given an organisation of its own, and NOT NULL
-- is set afterwards — which is the shape this needs permanently anyway.
--
-- Promotion is deliberately narrow: only workspace OWNERS become organisation
-- owners. Promoting workspace admins as well would hand them authority over
-- every workspace the organisation gains later, which is not what they were
-- granted. Where a workspace has no active owner — which is how every
-- workspace in this database sat until recently — active admins are promoted
-- instead, and if there is nobody at all the migration ABORTS rather than
-- leave an organisation no human can see.

-- ---------------------------------------------------------------- tables ----

create table public.organizations (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  slug       extensions.citext not null unique,
  status     text not null default 'active' check (status in ('active', 'suspended')),
  settings   jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.organizations is
  'Tenant above workspace. Owns workspaces; org owners/admins can see and administer every workspace it owns, but hold no work capabilities inside projects.';

create table public.organization_members (
  id              uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations (id) on delete restrict,
  user_id         uuid not null references public.profiles (id) on delete restrict,
  role            text not null check (role in ('owner', 'admin', 'member')),
  status          text not null default 'active'
                  check (status in ('invited', 'active', 'suspended', 'removed')),
  invited_at      timestamptz not null default now(),
  activated_at    timestamptz,
  removed_at      timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (organization_id, user_id)
);

comment on column public.organization_members.role is
  'owner and admin both see and administer every workspace in the org; owner additionally controls the owner role itself. member confers NO implicit workspace access.';

-- on delete restrict: deleting an organisation that still owns workspaces must
-- fail loudly rather than orphan or cascade away a tenant's entire estate.
-- Nullable for the length of the backfill below, then NOT NULL.
alter table public.workspaces
  add column organization_id uuid references public.organizations (id) on delete restrict;

do $backfill$
declare
  r      record;
  v_org  uuid;
  v_base text;
  v_slug text;
  v_n    integer;
  v_seats integer;
begin
  for r in
    select id, name, slug::text as slug
      from public.workspaces
     where organization_id is null
     order by created_at
  loop
    v_base := trim(both '-' from regexp_replace(lower(r.slug), '[^a-z0-9]+', '-', 'g'));
    v_base := left(nullif(v_base, ''), 56);
    if v_base is null then
      v_base := 'org';
    end if;
    v_slug := v_base;
    v_n    := 1;
    while exists (select 1 from public.organizations where lower(slug::text) = v_slug) loop
      v_n    := v_n + 1;
      v_slug := v_base || '-' || v_n::text;
    end loop;

    insert into public.organizations (name, slug, status)
    values (r.name, v_slug::extensions.citext, 'active')
    returning id into v_org;

    insert into public.organization_members (
      organization_id, user_id, role, status, invited_at, activated_at
    )
    select v_org, wm.user_id, 'owner', 'active', now(), now()
      from public.workspace_members wm
     where wm.workspace_id = r.id
       and wm.status       = 'active'
       and wm.role         = 'owner'
    on conflict (organization_id, user_id) do nothing;

    get diagnostics v_seats = row_count;

    if v_seats = 0 then
      -- No active owner. Fall back to admins so the organisation is not born
      -- unreachable.
      insert into public.organization_members (
        organization_id, user_id, role, status, invited_at, activated_at
      )
      select v_org, wm.user_id, 'owner', 'active', now(), now()
        from public.workspace_members wm
       where wm.workspace_id = r.id
         and wm.status       = 'active'
         and wm.role         = 'admin'
      on conflict (organization_id, user_id) do nothing;
      get diagnostics v_seats = row_count;
    end if;

    if v_seats = 0 then
      raise exception
        'app_015: workspace % (%) has no active owner or admin — refusing to create an organisation nobody can administer',
        r.name, r.id
        using errcode = '23514';
    end if;

    update public.workspaces set organization_id = v_org where id = r.id;
  end loop;
end $backfill$;

alter table public.workspaces alter column organization_id set not null;

comment on column public.workspaces.organization_id is
  'Owning tenant. NOT NULL from the start — added while the table was empty.';

-- Rule 10: every foreign key gets a covering index.
create index organization_members_organization_id_idx on public.organization_members (organization_id);
create index organization_members_user_id_idx         on public.organization_members (user_id);
-- The shape lign_is_org_admin probes: "is this user an active admin of this org".
create index organization_members_user_org_idx        on public.organization_members (user_id, organization_id)
  where status = 'active';
create index workspaces_organization_id_idx           on public.workspaces (organization_id);

create trigger organizations_set_updated_at
  before update on public.organizations
  for each row execute function public.set_updated_at();

create trigger organization_members_set_updated_at
  before update on public.organization_members
  for each row execute function public.set_updated_at();

-- --------------------------------------------------------------- helpers ----
-- Same shape as lign_is_workspace_member: stable, parallel safe, security
-- definer with an empty search_path. Definer is what lets these read the
-- membership tables without tripping the RLS policies that call them.

create or replace function public.lign_is_org_member(p_organization_id uuid)
returns boolean
language sql
stable parallel safe security definer
set search_path to ''
as $function$
  select exists (
    select 1
      from public.organization_members
     where user_id         = auth.uid()
       and organization_id = p_organization_id
       and status          = 'active'
  );
$function$;

create or replace function public.lign_is_org_admin(p_organization_id uuid)
returns boolean
language sql
stable parallel safe security definer
set search_path to ''
as $function$
  select exists (
    select 1
      from public.organization_members
     where user_id         = auth.uid()
       and organization_id = p_organization_id
       and status          = 'active'
       and role in ('owner', 'admin')
  );
$function$;

create or replace function public.lign_org_of_workspace(p_workspace_id uuid)
returns uuid
language sql
stable parallel safe security definer
set search_path to ''
as $function$
  select organization_id from public.workspaces where id = p_workspace_id;
$function$;

-- ------------------------------------------------------------------- RLS ----

alter table public.organizations enable row level security;
alter table public.organization_members enable row level security;

-- Reads only. Every write goes through the RPCs below, which is how the rest
-- of this schema works (PLATFORM_CHEATSHEET rule 2).
create policy organizations_select_member on public.organizations
  for select to authenticated
  using (public.lign_is_org_member(id));

create policy organization_members_select_org on public.organization_members
  for select to authenticated
  using (public.lign_is_org_member(organization_id));

-- ----------------------------------------------------- widened helpers ------
-- The whole propagation mechanism. Two clauses, and every one of the 69
-- policies starts answering correctly for org admins.
--
-- lign_is_workspace_member gates the `workspaces` SELECT policy, so this is
-- the clause that literally delivers "the owner can view all the workspaces".
--
-- lign_is_workspace_admin is consulted by lign_has_capability for the six
-- workspace keys and the nineteen project read keys, so this is the clause
-- that lets an org admin read every project in the org.

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
  )
  or public.lign_is_org_admin(public.lign_org_of_workspace(p_workspace_id));
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
  )
  or public.lign_is_org_admin(public.lign_org_of_workspace(p_workspace_id));
$function$;

-- ------------------------------------------------------------------ RPCs ----

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

  -- Slug is globally unique, so a name another tenant already took must not
  -- fail someone's first run. Suffix until free, the same way
  -- create_project_full derives project slugs.
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

  -- No activity event: activity_events.workspace_id is NOT NULL, so there is
  -- nowhere to record an organisation-scoped action. Flagged in the APP 015
  -- report rather than worked around by inventing a workspace.

  return v_org;
end;
$function$;

-- create_workspace grows an organisation parameter. The 2-arg version is
-- DROPPED rather than left beside this one: two functions of the same name
-- reachable from PostgREST is the PGRST203 ambiguity that bit create_review,
-- and a default-tail parameter means every existing 2-arg call still resolves.
drop function if exists public.create_workspace(text, text);

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
    -- First run: no organisation named, and the caller belongs to none. Create
    -- both from the one name the welcome screen asked for.
    --
    -- If they DO already belong to an organisation, refuse rather than quietly
    -- starting a second one. Silently creating a parallel tenant is the kind of
    -- mistake that is invisible until two people cannot see each other's work.
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

  -- workspaces_slug_key is UNIQUE(slug) GLOBALLY, not per organisation, so one
  -- tenant's choice of name can block another's. Suffixing keeps creation from
  -- failing on a stranger's slug; making the constraint per-org would mean
  -- dropping a frozen unique key, which is out of scope here and flagged.
  v_base := regexp_replace(lower(coalesce(nullif(trim(coalesce(p_slug, '')), ''), trim(p_name))),
                           '[^a-z0-9]+', '-', 'g');
  v_base := trim(both '-' from v_base);
  v_base := left(nullif(v_base, ''), 56);
  if v_base is null then
    v_base := 'workspace';
  end if;
  v_slug := v_base;
  while exists (
    select 1 from public.workspaces where lower(slug::text) = v_slug
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

-- Org membership management. Included even though no screen drives it yet,
-- because without it an org owner can never appoint a second admin — the same
-- bootstrap dead end that left every workspace in this database ownerless.

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
  -- Only an owner may mint another owner, mirroring the workspace rule.
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
end;
$function$;

-- ---------------------------------------------------------------- grants ----
-- Tables carry blanket DML to authenticated, matching PLATFORM 001; RLS is
-- what actually restricts, and every write path here is an RPC.
grant select, insert, update, delete, truncate, references, trigger
  on table public.organizations to anon, authenticated, service_role;
grant select, insert, update, delete, truncate, references, trigger
  on table public.organization_members to anon, authenticated, service_role;

grant execute on function public.lign_is_org_member(uuid)                to authenticated;
grant execute on function public.lign_is_org_admin(uuid)                 to authenticated;
grant execute on function public.lign_org_of_workspace(uuid)             to authenticated;
grant execute on function public.create_organization(text, text)         to authenticated;
grant execute on function public.create_workspace(text, text, uuid)      to authenticated;
grant execute on function public.add_org_member(uuid, uuid, text)        to authenticated;
grant execute on function public.change_org_member_role(uuid, text)      to authenticated;
grant execute on function public.remove_org_member(uuid)                 to authenticated;