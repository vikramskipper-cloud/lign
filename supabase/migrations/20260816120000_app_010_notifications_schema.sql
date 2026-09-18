-- APP 010: Notifications product-surface additive schema (Migration A).
--
-- Applied to remote (Supabase project hsfporioghapwghrvvzd) as migration
-- version 20260805154249 (app_010_notifications_schema). Filename here uses
-- the freeze-index-mandated timestamp 20260816120000 for local ordering
-- parity with APP 006/007/008/009 filename pattern.
--
-- Delivers per APP_010_BACKEND_PROPOSAL §3–§10:
--   * 1 new wired table (public.notifications) with 19 product-domain columns
--     (21 physical columns counting created_at + updated_at housekeeping)
--   * 9 additive indexes I-1 … I-9 (partial + composite; every FK covered
--     except source_event_id per §6 rationale — INFO advisor only)
--   * 5 additive CHECK constraints (enum stability + payload size cap)
--   * 4 additive FKs (1 composite tenancy on (project_id, workspace_id);
--     3 non-composite on recipient_profile_id, source_event_id, actor_profile_id)
--   * 1 partial unique index (I-7) doubling as dedup constraint per G-7
--   * RLS enabled + 4 policies on notifications (§10.1)
--   * 3 row-local triggers on notifications (immutability, RPC-only-writes,
--     set_updated_at) — ALL NON-SECURITY-DEFINER per F-6
--
-- All additions are additive-only. Frozen surfaces preserved byte-identically:
--   * activity_events schema + append-only triggers (Migration 009)
--   * All APP 001–009 tables, indexes, RLS policies, triggers, RPCs
--
-- The routing bridge trigger on activity_events and the extension of
-- lign_has_capability land in Migration B (app_010_notifications_authz_and_rpcs).

------------------------------------------------------------------------------
-- 1. notifications table (§4.1, §5)
------------------------------------------------------------------------------

create table public.notifications (
  id                    uuid                    primary key default gen_random_uuid(),
  workspace_id          uuid                    not null,
  project_id            uuid                    null,
  recipient_profile_id  uuid                    not null,
  source_event_id       uuid                    not null,
  event_type            text                    not null,
  notification_type     text                    not null,
  category              text                    not null,
  priority              text                    not null default 'medium',
  channels_attempted    text[]                  not null default array['in_app']::text[],
  delivery_state        text                    not null default 'delivered',
  subject_kind          text                    not null,
  subject_id            uuid                    null,
  subject_label         text                    null,
  actor_profile_id      uuid                    null,
  payload               jsonb                   not null default '{}'::jsonb,
  read_at               timestamptz             null,
  dismissed_at          timestamptz             null,
  archived_at           timestamptz             null,
  created_at            timestamptz             not null default now(),
  updated_at            timestamptz             not null default now(),

  constraint notifications_category_check
    check (category in ('assigned_to_me','mentions','project_activity',
                        'governance_state_change','deadlines','system')),
  constraint notifications_priority_check
    check (priority in ('critical','high','medium','low','informational')),
  constraint notifications_delivery_state_check
    check (delivery_state in ('pending','delivered','failed','suppressed')),
  constraint notifications_channels_attempted_check
    check (channels_attempted <@ array['in_app','email_payload','push_payload']::text[]),
  constraint notifications_payload_size_check
    check (octet_length(payload::text) <= 16384)
);

-- Composite tenancy FK reuses APP 003 project composite anchor unique.
alter table public.notifications
  add constraint notifications_recipient_profile_fk
    foreign key (recipient_profile_id) references public.profiles (id) on delete set null,
  add constraint notifications_project_workspace_fk
    foreign key (project_id, workspace_id)
    references public.projects (id, workspace_id) on delete cascade,
  add constraint notifications_source_event_fk
    foreign key (source_event_id) references public.activity_events (id) on delete cascade,
  add constraint notifications_actor_profile_fk
    foreign key (actor_profile_id) references public.profiles (id) on delete set null;

-- I-1 … I-9 (§6). See app_010_notifications_schema DB migration for details.
create index if not exists notifications_unread_by_recipient_idx
  on public.notifications (recipient_profile_id, workspace_id, read_at)
  where read_at is null and dismissed_at is null and archived_at is null
    and priority != 'informational';

create index if not exists notifications_inbox_all_idx
  on public.notifications (recipient_profile_id, workspace_id, created_at desc, id desc)
  where dismissed_at is null and archived_at is null;

create index if not exists notifications_category_idx
  on public.notifications (recipient_profile_id, workspace_id, category, created_at desc)
  where dismissed_at is null and archived_at is null;

create index if not exists notifications_priority_idx
  on public.notifications (recipient_profile_id, workspace_id, priority, created_at desc)
  where dismissed_at is null and archived_at is null;

create index if not exists notifications_archived_idx
  on public.notifications (recipient_profile_id, workspace_id, archived_at desc)
  where archived_at is not null;

create index if not exists notifications_project_scope_idx
  on public.notifications (project_id, workspace_id, created_at desc)
  where project_id is not null;

create unique index if not exists notifications_dedup_uniq_idx
  on public.notifications (recipient_profile_id, source_event_id, notification_type)
  where archived_at is null;

create index if not exists notifications_subject_reverse_idx
  on public.notifications (subject_kind, subject_id, created_at desc)
  where subject_id is not null;

create index if not exists notifications_actor_idx
  on public.notifications (actor_profile_id, workspace_id, created_at desc)
  where actor_profile_id is not null;

------------------------------------------------------------------------------
-- 2. RLS + 4 policies (§10.1)
------------------------------------------------------------------------------

alter table public.notifications enable row level security;

create policy notifications_select on public.notifications
  for select to authenticated
  using (
    recipient_profile_id = (select auth.uid())
    and public.lign_has_capability(project_id, workspace_id, 'notification.view')
    and (
      project_id is null
      or public.lign_project_role(project_id) is not null
      or public.lign_is_workspace_admin(workspace_id)
    )
  );

create policy notifications_insert on public.notifications
  for insert to authenticated with check (false);

create policy notifications_update on public.notifications
  for update to authenticated
  using (recipient_profile_id = (select auth.uid()))
  with check (recipient_profile_id = (select auth.uid()));

create policy notifications_delete on public.notifications
  for delete to authenticated using (false);

------------------------------------------------------------------------------
-- 3. Row-local triggers: immutability, RPC-only-writes, set_updated_at
------------------------------------------------------------------------------
-- Full function bodies applied via Supabase MCP apply_migration. See DB
-- migration app_010_notifications_schema for definitions. Both immutability
-- and RPC-only-write functions are NOT SECURITY DEFINER (row-local; F-6).
-- set_updated_at reuses the frozen APP 001 helper.

-- NOTE: notifications is NOT added to supabase_realtime publication (§25.1).
