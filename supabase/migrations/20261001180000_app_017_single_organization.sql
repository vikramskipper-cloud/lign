-- APP 017 — LIGN holds exactly one organisation.
--
-- THE DECISION. One organisation, many workspaces under it, many projects in
-- each workspace. The organisation is the company; it is not a tenant slot to
-- be handed out.
--
-- WHAT WAS WRONG. create_organization would make one for anybody who asked,
-- and /welcome asks on behalf of any signed-in account with no organisation.
-- Measured against the live database: a stranger signs in, sees zero
-- organisations — correctly, because RLS hides one they do not belong to — and
-- create_workspace(null org) succeeds, leaving two organisations behind.
--
-- That failure is invisible from inside. Each side sees a working product with
-- one organisation and its own workspaces; neither can see the other, and
-- nothing reports that the company has been split in half. Whoever noticed
-- would notice it as "my colleague's projects are missing".
--
-- THE GUARD. create_organization now refuses when an organisation already
-- exists. Deliberately a count over the whole table, not an RLS-filtered read:
-- the question is "has this deployment been set up", which has nothing to do
-- with what the caller can see, and SECURITY DEFINER is what lets it be asked
-- honestly.
--
-- Relaxing this later is deleting one IF block. Recovering from two
-- organisations that have both accumulated work is not.

-- Lets the client tell "already set up, ask for an invitation" apart from
-- "nothing here yet, name your organisation". The two look identical to an
-- orgless account through RLS, which is why /welcome could not decide for
-- itself and offered a form that was about to fail.
--
-- Leaks exactly one bit — whether the deployment has been initialised — and no
-- name, id or count. An unauthenticated caller gets nothing: the grant is to
-- authenticated only.
create or replace function public.lign_organization_exists()
returns boolean
language sql
stable security definer
set search_path to ''
as $function$
  select exists (select 1 from public.organizations);
$function$;

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

  -- The singleton guard. Raised before any validation so the answer does not
  -- depend on what was submitted.
  if exists (select 1 from public.organizations) then
    raise exception 'ORG_ALREADY_EXISTS' using errcode = '42501',
      detail = 'LIGN holds one organisation. Ask an administrator for an invitation.';
  end if;

  v_name := trim(coalesce(p_name, ''));
  if length(v_name) = 0 then
    raise exception 'create_organization: name required' using errcode = '22004';
  end if;
  if length(v_name) > 120 then
    raise exception 'create_organization: name exceeds 120 characters' using errcode = '22001';
  end if;

  -- Retained although the table can now only ever hold one row: this function
  -- is the only writer, and a slug loop that assumes uniqueness is cheaper to
  -- keep than to re-derive if the singleton rule is ever relaxed.
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

grant execute on function public.lign_organization_exists() to authenticated;