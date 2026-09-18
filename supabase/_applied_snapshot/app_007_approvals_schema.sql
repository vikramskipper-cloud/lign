
-- APP 007 (Approvals) — Schema
--
-- Additive backend re-freeze for APP 007 Approvals. Implements the frozen
-- APP_007_BACKEND_PROPOSAL.md schema surface. All changes are additive;
-- APP 001-006 tables/RPCs/policies remain byte-identical (see §Preservation).

------------------------------------------------------------------------------
-- 1. approval_requests — new columns
------------------------------------------------------------------------------

alter table public.approval_requests
  add column if not exists expires_at                     timestamptz null,
  add column if not exists related_review_id              uuid        null,
  add column if not exists supersedes_approval_request_id uuid        null,
  add column if not exists root_approval_request_id       uuid        null,
  add column if not exists quorum_min                     integer     null,
  add column if not exists cancellation_reason            text        null;

comment on column public.approval_requests.expires_at is
  'APP 007: hard deadline. Non-terminal requests auto-expire past this via cron (deferred to cron slice).';
comment on column public.approval_requests.related_review_id is
  'APP 007: informational loose FK to APP 006 review. Never enforced by release/requirement layers.';
comment on column public.approval_requests.supersedes_approval_request_id is
  'APP 007: chain parent. Non-null on supersession requests; NULL on chain roots. Immutable after insert (chain trigger).';
comment on column public.approval_requests.root_approval_request_id is
  'APP 007: chain root. Self on roots; parent''s root on supersessions. Must be set inline at INSERT (F-7.1). Immutable.';
comment on column public.approval_requests.quorum_min is
  'APP 007: minimum required approvals when policy=quorum. NULL otherwise.';
comment on column public.approval_requests.cancellation_reason is
  'APP 007: mandatory-on-cancel audit reason (D-8 posture mirrored from APP 006).';

-- Backfill pre-existing cancelled test rows before applying the mandatory CHECK.
-- No production data; test fixtures only.
update public.approval_requests
   set cancellation_reason = coalesce(outcome_note, 'legacy cancellation (pre-APP-007 backfill)')
 where status = 'cancelled' and cancellation_reason is null;

------------------------------------------------------------------------------
-- 2. approval_requests — CHECK constraints
------------------------------------------------------------------------------

alter table public.approval_requests
  drop constraint if exists approval_requests_status_check;
alter table public.approval_requests
  add constraint approval_requests_status_check
    check (status in (
      'draft','pending','in_progress',
      'approved','rejected','cancelled','expired','superseded'
    ));

alter table public.approval_requests
  drop constraint if exists approval_requests_policy_check;
alter table public.approval_requests
  add constraint approval_requests_policy_check
    check (policy in (
      'any','all',
      'single','unanimous','majority','quorum','sequential'
    ));

alter table public.approval_requests
  drop constraint if exists approval_requests_sent_metadata_check;
alter table public.approval_requests
  add constraint approval_requests_sent_metadata_check
    check (status in ('draft','pending') or sent_at is not null);

alter table public.approval_requests
  drop constraint if exists approval_requests_outcome_metadata_check;
alter table public.approval_requests
  add constraint approval_requests_outcome_metadata_check
    check (
      status not in ('approved','rejected','cancelled','expired','superseded')
      or outcome_at is not null
    );

alter table public.approval_requests
  drop constraint if exists approval_requests_chain_integrity_check;
alter table public.approval_requests
  add constraint approval_requests_chain_integrity_check
    check (
      (supersedes_approval_request_id is null
        and (root_approval_request_id is null or root_approval_request_id = id))
      or
      (supersedes_approval_request_id is not null
        and root_approval_request_id is not null)
    );

alter table public.approval_requests
  drop constraint if exists approval_requests_quorum_min_check;
alter table public.approval_requests
  add constraint approval_requests_quorum_min_check
    check ((policy <> 'quorum') or (quorum_min is not null and quorum_min > 0));

alter table public.approval_requests
  drop constraint if exists approval_requests_cancellation_reason_check;
alter table public.approval_requests
  add constraint approval_requests_cancellation_reason_check
    check (
      (status <> 'cancelled')
      or (cancellation_reason is not null and length(cancellation_reason) between 3 and 500)
    );

------------------------------------------------------------------------------
-- 3. approval_requests — composite tenancy FKs for chain + review link
------------------------------------------------------------------------------

alter table public.approval_requests
  drop constraint if exists approval_requests_supersedes_fk;
alter table public.approval_requests
  add constraint approval_requests_supersedes_fk
    foreign key (supersedes_approval_request_id, workspace_id)
    references public.approval_requests (id, workspace_id)
    on delete restrict;

alter table public.approval_requests
  drop constraint if exists approval_requests_root_fk;
alter table public.approval_requests
  add constraint approval_requests_root_fk
    foreign key (root_approval_request_id, workspace_id)
    references public.approval_requests (id, workspace_id)
    on delete restrict;

alter table public.approval_requests
  drop constraint if exists approval_requests_related_review_fk;
alter table public.approval_requests
  add constraint approval_requests_related_review_fk
    foreign key (related_review_id, workspace_id)
    references public.reviews (id, workspace_id)
    on delete set null;

------------------------------------------------------------------------------
-- 4. approval_request_approvers — new columns
------------------------------------------------------------------------------

alter table public.approval_request_approvers
  add column if not exists required        boolean     not null default true,
  add column if not exists veto_power      boolean     not null default false,
  add column if not exists removed_at      timestamptz null,
  add column if not exists removed_reason  text        null;

comment on column public.approval_request_approvers.required is
  'APP 007: required vs optional approver. Required approvers block outcome computation; optional are courtesy-notified.';
comment on column public.approval_request_approvers.veto_power is
  'APP 007: per-approver veto flag. Composes orthogonally with any base policy.';
comment on column public.approval_request_approvers.removed_at is
  'APP 007: soft-removal timestamp. Preserves audit trail for approvers who already responded.';
comment on column public.approval_request_approvers.removed_reason is
  'APP 007: mandatory reason accompanying removed_at (paired via CHECK).';

alter table public.approval_request_approvers
  drop constraint if exists approval_request_approvers_removal_pair_check;
alter table public.approval_request_approvers
  add constraint approval_request_approvers_removal_pair_check
    check (
      (removed_at is null and removed_reason is null)
      or (removed_at is not null and removed_reason is not null
          and length(removed_reason) between 3 and 500)
    );

------------------------------------------------------------------------------
-- 5. approval_responses — decision enum widening + mandatory reason
------------------------------------------------------------------------------

-- 5a. Decision enum widening — adds 'abstained' (F-2.1)
alter table public.approval_responses
  drop constraint if exists approval_responses_decision_check;
alter table public.approval_responses
  add constraint approval_responses_decision_check
    check (decision in ('approved','rejected','abstained','changes_requested'));

-- 5b. Mandatory reason via widened comment CHECK (F-2.2)
-- The frozen enforce_approval_response_immutable trigger (Migration 007
-- L403-L427) blocks any UPDATE — including a schema-migration backfill of
-- comment. Temporarily disable the UPDATE-blocking trigger for the
-- backfill, then re-enable. DELETE-blocking trigger is unaffected.
alter table public.approval_responses disable trigger approval_responses_no_update;

update public.approval_responses
   set comment = 'legacy response (pre-APP-007 backfill)'
 where comment is null or length(coalesce(comment, '')) < 3;

alter table public.approval_responses enable trigger approval_responses_no_update;

alter table public.approval_responses
  drop constraint if exists approval_responses_comment_reason_check;
alter table public.approval_responses
  add constraint approval_responses_comment_reason_check
    check (length(coalesce(comment, '')) between 3 and 2000);

-- 5c. New columns: decision_metadata (v2), is_veto_cast (denormalized)
alter table public.approval_responses
  add column if not exists decision_metadata jsonb   null,
  add column if not exists is_veto_cast      boolean not null default false;

comment on column public.approval_responses.decision_metadata is
  'APP 007: reserved for v2 e-signature / IP / device-fingerprint capture. No UI in v1.';
comment on column public.approval_responses.is_veto_cast is
  'APP 007: denormalized flag — true when a rejected decision was cast by an approver with veto_power=true.';

alter table public.approval_responses
  drop constraint if exists approval_responses_veto_cast_consistency_check;
alter table public.approval_responses
  add constraint approval_responses_veto_cast_consistency_check
    check ((is_veto_cast = false) or (decision = 'rejected'));

------------------------------------------------------------------------------
-- 6. Indexes
------------------------------------------------------------------------------

create index if not exists approval_requests_root_id_idx
  on public.approval_requests (root_approval_request_id)
  where root_approval_request_id is not null;

create index if not exists approval_requests_supersedes_id_idx
  on public.approval_requests (supersedes_approval_request_id)
  where supersedes_approval_request_id is not null;

create index if not exists approval_requests_related_review_id_idx
  on public.approval_requests (related_review_id)
  where related_review_id is not null;

create index if not exists approval_requests_root_workspace_idx
  on public.approval_requests (root_approval_request_id, workspace_id)
  where root_approval_request_id is not null;

create index if not exists approval_requests_supersedes_workspace_idx
  on public.approval_requests (supersedes_approval_request_id, workspace_id)
  where supersedes_approval_request_id is not null;

create index if not exists approval_requests_related_review_workspace_idx
  on public.approval_requests (related_review_id, workspace_id)
  where related_review_id is not null;

create index if not exists approval_requests_project_status_updated_idx
  on public.approval_requests (project_id, status, updated_at desc);

create index if not exists approval_requests_workspace_status_updated_idx
  on public.approval_requests (workspace_id, status, updated_at desc);

create index if not exists approval_requests_version_status_idx
  on public.approval_requests (version_id, status);

create index if not exists approval_requests_expires_at_partial_idx
  on public.approval_requests (expires_at)
  where status in ('pending','in_progress') and expires_at is not null;

create index if not exists approval_request_approvers_request_required_idx
  on public.approval_request_approvers (approval_request_id, required)
  where removed_at is null;

create index if not exists approval_responses_responder_idx
  on public.approval_responses (responder_profile_id, responded_at desc);

------------------------------------------------------------------------------
-- 7. Chain-immutability trigger (BEFORE UPDATE)
------------------------------------------------------------------------------

create or replace function public.enforce_approval_requests_chain_immutable()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.supersedes_approval_request_id is distinct from old.supersedes_approval_request_id then
    raise exception 'approval_requests.supersedes_approval_request_id is immutable after insert (chain integrity)'
      using errcode = '23514';
  end if;
  if new.root_approval_request_id is distinct from old.root_approval_request_id then
    raise exception 'approval_requests.root_approval_request_id is immutable after insert (chain integrity)'
      using errcode = '23514';
  end if;
  if new.related_review_id is distinct from old.related_review_id then
    raise exception 'approval_requests.related_review_id is immutable after insert (F-10.2)'
      using errcode = '23514';
  end if;
  return new;
end $$;

comment on function public.enforce_approval_requests_chain_immutable() is
  'APP 007: defense-in-depth trigger enforcing chain-column immutability after insert. F-10.2 immutable set: supersedes, root, related_review_id.';

revoke all on function public.enforce_approval_requests_chain_immutable() from public;
revoke all on function public.enforce_approval_requests_chain_immutable() from anon;
revoke all on function public.enforce_approval_requests_chain_immutable() from authenticated;

drop trigger if exists approval_requests_chain_immutable on public.approval_requests;
create trigger approval_requests_chain_immutable
  before update on public.approval_requests
  for each row execute function public.enforce_approval_requests_chain_immutable();

------------------------------------------------------------------------------
-- 8. No-self-approve trigger (BEFORE INSERT)
------------------------------------------------------------------------------

create or replace function public.enforce_approval_responses_no_self_approve()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_created_by uuid;
begin
  select created_by_profile_id into v_created_by
    from public.approval_requests
   where id = new.approval_request_id;

  if v_created_by is null then
    raise exception 'enforce_approval_responses_no_self_approve: approval_request % not found', new.approval_request_id
      using errcode = '23503';
  end if;

  if v_created_by = new.responder_profile_id then
    raise exception 'approval_responses: requester cannot respond to their own approval request (F-2.4, D-11)'
      using errcode = '23514';
  end if;

  return new;
end $$;

comment on function public.enforce_approval_responses_no_self_approve() is
  'APP 007: DB-boundary trigger enforcing requester-cannot-self-approve (Freeze Index D-11). Defense-in-depth mirroring APP 006.';

revoke all on function public.enforce_approval_responses_no_self_approve() from public;
revoke all on function public.enforce_approval_responses_no_self_approve() from anon;
revoke all on function public.enforce_approval_responses_no_self_approve() from authenticated;

drop trigger if exists approval_responses_no_self_approve on public.approval_responses;
create trigger approval_responses_no_self_approve
  before insert on public.approval_responses
  for each row execute function public.enforce_approval_responses_no_self_approve();
