-- Migration 009: activity_events
-- See supabase/migrations/20260729235959_activity_events.sql for full documentation.

create table public.activity_events (
  id                   uuid                    primary key default gen_random_uuid(),
  workspace_id         uuid                    not null references public.workspaces (id) on delete restrict,
  project_id           uuid                    null,
  occurred_at          timestamptz             not null default now(),
  event_type           text                    not null,
  actor_profile_id     uuid                    null references public.profiles (id) on delete set null,
  actor_kind           text                    not null,
  subject_kind         text                    null,
  subject_id           uuid                    null,
  subject_label        text                    null,
  subject_snapshot     jsonb                   not null default '{}'::jsonb,
  payload              jsonb                   not null default '{}'::jsonb,

  constraint activity_events_actor_kind_check
    check (actor_kind in ('user','system')),

  constraint activity_events_actor_coherence_check
    check (
      (actor_kind = 'user'   and actor_profile_id is not null)
      or (actor_kind = 'system' and actor_profile_id is null)
    )
);

comment on table public.activity_events is
  'Append-only historical event log. Powers Design History, Workspace Audit, future notification derivation, and future AI historical context. NOT the source of truth for domain state. DATABASE_SCHEMA.md v0.3 §3.25.';
comment on column public.activity_events.project_id is
  'Nullable. Populated for project-scoped events; NULL for workspace-level admin events. INTENTIONALLY NOT a foreign key.';
comment on column public.activity_events.subject_id is
  'Nullable. INTENTIONALLY NOT a foreign key. subject_label and subject_snapshot preserve historical interpretability.';

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

alter table public.activity_events enable row level security;

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
  'DB-boundary trigger: activity_events rows are strictly append-only. UPDATE and DELETE rejected.';

drop trigger if exists activity_events_no_update on public.activity_events;
create trigger activity_events_no_update
  before update on public.activity_events
  for each row execute function public.enforce_activity_events_append_only();

drop trigger if exists activity_events_no_delete on public.activity_events;
create trigger activity_events_no_delete
  before delete on public.activity_events
  for each row execute function public.enforce_activity_events_append_only();