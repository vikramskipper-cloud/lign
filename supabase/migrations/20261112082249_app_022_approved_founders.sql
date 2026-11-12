-- APP 022 — one organisation per APPROVED APPLICANT, not one per deployment.
-- Reverses the APP 017 singleton and gives "request access" its purpose.
--
-- WHAT CHANGED ABOVE THE DATABASE. The product model is now explicit:
--
--   * An org owner or admin ADDS people to their own organisation. Those people
--     are emailed, sign in, and join the workspace or project they were added
--     to. That path already exists (invite_org_member, workspace and
--     stakeholder invitations) and is untouched here.
--
--   * A NEW owner — someone who wants to try LIGN and bring their own company —
--     uses the public request-access form. A LIGN platform administrator
--     approves it. Request access exists FOR AND ONLY FOR founding a new
--     organisation.
--
-- APP 017 made that impossible. It allowed exactly one organisation per
-- deployment, so approving an applicant could only ever have meant adding them
-- to somebody else's company. The singleton was right for a one-customer beta
-- and is wrong for this model, so it goes.
--
-- REMOVING IT WITHOUT OPENING THE DOOR. The singleton was doing two jobs: it
-- capped the tenant count, and it stopped any signed-in stranger from creating
-- a company. Only the first job is obsolete. Deleting the guard outright would
-- mean anyone who can reach /sign-up could found an organisation — and signup
-- is open at the auth server (disable_signup: false), so that is everyone.
--
-- So the guard is REPLACED rather than removed: creating an organisation now
-- requires an entitlement, and the only things that grant one are
--
--   1. an APPROVED access request matching the caller's own email address, or
--   2. being a LIGN platform administrator, so staff can provision directly.
--
-- The approval IS the entitlement — there is no second token to issue, expire
-- or leak, and the audit trail is the access request itself. One approval
-- founds one organisation: access_requests.founded_organization_id records
-- which, and a consumed approval cannot be spent twice.
--
-- EMAIL MATCHING. The caller's profile email must equal the applied-for
-- address. Applying as ada@studio.example and signing up as ada@gmail.com
-- yields no entitlement, which is the same rule accept_invitation already
-- enforces. Matched on explicit lower(...) over text on both sides: both
-- columns are citext, and inside a function with search_path='' the citext '='
-- operator is invisible and silently degrades to case-SENSITIVE text equality.
-- That is the defect that duplicated a stakeholder in APP 014.
--
-- lign_organization_exists() is left in place but is now vestigial — "has this
-- deployment been initialised" stopped being the question that decides whether
-- somebody may create a company. lign_may_found_organization() is what the
-- welcome screen should ask instead.

-- -------------------------------------------------- the approval is the grant
alter table public.access_requests
  add column founded_organization_id uuid references public.organizations (id);

comment on column public.access_requests.founded_organization_id is
  'The organisation this approval was spent founding, null while unspent. One approved request founds exactly one organisation; this column is what makes the entitlement single-use, and it is the audit link from a company back to the application that created it.';

-- Rule 10: every FK covered.
create index access_requests_founded_org_idx
  on public.access_requests (founded_organization_id);

-- ------------------------------------------------------------- may I found? --
-- Asked by the welcome screen so it can tell "name your company" from "you are
-- waiting on approval". The answer is a courtesy; create_organization re-checks
-- it and is the control.
--
-- Leaks one bit about the caller's OWN application and nothing about anyone
-- else's, which is why it is safe to grant to authenticated while
-- access_requests itself stays readable only by platform admins.
create or replace function public.lign_may_found_organization()
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select
    public.lign_is_platform_admin()
    or exists (
      select 1
        from public.access_requests r
        join public.profiles p on lower(p.email::text) = lower(r.email::text)
       where p.id = auth.uid()
         and r.status = 'approved'
         and r.founded_organization_id is null
    );
$function$;

comment on function public.lign_may_found_organization() is
  'True when the caller holds an unspent approved access request for their own email address, or is a LIGN platform administrator. Nothing else permits founding an organisation.';

revoke all on function public.lign_may_found_organization() from public;
revoke all on function public.lign_may_found_organization() from anon;
grant execute on function public.lign_may_found_organization() to authenticated, service_role;

-- ------------------------------------------------- create_organization, re-gated
-- Same signature, so CREATE OR REPLACE. Everything after the guard — the name
-- checks, the slug loop, the owner membership, the organization.created event —
-- is APP 017's, unchanged.
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
  v_caller  uuid;
  v_name    text;
  v_base    text;
  v_slug    text;
  v_n       integer := 1;
  v_org     uuid;
  v_request uuid;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'create_organization: authentication required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.profiles where id = v_caller) then
    raise exception 'create_organization: caller profile % not found', v_caller using errcode = '23503';
  end if;

  -- Was: refuse if ANY organisation exists (APP 017's singleton). Now: refuse
  -- unless this caller is entitled. Claimed with FOR UPDATE so two concurrent
  -- attempts cannot both spend the same approval and found two companies from
  -- one application.
  --
  -- Platform admins skip the claim entirely: they are provisioning, not
  -- spending an entitlement, and consuming somebody's approval on their behalf
  -- would make the audit trail say the applicant founded it.
  if not public.lign_is_platform_admin() then
    select r.id into v_request
      from public.access_requests r
      join public.profiles p on lower(p.email::text) = lower(r.email::text)
     where p.id = v_caller
       and r.status = 'approved'
       and r.founded_organization_id is null
     order by r.decided_at
     limit 1
       for update of r;

    if v_request is null then
      raise exception 'ORG_NOT_PERMITTED' using errcode = '42501',
        detail = 'Creating an organisation needs an approved access request for this email address.';
    end if;
  end if;

  v_name := trim(coalesce(p_name, ''));
  if length(v_name) = 0 then
    raise exception 'create_organization: name required' using errcode = '22004';
  end if;
  if length(v_name) > 120 then
    raise exception 'create_organization: name exceeds 120 characters' using errcode = '22001';
  end if;

  -- The slug loop now earns its keep: APP 017 kept it on the argument that the
  -- singleton rule might one day be relaxed. It has been.
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

  -- Spend the approval. After this the same request cannot found a second
  -- organisation, and the company is traceable back to the application.
  if v_request is not null then
    update public.access_requests
       set founded_organization_id = v_org
     where id = v_request;
  end if;

  insert into public.organization_events (
    organization_id, occurred_at, event_type, actor_profile_id, actor_kind,
    subject_kind, subject_id, subject_label, subject_snapshot, payload
  )
  values (
    v_org, now(), 'organization.created', v_caller, 'user',
    'organization', v_org, v_name,
    jsonb_build_object('name', v_name, 'slug', v_slug),
    -- Records HOW it came to exist: spent an approved application, or was
    -- provisioned by LIGN staff. Worth having on the permanent record.
    jsonb_build_object('actor_capacity', 'internal',
                       'founded_via', case when v_request is not null
                                           then 'access_request' else 'platform_admin' end,
                       'access_request_id', v_request)
  );

  return v_org;
end;
$function$;
