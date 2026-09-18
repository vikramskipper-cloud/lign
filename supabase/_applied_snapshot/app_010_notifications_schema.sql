-- APP 010: Notifications product-surface additive schema (Migration A).
--
-- Delivers per APP_010_BACKEND_PROPOSAL §3–§10:
--   * 1 new wired table (public.notifications) with 19 product-domain columns
--     (21 physical columns counting created_at + updated_at housekeeping)
--   * 9 additive indexes I-1 … I-9 (partial + composite; every FK covered)
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

  -- CHECK constraints (§7.1–§7.5)
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

comment on table public.notifications is
  'APP 010 §4.1: per-recipient delivery record. Every row represents one delivered notification for one recipient about one source activity_event. Row lifecycle: delivered → read → (dismissed | archived). Payload materialized at INSERT time; immutable except for read_at/dismissed_at/archived_at/updated_at.';

comment on column public.notifications.id is
  'APP 010 §5.1: primary key. Immutable after INSERT.';
comment on column public.notifications.workspace_id is
  'APP 010 §5.2: tenant scope. Copied verbatim from activity_events.workspace_id at INSERT time. Immutable.';
comment on column public.notifications.project_id is
  'APP 010 §5.3: project scope for project-scoped source events. NULL for workspace-scoped events (mirrors activity_events.project_id NULL-per-scope). Immutable.';
comment on column public.notifications.recipient_profile_id is
  'APP 010 §5.4: recipient. Primary axis of RLS (recipient_profile_id = auth.uid()). FK → profiles(id) ON DELETE SET NULL. Immutable.';
comment on column public.notifications.source_event_id is
  'APP 010 §5.5: originating activity_events.id. FK → activity_events(id) ON DELETE CASCADE. Non-composite because activity_events has PK only on (id). Immutable.';
comment on column public.notifications.event_type is
  'APP 010 §5.6: denormalized copy of activity_events.event_type. Powers filter-by-source-module without joining. Immutable.';
comment on column public.notifications.notification_type is
  'APP 010 §5.7: notification.*-typed classification (e.g. review.assigned_to_you). Distinct from event_type. Enum-validity enforced in router body; no DB CHECK to keep additive types cheap. Immutable.';
comment on column public.notifications.category is
  'APP 010 §5.8 / §6: high-level grouping. Enum enforced via CHECK. Immutable.';
comment on column public.notifications.priority is
  'APP 010 §5.9 / §7: priority ladder. Immutable per row (no decay).';
comment on column public.notifications.channels_attempted is
  'APP 010 §5.10 / G-4: attempted channels. v1 always {in_app}; router adds email_payload / push_payload when routing rule specifies. Immutable.';
comment on column public.notifications.delivery_state is
  'APP 010 §5.11 / §10: v1 always ''delivered''. pending/failed/suppressed reserved for post-v1 async channels. Server-managed.';
comment on column public.notifications.subject_kind is
  'APP 010 §5.12: denormalized copy of activity_events.subject_kind. Immutable.';
comment on column public.notifications.subject_id is
  'APP 010 §5.13: denormalized copy of activity_events.subject_id. Nullable per EVENT_MODEL convention. Deliberately NOT a FK (mirrors frozen activity_events.subject_id posture). Immutable.';
comment on column public.notifications.subject_label is
  'APP 010 §5.14 / G-57: denormalized copy of activity_events.subject_label. Immutable — renames of source subject do not retroactively change the notification.';
comment on column public.notifications.actor_profile_id is
  'APP 010 §5.15 / G-37: denormalized copy of activity_events.actor_profile_id. NULL for actor_kind=system events. FK ON DELETE SET NULL. Immutable.';
comment on column public.notifications.payload is
  'APP 010 §5.16 / §10.4 / G-39: rendering-ready material. Contains actor_display_name, deep_link{kind,id,workspace_id,project_id?}, preview_snippet, plus email_/push_ keys when applicable. 16 KB hard cap. Immutable per G-57.';
comment on column public.notifications.read_at is
  'APP 010 §5.17 / §11: set by mark_notification_read. NULL = unread. Mutable via RPC only.';
comment on column public.notifications.dismissed_at is
  'APP 010 §5.18 / §11: set by dismiss_notification. NULL = not dismissed. One-way in v1 (no undismiss RPC).';
comment on column public.notifications.archived_at is
  'APP 010 §5.19 / §11 / G-40: set by archive_notification. NULL = not archived. One-way in v1 (unarchive RESERVED for future wave).';
comment on column public.notifications.created_at is
  'APP 010 §5.20: router INSERT timestamp. Powers Inbox default sort and cursor pagination. Immutable.';
comment on column public.notifications.updated_at is
  'APP 010 §5.21: standard maintenance timestamp. Touched by notifications_set_updated_at trigger on any recipient-axis write.';

------------------------------------------------------------------------------
-- 2. Foreign keys (§7.7)
------------------------------------------------------------------------------

-- FK-1: recipient_profile_id → profiles(id) ON DELETE SET NULL (Non-composite)
alter table public.notifications
  add constraint notifications_recipient_profile_fk
    foreign key (recipient_profile_id)
    references public.profiles (id)
    on delete set null;

-- FK-2: composite (project_id, workspace_id) → projects(id, workspace_id)
-- Reuses APP 003 project composite anchor unique. Enforced only when project_id NOT NULL.
alter table public.notifications
  add constraint notifications_project_workspace_fk
    foreign key (project_id, workspace_id)
    references public.projects (id, workspace_id)
    on delete cascade;

-- FK-3: source_event_id → activity_events(id) ON DELETE CASCADE (Non-composite)
-- Frozen activity_events has PK only on (id); no composite anchor exists.
alter table public.notifications
  add constraint notifications_source_event_fk
    foreign key (source_event_id)
    references public.activity_events (id)
    on delete cascade;

-- FK-4: actor_profile_id → profiles(id) ON DELETE SET NULL (Non-composite)
alter table public.notifications
  add constraint notifications_actor_profile_fk
    foreign key (actor_profile_id)
    references public.profiles (id)
    on delete set null;

------------------------------------------------------------------------------
-- 3. Additive indexes I-1 … I-9 (§6)
------------------------------------------------------------------------------

-- I-1: Bell-badge unread count hot path. Powers get_notification_badge_count.
create index if not exists notifications_unread_by_recipient_idx
  on public.notifications (recipient_profile_id, workspace_id, read_at)
  where read_at is null
    and dismissed_at is null
    and archived_at is null
    and priority != 'informational';

-- I-2: Inbox "All" tab scan + cursor pagination target.
create index if not exists notifications_inbox_all_idx
  on public.notifications (recipient_profile_id, workspace_id, created_at desc, id desc)
  where dismissed_at is null and archived_at is null;

-- I-3: Category-filtered scans (mentions/assigned/governance tabs).
create index if not exists notifications_category_idx
  on public.notifications (recipient_profile_id, workspace_id, category, created_at desc)
  where dismissed_at is null and archived_at is null;

-- I-4: Priority filter chip scans.
create index if not exists notifications_priority_idx
  on public.notifications (recipient_profile_id, workspace_id, priority, created_at desc)
  where dismissed_at is null and archived_at is null;

-- I-5: Archived-tab scan.
create index if not exists notifications_archived_idx
  on public.notifications (recipient_profile_id, workspace_id, archived_at desc)
  where archived_at is not null;

-- I-6: Project-filter scans. Covers composite FK (project_id, workspace_id).
create index if not exists notifications_project_scope_idx
  on public.notifications (project_id, workspace_id, created_at desc)
  where project_id is not null;

-- I-7: Dedup enforcement (G-7). Partial unique index.
-- WHERE archived_at IS NULL is defensive scaffolding for Wave 4 replay workers
-- (unreachable in v1 traffic); locks the dedup contract shape early.
create unique index if not exists notifications_dedup_uniq_idx
  on public.notifications (recipient_profile_id, source_event_id, notification_type)
  where archived_at is null;

-- I-8: Reverse-lookup queries (list_notifications_by_source).
create index if not exists notifications_subject_reverse_idx
  on public.notifications (subject_kind, subject_id, created_at desc)
  where subject_id is not null;

-- I-9: Actor-filter chip scans. Covers actor_profile_id FK.
create index if not exists notifications_actor_idx
  on public.notifications (actor_profile_id, workspace_id, created_at desc)
  where actor_profile_id is not null;

------------------------------------------------------------------------------
-- 4. RLS enable + 4 policies (§10.1)
------------------------------------------------------------------------------

alter table public.notifications enable row level security;

-- SELECT policy: recipient-only + capability + belt-and-braces subject access.
create policy notifications_select
  on public.notifications
  for select
  to authenticated
  using (
    recipient_profile_id = (select auth.uid())
    and public.lign_has_capability(project_id, workspace_id, 'notification.view')
    and (
      project_id is null
      or public.lign_project_role(project_id) is not null
      or public.lign_is_workspace_admin(workspace_id)
    )
  );

-- INSERT policy: deny to authenticated. Router trigger is SECURITY DEFINER
-- and bypasses RLS.
create policy notifications_insert
  on public.notifications
  for insert
  to authenticated
  with check (false);

-- UPDATE policy: recipient-only. Further gated by the RPC-only-write trigger.
create policy notifications_update
  on public.notifications
  for update
  to authenticated
  using (recipient_profile_id = (select auth.uid()))
  with check (recipient_profile_id = (select auth.uid()));

-- DELETE policy: deny to all. Retention pruning (Wave 4) uses service_role.
create policy notifications_delete
  on public.notifications
  for delete
  to authenticated
  using (false);

------------------------------------------------------------------------------
-- 5. Trigger: enforce_notification_immutable_fields — BEFORE UPDATE (§9.2)
------------------------------------------------------------------------------
-- Rejects any UPDATE that changes a column outside the mutable-flag set
-- (read_at, dismissed_at, archived_at, updated_at).
--
-- Row-local; inspects only OLD/NEW columns of its own row. NOT SECURITY
-- DEFINER per APP 009 F-6 precedent. SET search_path = '' for safety.

create or replace function public.enforce_notification_immutable_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id is distinct from old.id then
    raise exception 'notifications.id is immutable after INSERT (row id=%)', old.id
      using errcode = '23514';
  end if;
  if new.workspace_id is distinct from old.workspace_id then
    raise exception 'notifications.workspace_id is immutable after INSERT (row id=%)', old.id
      using errcode = '23514';
  end if;
  if new.project_id is distinct from old.project_id then
    raise exception 'notifications.project_id is immutable after INSERT (row id=%)', old.id
      using errcode = '23514';
  end if;
  if new.recipient_profile_id is distinct from old.recipient_profile_id then
    raise exception 'notifications.recipient_profile_id is immutable after INSERT (row id=%)', old.id
      using errcode = '23514';
  end if;
  if new.source_event_id is distinct from old.source_event_id then
    raise exception 'notifications.source_event_id is immutable after INSERT (row id=%)', old.id
      using errcode = '23514';
  end if;
  if new.event_type is distinct from old.event_type then
    raise exception 'notifications.event_type is immutable after INSERT (row id=%)', old.id
      using errcode = '23514';
  end if;
  if new.notification_type is distinct from old.notification_type then
    raise exception 'notifications.notification_type is immutable after INSERT (row id=%)', old.id
      using errcode = '23514';
  end if;
  if new.category is distinct from old.category then
    raise exception 'notifications.category is immutable after INSERT (row id=%)', old.id
      using errcode = '23514';
  end if;
  if new.priority is distinct from old.priority then
    raise exception 'notifications.priority is immutable after INSERT (row id=%)', old.id
      using errcode = '23514';
  end if;
  if new.channels_attempted is distinct from old.channels_attempted then
    raise exception 'notifications.channels_attempted is immutable after INSERT (row id=%)', old.id
      using errcode = '23514';
  end if;
  if new.delivery_state is distinct from old.delivery_state then
    raise exception 'notifications.delivery_state is immutable in v1 (row id=%); async delivery workers land in Wave 4', old.id
      using errcode = '23514';
  end if;
  if new.subject_kind is distinct from old.subject_kind then
    raise exception 'notifications.subject_kind is immutable after INSERT (row id=%)', old.id
      using errcode = '23514';
  end if;
  if new.subject_id is distinct from old.subject_id then
    raise exception 'notifications.subject_id is immutable after INSERT (row id=%)', old.id
      using errcode = '23514';
  end if;
  if new.subject_label is distinct from old.subject_label then
    raise exception 'notifications.subject_label is immutable after INSERT (row id=%)', old.id
      using errcode = '23514';
  end if;
  if new.actor_profile_id is distinct from old.actor_profile_id then
    raise exception 'notifications.actor_profile_id is immutable after INSERT (row id=%)', old.id
      using errcode = '23514';
  end if;
  if new.payload is distinct from old.payload then
    raise exception 'notifications.payload is immutable after INSERT (row id=%)', old.id
      using errcode = '23514';
  end if;
  if new.created_at is distinct from old.created_at then
    raise exception 'notifications.created_at is immutable after INSERT (row id=%)', old.id
      using errcode = '23514';
  end if;
  return new;
end;
$$;

comment on function public.enforce_notification_immutable_fields() is
  'APP 010 §9.2 / §4.2 / G-57: rejects any UPDATE that changes a column outside the mutable-flag set (read_at, dismissed_at, archived_at, updated_at). Row-local; NOT SECURITY DEFINER per APP 009 F-6 precedent.';

revoke all on function public.enforce_notification_immutable_fields() from public;
revoke all on function public.enforce_notification_immutable_fields() from anon;
revoke all on function public.enforce_notification_immutable_fields() from authenticated;

drop trigger if exists enforce_notification_immutable_fields on public.notifications;
create trigger enforce_notification_immutable_fields
  before update on public.notifications
  for each row execute function public.enforce_notification_immutable_fields();

------------------------------------------------------------------------------
-- 6. Trigger: enforce_notification_rpc_only_writes — BEFORE UPDATE (§9.3)
------------------------------------------------------------------------------
-- Blocks direct UPDATE from user code. Only the 8 write RPCs may write —
-- they set the lign.allow_notification_rpc_write GUC transaction-local
-- before their UPDATE and reset it after.
--
-- Row-local + GUC only. NOT SECURITY DEFINER per F-6.

create or replace function public.enforce_notification_rpc_only_writes()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_gate text;
begin
  v_gate := coalesce(current_setting('lign.allow_notification_rpc_write', true), '');
  if v_gate <> 'true' then
    raise exception 'notifications may only be updated via mark_/dismiss_/archive_ RPCs (row id=%)', old.id
      using errcode = '42501';
  end if;
  return new;
end;
$$;

comment on function public.enforce_notification_rpc_only_writes() is
  'APP 010 §9.3 / §4.2: RPC-only-write gate. Requires transaction-local GUC lign.allow_notification_rpc_write=''true'' (only settable inside the 8 SECURITY DEFINER write RPCs). Mirrors frozen enforce_release_status_via_rpc pattern. Row-local; NOT SECURITY DEFINER per F-6.';

revoke all on function public.enforce_notification_rpc_only_writes() from public;
revoke all on function public.enforce_notification_rpc_only_writes() from anon;
revoke all on function public.enforce_notification_rpc_only_writes() from authenticated;

drop trigger if exists enforce_notification_rpc_only_writes on public.notifications;
create trigger enforce_notification_rpc_only_writes
  before update on public.notifications
  for each row execute function public.enforce_notification_rpc_only_writes();

------------------------------------------------------------------------------
-- 7. Trigger: notifications_set_updated_at — BEFORE UPDATE (§9.4)
------------------------------------------------------------------------------
-- Reuses the frozen public.set_updated_at() function from APP 001 foundation.
-- No new function declared.

drop trigger if exists notifications_set_updated_at on public.notifications;
create trigger notifications_set_updated_at
  before update on public.notifications
  for each row execute function public.set_updated_at();

------------------------------------------------------------------------------
-- 8. Realtime posture: notifications is NOT in supabase_realtime publication.
--    Reserved for APP 011 re-freeze per Freeze Index §25.
------------------------------------------------------------------------------
-- Intentionally omitted: no `alter publication supabase_realtime add table`.
