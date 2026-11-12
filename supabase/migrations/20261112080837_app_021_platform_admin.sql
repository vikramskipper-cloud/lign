-- APP 021 — separate the LIGN platform operator from a customer's
-- organisation administrator. Corrects APP 020.
--
-- THE DEFECT. APP 020 gated access_requests and email_outbox on "owner or
-- admin of an organisation". That conflated two roles that must never be the
-- same people:
--
--   organisation owner/admin   runs a CUSTOMER's company inside LIGN
--   platform admin             runs LIGN itself, and decides who gets in
--
-- A request for access is vendor data: it is a stranger's name, work email,
-- phone number and company role, submitted before they belong to anything. As
-- written, every customer org admin could read the full list of everyone
-- applying to LIGN, and approve or decline them. That is other people's
-- personal data handed to a tenant, and an onboarding decision handed to the
-- wrong party.
--
-- It is latent today only because this instance holds one organisation whose
-- owner also happens to be the operator. It becomes a real leak the first time
-- a customer is made an org admin — which is the normal case.
--
-- THE FIX. A membership that sits OUTSIDE the organisation hierarchy
-- altogether, because that is the honest shape: platform operators are not a
-- senior tier of the customer tree, they are beside it. Nothing in
-- organizations, workspaces or projects grants it, and holding it grants no
-- access to any customer's work — it is deliberately not a superuser role.
-- Reading a project still requires a project capability, exactly as before.
--
-- FAILS CLOSED. platform_admins starts EMPTY, so immediately after this runs
-- nobody can read the queue — including the account that could yesterday. That
-- is intentional: a bootstrap that auto-promoted "the first org owner" would
-- re-make the exact conflation this migration exists to undo. Grant the first
-- operator with ops/grant_platform_admin.sql.
--
-- NO POLICY IS DROPPED. The two APP 020 policies are repointed in place with
-- ALTER POLICY ... USING and renamed to match, so this migration contains no
-- destructive statement and the tables are never briefly unprotected.

-- ------------------------------------------------------------- the operators
create table public.platform_admins (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  granted_at timestamptz not null default now(),
  granted_by_profile_id uuid references public.profiles (id),
  note text
);

comment on table public.platform_admins is
  'LIGN staff who operate the platform: they triage access requests and decide who is admitted. Deliberately OUTSIDE the organisation hierarchy — no org, workspace or project role grants it, and holding it grants no access to any customer project. Starts empty; seed with ops/grant_platform_admin.sql.';

-- Rule 10: every FK covered. (profile_id is the primary key, so it already is.)
create index platform_admins_granted_by_idx
  on public.platform_admins (granted_by_profile_id);

alter table public.platform_admins enable row level security;

grant select, insert, update, delete, truncate, references, trigger
  on table public.platform_admins to anon, authenticated, service_role;

-- ------------------------------------------------------------------ the test
-- One flat query, no nesting. APP 016a measured a nested SECURITY DEFINER call
-- on an RLS path at 14x the inlined cost; this is a single primary-key probe
-- against a table holding a handful of rows.
create or replace function public.lign_is_platform_admin()
returns boolean
language sql
stable
parallel safe
security definer
set search_path to ''
as $function$
  select exists (
    select 1 from public.platform_admins pa where pa.profile_id = auth.uid()
  );
$function$;

comment on function public.lign_is_platform_admin() is
  'True when the caller operates LIGN itself. Unrelated to every organisation, workspace and project role — it grants no access to customer work, only to platform administration surfaces.';

revoke all on function public.lign_is_platform_admin() from public;
revoke all on function public.lign_is_platform_admin() from anon;
-- Granted to authenticated so the client can ask "should I render the admin
-- surface at all". The answer is a courtesy; the policies below are the control.
grant execute on function public.lign_is_platform_admin() to authenticated, service_role;

-- Operators can see who else is one. Nobody can write from the client: there
-- is no INSERT, UPDATE or DELETE policy, and no RPC. Granting this role is a
-- deliberate out-of-band act, not a button — it is the role that decides who
-- uses the product.
--
-- The predicate MUST go through the function rather than querying this table
-- directly. `using (exists (select 1 from platform_admins ...))` is the
-- obvious spelling and it is wrong: evaluating the policy reads the table,
-- which evaluates the policy, and Postgres stops it with 42P17 "infinite
-- recursion detected in policy". Caught in the dry run, on the read that lists
-- operators. lign_is_platform_admin is SECURITY DEFINER and so runs as the
-- owner, for whom RLS does not apply — which breaks the cycle.
create policy platform_admins_select_self on public.platform_admins
  for select to authenticated
  using (public.lign_is_platform_admin());

-- ------------------------------------------------------- repoint APP 020 RLS
-- ALTER, not DROP + CREATE: the predicate is swapped atomically and the table
-- is never left without a policy.
alter policy access_requests_select_org_admin on public.access_requests
  using (public.lign_is_platform_admin());
alter policy access_requests_select_org_admin on public.access_requests
  rename to access_requests_select_platform_admin;

alter policy email_outbox_select_org_admin on public.email_outbox
  using (public.lign_is_platform_admin());
alter policy email_outbox_select_org_admin on public.email_outbox
  rename to email_outbox_select_platform_admin;

-- ---------------------------------------------------------- repoint the RPC
-- Same signature, so CREATE OR REPLACE. Only the authority test changes; the
-- single-decision rule, the row lock and the queued outcome email are as
-- APP 020 left them.
create or replace function public.decide_access_request(
  p_request_id uuid,
  p_approve    boolean,
  p_note       text default null
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_caller uuid; v_email extensions.citext; v_name text; v_status text;
begin
  v_caller := auth.uid();
  if v_caller is null then
    raise exception 'decide_access_request: authentication required' using errcode = '42501';
  end if;
  if p_request_id is null then
    raise exception 'decide_access_request: request_id required' using errcode = '22004';
  end if;
  if p_approve is null then
    raise exception 'decide_access_request: approve must be true or false' using errcode = '22004';
  end if;

  -- The correction. Was: owner or admin of any organisation — a customer.
  if not public.lign_is_platform_admin() then
    raise exception 'decide_access_request: forbidden (LIGN platform administrators only)'
      using errcode = '42501';
  end if;

  select email, name, status into v_email, v_name, v_status
    from public.access_requests where id = p_request_id for update;
  if v_email is null then
    raise exception 'decide_access_request: request % not found', p_request_id using errcode = '23503';
  end if;
  -- Deciding twice is refused rather than silently overwritten: the second
  -- decision would erase who made the first one and when.
  if v_status <> 'pending' then
    raise exception 'decide_access_request: request % is already %', p_request_id, v_status
      using errcode = '23514';
  end if;

  update public.access_requests
     set status = case when p_approve then 'approved' else 'rejected' end,
         note = nullif(trim(coalesce(p_note, '')), ''),
         decided_by_profile_id = v_caller,
         decided_at = now()
   where id = p_request_id;

  -- Approval queues the "you're in" message. It does NOT issue an invitation:
  -- whether an approved applicant joins an organisation or a single project as
  -- an external is a per-person decision, and the invite RPCs for both already
  -- exist. Inventing a default here would silently hand out the wrong level of
  -- access.
  insert into public.email_outbox (to_email, template, payload)
  values (v_email, case when p_approve then 'access_request_approved' else 'access_request_declined' end,
          jsonb_build_object('name', v_name));
end;
$function$;

comment on function public.decide_access_request(uuid, boolean, text) is
  'Records a LIGN platform administrator''s decision on a beta access request and queues the outcome email. Organisation and workspace roles confer no authority here — see APP 021. Deliberately does not issue an invitation.';
