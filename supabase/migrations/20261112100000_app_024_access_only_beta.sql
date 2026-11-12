-- APP 024: access-only beta. Historical applications have no company; do not
-- invent one. Pending legacy applicants must resubmit before approval.
alter table public.access_requests add column company text
  check (company is null or (length(trim(company)) between 1 and 120));

-- Remove the old callable signature, so anonymous clients cannot omit company.
drop function public.submit_access_request(text, text, text, text, text);

create or replace function public.submit_access_request(
  p_name         text,
  p_email        text,
  p_phone        text,
  p_company_role text,
  p_team_size    text,
  p_company      text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_name text; v_email text; v_phone text; v_role text; v_existing uuid; v_company text;
begin
  v_name  := trim(coalesce(p_name, ''));
  v_email := lower(trim(coalesce(p_email, '')));
  v_phone := nullif(trim(coalesce(p_phone, '')), '');
  v_role  := trim(coalesce(p_company_role, ''));
  v_company := trim(coalesce(p_company, ''));
  if v_company = '' or length(v_company) > 120 then
    raise exception 'submit_access_request: company is required (120 characters max)' using errcode = '22023';
  end if;
  if v_phone is null then
    raise exception 'submit_access_request: phone required' using errcode = '22004';
  end if;

  if v_name = '' then
    raise exception 'submit_access_request: name required' using errcode = '22004';
  end if;
  if length(v_name) > 120 then
    raise exception 'submit_access_request: name exceeds 120 characters' using errcode = '22001';
  end if;
  if v_email = '' then
    raise exception 'submit_access_request: email required' using errcode = '22004';
  end if;
  if length(v_email) > 254 or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'submit_access_request: email is not a valid address' using errcode = '22023';
  end if;
  if v_role = '' then
    raise exception 'submit_access_request: company role required' using errcode = '22004';
  end if;
  if length(v_role) > 120 then
    raise exception 'submit_access_request: company role exceeds 120 characters' using errcode = '22001';
  end if;
  if v_phone is not null and length(v_phone) > 40 then
    raise exception 'submit_access_request: phone exceeds 40 characters' using errcode = '22001';
  end if;
  -- Checked here as well as by the column constraint so the caller gets a
  -- named error instead of a constraint name.
  if coalesce(p_team_size, '') not in ('1', '2-5', '6-20', '21-50', '51-200', '200+') then
    raise exception 'submit_access_request: team_size must be one of 1, 2-5, 6-20, 21-50, 51-200, 200+'
      using errcode = '22023';
  end if;

  if exists (select 1 from public.access_requests
              where lower(email::text) = v_email and status = 'approved') then
    return;
  end if;

  -- Serialize by email; concurrent resubmissions update one pending request.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_email, 24));
  select id into v_existing from public.access_requests
   where lower(email::text) = v_email and status = 'pending' for update;
  if v_existing is not null then
    update public.access_requests
       set name = v_name, phone = v_phone, company = v_company,
           company_role = v_role, team_size = p_team_size
     where id = v_existing;
    return;
  end if;
  insert into public.access_requests (name, email, phone, company, company_role, team_size)
  values (v_name, v_email::extensions.citext, v_phone, v_company, v_role, p_team_size);

  insert into public.email_outbox (to_email, template, payload)
  values (v_email::extensions.citext, 'access_request_received', jsonb_build_object('name', v_name));
end;
$function$;

revoke all on function public.submit_access_request(text, text, text, text, text, text) from public;
grant execute on function public.submit_access_request(text, text, text, text, text, text)
  to anon, authenticated, service_role;

comment on function public.submit_access_request(text, text, text, text, text, text) is
  'Public beta access application. Always succeeds for a well-formed submission, whether or not the address has applied before — a "you already applied" response would be an enumeration oracle. A resubmission while pending updates the details and queues no further email.';


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

  if p_approve and not exists (
    select 1 from public.access_requests where id = p_request_id and company is not null
  ) then
    raise exception 'Company name is missing. Ask the applicant to resubmit before approval.' using errcode = '22023';
  end if;
  insert into public.email_outbox (to_email, template, payload, dedupe_key)
  values (v_email, case when p_approve then 'access_request_approved' else 'access_request_declined' end,
          jsonb_build_object('name', v_name, 'request_id', p_request_id),
          'access-decision:' || p_request_id::text);
end;
$function$;

comment on function public.decide_access_request(uuid, boolean, text) is
  'LIGN staff decision. Approval queues a welcome email with secure password activation.';

-- Called after password setup. Uses only the authenticated, verified identity;
-- no caller-selected email, organisation or owner ID. Locks make retries safe.
create or replace function public.complete_approved_access()
returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare
  v_request public.access_requests%rowtype;
  v_org uuid;
  v_workspace uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;
  if not exists (select 1 from auth.users where id = auth.uid() and email_confirmed_at is not null) then
    raise exception 'Verify your email before activation' using errcode = '42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(auth.uid()::text, 24));
  select r.* into v_request
    from public.access_requests r join public.profiles p on lower(p.email::text) = lower(r.email::text)
   where p.id = auth.uid() and r.status = 'approved'
   -- Prefer an already-founded company if historical duplicate approvals exist.
   order by (r.founded_organization_id is null), r.decided_at, r.id limit 1 for update of r;
  if not found then return null; end if; -- Invited members use their claim route.
  v_org := v_request.founded_organization_id;
  if v_org is null then
    if v_request.company is null then
      raise exception 'Company name is missing; contact LIGN' using errcode = '22023';
    end if;
    v_org := public.create_organization(v_request.company);
  end if;
  if not exists (select 1 from public.organization_members
                  where organization_id = v_org and user_id = auth.uid() and role = 'owner' and status = 'active') then
    raise exception 'Organisation owner required' using errcode = '42501';
  end if;
  select id into v_workspace from public.workspaces where organization_id = v_org order by created_at limit 1;
  if v_workspace is null then
    v_workspace := public.create_workspace(v_request.company, null, v_org);
  end if;
  return v_workspace;
end;
$function$;
revoke all on function public.complete_approved_access() from public, anon;
grant execute on function public.complete_approved_access() to authenticated;

-- Service-only leases prevent two workers from rotating/sending the same link.
alter table public.email_outbox add column locked_until timestamptz;
alter table public.email_outbox add column lock_token uuid;

create or replace function public.claim_email_batch(p_outbox_id uuid default null)
returns setof public.email_outbox
language plpgsql security definer set search_path = ''
as $function$
begin
  -- Exhausted jobs whose worker crashed are visible as failures, not stuck.
  update public.email_outbox set status = 'failed', locked_until = null, lock_token = null,
         last_error = 'Delivery attempts exhausted'
   where status = 'queued' and attempts >= 5 and (locked_until is null or locked_until < now());
  return query
  with jobs as (
    select id from public.email_outbox
     where status = 'queued' and attempts < 5
       and (locked_until is null or locked_until < now())
       and (p_outbox_id is null or id = p_outbox_id)
     order by created_at limit 10 for update skip locked
  )
  update public.email_outbox q
     set locked_until = now() + interval '10 minutes',
         lock_token = gen_random_uuid(), attempts = attempts + 1
    from jobs where q.id = jobs.id returning q.*;
end;
$function$;
revoke all on function public.claim_email_batch(uuid) from public, anon, authenticated;
grant execute on function public.claim_email_batch(uuid) to service_role;

-- A deliberate resend mints a fresh link. Normal delivery retries retain the
-- previous link; retries must not invalidate a welcome message already sent.
create or replace function public.resend_access_welcome(p_request_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $function$
declare v_request public.access_requests%rowtype;
begin
  if not public.lign_is_platform_admin() then
    raise exception 'LIGN platform administrators only' using errcode = '42501';
  end if;
  select * into v_request from public.access_requests where id = p_request_id and status = 'approved' for update;
  if not found then raise exception 'Approved request not found' using errcode = '22023'; end if;
  insert into public.email_outbox (to_email, template, payload, dedupe_key)
  values (v_request.email, 'access_request_approved', jsonb_build_object('name', v_request.name, 'request_id', p_request_id),
          'access-decision:' || p_request_id::text)
  on conflict (dedupe_key) where dedupe_key is not null do update
    set status = 'queued', sent_at = null, attempts = 0, last_error = null,
        payload = excluded.payload, locked_until = null, lock_token = null
    where public.email_outbox.locked_until is null or public.email_outbox.locked_until < now();
end;
$function$;
revoke all on function public.resend_access_welcome(uuid) from public, anon;
grant execute on function public.resend_access_welcome(uuid) to authenticated;
