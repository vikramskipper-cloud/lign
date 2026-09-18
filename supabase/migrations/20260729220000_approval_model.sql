-- Migration 007: approval_model
-- See supabase/migrations/20260729220000_approval_model.sql for full documentation.

------------------------------------------------------------------------------
-- 1. approval_requests
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

  constraint approval_requests_sent_metadata_check
    check (status = 'pending' or sent_at is not null),

  constraint approval_requests_outcome_metadata_check
    check (status not in ('approved','rejected','cancelled','expired') or outcome_at is not null),

  constraint approval_requests_design_asset_fk
    foreign key (design_asset_id, project_id, workspace_id)
    references public.design_assets (id, project_id, workspace_id)
    on delete restrict,

  constraint approval_requests_version_fk
    foreign key (version_id, design_asset_id)
    references public.asset_versions (id, design_asset_id)
    on delete restrict,

  constraint approval_requests_id_workspace_key unique (id, workspace_id)
);

create unique index approval_requests_active_target_key
  on public.approval_requests (design_asset_id, version_id)
  where status in ('pending','in_progress');

comment on table public.approval_requests is
  'Formal request for approval on a specific version. Terminal status + immutable approval_responses IS the outcome (no separate approvals aggregate table). DATABASE_SCHEMA.md v0.3 §3.20.';

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
    raise exception 'enforce_approval_request_target_eligibility: version_id % not found', new.version_id
      using errcode = '23503';
  end if;

  if v_version_status <> 'published' then
    raise exception 'approval_requests target must be a published version (version_id=%, status=%)', new.version_id, v_version_status
      using errcode = '23514';
  end if;

  return new;
end;
$$;

comment on function public.enforce_approval_request_target_eligibility() is
  'DB-boundary trigger: approval_requests may only target a published asset_version. SECURITY DEFINER so the internal lookup bypasses RLS.';

revoke all on function public.enforce_approval_request_target_eligibility() from public;
revoke all on function public.enforce_approval_request_target_eligibility() from anon;
revoke all on function public.enforce_approval_request_target_eligibility() from authenticated;

drop trigger if exists approval_requests_target_eligibility on public.approval_requests;
create trigger approval_requests_target_eligibility
  before insert on public.approval_requests
  for each row execute function public.enforce_approval_request_target_eligibility();

alter table public.approval_requests enable row level security;

------------------------------------------------------------------------------
-- 2. approval_request_approvers
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

  constraint approval_request_approvers_request_fk
    foreign key (approval_request_id, workspace_id)
    references public.approval_requests (id, workspace_id)
    on delete restrict,

  constraint approval_request_approvers_workspace_member_fk
    foreign key (workspace_member_id, workspace_id)
    references public.workspace_members (id, workspace_id)
    on delete restrict,

  constraint approval_request_approvers_stakeholder_fk
    foreign key (stakeholder_id, workspace_id)
    references public.stakeholders (id, workspace_id)
    on delete restrict,

  constraint approval_request_approvers_id_request_key unique (id, approval_request_id)
);

comment on table public.approval_request_approvers is
  'Frozen approver-slot roster. XOR (workspace_member_id | stakeholder_id). Frozen-set enforcement lives at RPC + RLS layers. DATABASE_SCHEMA.md v0.3 §3.21.';

create unique index approval_request_approvers_request_member_key
  on public.approval_request_approvers (approval_request_id, workspace_member_id)
  where workspace_member_id is not null;

create unique index approval_request_approvers_request_stakeholder_key
  on public.approval_request_approvers (approval_request_id, stakeholder_id)
  where stakeholder_id is not null;

create index approval_request_approvers_request_workspace_idx
  on public.approval_request_approvers (approval_request_id, workspace_id);

create index approval_request_approvers_member_workspace_idx
  on public.approval_request_approvers (workspace_member_id, workspace_id)
  where workspace_member_id is not null;

create index approval_request_approvers_stakeholder_workspace_idx
  on public.approval_request_approvers (stakeholder_id, workspace_id)
  where stakeholder_id is not null;

alter table public.approval_request_approvers enable row level security;

------------------------------------------------------------------------------
-- 3. approval_responses
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

  constraint approval_responses_slot_request_fk
    foreign key (approver_slot_id, approval_request_id)
    references public.approval_request_approvers (id, approval_request_id)
    on delete restrict,

  constraint approval_responses_request_workspace_fk
    foreign key (approval_request_id, workspace_id)
    references public.approval_requests (id, workspace_id)
    on delete restrict,

  constraint approval_responses_slot_key unique (approver_slot_id)
);

comment on table public.approval_responses is
  'One immutable response per approver slot. Decision vocabulary: approved | rejected | changes_requested. DATABASE_SCHEMA.md v0.3 §3.22.';

create index approval_responses_slot_request_idx
  on public.approval_responses (approver_slot_id, approval_request_id);

create index approval_responses_request_workspace_idx
  on public.approval_responses (approval_request_id, workspace_id);

create index approval_responses_request_responded_idx
  on public.approval_responses (approval_request_id, responded_at);

create index approval_responses_responder_profile_id_idx
  on public.approval_responses (responder_profile_id);

alter table public.approval_responses enable row level security;

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
  'DB-boundary trigger: approval_responses.responder_profile_id must equal the profile behind approver_slot_id. SECURITY DEFINER for cross-table lookups.';

revoke all on function public.enforce_approval_response_slot_coherence() from public;
revoke all on function public.enforce_approval_response_slot_coherence() from anon;
revoke all on function public.enforce_approval_response_slot_coherence() from authenticated;

drop trigger if exists approval_responses_slot_coherence on public.approval_responses;
create trigger approval_responses_slot_coherence
  before insert on public.approval_responses
  for each row execute function public.enforce_approval_response_slot_coherence();

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
  'DB-boundary trigger: approval_responses rows are immutable after insert. UPDATE and DELETE rejected.';

drop trigger if exists approval_responses_no_update on public.approval_responses;
create trigger approval_responses_no_update
  before update on public.approval_responses
  for each row execute function public.enforce_approval_response_immutable();

drop trigger if exists approval_responses_no_delete on public.approval_responses;
create trigger approval_responses_no_delete
  before delete on public.approval_responses
  for each row execute function public.enforce_approval_response_immutable();

------------------------------------------------------------------------------
-- 4. Complete deferred Comment FK
------------------------------------------------------------------------------

alter table public.comments
  add constraint comments_target_approval_request_fk
    foreign key (target_approval_request_id, workspace_id)
    references public.approval_requests (id, workspace_id)
    on delete restrict;

comment on constraint comments_target_approval_request_fk on public.comments is
  'Deferred from Migration 005 — added when the approval_requests table came online. Seven-way comment target XOR unchanged.';

create index if not exists comments_target_approval_request_workspace_idx
  on public.comments (target_approval_request_id, workspace_id)
  where target_approval_request_id is not null;

------------------------------------------------------------------------------
-- 5. Complete deferred Decision FK
------------------------------------------------------------------------------
-- Covering index decisions_target_approval_request_workspace_idx was
-- preemptively created in Migration 006.

alter table public.decisions
  add constraint decisions_target_approval_request_fk
    foreign key (target_approval_request_id, workspace_id)
    references public.approval_requests (id, workspace_id)
    on delete restrict;

comment on constraint decisions_target_approval_request_fk on public.decisions is
  'Deferred from Migration 006 — added when the approval_requests table came online. Five-way decision target XOR unchanged.';