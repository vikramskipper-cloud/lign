-- APP 020 — request access: the destination for the link the sign-in page has
-- been promising.
--
-- The front door already says "Access is invite-only during the beta ...
-- request access" and the link has pointed at href="#" since it was written.
-- This is the other end of it.
--
-- TWO TABLES, AND WHY THE SECOND ONE.
--
-- access_requests holds the application. email_outbox holds "a message should
-- go to this address", queued and unsent. SendGrid is deliberately not wired
-- yet, and the alternative to a queue was to pretend: either fire nothing and
-- let the UI claim an email was sent, or bolt the provider in now. A queue is
-- the honest seam — the row exists, carries everything the template needs, and
-- a drainer added later sends it without any change to this migration or to
-- the form. Until then the outbox is a to-send list an admin can read.
--
-- WRITES GO THROUGH ONE DEFINER RPC, NOT AN INSERT POLICY (rule 2). The form
-- is public, so a table-level INSERT policy for anon would let anyone write
-- arbitrary rows — any status, any decided_by, any column this migration adds
-- later. submit_access_request is the only writer and it chooses what a
-- stranger may set. access_requests has NO insert and NO update policy at all;
-- its SELECT policy is org admins only, so the form cannot read back what it
-- wrote and the table is not an email directory.
--
-- NON-ENUMERATION. Submitting always succeeds, whether or not that address has
-- applied before, already has an account, or was rejected last week. A form
-- that says "you have already applied" is a free oracle for whether an address
-- is known to us, and the only thing it buys the honest user is a message they
-- do not need.
--
-- CITEXT, CAREFULLY. email is citext for consistency with profiles.email, but
-- every comparison here is written as an explicit lower(...) on text. Under
-- `search_path = ''` the citext `=` operator is NOT visible, so a bare `=`
-- silently degrades to case-SENSITIVE text equality — which is exactly how
-- APP 014 created a duplicate stakeholder for Client@Acme.example. The partial
-- unique index below is on lower(email::text) for the same reason: it must
-- agree with the RPC's own test, not with citext's.
--
-- RATE LIMITING: NONE, and that is a known gap rather than an oversight. An
-- anon-callable RPC can be called in a loop with distinct addresses. Postgres
-- has nowhere good to put a per-IP limit (the IP is not in the session), so
-- this needs either an edge function in front or Supabase's own API gateway
-- limits. For an invite-only beta the blast radius is junk rows in a table
-- only an admin reads. Flagged, not papered over.

-- ------------------------------------------------------------------ the queue
create table public.email_outbox (
  id         uuid primary key default gen_random_uuid(),
  to_email   extensions.citext not null,
  template   text not null,
  payload    jsonb not null default '{}'::jsonb,
  status     text not null default 'queued' check (status in ('queued', 'sent', 'failed')),
  attempts   integer not null default 0,
  last_error text,
  created_at timestamptz not null default now(),
  sent_at    timestamptz,
  -- A sent message must say when, and an unsent one must not claim to have.
  constraint email_outbox_sent_at_coherent check (
    (status = 'sent' and sent_at is not null) or (status <> 'sent' and sent_at is null)
  )
);

comment on table public.email_outbox is
  'Messages that should be delivered, queued for a sender that does not exist yet. Drained by a future edge function holding the SendGrid key; nothing in the database sends mail.';

create index email_outbox_pending_idx
  on public.email_outbox (created_at) where status = 'queued';

-- ------------------------------------------------------------ the application
create table public.access_requests (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  email        extensions.citext not null,
  phone        text,
  company_role text not null,
  team_size    text not null check (team_size in ('1', '2-5', '6-20', '21-50', '51-200', '200+')),
  status       text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  note         text,
  created_at   timestamptz not null default now(),
  decided_by_profile_id uuid references public.profiles (id),
  decided_at   timestamptz,
  -- A pending row has no decision attached, and a decided one records when.
  -- Without this the triage screen cannot trust either field.
  constraint access_requests_decision_coherent check (
    (status =  'pending' and decided_at is null and decided_by_profile_id is null)
    or
    (status <> 'pending' and decided_at is not null)
  )
);

comment on table public.access_requests is
  'Beta access applications from the public request-access form. Written only by submit_access_request and decided only by decide_access_request; readable only by organisation owners and admins.';

-- One live application per address. Partial, so a rejected applicant can
-- reapply later and the history of earlier decisions is kept rather than
-- overwritten. On lower(email::text) to agree with the RPC — see the citext
-- note in the header.
create unique index access_requests_one_pending_per_email
  on public.access_requests (lower(email::text)) where status = 'pending';

create index access_requests_triage_idx
  on public.access_requests (status, created_at desc);

-- Rule 10: every FK covered.
create index access_requests_decided_by_idx
  on public.access_requests (decided_by_profile_id);

-- --------------------------------------------------------------------- RLS ---
alter table public.access_requests enable row level security;
alter table public.email_outbox    enable row level security;

-- Org owners and admins, and nobody else. Written flat rather than through
-- lign_is_org_admin(lign_org_of_workspace(...)) because APP 016a measured a
-- nested SECURITY DEFINER call on an RLS path at 14x the cost of the inlined
-- query, and there is no workspace here to resolve an org from anyway.
create policy access_requests_select_org_admin on public.access_requests
  for select to authenticated
  using (
    exists (
      select 1 from public.organization_members m
       where m.user_id = auth.uid()
         and m.status  = 'active'
         and m.role in ('owner', 'admin')
    )
  );

-- Same audience. Visible so an admin can see what is waiting to go out and
-- why a send failed; never writable from the client.
create policy email_outbox_select_org_admin on public.email_outbox
  for select to authenticated
  using (
    exists (
      select 1 from public.organization_members m
       where m.user_id = auth.uid()
         and m.status  = 'active'
         and m.role in ('owner', 'admin')
    )
  );

grant select, insert, update, delete, truncate, references, trigger
  on table public.access_requests to anon, authenticated, service_role;
grant select, insert, update, delete, truncate, references, trigger
  on table public.email_outbox to anon, authenticated, service_role;

-- ------------------------------------------------------------------ submit ---
-- Callable by anon: this is the public form. It is the ONLY way a row enters
-- access_requests, which is why it validates rather than trusting.
create or replace function public.submit_access_request(
  p_name         text,
  p_email        text,
  p_phone        text,
  p_company_role text,
  p_team_size    text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_name text; v_email text; v_phone text; v_role text; v_existing uuid;
begin
  v_name  := trim(coalesce(p_name, ''));
  v_email := lower(trim(coalesce(p_email, '')));
  v_phone := nullif(trim(coalesce(p_phone, '')), '');
  v_role  := trim(coalesce(p_company_role, ''));

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

  -- lower() on both sides, explicitly: see the citext note in the header.
  select id into v_existing
    from public.access_requests
   where lower(email::text) = v_email
     and status = 'pending'
   limit 1;

  if v_existing is not null then
    -- A resubmission while still pending is a correction, not a new
    -- application: update the details in place and queue NO second email.
    -- Queueing one per submit would turn the public form into a mailer
    -- pointed at any address a stranger types.
    update public.access_requests
       set name = v_name, phone = v_phone, company_role = v_role, team_size = p_team_size
     where id = v_existing;
    return;
  end if;

  insert into public.access_requests (name, email, phone, company_role, team_size)
  values (v_name, v_email::extensions.citext, v_phone, v_role, p_team_size);

  -- Only the name. Carrying company_role and team_size here would freeze a
  -- snapshot that a later resubmission silently makes stale: the queued mail
  -- would greet them with the title they first typed, not the corrected one.
  insert into public.email_outbox (to_email, template, payload)
  values (v_email::extensions.citext, 'access_request_received',
          jsonb_build_object('name', v_name));
end;
$function$;

revoke all on function public.submit_access_request(text, text, text, text, text) from public;
grant execute on function public.submit_access_request(text, text, text, text, text)
  to anon, authenticated, service_role;

comment on function public.submit_access_request(text, text, text, text, text) is
  'Public beta access application. Always succeeds for a well-formed submission, whether or not the address has applied before — a "you already applied" response would be an enumeration oracle. A resubmission while pending updates the details and queues no further email.';

-- ------------------------------------------------------------------ decide ---
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

  -- Flat, for the reason given on the SELECT policy above.
  if not exists (
    select 1 from public.organization_members m
     where m.user_id = v_caller
       and m.status  = 'active'
       and m.role in ('owner', 'admin')
  ) then
    raise exception 'decide_access_request: forbidden (organisation owner or admin only)'
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
  -- whether an approved applicant joins the organisation or a single project
  -- as an external is a per-person decision, and the invite RPCs for both
  -- already exist. Inventing a default here would silently hand out the wrong
  -- level of access.
  insert into public.email_outbox (to_email, template, payload)
  values (v_email, case when p_approve then 'access_request_approved' else 'access_request_declined' end,
          jsonb_build_object('name', v_name));
end;
$function$;

revoke all on function public.decide_access_request(uuid, boolean, text) from public;
revoke all on function public.decide_access_request(uuid, boolean, text) from anon;
grant execute on function public.decide_access_request(uuid, boolean, text)
  to authenticated, service_role;

comment on function public.decide_access_request(uuid, boolean, text) is
  'Records an organisation admin''s decision on a beta access request and queues the outcome email. Deliberately does not issue an invitation — org vs project-external is a separate, explicit choice.';
