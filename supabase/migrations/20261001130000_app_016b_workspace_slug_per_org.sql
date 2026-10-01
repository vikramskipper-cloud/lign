-- APP 016b — workspace slugs become unique per organisation, not globally.
--
-- workspaces_slug_key was UNIQUE(slug) across the whole table, which predates
-- there being a tenant above workspace. Its effect after APP 015 is that one
-- organisation's choice of name blocks every other organisation's: the first
-- tenant to call a workspace "studio" takes that slug from everyone.
--
-- create_workspace already suffixed around collisions, so nobody was ever
-- blocked outright — but the suffix was answering the wrong question. A second
-- tenant naming their workspace "Studio" would silently get "studio-2", which
-- leaks the existence of someone else's workspace through their own URL.
--
-- Two organisations may now both have a "studio"; one organisation still may
-- not have two. The suffix loop in create_workspace is scoped to match, so it
-- now only fires on a genuine collision inside your own organisation.
--
-- SAFETY. Nothing looks a workspace up BY slug: routing is by uuid
-- (/workspace/:ws_id), and the only reads are display (WorkspacePicker, the
-- settings screen). Grepped before dropping. The new key is strictly weaker,
-- so no existing row can violate it.

alter table public.workspaces drop constraint workspaces_slug_key;

alter table public.workspaces
  add constraint workspaces_organization_slug_key unique (organization_id, slug);

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

  -- Scoped to the organisation, matching the unique key above. Previously this
  -- scanned every workspace in the database, so a stranger's slug pushed you
  -- to "-2" and told you they existed.
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