-- Migration 009: activity_events
--
-- The final structural table for LIGN. After this migration, the public
-- schema is structurally complete and ready for the authorization + RPC
-- stages.
--
-- Contents:
--   1. public.activity_events — append-only historical event log.
--   2. enforce_activity_events_append_only trigger (blocks UPDATE and DELETE).
--   3. RLS enabled with NO policies (authorization stage).
--
-- Architectural principles:
--   - activity_events is a HISTORICAL/AUDIT record, NOT the source of
--     truth for domain state. Domain tables remain authoritative.
--   - Append-only. UPDATE and DELETE rejected via trigger.
--   - Deliberately non-FK on subject_id and project_id: the audit log
--     must remain readable even if the original subject is later
--     unavailable. This preserves durable historical readability.
--   - Actor attribution is Profile-based (post-v0.3 actor-model change).
--     No workspace_member/stakeholder XOR on event rows.
--   - subject_snapshot captures minimal durable context (e.g., asset name
--     and version sequence at emit time). Not a copy of the row.
--   - No generic AFTER trigger event sourcing on domain tables. Events
--     are SEMANTIC and will be emitted transactionally by controlled
--     RPCs in later migrations.
--
-- Ownership boundaries:
--   - Workspace scope: every event has workspace_id NOT NULL and a FK
--     to workspaces ON DELETE RESTRICT.
--   - Project scope: project_id NULLABLE. Populated for project-level
--     events; NULL for workspace-level admin events. NOT a foreign key
--     per DATABASE_SCHEMA.md v0.3 §3.25 — audit rows must survive
--     project deletion.
--   - Subject: subject_id is NOT a foreign key. Any (subject_kind,
--     subject_id) pair may refer to a row that later disappears.
--     subject_label and subject_snapshot preserve interpretability.
--
-- Actor model (frozen v0.3):
--   - actor_kind ∈ ('user','system').
--   - user events: actor_kind='user', actor_profile_id NOT NULL.
--   - system events: actor_kind='system', actor_profile_id NULL.
--     Enforced by check constraint.
--
-- Event vocabulary (EVENT_MODEL.md v1):
--   - event_type is a plain text column, not a native PG enum.
--     The 56 P0 event names live in application code; adding new event
--     types does not require a DB migration.
--
-- Index strategy (spec-required):
--   - (workspace_id, occurred_at DESC)               — workspace timeline
--     (also covers workspace_id FK cascade lookups by leading column)
--   - (workspace_id, event_type, occurred_at DESC)   — workspace by event type
--   - (project_id, occurred_at DESC) WHERE project_id IS NOT NULL
--                                                    — project timeline (v0.3)
--   - (subject_kind, subject_id, occurred_at DESC) WHERE subject_id IS NOT NULL
--                                                    — history of a subject
--   - (actor_profile_id, occurred_at DESC) WHERE actor_profile_id IS NOT NULL
--                                                    — profile activity;
--     also covers actor_profile_id FK by leading column.
--
-- Explicit non-goals:
--   - No notifications table, no email queue, no webhook dispatch.
--   - No AI infrastructure (no pgvector, no embeddings, no summaries).
--   - No storage buckets, no pg_cron, no pg_net.
--   - No generic domain-table AFTER triggers.
--   - No business RPCs to emit events.
--   - No RLS policies.
--   - No new domain tables beyond activity_events.

------------------------------------------------------------------------------
-- 1. activity_events (DATABASE_SCHEMA.md v0.3 §3.25)
------------------------------------------------------------------------------

create table public.activity_events (
  id                   uuid                    primary key default gen_random_uuid(),
  workspace_id         uuid                    not null references public.workspaces (id) on delete restrict,
  project_id           uuid                    null,        -- deliberately NOT a foreign key
  occurred_at          timestamptz             not null default now(),
  event_type           text                    not null,
  actor_profile_id     uuid                    null references public.profiles (id) on delete set null,
  actor_kind           text                    not null,
  subject_kind         text                    null,
  subject_id           uuid                    null,        -- deliberately NOT a foreign key
  subject_label        text                    null,
  subject_snapshot     jsonb                   not null default '{}'::jsonb,
  payload              jsonb                   not null default '{}'::jsonb,

  constraint activity_events_actor_kind_check
    check (actor_kind in ('user','system')),

  -- Actor coherence: user events require actor_profile_id; system events
  -- must not carry one.
  constraint activity_events_actor_coherence_check
    check (
      (actor_kind = 'user'   and actor_profile_id is not null)
      or (actor_kind = 'system' and actor_profile_id is null)
    )
);

comment on table public.activity_events is
  'Append-only historical event log. Powers Project Design History, Workspace Audit, future notification derivation, and future AI historical context. NOT the source of truth for domain state — domain tables remain authoritative. DATABASE_SCHEMA.md v0.3 §3.25.';
comment on column public.activity_events.project_id is
  'Nullable. Populated for project-scoped events; NULL for workspace-level admin events. INTENTIONALLY NOT a foreign key — audit rows must survive project deletion (v0.3 addition per PERMISSIONS.md §15.1).';
comment on column public.activity_events.subject_id is
  'Nullable. INTENTIONALLY NOT a foreign key. Any (subject_kind, subject_id) pair may refer to a row that later disappears. subject_label and subject_snapshot preserve historical interpretability.';
comment on column public.activity_events.subject_label is
  'Immutable human-readable snapshot of the subject at emit time (e.g., "Kitchen Layout · v3").';
comment on column public.activity_events.subject_snapshot is
  'Minimal structured snapshot of subject fields required to interpret the event historically. NOT a copy of the entire row. Populated by the emitting RPC.';
comment on column public.activity_events.payload is
  'Per-event-type structured detail (e.g., version sequence, approval decision). Not a copy of the subject.';
comment on column public.activity_events.event_type is
  'Plain text discriminator (e.g., ''version.published''). Not a PG enum — adding event types does not require a migration. EVENT_MODEL.md v1 §4 defines the P0 vocabulary; application code owns the valid set.';

-- Spec-required indexes.
create index activity_events_workspace_occurred_idx
  on public.activity_events (workspace_id, occurred_at desc);

create index activity_events_workspace_type_occurred_idx
  on public.activity_events (workspace_id, event_type, occurred_at desc);

create index activity_events_project_occurred_idx
  on public.activity_events (project_id, occurred_at desc)
  where project_id is not null;

create index activity_events_subject_occurred_idx
  on public.activity_events (subject_kind, subject_id, occurred_at desc)
  where subject_id is not null;

create index activity_events_actor_occurred_idx
  on public.activity_events (actor_profile_id, occurred_at desc)
  where actor_profile_id is not null;

-- No set_updated_at trigger: rows are immutable. No updated_at column
-- exists in this table per DATABASE_SCHEMA.md v0.3 §3.25 (only occurred_at
-- and DEFAULT-populated implicit created).

alter table public.activity_events enable row level security;

------------------------------------------------------------------------------
-- 2. Append-only trigger
------------------------------------------------------------------------------

create or replace function public.enforce_activity_events_append_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'activity_events is append-only; % operation not permitted (row id=%)',
    tg_op,
    case when tg_op = 'DELETE' then old.id else new.id end
    using errcode = '23514';
end;
$$;

comment on function public.enforce_activity_events_append_only() is
  'DB-boundary trigger: activity_events rows are strictly append-only. UPDATE and DELETE are rejected via ordinary application paths. Operational purge (if ever needed) is a deliberate admin operation.';

drop trigger if exists activity_events_no_update on public.activity_events;
create trigger activity_events_no_update
  before update on public.activity_events
  for each row execute function public.enforce_activity_events_append_only();

drop trigger if exists activity_events_no_delete on public.activity_events;
create trigger activity_events_no_delete
  before delete on public.activity_events
  for each row execute function public.enforce_activity_events_append_only();
