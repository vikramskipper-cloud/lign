-- Migration 007: approval_model
--
-- Formal Approval data model:
--   1. public.approval_requests           — formal approval on a specific version.
--   2. public.approval_request_approvers  — frozen approver slot roster.
--   3. public.approval_responses          — one immutable response per slot.
--
-- Plus:
--   4. Deferred Comment FK completed: comments.target_approval_request_id
--      → approval_requests(id, workspace_id).
--   5. Deferred Decision FK completed: decisions.target_approval_request_id
--      → approval_requests(id, workspace_id).
--   6. Three structural DB-boundary triggers:
--        - approval-target eligibility (target must be a published version)
--        - approval_response ↔ approver_slot ↔ responder_profile coherence
--        - approval_response immutability (blocks UPDATE and DELETE)
--   7. Covering indexes for every new FK (goal: zero new unindexed_foreign_keys).
--   8. RLS enabled on all three tables with NO policies.
--
-- Architectural notes:
--   - No separate "approvals" aggregate table. The terminal status of an
--     approval_request PLUS its immutable approval_responses IS the outcome
--     record. (DATABASE_SCHEMA.md v0.3 §8, PERMISSIONS.md §10, EVENT_MODEL.md §10.)
--   - Frozen approver set: enforced at the RPC layer (request_approval creates
--     request + slots atomically) plus RLS (denying direct slot inserts to
--     normal users). Not implemented as a static DB constraint in Migration 007.
--     Documented as deferred to the authorization+RPC stages.
--   - MVP status flow (STATE_MACHINES.md v1 §13): request_approval creates
--     directly in 'in_progress'. Schema default 'pending' is preserved as a
--     reserved future value for a possible draft-then-send flow.
--
-- Approval-target eligibility invariant (DB-boundary):
--   Per DATABASE_SCHEMA.md v0.3 §8, an approval_requests.version_id must
--   reference a published asset_versions row. Enforced by a BEFORE INSERT
--   trigger that reads asset_versions.status. SECURITY DEFINER so the
--   lookup bypasses RLS on asset_versions independently of the caller's
--   permissions. version_id is not expected to change post-insert; the
--   trigger fires only on INSERT.
--
-- Approval-response ↔ approver-slot ↔ responder-profile coherence (DB-boundary):
--   Per DATABASE_SCHEMA.md v0.3 §8, responder_profile_id must equal the
--   profile behind the slot: workspace_members.user_id for member slots, or
--   stakeholders.user_id for stakeholder slots (and the stakeholder must
--   have claimed a profile — stakeholders.user_id must be non-null).
--   Enforced by a BEFORE INSERT trigger with SECURITY DEFINER.
--
-- Approval-response immutability (DB-boundary):
--   Rows are frozen at insert. Trigger rejects UPDATE and DELETE with
--   errcode 23514. Standard timestamps are present but never advance.
--
-- Explicit non-goals:
--   - No request_approval / respond_to_approval / finalize_approval /
--     cancel_approval RPCs.
--   - No policy evaluation, terminal-status transition, or expiry cron.
--   - No approval events or notifications.
--   - No releases / activity_events / storage buckets / pg_cron / pg_net.
--   - No RLS policies.
--
-- Historical retention:
--   All FKs from approval tables to parent tables use ON DELETE RESTRICT.
--   Responder profile uses ON DELETE RESTRICT (not SET NULL) — responses
--   are decision-grade artifacts; profile purge is a deliberate ops path.

------------------------------------------------------------------------------
-- 1. approval_requests (DATABASE_SCHEMA.md v0.3 §3.20)
------------------------------------------------------------------------------

create table public.approval_requests (
  id                          uuid                    primary key default gen_random_uuid(),
  workspace_id                uuid                    not null,
  project_id                  uuid                    not null,
  design_asset_id             uuid                    not null,
  version_id                  uuid                    not null,
  policy                      text                    not null,
  status                      text                    not null default 'pending',
  title                       text                    null,
  description                 text                    null,
  due_at                      timestamptz             null,
  sent_at                     timestamptz             null,
  outcome_at                  timestamptz             null,
  outcome_actor_profile_id    uuid                    null references public.profiles (id) on delete set null,
  outcome_note                text                    null,
  created_by_profile_id       uuid                    null references public.profiles (id) on delete set null,
  created_at                  timestamptz             not null default now(),
  updated_at                  timestamptz             not null default now(),

  constraint approval_requests_policy_check
    check (policy in ('any','all')),

  constraint approval_requests_status_check
    check (status in ('pending','in_progress','approved','rejected','cancelled','expired')),

  -- Non-pending rows must carry sent_at.
  constraint approval_requests_sent_metadata_check
    check (status = 'pending' or sent_at is not null),

  -- Terminal rows must carry outcome_at.
  constraint approval_requests_outcome_metadata_check
    check (status not in ('approved','rejected','cancelled','expired') or outcome_at is not null),

  -- Composite tenant/scope FK: request belongs to asset's project + workspace.
  constraint approval_requests_design_asset_fk
    foreign key (design_asset_id, project_id, workspace_id)
    references public.design_assets (id, project_id, workspace_id)
    on delete restrict,

  -- Composite scope FK: version belongs to THIS asset.
  constraint approval_requests_version_fk
    foreign key (version_id, design_asset_id)
    references public.asset_versions (id, design_asset_id)
    on delete restrict,

  -- Composite unique target for downstream (approval_responses,
  -- approval_request_approvers, comments, decisions).
  constraint approval_requests_id_workspace_key unique (id, workspace_id)
);

-- At most one active approval_request per (asset, version).
create unique index approval_requests_active_target_key
  on public.approval_requests (design_asset_id, version_id)
  where status in ('pending','in_progress');

comment on table public.approval_requests is
  'Formal request for approval on a specific version. Terminal status + immutable approval_responses IS the outcome record (no separate approvals aggregate table). MVP policies: any | all. MVP creation enters in_progress directly per STATE_MACHINES.md v1 §13. DATABASE_SCHEMA.md v0.3 §3.20.';
comment on column public.approval_requests.status is
  'MVP transitions: (create) → in_progress → approved | rejected | cancelled | expired. Schema default ''pending'' reserved for a future draft-then-send flow.';
comment on column public.approval_requests.outcome_actor_profile_id is
  'Profile that finalized the request. NULL for system-set outcomes such as ''expired''.';
comment on column public.approval_requests.created_by_profile_id is
  'Profile that created the request. Capability enforcement (approval.request) happens at the RPC/RLS layer, not structurally.';

-- FK covering indexes.
create index approval_requests_design_asset_project_workspace_idx
  on public.approval_requests (design_asset_id, project_id, workspace_id);

create index approval_requests_version_asset_idx
  on public.approval_requests (version_id, design_asset_id);

create index approval_requests_created_by_profile_id_idx
  on public.approval_requests (created_by_profile_id)
  where created_by_profile_id is not null;

create index approval_requests_outcome_actor_profile_id_idx
  on public.approval_requests (outcome_actor_profile_id)
  where outcome_actor_profile_id is not null;

-- Spec-required domain query indexes.
create index approval_requests_asset_status_idx
  on public.approval_requests (design_asset_id, status);

create index approval_requests_workspace_open_due_idx
  on public.approval_requests (workspace_id, status, due_at)
  where status in ('pending','in_progress');

create index approval_requests_project_status_outcome_idx
  on public.approval_requests (project_id, status, outcome_at desc);

create index approval_requests_version_outcome_idx
  on public.approval_requests (version_id, outcome_at desc);

drop trigger if exists approval_requests_set_updated_at on public.approval_requests;
create trigger approval_requests_set_updated_at
  before update on public.approval_requests
  for each row execute function public.set_updated_at();

-- Approval-target eligibility trigger.
create or replace function public.enforce_approval_request_target_eligibility()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_version_status text;
begin
  select status into v_version_status
  from public.asset_versions
  where id = new.version_id;

  if v_version_status is null then
    -- Should be impossible given the composite FK, but defensive.
    raise exception 'enforce_approval_request_target_eligibility: version_id % not found', new.version_id
      using errcode = '23503';
  end if;

  -- MVP eligibility: target must be a published version.
  if v_version_status <> 'published' then
    raise exception 'approval_requests target must be a published version (version_id=%, status=%)', new.version_id, v_version_status
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function public.enforce_approval_request_target_eligibility() is
  'DB-boundary trigger: an approval_requests row may only target an asset_versions row with status=''published''. SECURITY DEFINER so the internal lookup bypasses RLS on asset_versions.';

revoke all on function public.enforce_approval_request_target_eligibility() from public;
revoke all on function public.enforce_approval_request_target_eligibility() from anon;
revoke all on function public.enforce_approval_request_target_eligibility() from authenticated;

drop trigger if exists approval_requests_target_eligibility on public.approval_requests;
create trigger approval_requests_target_eligibility
  before insert on public.approval_requests
  for each row execute function public.enforce_approval_request_target_eligibility();

alter table public.approval_requests enable row level security;

------------------------------------------------------------------------------
-- 2. approval_request_approvers (DATABASE_SCHEMA.md v0.3 §3.21)
------------------------------------------------------------------------------

create table public.approval_request_approvers (
  id                     uuid                    primary key default gen_random_uuid(),
  workspace_id           uuid                    not null,
  approval_request_id    uuid                    not null,
  workspace_member_id    uuid                    null,
  stakeholder_id         uuid                    null,
  sort_order             integer                 not null default 0,
  created_at             timestamptz             not null default now(),
  updated_at             timestamptz             not null default now(),

  constraint approval_request_approvers_actor_xor_check
    check ((workspace_member_id is not null) <> (stakeholder_id is not null)),

  constraint approval_request_approvers_sort_order_check
    check (sort_order >= 0),

  -- Composite tenant FK to approval_requests.
  constraint approval_request_approvers_request_fk
    foreign key (approval_request_id, workspace_id)
    references public.approval_requests (id, workspace_id)
    on delete restrict,

  -- Composite tenant FKs to actor identities.
  constraint approval_request_approvers_workspace_member_fk
    foreign key (workspace_member_id, workspace_id)
    references public.workspace_members (id, workspace_id)
    on delete restrict,

  constraint approval_request_approvers_stakeholder_fk
    foreign key (stakeholder_id, workspace_id)
    references public.stakeholders (id, workspace_id)
    on delete restrict,

  -- Composite unique target for approval_responses composite FK.
  constraint approval_request_approvers_id_request_key unique (id, approval_request_id)
);

comment on table public.approval_request_approvers is
  'Frozen approver-slot roster for an approval_request. First-class historical data. Slot exists at invitation time; the invitee may not yet have authenticated. XOR (workspace_member_id | stakeholder_id). Frozen-set enforcement happens at RPC + RLS layers (see later migrations). DATABASE_SCHEMA.md v0.3 §3.21.';
comment on column public.approval_request_approvers.sort_order is
  'Preserves invitation order. Foundation for future ''sequential'' policy (reserved).';

-- Partial uniques prevent duplicate slots per identity path per request.
create unique index approval_request_approvers_request_member_key
  on public.approval_request_approvers (approval_request_id, workspace_member_id)
  where workspace_member_id is not null;

create unique index approval_request_approvers_request_stakeholder_key
  on public.approval_request_approvers (approval_request_id, stakeholder_id)
  where stakeholder_id is not null;

-- FK covering indexes.
create index approval_request_approvers_request_workspace_idx
  on public.approval_request_approvers (approval_request_id, workspace_id);

create index approval_request_approvers_member_workspace_idx
  on public.approval_request_approvers (workspace_member_id, workspace_id)
  where workspace_member_id is not null;

create index approval_request_approvers_stakeholder_workspace_idx
  on public.approval_request_approvers (stakeholder_id, workspace_id)
  where stakeholder_id is not null;

-- No set_updated_at trigger: slots are frozen once the request is
-- active; updates are not part of MVP flow. If a status/lifecycle field
-- is added to slots in the future, revisit.

alter table public.approval_request_approvers enable row level security;

------------------------------------------------------------------------------
-- 3. approval_responses (DATABASE_SCHEMA.md v0.3 §3.22)
------------------------------------------------------------------------------

create table public.approval_responses (
  id                     uuid                    primary key default gen_random_uuid(),
  workspace_id           uuid                    not null,
  approval_request_id    uuid                    not null,
  approver_slot_id       uuid                    not null,
  responder_profile_id   uuid                    not null references public.profiles (id) on delete restrict,
  decision               text                    not null,
  comment                text                    null,
  responded_at           timestamptz             not null default now(),
  created_at             timestamptz             not null default now(),
  updated_at             timestamptz             not null default now(),

  constraint approval_responses_decision_check
    check (decision in ('approved','rejected','changes_requested')),

  -- Composite scope FK: response's slot must match response's request.
  constraint approval_responses_slot_request_fk
    foreign key (approver_slot_id, approval_request_id)
    references public.approval_request_approvers (id, approval_request_id)
    on delete restrict,

  -- Composite tenant FK to approval_requests.
  constraint approval_responses_request_workspace_fk
    foreign key (approval_request_id, workspace_id)
    references public.approval_requests (id, workspace_id)
    on delete restrict,

  -- Exactly one response per slot.
  constraint approval_responses_slot_key unique (approver_slot_id)
);

comment on table public.approval_responses is
  'One immutable response per approver slot. Decision vocabulary: approved | rejected | changes_requested (no abstain). Frozen at insert (trigger). DATABASE_SCHEMA.md v0.3 §3.22.';
comment on column public.approval_responses.responder_profile_id is
  'Authenticated profile that submitted the response. Coherence with approver_slot enforced by DB-boundary trigger. Stakeholder slots require the stakeholder to have claimed a profile (stakeholders.user_id non-null).';
comment on constraint approval_responses_slot_key on public.approval_responses is
  'Exactly one response per approver slot. Combined with the slot table''s per-request uniques, this yields one response per approver per request.';

-- FK covering indexes.
create index approval_responses_slot_request_idx
  on public.approval_responses (approver_slot_id, approval_request_id);

create index approval_responses_request_workspace_idx
  on public.approval_responses (approval_request_id, workspace_id);

-- Spec-required domain query indexes.
create index approval_responses_request_responded_idx
  on public.approval_responses (approval_request_id, responded_at);

create index approval_responses_responder_profile_id_idx
  on public.approval_responses (responder_profile_id);

alter table public.approval_responses enable row level security;

-- Responder ↔ slot ↔ profile coherence trigger.
create or replace function public.enforce_approval_response_slot_coherence()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_workspace_member_id uuid;
  v_stakeholder_id      uuid;
  v_expected_profile_id uuid;
begin
  -- Look up the slot's identity path.
  select workspace_member_id, stakeholder_id
    into v_workspace_member_id, v_stakeholder_id
    from public.approval_request_approvers
    where id = new.approver_slot_id;

  if not found then
    raise exception 'enforce_approval_response_slot_coherence: approver_slot_id % not found', new.approver_slot_id
      using errcode = '23503';
  end if;

  if v_workspace_member_id is not null then
    select user_id into v_expected_profile_id
      from public.workspace_members
      where id = v_workspace_member_id;
  else
    select user_id into v_expected_profile_id
      from public.stakeholders
      where id = v_stakeholder_id;

    if v_expected_profile_id is null then
      raise exception 'approval_responses cannot be submitted by an unclaimed stakeholder (slot=%, stakeholder=%)',
        new.approver_slot_id, v_stakeholder_id
        using errcode = '23514';
    end if;
  end if;

  if v_expected_profile_id is distinct from new.responder_profile_id then
    raise exception 'approval_responses.responder_profile_id (%) does not match the profile behind approver_slot_id % (expected %)',
      new.responder_profile_id, new.approver_slot_id, v_expected_profile_id
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function public.enforce_approval_response_slot_coherence() is
  'DB-boundary trigger: approval_responses.responder_profile_id must equal the profile behind approver_slot_id (workspace_members.user_id for member slots; stakeholders.user_id for stakeholder slots — requires claimed stakeholder). SECURITY DEFINER so slot/identity lookups bypass RLS.';

revoke all on function public.enforce_approval_response_slot_coherence() from public;
revoke all on function public.enforce_approval_response_slot_coherence() from anon;
revoke all on function public.enforce_approval_response_slot_coherence() from authenticated;

drop trigger if exists approval_responses_slot_coherence on public.approval_responses;
create trigger approval_responses_slot_coherence
  before insert on public.approval_responses
  for each row execute function public.enforce_approval_response_slot_coherence();

-- Response immutability trigger (blocks UPDATE and DELETE).
create or replace function public.enforce_approval_response_immutable()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'approval_responses is immutable after insert; % operation not permitted (row id=%)',
    tg_op,
    case when tg_op = 'DELETE' then old.id else new.id end
    using errcode = '23514';
end;
$$;

comment on function public.enforce_approval_response_immutable() is
  'DB-boundary trigger: approval_responses rows are immutable after insert. UPDATE and DELETE are rejected.';

drop trigger if exists approval_responses_no_update on public.approval_responses;
create trigger approval_responses_no_update
  before update on public.approval_responses
  for each row execute function public.enforce_approval_response_immutable();

drop trigger if exists approval_responses_no_delete on public.approval_responses;
create trigger approval_responses_no_delete
  before delete on public.approval_responses
  for each row execute function public.enforce_approval_response_immutable();

------------------------------------------------------------------------------
-- 4. Complete deferred Comment FK: comments.target_approval_request_id
------------------------------------------------------------------------------

alter table public.comments
  add constraint comments_target_approval_request_fk
    foreign key (target_approval_request_id, workspace_id)
    references public.approval_requests (id, workspace_id)
    on delete restrict;

comment on constraint comments_target_approval_request_fk on public.comments is
  'Deferred from Migration 005 — added when the approval_requests table came online. The seven-way comment target XOR check from Migration 005 is unchanged.';

-- Covering composite index for the new comment FK. Existing
-- comments_target_approval_request_idx (target_approval_request_id, created_at DESC)
-- doesn't match the composite FK column list.
create index if not exists comments_target_approval_request_workspace_idx
  on public.comments (target_approval_request_id, workspace_id)
  where target_approval_request_id is not null;

------------------------------------------------------------------------------
-- 5. Complete deferred Decision FK: decisions.target_approval_request_id
------------------------------------------------------------------------------
-- Composite index (target_approval_request_id, workspace_id) partial was
-- preemptively created in Migration 006 as
-- decisions_target_approval_request_workspace_idx. Adding the FK now
-- consumes that index — no new covering index required.

alter table public.decisions
  add constraint decisions_target_approval_request_fk
    foreign key (target_approval_request_id, workspace_id)
    references public.approval_requests (id, workspace_id)
    on delete restrict;

comment on constraint decisions_target_approval_request_fk on public.decisions is
  'Deferred from Migration 006 — added when the approval_requests table came online. The five-way decision target XOR check from Migration 006 is unchanged.';
