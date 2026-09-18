# APP 010 — Freeze Index

**Canonical architecture reference for the Lign Notifications module.**

Implementation has not started. This document consolidates the APP 010 (Notifications product surface + delivery substrate) architecture into one navigational reference on top of the **frozen event vocabulary** shipped by EVENT_MODEL.md and re-freeze-locked by APP 006–009. It preserves every APP 001–009 contract; extension is additive only. Sections marked **[additive]** identify surface expansions the follow-on `APP_010_BACKEND_PROPOSAL.md` will elaborate — no SQL, no migration, no RPC bodies, no trigger definitions are proposed here.

**Foundational premise (non-negotiable):**

> **APP 010 owns notification DELIVERY. It does NOT own business workflow.**
>
> Workflow lives inside Requirements (APP 008), Reviews (APP 006), Approvals (APP 007), Releases (APP 009), Comments (APP 005), and the underlying frozen event emitters. APP 010 **consumes** the events those slices commit to `activity_events` and **delivers** targeted, actionable prompts to specific recipients. APP 010 **never emits workflow events**. APP 010 **never mutates workflow state**. Every notification originates from a frozen event; APP 010 does not invent a single new workflow event type.

**Companion frozen inputs:**
- `docs/EVENT_MODEL.md` — the sole source of truth for the event vocabulary APP 010 consumes. All 60 P0 events with their `Notify` routing decisions are enumerated in §4.
- `docs/DATABASE_SCHEMA.md` §3.25 — the frozen `activity_events` table that APP 010 reads (never writes).
- `docs/PERMISSIONS.md` — capability primer; APP 010 introduces additive `notification.*` capabilities per §19.
- `docs/DOMAIN_MODEL.md`, `docs/STATE_MACHINES.md`, `docs/AUTHORIZATION_ARCHITECTURE.md`, `docs/PLATFORM_BASELINE.md`, `docs/PLATFORM_CHEATSHEET.md`, `docs/ARCHITECT_REVIEW_CHECKLIST.md`, `docs/SCHEMA_V1_LOCK.md`.
- `docs/APP_006_FREEZE_INDEX.md`, `docs/APP_007_FREEZE_INDEX.md`, `docs/APP_008_FREEZE_INDEX.md`, `docs/APP_009_FREEZE_INDEX.md` — the upstream product-surface contracts whose events APP 010 delivers.
- `docs/freeze/APP_006_FINAL_CERTIFICATION.md`, `docs/freeze/APP_007_FINAL_CERTIFICATION.md`, `docs/freeze/APP_008_FINAL_CERTIFICATION.md`, `docs/freeze/APP_009_FINAL_CERTIFICATION.md` — governance records certifying the frozen event vocabulary.
- Memory: `project_lign_schema_v1_lock.md`, `project_lign_storage_layer_lock.md`, `project_lign_requirements_layer_lock.md`.

---

## 1. Purpose

APP 010 owns the **product-surface architecture for Notifications** — the Inbox screen, the Notification Center popover, the bell-icon badge, the toast presentation layer, the read/unread/dismissed/archived lifecycle, the email-ready payload contract, the push-ready payload contract, the recipient-resolution logic, the event-to-notification router, and the small set of additive backend extensions the surface genuinely requires. It builds on the frozen event vocabulary from EVENT_MODEL.md without inventing a single new workflow event and without weakening any invariant.

### 1.1 What Notifications ARE, ARE NOT, and DO

| Axis | Notifications ARE | Notifications are NOT | Notifications DO |
|---|---|---|---|
| **Nature** | A targeted, actionable prompt to a specific person — derived from a committed domain event | A synonym for `activity_events`; a duplicate of the audit log; a workflow state store; a chat feed | Route committed events to the specific recipients who need to act on them |
| **Weight** | Advisory (a prompt to look at something) — never contractual, never binding | A vote, a decision, an approval, an assessment, a release | Nudge the recipient toward an underlying workflow surface |
| **Cardinality (v1)** | Zero-to-many notifications per source event (one per resolved recipient after dedup + self-exclusion) | One-to-one with events; one-to-one with users | Fan out per §9 recipient resolution rules |
| **Source of truth for workflow state** | No — the emitting slice owns state (`reviews`, `approval_requests`, `requirements`, `releases`, `comments`) | The place to track state | Reference the source `activity_events` row + subject id + subject snapshot for rendering |
| **Mutation posture** | Read/unread/dismissed/archived are per-user recipient-side flags on the notification row; the notification row's `payload` is immutable | Editable content; workflow you can "resolve" from the notification | Preserve the historical event exactly as committed |
| **Effect on workflow** | None — clicking a notification navigates to the source surface; the notification itself completes no workflow | Complete a review, respond to an approval, edit a requirement, publish a release | Deep-link, mark-as-read, and get out of the way |
| **First-class status** | A full module with an Inbox screen, a Notification Center popover, badges on the bell + NavRail items, toasts, and reserved AI seams | A sidecar tab | Own the recipient-side delivery record |

### 1.2 The event → notification pipeline

```
      APP 005-009 (workflow)             APP 010 (delivery)                Recipient
     ────────────────────────           ────────────────────              ──────────
      Frozen RPC commits          ┌─▶  Router materializes
      workflow state              │    notification rows              ┌─▶ Inbox screen
      (review.opened,             │    (per recipient, per            │
       approval.requested,        │     resolved rule set,            ├─▶ Notification Center
       requirement.assessed,      │     with dedup + self-exclusion)  │
       release.finalized, …)      │                                   ├─▶ Badge counts (bell)
                │                 │                    │              │
                ▼                 │                    ▼              ├─▶ Badge counts (NavRail)
      activity_events INSERT ─────┘           notifications table     │
      (same TX; committed fact)                (per-user rows)         ├─▶ Toast (transient)
                │                                        │            │
                │                                        ▼            └─▶ email-ready payload
                └──────── audit / history / feed ─── deep_link ───────────▶ push-ready payload
                          (owned by APP 002/003)  (owned by source slice)
```

Every APP 010 subsystem enforces this pipeline. The router consumes `activity_events` rows committed by the upstream slices' RPCs. It **never** writes to `activity_events`, never mutates any workflow table, never emits a workflow event. Deep-link resolution is delegated to the source module (release → `/deep/release/:id`, approval → `/deep/approval/:id`, etc. — all owned by the emitting slice per APP 002 DeepLinkResolver conventions).

### 1.3 What APP 010 owns exclusively

- The `notifications` table (**[additive]**; §4) and its lifecycle (`pending → delivered → read | dismissed | archived`, §3).
- The event-to-notification router (**[additive]** trigger on `activity_events` insert; §20).
- The recipient-resolution rules (§9).
- The Inbox screen at `/workspace/:ws_id/inbox` and its filter/tab/URL grammar (§12, §16).
- The Notification Center popover (bell-icon dropdown; §13).
- The bell-icon unread badge and the NavRail category badges' notification-derived counts (§14).
- The toast presentation layer (rate-limited to 3 concurrent per G-19; §13.5).
- Read/unread/dismissed/archived state transitions and their bulk RPCs (§11).
- Deep-link out (**not** the target route — that belongs to the source slice) and the `/deep/notification/:id` slot (recommend: rare-use fallback; §15).
- The email-ready and push-ready payload contracts (payload materialization only — no SMTP, no APNS, no FCM; §10.4, §29.2).
- Additive capabilities and event names reserved in §19–20, §24.
- Reusable primitives introduced in §27 (`NotificationBell`, `NotificationCenter`, `NotificationCard`, `InboxScreen`, `NotificationFilterBar`, `NotificationBadge`, `useNotificationBadgeCount`).

### 1.4 What APP 010 must not touch

- Frozen surface of Migrations 001–010 (tables, columns, triggers, RLS, capability keys, event vocabulary). Any conflict is recorded in §28 as a candidate for future re-freeze.
- APP 001–009 domain invariants, capability primer, `qk` conventions, router shape, URL grammar, deep-link kinds, hotkey bindings, or component APIs.
- `activity_events` — READ only. APP 010 never writes to the audit log.
- The workflow tables of APP 005 (`comments`, `annotations`), APP 006 (`reviews`, `review_participants`, `review_rounds`), APP 007 (`approval_requests`, `approval_responses`, `approvals`), APP 008 (`requirements`, `version_requirement_assessments`), APP 009 (`releases`, `release_items`) — READ only where needed for recipient resolution (via `project_participants`, `workspace_members`, and the RPCs those slices already expose).
- The frozen event vocabulary itself. APP 010 registers no new event names in the workflow vocabulary; the only APP-010-owned event names live under the `notification.*` namespace and are all **reserved** (name-locked, no emitter in v1) — see §24.4.
- Storage layer (STORAGE 001–004) — untouched.
- Realtime publication (REALTIME 001–002) — the `notifications` table remains OUT of `supabase_realtime` in APP 010 v1; see §25. Adding it belongs to APP 011 re-freeze.

### 1.5 Collaboration with APP 005 (Comments), APP 006 (Reviews), APP 007 (Approvals), APP 008 (Requirements), APP 009 (Releases), APP 011 (Realtime)

| Surface | APP 005 Comments | APP 006 Reviews | APP 007 Approvals | APP 008 Requirements | APP 009 Releases | APP 010 Notifications (this) | APP 011 Realtime (future) |
|---|---|---|---|---|---|---|---|
| Purpose | Discuss anything | Iterate on a version | Grant authority | Bind obligations | Publish version | Deliver prompts | Transport live |
| Emits | `comment.*`, `annotation.*` | `review.*` | `approval.*` | `requirement.*` | `release.*` | **None** in workflow vocabulary; `notification.*` reserved | — |
| Consumed by APP 010 | `comment.mentioned` (P0 notify) — see §5.5 EVENT_MODEL | `review.opened`, `review.completed`, `review.cancelled`, `review.reviewer_responded` — see EVENT_MODEL §4.7 | All 6 `approval.*` P0 events — see EVENT_MODEL §4.11 | Feed-only in MVP per EVENT_MODEL §4.13 / §4.14 (0 notifications from `requirement.*` in v1) | 2 of 5 `release.*` P0 events (`release.finalized`, `release.withdrawn`) — see EVENT_MODEL §4.12 | — | Reserved consumer of `notifications` INSERT (future push) |
| Writes back to APP 010 | Never | Never | Never | Never | Never | — | Never (transport only) |

APP 010 is exclusively a **downstream consumer** of the frozen event vocabulary. Every write path in APP 010 (`mark_notification_read`, `mark_all_notifications_read`, `dismiss_notification`, `archive_notification`, `mark_notification_unread`) only mutates the caller's own rows in the **[additive]** `notifications` table — never in the upstream slices' tables, never in `activity_events`.

---

## 2. Notifications vs business workflow

### 2.1 The bright line

The core discipline of APP 010 is the **bright-line separation** between event-producing workflow slices and event-consuming delivery. Every temptation to blur this line is a bug in the making.

```
                       WORKFLOW SIDE                          DELIVERY SIDE
                      (APP 005 - 009)                          (APP 010)
                       ─────────────                          ──────────
                          owns state                          owns recipient rows
                          emits events                        consumes events
                          fires RPCs                          renders inbox
                          writes activity_events              reads activity_events
                          answers "what happened?"            answers "who should know?"
                                       │                             │
                                       │   activity_events INSERT    │
                                       └────────────(bridge)─────────┘
                                                (trigger, §20)
```

Every workflow event committed to `activity_events` is a potential source for zero-to-many notification rows. The router decides. The workflow slice does not know that notifications exist. This is the same "audit-writer / audit-reader" pattern the platform uses throughout — Notifications is a distinguished audit-reader that materializes a per-user delivery record.

### 2.2 Non-ownership statement

APP 010 has **no capability** to:
- Complete a review, cancel a review, reassign a reviewer.
- Respond to an approval, cancel an approval, supersede an approval, expire an approval.
- Edit a requirement, archive a requirement, assess a requirement, set requirement applicability.
- Create a release, add a release item, finalize a release, withdraw a release.
- Create, edit, resolve, or delete a comment or annotation.
- Publish, supersede, deprecate, or discard a version.
- Add, remove, or change roles for a project participant or workspace member.

Every APP 010 RPC is scoped to the caller's own `notifications` rows.

### 2.3 Event → Router → Recipient Resolution → Delivery → Read Receipt

The precise data flow:

```
   1. Workflow RPC (frozen)                 e.g. create_review, respond_to_approval,
                                            finalize_release
             │
             ▼
   2. activity_events INSERT (same TX)      row with actor_profile_id, subject_kind,
                                            subject_id, project_id, event_type,
                                            subject_snapshot, occurred_at
             │
             ▼ (AFTER INSERT trigger, §20)
   3. Router (new; §8)                      map event_type + subject_snapshot →
                                            notification_type + category + priority +
                                            recipient set
             │
             ▼
   4. Recipient resolution (§9)             direct-actor / owner / requester /
                                            project-broadcast / mentioned;
                                            self-exclusion; dedup per (source_event_id,
                                            recipient_profile_id)
             │
             ▼
   5. notifications INSERT (per recipient)  delivery_state = 'delivered' in v1 (in-app
                                            synchronous); payload jsonb materialized
                                            from event
             │
             ▼
   6. Client fetch (§17)                    list_notifications / notification badge
                                            queries via TanStack
             │
             ▼
   7. Presentation (§13)                    Notification Center + Inbox + Badge + Toast
             │
             ▼
   8. Read receipt (§11)                    mark_notification_read → notifications.read_at
                                            set; invalidates badge + list
```

### 2.4 What the router does NOT do

- Does not consult APP 010 preferences (there are none in v1; see §29.1).
- Does not batch or defer (per G-18; per-event notifications only).
- Does not re-emit workflow events, ever.
- Does not modify `activity_events` (append-only; direct enforcement per DATABASE_SCHEMA.md §3.25).
- Does not delete or update rows the upstream slice owns.

### 2.5 What the router MUST do

- Deduplicate per `(source_event_id, recipient_profile_id)` at INSERT time (G-7; enforced via unique index).
- Exclude the actor of the event from the recipient set (G-8, G-15).
- Preserve rendering stability by materializing `subject_snapshot` fields into `payload` at write time — later renames of the subject do not change the historical notification.
- Honor RLS: the notification row's SELECT policy still requires that the recipient has access to the source subject (see §21 for the "notifications never bypass RLS" invariant, inherited from EVENT_MODEL.md §7.7).

---

## 3. Notification lifecycle

### 3.1 The v1 lifecycle

Every notification row moves through a small state machine on two orthogonal axes:

- **Delivery axis** (per-channel; §10): `pending → delivered → failed | suppressed`.
- **Recipient axis** (per-user flags; §11): `unread → read`; `not_dismissed → dismissed`; `not_archived → archived`.

The delivery axis is server-side (owned by the router and future delivery workers). The recipient axis is per-user, mutated by the caller's own `mark_*` RPCs.

Rendered as a superposition:

```
                        pending
                           │
              (router INSERT; v1 in-app is synchronous)
                           ▼
                       delivered ◀────────────────┐
                           │                       │
                           │ mark_notification_read│ mark_notification_unread (G-5 allows)
                           ▼                       │
                          read ──────────────────┤
                           │                       │
                           │ dismiss_notification  │
                           ▼                       │
                       dismissed ─── (no un-dismiss; terminal on that axis)
                           │
                           │ archive_notification (from read, dismissed, or unread)
                           ▼
                        archived ─── (no un-archive in v1; terminal on that axis)
```

Legal transitions per G-5:
- `unread ↔ read` — reversible via `mark_notification_read` / `mark_notification_unread`.
- `not_dismissed → dismissed` — one-way (dismissal is a hide-from-inbox intent; the notification remains queryable via `?tab=archived` if it was also archived, otherwise it disappears from all views except a hypothetical "dismissed" filter — see §12.3).
- `not_archived → archived` — one-way; archived notifications remain queryable via `?tab=archived`.
- `pending → delivered` — internal to the router; observable via `delivery_state`.
- `delivered → failed` — reserved for future async channels; not observable in v1 (in-app delivery is synchronous).

### 3.2 Terminal states

- On the **delivery axis**: `delivered` (v1 target state); `failed` and `suppressed` are reserved and not exercised in v1 (in-app is synchronous; failures raise, they do not park).
- On the **recipient axis**: `archived` is terminal in v1 (no `unarchive_notification` RPC ships; the state is a hide-forever intent).

### 3.3 Retention

- Read notifications: **90 days** by default. A retention job (deferred; not v1 — the field `deleted_at` on `notifications` is reserved) may purge older rows.
- Unread notifications: **forever** until explicitly acted on. Never auto-purged.
- Dismissed but not archived: 30 days then eligible for purge (deferred).
- Archived: forever (audit-adjacent record).

Decision recorded as G-9 in §28.

### 3.4 Cascade posture

- On profile soft-delete (`profiles.deleted_at IS NOT NULL`): notifications for that recipient are preserved (audit trail of "user X was notified of Y at time T remains meaningful"); the row remains SELECT-restricted per RLS.
- On profile hard-delete (not permitted in v1; profiles are soft-deleted): would cascade via FK `ON DELETE SET NULL` on `recipient_profile_id` (G-11); orphaned rows would render as "recipient no longer exists" and be excluded from lists.
- On source workflow row deletion (rare — most workflow rows are archive-only): the source event in `activity_events` remains (audit is append-only), so `source_event_id` remains valid; the notification `payload` remains renderable from the snapshot.

Decision recorded as G-11 in §28.

---

## 4. Notification domain model

APP 010 introduces **one new table** in v1: `notifications`. Every column is enumerated below; the Backend Proposal will provide exact DDL. Two additional tables are **name-reserved but not shipped in v1** (§4.4).

### 4.1 The `notifications` table (**[additive]**, v1)

| Column | Type | Nullable | Default | Purpose | Notes |
|---|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | Primary key | Immutable |
| `workspace_id` | `uuid` | no | — | Tenant scope; composite FK together with `project_id` back to `projects(id, workspace_id)` when `project_id IS NOT NULL` | Immutable |
| `project_id` | `uuid` | yes | — | Project scope for project-scoped events; NULL for workspace-scoped events (mirrors `activity_events.project_id` per DATABASE_SCHEMA.md §3.25) | Immutable |
| `recipient_profile_id` | `uuid` | no | — | FK → `profiles(id)` ON DELETE SET NULL (G-11) | Immutable |
| `source_event_id` | `uuid` | no | — | FK → `activity_events(id)` — the originating committed event | Immutable |
| `event_type` | `text` | no | — | Denormalized copy of `activity_events.event_type` (e.g. `approval.requested`, `review.opened`) — powers filters without a join | Immutable |
| `notification_type` | `text` | no | — | The `notification.*`-typed classification (see §5) — e.g. `review.assigned_to_you`, `approval.awaiting_your_decision` | Immutable |
| `category` | `text` | no | — | High-level grouping (§6): `assigned_to_me / mentions / project_activity / governance_state_change / deadlines / system` | Immutable |
| `priority` | `text` | no | `'medium'` | `critical / high / medium / low / informational` (§7) | Immutable |
| `channels_attempted` | `text[]` | no | `ARRAY['in_app']` | Which channels the router attempted (v1: always `['in_app']`; email-ready and push-ready payloads land here in future) — G-4 | Immutable after INSERT |
| `delivery_state` | `text` | no | `'delivered'` | `pending / delivered / failed / suppressed` — v1 defaults to `delivered` (synchronous in-app) | Server-managed |
| `subject_kind` | `text` | no | — | Denormalized copy of `activity_events.subject_kind` for filter/link resolution | Immutable |
| `subject_id` | `uuid` | yes | — | Denormalized copy of `activity_events.subject_id` (nullable per EVENT_MODEL.md convention) | Immutable |
| `subject_label` | `text` | yes | — | Denormalized copy of `activity_events.subject_label` (e.g. "Kitchen Layout · v3") — powers rendering without a join | Immutable |
| `actor_profile_id` | `uuid` | yes | — | Denormalized copy of `activity_events.actor_profile_id` (NULL for `actor_kind='system'` events) | Immutable |
| `payload` | `jsonb` | no | `'{}'::jsonb` | Rendering-ready material derived from `activity_events.subject_snapshot` plus computed convenience fields (e.g. `preview_snippet`, `deep_link_kind`, `deep_link_id`); see §10.4 | Immutable |
| `read_at` | `timestamptz` | yes | — | Set by `mark_notification_read`; NULL means unread | Mutable; nullable |
| `dismissed_at` | `timestamptz` | yes | — | Set by `dismiss_notification`; NULL means not dismissed | Mutable; nullable (§11) |
| `archived_at` | `timestamptz` | yes | — | Set by `archive_notification`; NULL means not archived | Mutable; nullable (§11) |
| `created_at` | `timestamptz` | no | `now()` | Router INSERT timestamp | Immutable |
| `updated_at` | `timestamptz` | no | `now()` | Standard maintenance timestamp (touch on any recipient-axis write) | Server-managed |

### 4.2 Immutability posture

The following columns are immutable after INSERT and enforced by an **[additive]** BEFORE UPDATE trigger (`enforce_notification_immutable_fields`, §26.7):
- `id`, `workspace_id`, `project_id`, `recipient_profile_id`, `source_event_id`, `event_type`, `notification_type`, `category`, `priority`, `subject_kind`, `subject_id`, `subject_label`, `actor_profile_id`, `payload`, `created_at`, `channels_attempted`.

The following columns are mutable via the specific `mark_*` / `dismiss_*` / `archive_*` RPCs:
- `read_at`, `dismissed_at`, `archived_at`, `updated_at`, `delivery_state` (server-managed).

Direct UPDATE from user code is denied by RLS; only the RPCs may write (using an `is_lign_notification_rpc()` GUC guard analogous to APP 009's `lign.allow_release_status_write`).

### 4.3 Composite FK for tenant coherence

Per the platform's composite-tenant-integrity pattern (SCHEMA_V1_LOCK.md; APP 009 §5.1 precedent), the `notifications` table carries composite FKs:

- `(project_id, workspace_id)` → `projects(id, workspace_id)` — enforced when `project_id IS NOT NULL`; NULL for workspace-scoped events.
- `(source_event_id, workspace_id)` → `activity_events(id, workspace_id)` — every notification's source event lives in the same workspace.
- `(recipient_profile_id)` → `profiles(id)` — simple FK; the tenant match is enforced via `workspace_members` at RLS time.

### 4.4 Reserved tables (name-locked; not shipped in v1)

| Table | Purpose (future) | Reservation reason |
|---|---|---|
| `notification_preferences` | Per-user per-category muting / channel selection | Deferred to a future wave; the router in v1 has no preferences to consult (G-3) |
| `notification_deliveries` | Per-channel delivery attempt join (with retry count, last error, provider-message-id) | Deferred until non-in-app channels ship (G-4 alternative); v1 uses `channels_attempted text[]` inline on `notifications` |
| `notification_digests` | Batched digest sends (daily / weekly summary) | Explicitly out of scope per user brief; reserved for future cron/AI slice |

Names are name-locked here so a later re-freeze does not have to rename. No columns proposed for these reserved tables in APP 010.

### 4.5 Cardinality summary

- One `activity_events` row produces **zero to many** `notifications` rows (one per resolved recipient after dedup + self-exclusion).
- One `notifications` row belongs to exactly one recipient profile.
- One `notifications` row references exactly one `activity_events` row via `source_event_id`.
- One profile may hold **many** notifications; unread count is per-workspace scoped (G-12).
- No cross-notification relationships in v1 (no threading, no grouping-key beyond `notification_type` + `subject_id`).

### 4.6 What the Backend Proposal will elaborate

Every **[additive]** field, index, trigger, RPC, capability, and event-name reference in this document will be enumerated with signatures, defaults, and rationale in the forthcoming `APP_010_BACKEND_PROPOSAL.md`. Preliminary counts appear in §26.

---

## 5. Notification types

The `notification_type` column classifies a notification by its **actionable meaning to the recipient**, which is finer-grained than the source `event_type`. One event may produce different notification types for different recipients (e.g. `approval.requested` produces `approval.awaiting_your_decision` for approvers and `approval.sent_by_you` — reserved — for the requester, though v1 suppresses actor self-notifications per G-8/G-15).

All notification types below are prefixed by the source module for stability. Every type maps to exactly one source event (see routing table in §8). Names are lowercase, dot-separated, past-participle where the recipient is passive, imperative where the recipient must act.

### 5.1 Review-derived notification types (5)

Source: `review.*` events (EVENT_MODEL.md §4.7).

| `notification_type` | Fires on | Recipient | Category | Priority |
|---|---|---|---|---|
| `review.assigned_to_you` | `review.opened` where recipient is in the review's reviewer roster | Assigned reviewer | `assigned_to_me` | `high` |
| `review.your_review_completed` | `review.completed` where recipient is the review creator | Review creator | `governance_state_change` | `medium` |
| `review.your_review_cancelled` | `review.cancelled` where recipient is the review creator | Review creator | `governance_state_change` | `medium` |
| `review.reviewer_responded_on_your_review` | `review.reviewer_responded` where recipient is the review creator | Review creator | `project_activity` | `medium` |
| `review.you_were_removed_as_reviewer` | Payload-derived: `review.reviewer_responded` with `reviewer_status='declined'` is the closest v1 signal; the reserved future event `review.reviewer_removed` (APP 006 §21) will fire this cleanly. Deferred; not v1. | (reserved) | `assigned_to_me` | `medium` |

### 5.2 Approval-derived notification types (6)

Source: `approval.*` events (EVENT_MODEL.md §4.11).

| `notification_type` | Fires on | Recipient | Category | Priority |
|---|---|---|---|---|
| `approval.awaiting_your_decision` | `approval.requested` where recipient is an assigned approver (all slots receive this) | Approvers with `pending` slot | `assigned_to_me` | `high` |
| `approval.responded_on_your_request` | `approval.responded` where recipient is the request creator | Request creator | `project_activity` | `medium` |
| `approval.approved_your_request` | `approval.approved` where recipient ∈ {request creator, project leads} (per EVENT_MODEL D10) | Creator + project leads | `governance_state_change` | `high` |
| `approval.rejected_your_request` | `approval.rejected` where recipient ∈ {request creator, project leads} (per EVENT_MODEL D10) | Creator + project leads | `governance_state_change` | `high` |
| `approval.expired_your_request` | `approval.expired` where recipient ∈ {request creator, project leads} | Creator + project leads | `governance_state_change` | `high` |
| `approval.request_cancelled` | `approval.cancelled` where recipient is a still-pending approver | Approvers | `governance_state_change` | `medium` |

### 5.3 Comment / mention notification types (1 in v1)

Source: `comment.mentioned` (EVENT_MODEL.md §4.8; single-recipient event by construction).

| `notification_type` | Fires on | Recipient | Category | Priority |
|---|---|---|---|---|
| `comment.mentioned_you` | `comment.mentioned` where recipient is the `mentioned_profile_id` in the event payload | Mentioned participant | `mentions` | `high` |

Other comment / annotation events are feed-only per EVENT_MODEL.md §7.3, §7.4 and produce no notifications in v1. The reserved future types `comment.reply_to_your_comment` and `comment.your_comment_resolved` are name-locked but not wired in v1 (the underlying events `comment.resolved` and `comment.reopened` are feed-only for now — see §5.8).

### 5.4 Change / decision notification types

Source: `change.*` (EVENT_MODEL.md §4.9), `decision.recorded` (§4.10).

`change.*` events fan out to project leads via feed; `decision.recorded` likewise. Per EVENT_MODEL.md §7.3 both are **feed-only for leads (no push)** in MVP. Therefore no `notification.*` types materialize for these events in v1. Reserved types for a future notify-on-change wave: `change.needs_your_review`, `change.your_change_accepted`, `change.your_change_rejected`, `decision.recorded_in_your_project` — all name-locked, not wired.

### 5.5 Release notification types (2)

Source: `release.*` events (EVENT_MODEL.md §4.12). Only `release.finalized` and `release.withdrawn` have `Notify=✓` in EVENT_MODEL.md.

| `notification_type` | Fires on | Recipient | Category | Priority |
|---|---|---|---|---|
| `release.published_in_your_project` | `release.finalized` for every recipient in the project's `project_participants` set | Project participants | `project_activity` | `medium` |
| `release.withdrawn_in_your_project` | `release.withdrawn` for the same set that received the `release.finalized` (per APP 009 §22.1 parity rule) | Project participants | `governance_state_change` | `high` |

`release.created`, `release.item_added`, `release.item_removed` are audit-only in EVENT_MODEL.md and produce no notifications. Reserved future notification types (name-locked): `release.your_draft_ready_to_publish` (APP 009 §22.5 forward-reference — deferred; keyed off `approval.approved` on a version referenced by a draft release), `release.critical_requirement_regressed` (APP 009 §22.5; keyed off `requirement.assessed` with `is_critical_unsatisfied=true` on a released-version).

### 5.6 Requirement notification types (0 in v1)

Source: `requirement.*` events (EVENT_MODEL.md §4.13). Per EVENT_MODEL.md §4.14 summary, all four `requirement.*` events are **feed-only in MVP — no notifications**.

Reserved future types (name-locked; not wired in v1):

- `requirement.assigned_to_you` — fires when a requirement is created with the recipient as owner (payload key `owner_profile_id` — deferred until APP 008 wires ownership; see APP 008 §12.1 reserved).
- `requirement.your_requirement_updated` — fires on `requirement.updated` where recipient is the requirement author or owner.
- `requirement.critical_regressed` — fires on `requirement.assessed` where `status` transitioned to a not-satisfied value on a critical requirement, targeting project leads.
- `requirement.assessed_by_you_stale` — fires when an asset version is superseded but the recipient last assessed it (freshness prompt).

### 5.7 Workspace / project administration notification types (7)

Source: `workspace.*`, `stakeholder.*`, `project.*`, `invitation.*` (EVENT_MODEL.md §4.1, §4.2).

| `notification_type` | Fires on | Recipient | Category | Priority |
|---|---|---|---|---|
| `workspace.you_were_invited` | `workspace.member.invited` (recipient is the invitee — pre-profile; delivered via email in v1, see §29.2) | Invitee (email) | `system` | `high` |
| `workspace.your_invitation_was_accepted` | `workspace.member.activated` | Inviter | `system` | `medium` |
| `workspace.your_role_changed` | `workspace.member.role_changed` | Affected member | `governance_state_change` | `high` (security-sensitive) |
| `workspace.you_were_suspended` | `workspace.member.suspended` | Affected member | `governance_state_change` | `critical` |
| `workspace.you_were_removed` | `workspace.member.removed` | Affected member | `governance_state_change` | `critical` |
| `project.you_were_added` | `project.participant.added` | Added participant | `assigned_to_me` | `high` |
| `project.your_role_changed` | `project.participant.role_changed` | Affected participant | `governance_state_change` | `medium` |
| `project.you_were_removed` | `project.participant.removed` | Affected participant | `governance_state_change` | `high` (security-sensitive) |
| `stakeholder.you_were_invited` | `stakeholder.invited` (invitee — pre-profile; email in v1) | Invitee (email) | `system` | `high` |
| `stakeholder.you_were_revoked` | `stakeholder.revoked` | Affected stakeholder | `governance_state_change` | `high` (security-sensitive) |

Some of the above (`workspace.you_were_invited`, `stakeholder.you_were_invited`) target a recipient who has no profile yet. For these, APP 010 v1 emits an **email-ready payload** only — the in-app inbox is not applicable. See §10.4 and §29.2.

### 5.8 Feed-only events → no notification types

The following P0 events are `Notify=—` in EVENT_MODEL.md §4 tables and produce **zero notification types in APP 010 v1**:

- `workspace.created`, `project.created`, `collection.created`, `collection.archived`, `asset.created`, `asset.archived`, `asset.unarchived`, `asset.current_version_changed`, `version.uploaded`, `version.published`, `version.superseded`, `version.deprecated`, `version.draft_discarded`, `file.attached`, `file.purged`, `annotation.created`, `annotation.archived`, `comment.created`, `comment.edited`, `comment.deleted`, `comment.resolved` (feed-only for author per EVENT_MODEL §7.3), `comment.reopened` (feed-only for author per EVENT_MODEL §7.3), `invitation.expired`, `invitation.revoked`, `decision.recorded`, `release.created`, `release.item_added`, `release.item_removed`, `change.*` (leads-via-feed, no push), all 4 `requirement.*` events.

Some of these do carry `Notify=✓` in EVENT_MODEL.md §4 (e.g., `asset.archived → project participants`, `annotation.resolved → annotation author`). For MVP APP 010 the following EVENT_MODEL rows also produce a notification type (aligning with EVENT_MODEL's explicit `Notify` cell):

| `notification_type` | Fires on | Recipient | Category | Priority |
|---|---|---|---|---|
| `asset.archived_in_your_project` | `asset.archived` | Project participants | `project_activity` | `low` |
| `asset.unarchived_in_your_project` | `asset.unarchived` | Project participants | `low` | `low` |
| `annotation.your_annotation_resolved` | `annotation.resolved` | Annotation author | `project_activity` | `low` |
| `change.needs_leads_attention` | `change.created` | Project leads | `project_activity` | `medium` |
| `change.your_change_accepted` | `change.accepted` | Change author | `governance_state_change` | `medium` |
| `change.your_change_rejected` | `change.rejected` | Change author | `governance_state_change` | `medium` |
| `change.your_change_withdrawn` | `change.withdrawn` | Change author | `governance_state_change` | `low` |
| `project.archived_in_your_project` | `project.archived` | Project participants | `governance_state_change` | `medium` |
| `project.unarchived_in_your_project` | `project.unarchived` | Project participants | `project_activity` | `low` |
| `invitation.your_invitation_expired` | `invitation.expired` (optional recipient per EVENT_MODEL §4.1) | Inviter (optional) | `system` | `low` |

### 5.9 Type count

- **Wired in v1**: ~25 `notification_type` values across the six source areas.
- **Name-reserved for future waves**: ~10 additional values across releases, requirements, comments, changes, reviews.

The full enumeration lives in `src/features/notifications/types.ts` as a discriminated union. Adding a new type is an additive extension per §26.

---

## 6. Notification categories

Categories group notification types into a small, user-facing filter vocabulary. Every `notification_type` maps to exactly one category. The category enum is stable and small; adding a category is a rare re-freeze event.

### 6.1 The six v1 categories

| `category` | Meaning | Includes (representative types) | Default filter behavior |
|---|---|---|---|
| `assigned_to_me` | Something needs the recipient's action right now | `review.assigned_to_you`, `approval.awaiting_your_decision`, `project.you_were_added` | Default tab on Inbox after "All" and "Unread" |
| `mentions` | The recipient was directly named | `comment.mentioned_you` | Own tab on Inbox |
| `project_activity` | Something happened in a project the recipient participates in | `release.published_in_your_project`, `review.reviewer_responded_on_your_review`, `asset.archived_in_your_project`, `change.needs_leads_attention` | Filter chip |
| `governance_state_change` | A binding decision or role change occurred | `approval.approved_your_request`, `release.withdrawn_in_your_project`, `workspace.your_role_changed`, `project.you_were_removed` | Own tab on Inbox |
| `deadlines` | (Reserved for future — no v1 emitter until `review.deadline_approached` / `approval.deadline_approached` cron ships) | (empty in v1) | Filter chip visible but empty state |
| `system` | Administrative / platform events not tied to project work | `workspace.you_were_invited`, `invitation.your_invitation_expired` | Filter chip |

### 6.2 Enum vs tags

Categories are modeled as a **single-valued text column with CHECK constraint** (not a tag array), per G-13. Tags are reserved but not shipped; rationale: v1 needs simple filter chips, and a single-valued category matches how humans think about notifications. If a notification legitimately spans two categories, the routing table picks the more specific one (usually `assigned_to_me > mentions > governance_state_change > project_activity > deadlines > system`).

### 6.3 Deadline category — reserved shape

When the cron slice ships `review.deadline_approached`, `review.deadline_passed`, `approval.deadline_approached` (all reserved per EVENT_MODEL.md §7 / APP 006 §21 / APP 007 §21 certifications), APP 010's router gains the corresponding notification types (`review.deadline_approaching_yours`, `approval.deadline_approaching_yours`, etc.) with `category='deadlines'`. Names are name-locked here so the future re-freeze does not rename the category or the types.

---

## 7. Notification priorities

### 7.1 The priority ladder

Five values, top-down:

| `priority` | Effect on presentation | Effect on badge count | Effect on toast |
|---|---|---|---|
| `critical` | Bright accent color; sticky in Inbox top; may trigger a modal in future | Included | Toast auto-shown; requires explicit dismiss |
| `high` | Elevated accent; sorted above `medium` within same day | Included | Toast auto-shown (default 6s) |
| `medium` | Standard row; default sort | Included | No toast (silent notification) |
| `low` | De-emphasized styling; can be collapsed by future preference | Included | No toast |
| `informational` | Grayscale; sub-line only | **Excluded from primary bell badge**; included in NavRail badges only | No toast |

Decision recorded as G-14 in §28 — priority enum values chosen to mirror APP 008 requirement `priority` naming for terminology consistency across the platform.

### 7.2 Priority assignment table

The default priority for each notification type is set in the routing table (§8). Priority is **immutable per notification row** — a `high`-priority notification does not decay to `medium` over time. Preferences that could downgrade priority per-user are reserved for the future `notification_preferences` table (§4.4).

### 7.3 Security-sensitive events

Every event where EVENT_MODEL.md §4 marks `Sec=✓` maps to a notification with `priority='critical'` or `priority='high'` and `category='governance_state_change'`:

- `workspace.member.role_changed` → `high`.
- `workspace.member.suspended` → `critical`.
- `workspace.member.removed` → `critical`.
- `stakeholder.revoked` → `high`.
- `release.finalized` / `release.withdrawn` → `medium`/`high` respectively (Sec=✓ per EVENT_MODEL.md §4.12).
- `project.participant.removed` → `high`.
- `file.purged` → not user-facing (system event; no notification).

### 7.4 Presentation-only overrides

The v1 UI never permits users to override a notification's own priority (there are no per-user preferences per G-3). Filter chips in the Inbox let users hide `informational` or `low` — that is a view filter, not a mutation.

---

## 8. Notification routing

The **routing table** maps each source event type to the set of notification types it may produce, plus the recipient rule and default priority. This is the canonical source of truth for the router trigger (§20). Every row cites EVENT_MODEL.md for the recipient token.

### 8.1 Routing table (v1)

| Source `event_type` | Recipient rule (§9) | Produces `notification_type` | Category | Priority | Channels attempted |
|---|---|---|---|---|---|
| `review.opened` | Direct-actor: `review_participants` where `profile_id != actor` | `review.assigned_to_you` | `assigned_to_me` | `high` | `in_app` |
| `review.completed` | Requester + roster: `review.created_by_profile_id`, `review_participants.profile_id` (excluding actor) | `review.your_review_completed` (for creator); no distinct type for reviewers in v1 (they receive same row) | `governance_state_change` | `medium` | `in_app` |
| `review.cancelled` | Requester + roster: same as above | `review.your_review_cancelled` | `governance_state_change` | `medium` | `in_app` |
| `review.reviewer_responded` | Requester: `reviews.created_by_profile_id` (excluding actor) | `review.reviewer_responded_on_your_review` | `project_activity` | `medium` | `in_app` |
| `approval.requested` | Direct-actor: `approval_request_approvers` where `profile_id != actor` | `approval.awaiting_your_decision` | `assigned_to_me` | `high` | `in_app` + `email_payload` (per EVENT_MODEL §5.6 / §7.6) |
| `approval.responded` | Requester: `approval_requests.created_by_profile_id` (excluding actor) | `approval.responded_on_your_request` | `project_activity` | `medium` | `in_app` |
| `approval.approved` | Requester + project leads (per EVENT_MODEL D10) | `approval.approved_your_request` | `governance_state_change` | `high` | `in_app` |
| `approval.rejected` | Requester + project leads (per EVENT_MODEL D10) | `approval.rejected_your_request` | `governance_state_change` | `high` | `in_app` |
| `approval.expired` | Requester + project leads | `approval.expired_your_request` | `governance_state_change` | `high` | `in_app` |
| `approval.cancelled` | Approvers with `pending` slot (per EVENT_MODEL §4.11) | `approval.request_cancelled` | `governance_state_change` | `medium` | `in_app` |
| `comment.mentioned` | Direct-mention: `subject_snapshot.mentioned_profile_id` (excluding actor) | `comment.mentioned_you` | `mentions` | `high` | `in_app` |
| `annotation.resolved` | Owner: `annotations.author_profile_id` (excluding actor) | `annotation.your_annotation_resolved` | `project_activity` | `low` | `in_app` |
| `change.created` | Project leads (excluding actor) | `change.needs_leads_attention` | `project_activity` | `medium` | `in_app` |
| `change.accepted` | Owner: `changes.author_profile_id` (excluding actor) | `change.your_change_accepted` | `governance_state_change` | `medium` | `in_app` |
| `change.rejected` | Owner: `changes.author_profile_id` (excluding actor) | `change.your_change_rejected` | `governance_state_change` | `medium` | `in_app` |
| `change.withdrawn` | Owner: `changes.author_profile_id` (excluding actor) | `change.your_change_withdrawn` | `governance_state_change` | `low` | `in_app` |
| `release.finalized` | Project-broadcast: all `project_participants` with `release.view` (excluding actor) | `release.published_in_your_project` | `project_activity` | `medium` | `in_app` |
| `release.withdrawn` | Same set as prior `release.finalized` for the same release (per APP 009 §22.1 parity) — excluding actor | `release.withdrawn_in_your_project` | `governance_state_change` | `high` | `in_app` |
| `asset.archived` | Project-broadcast: `project_participants` (excluding actor) | `asset.archived_in_your_project` | `project_activity` | `low` | `in_app` |
| `asset.unarchived` | Project-broadcast: `project_participants` (excluding actor) | `asset.unarchived_in_your_project` | `project_activity` | `low` | `in_app` |
| `project.archived` | Project-broadcast: `project_participants` (excluding actor) | `project.archived_in_your_project` | `governance_state_change` | `medium` | `in_app` |
| `project.unarchived` | Project-broadcast: `project_participants` (excluding actor) | `project.unarchived_in_your_project` | `project_activity` | `low` | `in_app` |
| `project.participant.added` | Direct-actor: `project_participants` row that was inserted (`profile_id`) — excluding actor | `project.you_were_added` | `assigned_to_me` | `high` | `in_app` |
| `project.participant.role_changed` | Affected participant (excluding actor) | `project.your_role_changed` | `governance_state_change` | `medium` | `in_app` |
| `project.participant.removed` | Affected participant (excluding actor) | `project.you_were_removed` | `governance_state_change` | `high` | `in_app` |
| `workspace.member.invited` | Invitee-by-email (pre-profile) | `workspace.you_were_invited` | `system` | `high` | `email_payload` only (no in-app row — invitee has no profile yet; per EVENT_MODEL §7.6) |
| `workspace.member.activated` | Inviter (excluding actor) | `workspace.your_invitation_was_accepted` | `system` | `medium` | `in_app` |
| `workspace.member.role_changed` | Affected member (excluding actor) | `workspace.your_role_changed` | `governance_state_change` | `high` | `in_app` |
| `workspace.member.suspended` | Affected member (excluding actor) | `workspace.you_were_suspended` | `governance_state_change` | `critical` | `in_app` + `email_payload` |
| `workspace.member.removed` | Affected member (excluding actor) | `workspace.you_were_removed` | `governance_state_change` | `critical` | `in_app` + `email_payload` |
| `stakeholder.invited` | Invitee-by-email (pre-profile) | `stakeholder.you_were_invited` | `system` | `high` | `email_payload` only |
| `stakeholder.claimed` | Inviter (excluding actor) | `stakeholder.claimed_by_recipient` | `system` | `medium` | `in_app` |
| `stakeholder.revoked` | Affected stakeholder (excluding actor) | `stakeholder.you_were_revoked` | `governance_state_change` | `high` | `in_app` |
| `invitation.expired` | Inviter (optional per EVENT_MODEL §4.1) | `invitation.your_invitation_expired` | `system` | `low` | `in_app` |
| **All other P0 events** | — | (none — feed-only per EVENT_MODEL.md §7.3–§7.4) | — | — | — |

### 8.2 Routing extensibility

- New source event → new routing table row → additive `notification_type` addition; strictly additive per §26.
- Reserved event names (e.g. `review.deadline_approached`, `approval.deadline_approached`, `release.scheduled`, `release.superseded`, `release.recalled`, `release.notes_updated`, all `notification.*` reserved names) pre-lock target row shapes in the router; no emitter until the source slice re-freezes.
- The routing table lives in a single application constant (`src/features/notifications/routing.ts`) plus a mirror in the DB trigger body (`resolve_notification_router_targets(activity_event_row)`, **[additive]**). Both must be updated in the same additive change.

### 8.3 Payload extension source fields the router relies on

- `activity_events.event_type` — primary dispatch.
- `activity_events.subject_kind` — secondary dispatch for polymorphic events.
- `activity_events.subject_id` — identifies the specific subject (release, review, approval, requirement, comment, project participant, workspace member).
- `activity_events.project_id` — scope for project-broadcast recipient rule (§9.3).
- `activity_events.workspace_id` — scope for workspace-scoped events with NULL project_id.
- `activity_events.actor_profile_id` — self-exclusion source.
- `activity_events.subject_snapshot` — carries additive payload keys registered by APP 006–009 (see APP 006 §17, APP 008 §12, APP 009 §20.4). The router reads only the keys documented per the source slice's freeze index; unknown keys are ignored per the additive-consumer contract.

APP 010 registers **no** new required payload keys on any frozen event. Every routing decision runs on keys already frozen by the emitting slice.

---

## 9. Recipient resolution

Recipient resolution turns an `activity_events` row into a set of `recipient_profile_id` values. The rules below compose in the router; a single event may exercise multiple rules and the results are unioned + deduped + self-excluded.

### 9.1 Direct-actor rule

The most common rule: notifications about "you being assigned / added / mentioned" go to the actor of the assignment.

- `review.opened` → each row of `review_participants` for the review, resolving `profile_id` per XOR (`workspace_member_id` OR `stakeholder_id` — mirroring APP 006 pattern).
- `approval.requested` → each row of `approval_request_approvers` for the request.
- `project.participant.added` → the newly-added participant.
- `workspace.member.*` (except `.invited`) → the affected member.
- `comment.mentioned` → the single `mentioned_profile_id` in the event payload.

### 9.2 Owner rule

Notifications about mutations to a resource go to its owner / author.

- `annotation.resolved` → `annotations.author_profile_id`.
- `change.*` (accepted, rejected, withdrawn) → `changes.author_profile_id`.
- Reserved: `requirement.assessed` critical-regression → requirement author (when requirement ownership ships; deferred).

### 9.3 Project-broadcast rule

High-visibility events fan out to every project participant with the appropriate capability.

- `release.finalized`, `release.withdrawn` → all `project_participants` for `activity_events.project_id` where the participant holds `release.view` (frozen APP 009 capability).
- `asset.archived`, `asset.unarchived`, `project.archived`, `project.unarchived` → all `project_participants` for the project.
- Notification `project.you_were_added` uses the direct-actor rule (§9.1) — the project-broadcast is not for participant additions.

### 9.4 Requester rule

Notifications about "your request was acted on" go to the requester.

- `review.completed`, `review.cancelled`, `review.reviewer_responded` → `reviews.created_by_profile_id`.
- `approval.responded`, `approval.approved`, `approval.rejected`, `approval.expired` → `approval_requests.created_by_profile_id`.
- `stakeholder.claimed` → `invitations.invited_by_profile_id` (via stakeholder linkage).

### 9.5 Project-leads rule

Governance outcome events also fan out to project leads (users with `project_participants.role='lead'`).

- `approval.approved`, `approval.rejected`, `approval.expired` — per EVENT_MODEL D10.
- `change.created` — per EVENT_MODEL §4.9.

### 9.6 Invitee-by-email rule (pre-profile)

For events fired before the recipient has a profile:

- `workspace.member.invited` → the invitee's email address (stored in `invitations.email`).
- `stakeholder.invited` → the invitee's email address.

For these, **no in-app `notifications` row is inserted**; instead the router materializes an **email-ready payload** (see §10.4) and hands it to the future email delivery layer. In v1 APP 010 does not send email — it only produces the payload; a downstream cron or edge-function (deferred; not owned by APP 010) picks up the payload. See §29.2.

### 9.7 Deduplication rule

Per (`source_event_id`, `recipient_profile_id`) is unique. Enforced by a unique index (`notifications_dedup_uniq_idx`) on those two columns (**[additive]**; §26.7). If a rule composition produces the same `(event, recipient)` pair via two paths (e.g., a request creator who is also a project lead), the router INSERTs once. G-7.

### 9.8 Self-exclusion rule

The event's actor never receives a notification for their own action. Enforced by the router:

```
WHERE recipient_profile_id != activity_events.actor_profile_id
```

Applies universally except for `actor_kind='system'` events (`invitation.expired`, `approval.expired`, `file.purged`, system-emitted `approval.approved`/`.rejected`), where there is no actor to exclude. G-8, G-15.

### 9.9 Access-check rule (RLS pre-filter — belt & braces)

Even if a recipient is resolved by the rules above, the notifications SELECT policy re-verifies at read time that the recipient still has access to the source subject. Notifications never bypass RLS per EVENT_MODEL.md §7.7 and §21.1. Rationale: memberships change; a user removed from a project between the event and the fetch should not see historical notifications leak project-scoped payload data.

### 9.10 Recipient-list boundedness

A single event's recipient set is bounded by:
- Direct-actor: 1 recipient (mentions, participant events) or O(N) where N is the roster size (reviews, approvals — capped by product-side maximum roster size per APP 006 / APP 007).
- Project-broadcast: O(P) where P is the number of project participants — bounded by the product-side maximum (typically < 200 in practice).
- Owner / requester: 1 recipient.
- Project-leads: O(L) where L is typically 1–3 per project.

The router does not batch across events; if a single event triggers 200 notifications, 200 rows are INSERTed in the same transaction. This is acceptable per G-18 (no v1 batching); high-volume future events should re-evaluate.

---

## 10. Delivery states

### 10.1 The delivery-state enum

`delivery_state text CHECK (delivery_state IN ('pending', 'delivered', 'failed', 'suppressed'))`:

- `pending` — the router has resolved the recipient but delivery to the channel(s) is not yet complete. Reserved for future async channels; not used in v1.
- `delivered` — the notification is available on all attempted channels. **v1 default** because in-app delivery is synchronous (write to the `notifications` table = deliver to Inbox).
- `failed` — a channel attempt failed and no retry is scheduled. Reserved for future async channels.
- `suppressed` — the router refused to deliver because of a user preference or category-mute. Reserved for future preferences table (§4.4); not used in v1.

### 10.2 v1: synchronous in-app delivery

In v1 every APP-010-owned channel is in-app (the row in `notifications` **is** the delivery), so `delivery_state` on INSERT is always `'delivered'`. There is no async retry loop, no dead-letter queue, no failure surface. If the router trigger raises, the parent workflow transaction rolls back (see §20.3) — which is the desired posture for the "committed fact → derived delivery" invariant.

### 10.3 Future asynchronous channels

When email / push land (post-v1):
- The router still INSERTs the row synchronously with `delivery_state='pending'` and `channels_attempted={in_app, email}` (or push).
- A background worker (deferred; not owned by APP 010) picks up rows with a non-in-app channel and dispatches via SMTP / APNS / FCM.
- On success: worker UPDATEs `delivery_state='delivered'` and writes to the reserved `notification_deliveries` table (§4.4) for per-channel provenance.
- On failure: worker sets `delivery_state='failed'` and records last-error in `notification_deliveries.last_error_text`.

APP 010 v1 does not ship this worker. It only produces the payload contract that a future worker will consume.

### 10.4 Payload materialization

The router copies from the source event into the notification's own `payload jsonb`:

**Base keys (always present):**
- `source_event_type` — mirror of `activity_events.event_type`.
- `actor_profile_id` — mirror of the source actor (NULL for system events).
- `actor_display_name` — resolved at router time from `profiles.display_name` (or "System" for system events); frozen at INSERT (rendering stability).
- `subject_kind`, `subject_id`, `subject_label` — mirrored.
- `occurred_at` — mirror of `activity_events.occurred_at`.
- `deep_link` — `{ kind: <deep-link kind per source slice>, id: <subject_id> }`. The Inbox and Notification Center render this via APP 002 `DeepLinkResolver` — APP 010 does not own the target route (§15.1).

**Rendering-only keys (per notification_type):**
- Type-specific fields the UI needs for the preview snippet — e.g. `preview_snippet`, `avatar_seed`, `type_icon_hint`.
- Extracted from `subject_snapshot` — never a full copy; only the small subset the UI renders.

**Email-ready keys (populated when `channels_attempted` includes `email_payload`):**
- `email_subject_line` — pre-rendered subject (e.g., "You have been added to the project 'Kitchen Redesign'").
- `email_body_snippet` — plain-text one-paragraph preview.
- `email_cta_url` — full URL to the deep-link target (workspace-qualified).
- `email_cta_label` — button label (e.g., "Review this approval").

**Push-ready keys (populated when `channels_attempted` includes `push_payload`):**
- `push_title`, `push_body` — short strings for notification-center display.
- `push_data` — `{ deep_link_kind, deep_link_id, workspace_id, project_id }` object for the client to route on tap.

**Note on payload sizing.** The payload is kept small (typical < 2 KB) — full row contents from the source subject are never embedded per EVENT_MODEL.md §5 conventions. If the UI needs additional data (e.g., the full comment body for a mention notification), it fetches at render time via the source slice's read RPC using `subject_id`.

### 10.5 Suppression (reserved)

Suppression exists only as a name-locked delivery-state; in v1 no code path sets `delivery_state='suppressed'`. When preferences ship (post-v1), the router will consult the preferences table and set `suppressed` instead of INSERTing (or INSERT + mark suppressed for audit; TBD in the preferences slice).

---

## 11. Read/unread model

### 11.1 State markers

Three orthogonal per-user flags on the notification row (G-5):

- `read_at timestamptz` — NULL = unread; non-NULL = read.
- `dismissed_at timestamptz` — NULL = not dismissed; non-NULL = dismissed.
- `archived_at timestamptz` — NULL = not archived; non-NULL = archived.

Orthogonality: a notification can be `read` + `dismissed` + `archived` independently. The UI collapses these into a single presentation lifecycle (`unread → read → dismissed | archived`), but the storage layer keeps the flags separate for auditability and future preference features.

### 11.2 RPCs (all **[additive]**)

| RPC | Purpose | Bulk? |
|---|---|---|
| `mark_notification_read(notification_id)` | Set `read_at=now()` if NULL; no-op if already read | No |
| `mark_notification_unread(notification_id)` | Set `read_at=NULL` — re-marks the notification unread (G-5 explicitly allows) | No |
| `mark_all_notifications_read(workspace_id)` | Set `read_at=now()` for every unread notification of the caller in the workspace (single UPDATE per G-10) | Yes |
| `mark_notifications_read_bulk(notification_ids uuid[])` | Set `read_at=now()` for each listed notification if the caller owns them | Yes |
| `dismiss_notification(notification_id)` | Set `dismissed_at=now()`; also sets `read_at=now()` if unread (dismissing implies acknowledged) | No |
| `dismiss_notifications_bulk(notification_ids uuid[])` | Dismiss many | Yes |
| `archive_notification(notification_id)` | Set `archived_at=now()`; also `read_at=now()` if unread | No |
| `archive_notifications_bulk(notification_ids uuid[])` | Archive many | Yes |

All RPCs enforce `recipient_profile_id = auth.uid()` at the RPC boundary (SECURITY DEFINER + capability check + explicit `WHERE recipient_profile_id = auth.uid()` predicate) and additionally at RLS. Cross-recipient mutation is impossible.

### 11.3 Effect on badge counts

Each RPC invalidates:
- `qk.notificationBadgeCount(wsId)` (bell badge).
- `qk.notificationsUnread(wsId, filters)` (unread list).
- `qk.notificationsInbox(wsId, filters)` (inbox list — if the filters cover the row).
- `qk.notificationCenter(wsId)` (popover list).
- Per-category badges on NavRail items (see §14.3).

Server-side, the effect on the badge count is a re-query — not maintained as a materialized count. G-6: badge counts derive from the `notifications` table only, never from workflow tables.

### 11.4 Undo affordance

- `mark_notification_read` in the Notification Center popover shows a transient "Undo" for 5s that fires `mark_notification_unread`.
- `dismiss_notification` and `archive_notification` do **not** show Undo in v1 (they are stronger intents; the row can still be found in the Archived tab).
- `mark_all_notifications_read` shows an Undo for 5s that reverses the entire batch (via a stored `last_bulk_read_timestamp` on the caller; deferred implementation — v1 shows no Undo for this bulk op; G-10 documents the trade-off).

### 11.5 Idempotency

Every mutation is idempotent under the semantics "eventually N such calls produce the same terminal state":
- `mark_notification_read` on an already-read row: no-op.
- `mark_all_notifications_read` on a workspace with 0 unread: no-op, returns 0 count.
- `dismiss_notification` on a dismissed row: no-op.
- `archive_notification` on an archived row: no-op.

Each RPC returns a summary (rows affected + resulting state) so the client can update local cache without a re-fetch.

---

## 12. Inbox architecture

### 12.1 Route

`/workspace/:ws_id/inbox` — the workspace-scoped Inbox screen. Owned by APP 010. NavRail entry added per §14.1.

There is no project-scoped Inbox (`/workspace/:ws_id/project/:project_id/inbox`) in v1: users think of "my inbox" as a person-scoped concept, and the workspace scope naturally aggregates project-scoped notifications. The URL grammar supports `?scope=project&project_id=...` as a filter within the workspace inbox — see §16. G-12.

### 12.2 Tabs

Six tabs at the top of the Inbox, in the following left-to-right order:

| Tab | URL param | Filter predicate |
|---|---|---|
| **All** | `?tab=all` (default) | Every non-dismissed, non-archived notification for the caller in the workspace |
| **Unread** | `?tab=unread` | `read_at IS NULL AND dismissed_at IS NULL AND archived_at IS NULL` |
| **Mentions** | `?tab=mentions` | `category='mentions' AND dismissed_at IS NULL AND archived_at IS NULL` |
| **Assigned** | `?tab=assigned` | `category='assigned_to_me' AND dismissed_at IS NULL AND archived_at IS NULL` |
| **Governance** | `?tab=governance` | `category='governance_state_change' AND dismissed_at IS NULL AND archived_at IS NULL` |
| **Archived** | `?tab=archived` | `archived_at IS NOT NULL` |

The Dismissed set is intentionally not surfaced as a tab in v1 (rationale: dismissal is "hide, don't retain"; users who want to find a dismissed notification search or use `?tab=archived` after also archiving). Reserved future tab: `?tab=dismissed`.

### 12.3 Filters

Below the tabs, a filter bar (`NotificationFilterBar`, §27.4) with:

- **Category chips** (multi-select): `assigned_to_me | mentions | project_activity | governance_state_change | deadlines | system`.
- **Priority chips** (multi-select): `critical | high | medium | low | informational`.
- **Source module chips** (multi-select): `review | approval | requirement | release | comment | change | annotation | project | workspace | stakeholder | invitation`.
- **Date range** (from / to): `date_from`, `date_to`.
- **Project filter** (single-select dropdown): filters to notifications where `project_id` matches; NULL means "workspace-scoped events only" is a special selection.
- **Actor filter** (single-select typeahead): filters to notifications where `actor_profile_id` matches. Useful for "show me everything Alice did that I need to know about."

All filters compose (AND semantics between filter families; OR within a family with multi-select).

### 12.4 Pagination

Cursor-based, `limit=50` default. Cursor is `(created_at desc, id desc)` — deterministic per the standard qk pattern.

### 12.5 Empty / loading / error states

| Condition | Copy |
|---|---|
| Empty inbox (all tabs) | "You're all caught up — no notifications yet in this workspace." |
| Empty Unread | "Nothing unread. You've handled everything." |
| Empty Mentions | "You have not been mentioned in any comments yet." |
| Empty Assigned | "Nothing is currently waiting on you. Good work." |
| Empty Governance | "No governance activity in the last <retention window>." |
| Empty Archived | "You have not archived any notifications yet." |
| Empty after filters | "No notifications match these filters. Clear filters or try a different view." |
| Loading | 8 skeleton rows (`NotificationCard` skeleton, §24) |
| Failed to load | "Couldn't load your notifications. Retry." + Retry button |

### 12.6 Bulk actions

Selecting one or more notification cards exposes a bulk action bar at the top of the inbox:

- **Mark read** (bulk) — via `mark_notifications_read_bulk`.
- **Dismiss** (bulk) — via `dismiss_notifications_bulk`.
- **Archive** (bulk) — via `archive_notifications_bulk`.
- **Select all** — selects every card matching current tab + filters (paginated bounded to 500 for the RPC call).

### 12.7 Card rendering

Each card (`NotificationCard`, §27.4) renders:

- Priority chip on the left (color-coded per §7.1).
- Actor avatar + display name ("Alice" or "System").
- Notification type icon (per source module).
- Title line derived from `subject_label` (e.g., "Kitchen Layout · v3").
- Snippet line from `payload.preview_snippet` (2–3 sentences max).
- Timestamp (`occurred_at`, relative — "2 hours ago").
- Read/unread indicator (blue dot on unread).
- Category chip on the right.
- Row-hover: quick actions (mark read / dismiss / archive / copy link).

Click on the card body: navigates via `deep_link` and auto-marks read (single RPC call).

### 12.8 Group-by-day headers

Optional (default on): day headers ("Today", "Yesterday", "Earlier this week", "<Month DD>"). Deferred: group-by-source-module toggle.

---

## 13. Notification Center UI

### 13.1 Trigger

Bell icon in the top bar of the workspace layout (`WorkspaceHeader` — extended by APP 010 to include the `NotificationBell` primitive per §27.4). Click to open the popover; click again or click outside to close. Keyboard: press `N` to toggle (adds to the workspace-scoped hotkey palette per §14.4).

### 13.2 Popover contents

- **Header row**: title "Notifications" + link "View all in Inbox" (deep-link to `/workspace/:ws_id/inbox?tab=all`).
- **Sub-tabs**: `Unread` (default) | `All`. Two tabs only — richer filtering lives in the Inbox.
- **List**: 10–20 most recent notifications (bounded by `limit=15` in v1).
- **Group-by-day**: headers within the list ("Today", "Yesterday", "This week", "Older").
- **Per-item**: same card body as Inbox but compressed to two lines (title + one-line snippet + timestamp).
- **Footer row**: "Mark all read" button (fires `mark_all_notifications_read`).

### 13.3 Behavior

- On first open in a session: auto-fetch (React Query, invalidated on any workflow mutation per §18).
- Click on a card: navigates + marks read (same as Inbox).
- Middle-click / Cmd+click on a card: opens in a new tab, does not mark read.
- If more than `limit=15` unread exist, the footer shows "N more in Inbox".

### 13.4 Loading / empty / error

- Loading: 5 skeleton rows.
- Empty (Unread): "You're up to date." + friendly empty-state art.
- Empty (All): "No notifications yet."
- Error: "Couldn't load. Retry." + Retry button.

### 13.5 Toasts

APP 010 owns a toast presentation layer for high-priority notifications delivered while the user is active in the app:

- On INSERT of a `critical` or `high` notification for the current user in the current workspace, a toast animates in.
- Duration: `critical` sticky until dismissed; `high` 6 seconds; `medium` / `low` / `informational` no toast.
- Position: top-right on desktop; top-center on mobile.
- Max **3 concurrent toasts** (G-19 — rate limit); overflow visible in the Notification Center popover only.
- Click on toast: same as card click (deep-link + mark read).
- "X" dismisses without navigating.
- Requires realtime transport to fire on freshly-committed notifications; in v1 falls back to polling every 60s via `useNotificationBadgeCount` — toasts are best-effort while realtime is out (§25).

---

## 14. Badge architecture

### 14.1 Bell-icon badge

The bell icon shows an unread count badge, workspace-scoped, computed by:

```
SELECT COUNT(*) FROM notifications
WHERE recipient_profile_id = auth.uid()
  AND workspace_id = :ws_id
  AND read_at IS NULL
  AND dismissed_at IS NULL
  AND archived_at IS NULL
  AND priority != 'informational'
```

- Count displayed 1–99; 100+ shows "99+".
- Empty state: no badge (bell icon un-decorated).
- Backing RPC: `get_notification_badge_count(ws_id)` (**[additive]**; §26.3).
- Query key: `qk.notificationBadgeCount(wsId)` (§17).
- Polled every 60s per §25.4 in v1; realtime push when APP 011 ships.

### 14.2 NavRail category badges

Individual NavRail entries in the workspace layout also carry contextual badges — but these are **derived from the source slice's own inbox count RPC where one exists, plus notification-derived augmentation** (G-6 subordinates to source-of-truth):

| NavRail item | Badge source | Notes |
|---|---|---|
| Approvals | `get_approval_inbox_count(ws_id)` (frozen APP 007) | Unchanged; APP 010 adds a "notification unread" secondary indicator only if the item has an unread notification-typed row |
| Reviews | `get_review_inbox_count(ws_id)` (frozen APP 006) | Same posture |
| Requirements | `get_requirements_inbox_count(ws_id)` (frozen APP 008) | Same posture |
| Releases | `get_release_inbox_count(ws_id)` (frozen APP 009) | Same posture |
| Inbox (new — APP 010) | `get_notification_badge_count(ws_id)` (new — this slice) | Sole source |
| All other NavRail items | No badge in v1 | Reserved for future |

The NavRail existing badge sources continue to be authoritative for their respective workflow surfaces. APP 010's added dimension is a **workspace-level unread count** on the new "Inbox" NavRail entry — never overriding an existing per-module badge.

### 14.3 Cross-slice badge invalidation

When a `notifications` row is INSERTed, the router fires nothing observable on the client. The client polls (v1) or subscribes (post-APP-011) to keep badges live. Client-side query invalidation runs on:
- Any local mutation on `notifications` (mark read, dismiss, archive).
- Any cross-slice workflow mutation the caller performs (finalize approval → invalidate approval inbox + notification badge; finalize release → same).
- Route change into a page that shows a badge (SPA lazy invalidation).

### 14.4 Bell icon hotkey

`N` (single character) toggles the Notification Center popover. Bound in `useWorkspaceHotkeys` (from APP 006, extended additively per §27.5). Collides with nothing in prior slices (APP 006 uses `R` for "new review"; APP 007 uses `A` for "new approval"; APP 008 uses `Q` for "new requirement"; APP 009 uses `N` in release dashboards for "new release" — this is context-scoped per G-19 in APP 009, so the workspace-level `N` for notifications is unambiguous outside the release dashboard). See §16.6.

---

## 15. Deep links

### 15.1 Deep-link posture

APP 010 **does not own** the target routes for notifications — each notification's `deep_link` field points at a `/deep/<kind>/:id` route owned by the source slice:

- `review.assigned_to_you` → `/deep/review/:review_id` (owned by APP 006).
- `approval.awaiting_your_decision` → `/deep/approval/:approval_request_id` (owned by APP 007).
- `release.published_in_your_project` → `/deep/release/:release_id` (owned by APP 009).
- `comment.mentioned_you` → `/deep/comment/:comment_id` (owned by APP 005).
- `project.you_were_added` → `/workspace/:ws_id/project/:project_id` (a canonical project URL, resolved via APP 003).
- `workspace.your_role_changed` → `/workspace/:ws_id/settings/members` (owned by APP 002 / APP 003 settings).

The `payload.deep_link` object stores `{ kind, id, workspace_id, project_id?, extra? }`, and the client renders through `DeepLinkResolver` (APP 002) — adding no new resolver kinds unless the source slice does. G-20.

### 15.2 The `/deep/notification/:id` fallback

APP 010 owns exactly one deep-link kind of its own: `notification`. This resolves to `/workspace/:ws_id/inbox?highlight=<id>` — a rarely-used route intended for external referrers ("here is a link to that notification for archival reference"). It is a fallback; the primary deep-link path is always the source-slice's own deep link.

### 15.3 Inbox route

`/workspace/:ws_id/inbox` — the sole APP-010-owned page route (see §12.1).

### 15.4 `highlight=<notification_id>` param

Adding `?highlight=<uuid>` to `/workspace/:ws_id/inbox` scrolls the specified notification card into view and briefly pulses it. Non-authoritative; ignored if the id is invalid or the notification is not visible under current filters.

### 15.5 Copy-link affordance

Every notification card has a "Copy link" quick action wired to `useCopyLink` (APP 005 primitive, extended by APP 006/APP 007/APP 008/APP 009). APP 010 adds `LinkKind` values:
- `'notification'` — copies `/deep/notification/:id`.
- `'inbox'` — copies `/workspace/:ws_id/inbox` (with the current filter set encoded in the URL).

### 15.6 Deep-link 403 posture

If the recipient has lost access to the source subject between event emission and click (rare — role change, project participation removal), the source slice's `/deep/*` route already handles 403 with a friendly "You do not have access." APP 010 does not attempt a graceful fallback; the recipient sees the source slice's standard 403 screen, and the notification row remains visible (per the "notifications never bypass RLS" principle, the notification row itself may also become hidden if the RLS SELECT policy filters on subject access — see §21.1).

---

## 16. URL grammar

### 16.1 Inbox URL params

`/workspace/:ws_id/inbox` accepts the following URL parameters (all optional):

| Param | Values | Purpose |
|---|---|---|
| `tab` | `all` (default) / `unread` / `mentions` / `assigned` / `governance` / `archived` | Selects the visible tab |
| `category` | comma-separated: `assigned_to_me,mentions,project_activity,governance_state_change,deadlines,system` | Filter chip state |
| `priority` | comma-separated: `critical,high,medium,low,informational` | Filter chip state |
| `source` | comma-separated: `review,approval,requirement,release,comment,change,annotation,project,workspace,stakeholder,invitation` | Filter by source module |
| `project_id` | uuid | Filter to a single project |
| `actor_id` | uuid | Filter to a single actor |
| `date_from` | ISO date | Filter to notifications on/after this date |
| `date_to` | ISO date | Filter to notifications on/before this date |
| `cursor` | opaque | Pagination |
| `highlight` | uuid | Scroll a specific notification into view |

### 16.2 Notification Center popover

Transient UI — no URL state. Opening/closing the popover does not push a URL. "View all in Inbox" navigates to `/workspace/:ws_id/inbox?tab=<current subtab>` (unread / all).

### 16.3 URL param collision check

Verified against every prior slice's URL grammar:

| Param | Prior slice using | Collision? |
|---|---|---|
| `tab` | APP 003 (Design Workspace right-panel tab), APP 009 (Release Detail tab) | Different scope (inbox route); no collision — every route parses its own `tab` values. |
| `category` | (none) | New; unique. |
| `priority` | APP 008 requirement filters | Different scope (requirement dashboard); no collision. |
| `source` | (none) | New; unique. |
| `project_id` | APP 002 workspace-scoped queries | Same semantic (filter to project); consistent. |
| `actor_id` | APP 008 (requirement author filter) | Same semantic; consistent. |
| `date_from` / `date_to` | APP 007, APP 009 date filters | Same semantic; consistent. |
| `cursor` | Every paginated list | Same semantic; consistent. |
| `highlight` | (none) | New; unique. |

No collision. Adding new inbox params in future is additive per §26.

### 16.4 Deep-link URL structure

- `/deep/notification/:notification_id` — APP-010-owned.
- All other `/deep/*` kinds referenced by notification `deep_link` are owned by the source slice; no new kinds added by APP 010.

### 16.5 Query-string encoding

Standard URL encoding; boolean-flag params are represented as `key=true` (not `key` alone) for parser consistency.

### 16.6 Hotkey grammar

- `N` at workspace level (any page except release dashboards) — toggle Notification Center popover.
- `Shift+N` — navigate to Inbox (`/workspace/:ws_id/inbox`).
- `E` on a focused notification card — archive (mnemonic: "email inbox archive").
- `Backspace` / `Delete` on focused card — dismiss.

Bound via `useWorkspaceHotkeys` extension per §27.5. G-19 (APP 009's context-scoped hotkey precedent).

---

## 17. Query architecture

### 17.1 `qk` namespace additions (**[additive]**)

Following the APP 002 `qk` registry convention (per APP 006 §17 / APP 007 §17 / APP 008 §17 / APP 009 §17 precedent):

| Key builder | Signature | Purpose |
|---|---|---|
| `qk.notification(id)` | `['notification', id]` | Single notification row |
| `qk.notificationsList(wsId, filters)` | `['notification','list', wsId, filters]` | Inbox list (filtered) |
| `qk.notificationsUnread(wsId)` | `['notification','unread', wsId]` | Unread-only list |
| `qk.notificationsInbox(wsId, tab, filters, cursor)` | `['notification','inbox', wsId, tab, filters, cursor]` | Paginated inbox tab |
| `qk.notificationCenter(wsId)` | `['notification','center', wsId]` | Notification Center popover (top 15 unread) |
| `qk.notificationBadgeCount(wsId)` | `['notification','badge', wsId]` | Bell-icon unread count |
| `qk.notificationsForSubject(subjectKind, subjectId)` | `['notification','subject', kind, id]` | Reverse lookup — "which notifications reference this subject" (used by future cross-slice UX; not consumed in v1 UI) |

All keys are namespace-safe against APP 001–009 (whose namespaces are `workspace`, `project`, `asset`, `version`, `file`, `comment`, `annotation`, `review`, `approval`, `requirement`, `release`, `deep`, `bookmark`, `savedView`).

### 17.2 Cursor pagination shape

Standard cursor payload:

```json
{
  "created_at": "2026-08-05T10:23:00Z",
  "id": "01a0e5a2-…"
}
```

Encoded base64url; opaque to the client.

### 17.3 Stale-time posture

- `qk.notificationBadgeCount` — `staleTime: 30_000`, `refetchInterval: 60_000` (polling fallback per §25.4).
- `qk.notificationsUnread` / `qk.notificationCenter` — `staleTime: 30_000`, `refetchInterval: 60_000`.
- `qk.notificationsInbox` — `staleTime: 60_000`, no `refetchInterval` (Inbox is a screen; user-initiated refresh via pull-to-refresh or the "Reload" affordance).
- `qk.notification(id)` — `staleTime: 5 * 60_000` (individual notifications are effectively immutable after read; only the read/dismissed/archived flags change).

### 17.4 Invalidation on mutation

- `mark_notification_read(id)` → invalidate `notification(id)`, `notificationsUnread(wsId)`, `notificationsInbox(wsId,*)`, `notificationCenter(wsId)`, `notificationBadgeCount(wsId)`.
- `mark_all_notifications_read(wsId)` → invalidate all `qk.notification*` for that workspace.
- `dismiss_notification(id)` → same as read.
- `archive_notification(id)` → same as read.

### 17.5 Prefetching

- On Notification Center popover open: prefetch `notificationsInbox(wsId, 'unread', {}, null)` so the "View all in Inbox" transition is instant.
- On Inbox mount: prefetch the second page cursor if `first_page.has_more=true`.

### 17.6 Optimistic updates

- `mark_notification_read` — **optimistic** (invalidation follows on server confirmation).
- `dismiss_notification` — optimistic.
- `archive_notification` — optimistic.
- `mark_all_notifications_read` — **not** optimistic in v1 (bulk operation; risk of stale local state). Server confirmation required.

Rationale: single-row recipient-axis mutations are safe to optimistically update; bulk operations wait for server truth. Aligned with APP 009 G-30 posture.

---

## 18. Cache invalidation

### 18.1 Cross-slice mutation → notification badge/list invalidation

Any workflow mutation that could result in an `activity_events` INSERT (and therefore new notification rows for the caller) should invalidate the caller's notification badge and list queries. Because APP 010 does not know which specific mutations will produce notifications, the pragmatic approach:

- Every workflow mutation invokes a shared `invalidateNotificationSurfaces(wsId)` helper after success.
- The helper invalidates `qk.notificationBadgeCount(wsId)`, `qk.notificationsUnread(wsId)`, `qk.notificationCenter(wsId)`.
- Inbox list queries are not invalidated (they self-refresh on tab-focus per §17.3).

Helper location: `src/features/notifications/invalidation.ts` — exported as a small utility so every slice's mutation hooks can call it without importing the entire notifications feature.

### 18.2 Polling fallback interval

Per §25.4, v1 relies on polling to keep badge counts fresh in the absence of realtime:
- Bell badge: 60s.
- Center popover (when open): 30s.
- Inbox screen (when visible): 60s.

Configurable via `VITE_NOTIFICATIONS_POLL_INTERVAL_SEC` env var; default `60`. Retail deployments may lower this if network cost tolerates.

### 18.3 Tab-focus invalidation

On window `focus` event, invalidate `qk.notificationBadgeCount(wsId)` — cheap round-trip that keeps the bell honest without waiting for the 60s tick.

### 18.4 Reserved: SSE / websocket subscription hook

Once APP 011 ships, the polling fallback is replaced by a subscription:

```typescript
useNotificationRealtimeSubscription(wsId, {
  onInsert: (row) => queryClient.invalidateQueries(qk.notificationBadgeCount(wsId)),
  onUpdate: (row) => queryClient.invalidateQueries(qk.notification(row.id)),
});
```

Hook name reserved (`useNotificationRealtimeSubscription`); implementation deferred to APP 011.

### 18.5 Mark-read invalidation cascade

`mark_notification_read` returns the updated row; the client patches `notification(id)` directly (no re-fetch of that key) and invalidates the badge + list keys per §17.4.

### 18.6 Cross-tab consistency

`BroadcastChannel('lign-notifications')` reserved (name-locked; no implementation in v1) — future cross-tab sync so marking read in tab A invalidates badge in tab B without waiting for the poll.

---

## 19. Capability model

### 19.1 New capabilities (**[additive]**)

APP 010 introduces two capability keys, both scoped per-user (implicit: the caller acts on their own notifications):

| Capability | Purpose | Default role assignment |
|---|---|---|
| `notification.view` | Read the caller's own notifications; open the Inbox; see the bell badge | Granted to every project role and every workspace role — every authenticated member sees their own notifications |
| `notification.manage` | Mark read/unread, dismiss, archive the caller's own notifications | Granted alongside `notification.view` (recommend rolling into `.view` unless separation needed — G-24) |

Both capabilities are **implicit for every authenticated user** (every user has a right to see their own inbox). PERMISSIONS.md §5 role presets gain both capabilities across all rows (workspace roles + project roles + reviewer + stakeholder).

Rationale: notifications are **personal**; there is no "manage other users' notifications" surface. Recipient enforcement is via `recipient_profile_id = auth.uid()` in RLS + RPC. No admin can read another user's inbox in v1 (deferred: `notification.view_any` for compliance/support — see §29.1).

### 19.2 No `notification.send` capability

The router is system-triggered from `activity_events` INSERT — there is no user-facing "send a notification" affordance. APP 010 v1 exposes no RPC that writes to another user's `notifications` row. Recipient rows are exclusively produced by the router trigger. A future "manual system announcement" feature would introduce a distinct capability (`notification.announce` — reserved name, no implementation).

### 19.3 Reserved future capabilities (name-locked; not wired in v1)

| Capability | Purpose |
|---|---|
| `notification.view_any` | Compliance/support reading of another user's inbox (with audit trail) — reserved for future compliance slice |
| `notification.announce` | Manually create a broadcast notification (e.g., admin announcement) — reserved for future admin slice |
| `notification.ai_prioritize` | AI seam: re-order the recipient's inbox by learned priority — reserved for future AI slice (G-27) |
| `notification.ai_summarize` | AI seam: auto-generate a daily/weekly summary — reserved (G-27) |
| `notification.ai_digest` | AI seam: consume many notifications, emit one digest — reserved (G-27) |
| `notification.preference` | Manage own notification preferences — reserved for future preferences table (§4.4) |

### 19.4 Capability enforcement points

- `list_notifications` RPC: requires `notification.view`; further filtered by `recipient_profile_id = auth.uid()`.
- `mark_notification_read` and friends: require `notification.manage`; further filtered by ownership.
- `get_notification_badge_count`: requires `notification.view`.
- Inbox route (`/workspace/:ws_id/inbox`): route guard checks `notification.view` before mounting.
- Notification Center popover: mount-time check on `notification.view`.

### 19.5 Membership-class transparency

Per PERMISSIONS.md §1, membership class (WorkspaceMember vs Stakeholder) does not gate any capability. A stakeholder holding `notification.view` (which all authenticated users do) sees their own notifications for events on projects they participate in — same as a workspace member.

---

## 20. Event consumption

### 20.1 Bridging mechanism: DB-level trigger (recommended)

APP 010 recommends a single AFTER INSERT trigger on `activity_events`:

```
trigger name: enforce_notification_router_bridge
timing: AFTER INSERT
scope: FOR EACH ROW
```

This trigger invokes an **[additive]** function `resolve_notification_router_targets(event_row activity_events) RETURNS void`, which encapsulates the routing table (§8) and INSERTs the resolved `notifications` rows within the same transaction as the source workflow.

Rationale for DB-trigger over async worker:
- **Transactional guarantee** — a committed event produces its notifications atomically. No lag; no risk of notifications-lost-in-transit.
- **No new infrastructure** — matches EVENT_MODEL.md §1 principle "No new infrastructure; no Kafka, no queues, no webhooks in MVP."
- **Simpler failure mode** — if the router raises (e.g., because a required subject_snapshot key is missing), the parent transaction rolls back. This surfaces broken router → source-slice contracts loudly in dev; in prod, EXCEPTION-handling in the router body should log-and-continue rather than raise (per §20.3).
- **Same posture as EVENT_MODEL.md §6** — "Notifications derive from committed rows" implies a same-transaction derivation is natural.

Trade-off (async decoupling):
- With a trigger, a slow router body slows every workflow RPC.
- The router body must be lightweight (target < 5ms per event).
- Fanout must not touch external services (email send is deferred to a downstream worker; the trigger only materializes the payload).
- If future high-fan-out events (e.g., broadcast to 500 project participants) prove too slow, migrate to an async worker as a v1.1 architectural change (a separate slice re-freeze).

Decision recorded as G-2 in §28.

### 20.2 Router function contract

- **Input**: one `activity_events` row (as `NEW` in the trigger body).
- **Behavior**:
  1. Look up the routing table entry for `NEW.event_type` (and `NEW.subject_kind` if polymorphic).
  2. If no entry (feed-only event), return immediately (no rows inserted).
  3. Resolve recipient set per §9.
  4. Apply dedup (`ON CONFLICT DO NOTHING` on the `(source_event_id, recipient_profile_id)` unique index).
  5. Apply self-exclusion (`WHERE recipient_profile_id != NEW.actor_profile_id`).
  6. Materialize payload per §10.4 (base + rendering + email/push if applicable).
  7. INSERT one `notifications` row per resolved recipient.
- **Output**: `void`. No return value; count is not surfaced to the emitting RPC.
- **Isolation**: SECURITY DEFINER; `SET search_path = ''`; no direct table access outside `notifications` INSERT and `profiles` / `project_participants` / `workspace_members` / source-subject reads for recipient resolution.
- **Error handling**: EXCEPTION handler logs and returns; never raises (raising would roll back the workflow transaction, and a notification-router bug should not lose an audit event). Decision recorded as G-2 caveat.

### 20.3 Router failure posture

If the router body raises unhandled:
- **Development**: raises to surface the bug loudly.
- **Production**: EXCEPTION handler catches, writes a diagnostic row to a **[additive]** `notification_router_errors` table (reserved name; deferred), and returns void. The workflow transaction commits normally. The missed notification is a silent loss (visible in the errors table). Post-hoc reconciliation is deferred.

G-2 caveat: this defers the "at-least-once delivery" invariant a stricter design would provide. Rationale: workflow correctness > notification completeness. A missed notification is recoverable (the user still sees the underlying event via the source slice's own UI, badges from source slices, etc.); a rolled-back workflow is a data-corruption incident.

### 20.4 Alternative: async worker (rejected for v1)

Rejected. Explanation:
- Would require a queue infrastructure (`pgmq` or similar) — EVENT_MODEL.md forbids in MVP.
- Adds a new failure mode (worker down → notification lag) without solving the fan-out cost meaningfully in v1 (typical event → 1–10 recipients).
- Introduces staleness that undermines the "delivered synchronously" UX.

Reconsider in v1.1 if high-fan-out events (e.g., 500-recipient broadcasts) or expensive router work (AI prioritization) materially slow workflow RPCs.

### 20.5 Trigger installation order

The router trigger fires AFTER INSERT on `activity_events`, alongside any other AFTER INSERT triggers already installed by the audit / feed layer. Ordering constraint: **the router must run after any audit-derivation triggers** that write additional `subject_snapshot` fields (there are none in v1; noted for future extensions).

### 20.6 What the router does with unknown event types

- Unknown `event_type` (e.g., a value not in the routing table) → the router logs a warning and returns without INSERTing. This keeps forward-compatibility with reserved events (which may appear in `activity_events` before APP 010 adds their routing row).
- Known event with unknown `subject_kind` (polymorphic path) → same posture.

### 20.7 Consumption of additive payload keys

The router reads only the keys documented in the source slice's freeze index (APP 006 §17, APP 008 §12, APP 009 §20.4). Unknown keys are ignored per the additive-consumer contract. If a source slice adds a new key that the router needs, the source slice's freeze index gains that key first; APP 010's router extension follows in a coordinated additive change.

---

## 21. Cross-slice compatibility

### 21.1 The "notifications never bypass RLS" invariant

Inherited directly from EVENT_MODEL.md §7.7:

> Notifications never bypass RLS. Recipients still need access to the underlying subject to read the linked entity. Never expose content the recipient could not otherwise see.

Concretely, the `notifications` SELECT RLS policy is:

```
   (recipient_profile_id = auth.uid())
   AND (project_id IS NULL OR lign_is_project_participant(project_id) OR lign_is_workspace_admin(workspace_id))
```

Even if a notification was legitimately created at time T (when the recipient had access), a subsequent role change that removes access should filter the row at read time. Rationale: the payload might include `subject_label` or preview text that the recipient can no longer see.

This is the same discipline as the frozen `activity_events` SELECT policy per PERMISSIONS.md §8 Group K.

### 21.2 APP 001 (Domain Model)

- Reads: `profiles` (for recipient display name + avatar), `workspace_members` (for tenant membership check), `project_participants` (for recipient-broadcast fan-out).
- Writes: none in APP 001 tables.
- No domain-model changes proposed. The `Notification` entity is introduced as a first-class domain concept in the follow-on backend proposal; DOMAIN_MODEL.md gains an additive entry — a doc-only, additive extension.

### 21.3 APP 002 (Application shell)

- Extends: `qk` namespace (§17), `CAPABILITY_KEYS` (2 new + 6 reserved per §19), `DeepLinkResolver` (1 new kind: `notification`), `NavRail` (1 new item: Inbox), hotkey slots (`N`, `Shift+N`, `E`, `Backspace`).
- Router-shape additions: 1 new route (`/workspace/:ws_id/inbox`) + 1 new deep-link route (`/deep/notification/:id`).
- All additive.

### 21.4 APP 003 (Projects & Design Workspace)

- Reads: `project_participants` (for project-broadcast recipient rule), `projects` (for tenant-check and workspace lookups when a notification's `project_id` matches).
- Writes: none.
- No changes to project shells or Design Workspace. The Design Workspace does not gain a Notifications tab in the RightPanel (rationale: the bell + Center popover cover the need; RightPanel real estate is scarce and belongs to workflow surfaces).

### 21.5 APP 004 (Files & Viewer)

- Reads: none (notifications never render file bodies; deep-link takes over).
- Writes: none.

### 21.6 APP 005 (Comments & Annotations)

- Consumes: `comment.mentioned` (in-app notify per EVENT_MODEL.md §7.5), `annotation.resolved` (owner-notify per §5.8), `comment.created / .edited / .deleted / .resolved / .reopened` all feed-only in v1.
- Extends: `useCopyLink` (2 new `LinkKind` values: `notification`, `inbox`).
- Does NOT add: `target_notification_id` on `comments`. Rationale: notifications are not commentable (they are a delivery record, not a workflow surface). Analogous to APP 009 G-32.

### 21.7 APP 006 (Reviews)

- Consumes: `review.opened`, `review.completed`, `review.cancelled`, `review.reviewer_responded`.
- Reserved consumers (name-locked): `review.deadline_approached`, `review.deadline_passed`, `review.reviewer_removed`, `review.reviewer_reassigned`.
- Reads: `reviews`, `review_participants` for recipient resolution.
- Writes: none in APP 006 tables.

### 21.8 APP 007 (Approvals)

- Consumes: all 6 P0 `approval.*` events (see §5.2, §8.1).
- Reserved consumer: `approval.deadline_approached` (name-locked per APP 007 §21 certification).
- Reads: `approval_requests`, `approval_request_approvers` (for recipient resolution), `approval_responses` (indirectly, via `approval.responded` snapshot).
- Writes: none in APP 007 tables.

### 21.9 APP 008 (Requirements)

- Consumes: **zero** `requirement.*` events in v1 (all feed-only per EVENT_MODEL.md §4.14 / APP 008 §12 certification).
- Reserved consumers (name-locked): `requirement.assigned_to_you`, `requirement.your_requirement_updated`, `requirement.critical_regressed`, `requirement.assessed_by_you_stale`.
- Reads: `requirements` (for future requirement-owner recipient resolution when APP 008 ships owner column; deferred).
- Writes: none.

### 21.10 APP 009 (Releases)

- Consumes: `release.finalized`, `release.withdrawn`. Also consumes the additive payload extensions per APP 009 §20.4 (e.g., `release_type`, `published_by_profile_id`) for rendering-only fields in the notification payload.
- Reserved consumers (name-locked): `release.scheduled`, `release.superseded`, `release.recalled`, `release.notes_updated`, `release.ai_suggested`, `release.ai_classified`.
- Reads: `releases`, `release_items` (for recipient resolution — project participants with `release.view`).
- Writes: none in APP 009 tables.

### 21.11 APP 011 (Realtime — future)

- Reserved dependency. APP 010 v1 uses polling per §25; APP 011 will push notifications via websocket subscription when it lands.
- Reserved channels: `notifications:profile:<profile_id>`, `notifications:workspace:<ws_id>` (name-locked; §25.3).
- APP 011 re-freeze required to add the `notifications` table to `supabase_realtime` publication.

### 21.12 STORAGE (STORAGE 001–004)

- Untouched. Notifications do not carry file references beyond the `payload.avatar_seed`-style rendering hint.

### 21.13 AUTHORIZATION (AUTH 001+)

- Extends: `PERMISSIONS.md` §5 role preset table gains `notification.view` and `notification.manage` for every role. Additive.

---

## 22. Desktop/mobile behavior

### 22.1 Desktop (≥1024px)

- Bell icon in the top-right of the workspace header; badge overlay.
- Notification Center opens as a 400px-wide popover anchored to the bell.
- Inbox screen renders in the main content area with a left-aligned tab strip and a right-aligned filter drawer (expandable).
- Toasts appear top-right, stacking downward with max 3 concurrent.

### 22.2 Tablet (768–1024px)

- Notification Center popover is 90vw at most; anchored to the bell but shifts to center if it would overflow.
- Inbox screen: filter bar collapses to a "Filters" button that expands a bottom-sheet.
- Toasts: same as desktop.

### 22.3 Mobile (<768px)

- Bell icon in the top bar.
- Notification Center popover is full-screen sheet (slides up from bottom).
- Inbox screen tabs become a horizontal scroller; filters live behind a "Filters" button that opens a full-screen filter view.
- Toasts: single toast at a time (max 1 concurrent, overflow suppressed to Center).
- Long-press on a notification card → context menu (mark read, dismiss, archive, copy link).
- Swipe-left on card → archive (mobile-native affordance).
- Swipe-right on card → mark read.

### 22.4 Badge counts

Unchanged across breakpoints (numerical badge on bell; NavRail badges collapse into a dot on mobile if numeric would clip).

---

## 23. Loading/error states

### 23.1 Skeleton shapes

- **NotificationCard skeleton** — 64px height; priority chip placeholder, avatar circle, two text lines, timestamp shimmer. Renders during initial load and during pagination fetch of subsequent pages.
- **Notification Center popover skeleton** — 5 rows of card skeletons + header + footer skeleton.
- **Inbox tab-strip skeleton** — 6 tab placeholders + filter-bar shimmer.
- **Badge count skeleton** — briefly renders `—` before first fetch resolves; no numeric shimmer to avoid layout jank.

### 23.2 Empty-state copy

See §12.5 (Inbox empty states) and §13.4 (Popover empty states).

### 23.3 Error-state copy

| Error | Copy | Recovery |
|---|---|---|
| Failed to load badge count | Bell renders un-decorated (no badge); silent failure — no error surface | Retry on next poll tick |
| Failed to load Center popover | "Couldn't load notifications." | Retry button |
| Failed to load Inbox | "Couldn't load your notifications." | Retry button |
| Failed to mark read | "Couldn't mark read. Try again." | Retry button + optimistic revert |
| Failed to mark all read | "Couldn't mark all read." | Retry button |
| Failed to dismiss | "Couldn't dismiss." | Retry button + revert |
| Failed to archive | "Couldn't archive." | Retry button + revert |
| Deep-link 404 | Handled by source slice (never surfaces in APP 010) | — |
| Deep-link 403 | Handled by source slice | — |

### 23.4 Retry patterns

- Standard TanStack Query: 3× exponential backoff on network errors.
- No retry on 4xx (RLS-hidden result, capability failure — user-actionable).
- Manual retry buttons on all failure surfaces.

### 23.5 Rate limiting of error toasts

If the router-derived stream produces many errors in a short time (e.g., during network flap), the toast layer suppresses duplicates for 30s and shows one aggregated "Some notifications failed to load. Refresh." toast.

---

## 24. AI extension seams

### 24.1 Reserved capabilities (name-locked; no grants in v1)

Per G-27 (mirrors APP 009 §21):

- `notification.ai_prioritize` — re-order the inbox by learned priority.
- `notification.ai_summarize` — auto-generate summary lines.
- `notification.ai_digest` — batch many notifications into one digest.

Zero role grants in v1. Names are locked so a future AI slice does not have to rename.

### 24.2 Reserved AISlot primitives

Reserved (no wiring in APP 010 v1):

- `<AISlot kind="notification-priority-explanation" />` — inline "why is this priority?" tooltip.
- `<AISlot kind="notification-summary" />` — Inbox top-of-page daily summary.
- `<AISlot kind="notification-digest" />` — deferred digest tile.
- `<AISlot kind="mention-context" />` — expand a mention notification with AI-summarized upstream thread.

### 24.3 Reserved notification types

For AI-generated notifications (source: hypothetical `notification.*` events emitted by a future AI slice):

- `ai.suggestion` — an AI-generated recommendation (e.g., "You have not reviewed this critical asset in 30 days").
- `ai.summary` — an AI-generated summary notification (e.g., end-of-day digest).
- `ai.digest` — a batched-multi notification.

All name-locked; not wired in v1.

### 24.4 Reserved event names

Following EVENT_MODEL.md's naming convention (past-tense verbs; the past-tense-only rule from APP 006 F-4.2 / APP 007 §21 also applies to APP 010's reserved events):

- `notification.ai_prioritized` — fires when the AI re-orders the caller's inbox (future).
- `notification.ai_summarized` — fires when a summary is generated.
- `notification.digest_sent` — fires when a digest is delivered.

All in the `notification.*` namespace; not consumed by APP 010's router (it does not act on its own outputs — §28 G-16). Reserved for AI-slice consumers.

### 24.5 Boundary with the AI slice

APP 010 v1 provides **no AI hooks**. The reserved seams above document where AI extensibility will land without committing to any implementation. When AI ships:

- The AI slice reads `notifications` and `activity_events` (both via SECURITY DEFINER RPCs).
- The AI slice writes back to `notifications` **only** by emitting `notification.*` events that APP 010's router picks up and materializes as `ai.suggestion` / `ai.summary` rows.
- The AI slice never mutates existing `notifications` rows.

---

## 25. Realtime boundary (APP 011)

### 25.1 Explicit statement

**The `notifications` table is OUT of the `supabase_realtime` publication in APP 010 v1.** This is the frozen boundary set by REALTIME 001 (per memory `project_lign_schema_v1_lock.md` and mirroring APP 008 §22 / APP 009 §23 pattern).

Real-time updates to the Inbox, Notification Center, badge counts, and toasts happen via **polling + query invalidation** — never live-subscription.

### 25.2 Adding notifications to the publication is a REALTIME re-freeze event

Not an APP 010 decision. Any proposal to subscribe live to `notifications` INSERT must go through the REALTIME layer's re-freeze process (which will be APP 011's authority).

### 25.3 Reserved realtime channel names (name-locked; no subscription in APP 010)

Reserved for a future APP 011 re-freeze:

| Channel | Scope | Would invalidate |
|---|---|---|
| `notifications:profile:<profile_id>` | Per-user notification stream | `qk.notificationBadgeCount(*)`, `qk.notificationsUnread(*)`, `qk.notificationsInbox(*)`, `qk.notificationCenter(*)` |
| `notifications:workspace:<ws_id>` | Workspace-scoped notification stream (admin/support view) | `qk.notificationsWorkspaceInbox(ws_id)` (reserved qk) |

APP 010 exports these constants from `src/features/notifications/realtime.ts` as name-only placeholders. Subscription code is not shipped until APP 011.

### 25.4 Fallback in v1: polling

- Bell badge: 60s poll interval (configurable per §18.2).
- Notification Center (when open): 30s poll interval.
- Inbox screen (when visible): 60s poll interval.
- Tab-focus invalidation: additional cheap round-trip on window focus.
- Toasts: best-effort in v1 (rely on the same poll to detect new critical/high notifications and animate a toast). Latency: up to 60s. Acceptable per user brief.

Decision recorded as G-29 in §28.

### 25.5 Migration path to APP 011

When APP 011 ships:
1. REALTIME re-freeze adds `notifications` to `supabase_realtime` publication.
2. APP 010 gains `useNotificationRealtimeSubscription(wsId, handlers)` hook (name reserved; §18.4).
3. The polling fallback becomes a fallback-only (activated when the websocket is disconnected).
4. Toast latency drops to near-zero.
5. Cross-tab consistency (via `BroadcastChannel` — §18.6) becomes optional.

No workflow slice needs to change; the router trigger continues to INSERT notifications synchronously; the transport is the only change.

---

## 26. Backend delta preview

This is a scope statement for the follow-on `APP_010_BACKEND_PROPOSAL.md`. No SQL, no bodies, no migration ordering here — just the enumerated set of proposed additions the Backend Proposal will elaborate.

### 26.1 [additive] tables

| Table | Purpose | v1? |
|---|---|---|
| `notifications` | Per-recipient delivery record (§4.1) | **Yes** |
| `notification_preferences` | Per-user per-category preferences | Reserved (§4.4) — no v1 |
| `notification_deliveries` | Per-channel delivery attempt log | Reserved (§4.4) — no v1 |
| `notification_digests` | Batched digest sends | Reserved — no v1 |
| `notification_router_errors` | Router failure log | Reserved — no v1 |

### 26.2 [additive] columns (on `notifications`)

Fully enumerated in §4.1. Counts:

- 19 columns on `notifications` (id, workspace_id, project_id, recipient_profile_id, source_event_id, event_type, notification_type, category, priority, channels_attempted, delivery_state, subject_kind, subject_id, subject_label, actor_profile_id, payload, read_at, dismissed_at, archived_at, created_at, updated_at).
- No new columns on any frozen table.

### 26.3 [additive] read RPCs

| RPC | Purpose |
|---|---|
| `list_notifications(ws_id, tab, filters, cursor, limit)` | Paginated inbox list |
| `list_notifications_unread(ws_id, limit)` | Notification Center popover |
| `get_notification(notification_id)` | Single-row read (deep-link `/deep/notification/:id` resolver) |
| `get_notification_badge_count(ws_id)` | Bell badge |
| `get_notification_facets(ws_id, tab)` | Facet counts per category/priority/source (for filter chip counters) |
| `list_notifications_for_subject(subject_kind, subject_id)` | Reverse lookup (reserved; not consumed by v1 UI but exposed for future use) |

All: `SECURITY DEFINER`, `SET search_path = ''`, `REVOKE FROM public, anon`, `GRANT EXECUTE TO authenticated, service_role`. All gate on `notification.view` + `recipient_profile_id = auth.uid()`.

### 26.4 [additive] write RPCs

| RPC | Purpose | Capability |
|---|---|---|
| `mark_notification_read(notification_id)` | Set `read_at=now()` | `notification.manage` |
| `mark_notification_unread(notification_id)` | Set `read_at=NULL` (G-5) | `notification.manage` |
| `mark_all_notifications_read(ws_id)` | Bulk set `read_at=now()` for caller's unread | `notification.manage` |
| `mark_notifications_read_bulk(notification_ids uuid[])` | Bulk mark-read by id list | `notification.manage` |
| `dismiss_notification(notification_id)` | Set `dismissed_at=now()` | `notification.manage` |
| `dismiss_notifications_bulk(notification_ids uuid[])` | Bulk dismiss | `notification.manage` |
| `archive_notification(notification_id)` | Set `archived_at=now()` | `notification.manage` |
| `archive_notifications_bulk(notification_ids uuid[])` | Bulk archive | `notification.manage` |

**Reserved for future:**

- `set_notification_preference(...)` — reserved for the preferences table (§4.4).
- `mute_notification_category(...)` — reserved.
- `snooze_notification(...)` — reserved.

### 26.5 [additive] capabilities

Wired in v1: 2 (`notification.view`, `notification.manage`).

Reserved (name-locked): 6 (`notification.view_any`, `notification.announce`, `notification.ai_prioritize`, `notification.ai_summarize`, `notification.ai_digest`, `notification.preference`).

### 26.6 [additive] events

**None new emitted in APP 010 v1.** APP 010 consumes frozen workflow events; the only APP-010-owned event names live in the `notification.*` namespace and are all **reserved**:

- `notification.ai_prioritized` (reserved by APP 010 v1; past-tense).
- `notification.ai_summarized` (reserved by APP 010 v1; past-tense).
- `notification.digest_sent` (reserved by APP 010 v1; past-tense).

**Zero new workflow events.** APP 010 does not extend or add to any frozen event vocabulary; extensions to frozen events are cited (§20.7) but never proposed by APP 010.

### 26.7 [additive] indexes

| Table | Index | Purpose |
|---|---|---|
| `notifications` | `(recipient_profile_id, workspace_id, read_at) WHERE read_at IS NULL AND dismissed_at IS NULL AND archived_at IS NULL` | Unread-count / badge lookup |
| `notifications` | `(recipient_profile_id, workspace_id, created_at desc)` | Inbox "All" tab scan |
| `notifications` | `(recipient_profile_id, workspace_id, category, created_at desc)` | Category-filtered scan |
| `notifications` | `(recipient_profile_id, workspace_id, priority, created_at desc)` | Priority-filtered scan |
| `notifications` | `(source_event_id, recipient_profile_id) UNIQUE` | Dedup enforcement (G-7) |
| `notifications` | `(subject_kind, subject_id)` | Reverse-lookup queries |
| `notifications` | `(workspace_id, created_at desc)` | Workspace-wide admin queries (future) |
| `notifications` | `(recipient_profile_id, workspace_id, archived_at desc) WHERE archived_at IS NOT NULL` | Archived-tab scan |

Reused (frozen): none — `notifications` is a brand-new table.

### 26.8 [additive] triggers

| Trigger | Purpose |
|---|---|
| `enforce_notification_router_bridge` (AFTER INSERT on `activity_events`) | Invokes `resolve_notification_router_targets` — the event-to-notification bridge (§20) |
| `enforce_notification_immutable_fields` (BEFORE UPDATE on `notifications`) | Blocks post-INSERT mutation of every non-flag column (see §4.2) |
| `enforce_notification_rpc_only_writes` (BEFORE UPDATE on `notifications`) | Blocks direct UPDATE from user code; only the `mark_*` / `dismiss_*` / `archive_*` RPCs may write (via `is_lign_notification_rpc()` GUC guard) |
| `notifications_set_updated_at` | Standard timestamp maintenance |

Frozen triggers preserved unchanged:
- `activity_events` append-only trigger (DATABASE_SCHEMA.md §3.25).
- All workflow slice triggers from APP 006–009 remain byte-identical.

### 26.9 RLS policies

- `notifications_select` — `notification.view` capability + `recipient_profile_id = auth.uid()` + subject-access predicate (§21.1).
- `notifications_insert` — deny direct INSERT from user code (router trigger uses SECURITY DEFINER); INSERT allowed only via router path.
- `notifications_update` — deny direct UPDATE from user code (RPC-gate trigger enforces).
- `notifications_delete` — deny (v1 has no user-facing delete; retention job — reserved — would use service_role).

### 26.10 Reserved but not proposed

- Any REALTIME publication change (`supabase_realtime`) — belongs to REALTIME re-freeze (§25.2).
- Any email / push transport code — belongs to a future email/push slice; APP 010 only produces payload.
- Any cron / digest emitter — belongs to a future cron slice.
- Any AI wiring — belongs to a future AI slice.
- Any modification to `activity_events` schema — belongs to EVENT layer.
- Any modification to APP 001–009 tables, RPCs, capabilities, events, routes, or components.

### 26.11 Preliminary count

- 1 new table in v1 (`notifications`); 4 tables reserved-name-only.
- 19 columns on the new table; 0 new columns on any frozen table.
- 6 **[additive]** read RPCs.
- 8 **[additive]** write RPCs (all new; zero changes to frozen RPC signatures).
- 2 new capability keys wired in v1 (`notification.view`, `notification.manage`); 6 reserved for future.
- 0 new emitted events in v1; 3 reserved `notification.*` event names for future waves.
- ~8 **[additive]** indexes (btree + unique + partial).
- 4 **[additive]** triggers (bridge + 3 defense-in-depth).
- Realtime publication change: **none** — `notifications` remains OUT per §25.

---

## 27. Reusable primitives

### 27.1 Consumed unchanged from prior slices

- `DeepLinkResolver` (APP 002) — extend additively with `notification` kind per §15.
- `NavRail` (APP 002 + APP 006 badge prop) — new "Inbox" nav item + badge from `get_notification_badge_count`.
- `qk` registry patterns (APP 002, APP 005, APP 006).
- `useCopyLink` (APP 005; extended by APP 006, APP 007, APP 008, APP 009) — additive `LinkKind` values `'notification'`, `'inbox'`.
- `useWorkspaceHotkeys` (APP 006) — additive handler slots `onToggleNotificationCenter` (bound to `N`), `onNavigateInbox` (bound to `Shift+N`), `onArchiveNotification` (bound to `E` on focused card), `onDismissNotification` (bound to `Backspace`/`Delete` on focused card).
- `StateBadge` (APP 005) — additive `WorkflowState` union members are NOT introduced by APP 010 (notification states are per-user flags, not workflow states); state pill for a notification uses a lightweight `NotificationStateChip` primitive.
- Design tokens — `priority='critical'` → reuses `--color-state-blocked` (red); `priority='high'` → reuses `--color-state-attention` (amber); `priority='medium'` → `--color-state-neutral`; `priority='low'` → subdued; `priority='informational'` → grayscale. No new tokens declared.
- Timeline component (APP 006) — not reused (Inbox is card-list, not timeline).
- Toast layer — new; not previously shared.

### 27.2 NOT consumed: `CommentsPanel` (APP 005)

Per the foundational premise (§1), notifications are not commentable. APP 010 does NOT reuse APP 005's `CommentsPanel` and does NOT add a `target_notification_id` column to `comments`. Decision recorded as G-32 (parity with APP 009 G-32 posture).

### 27.3 NOT consumed: `RosterEditor` (APP 006)

Notifications have no assignee concept beyond the single `recipient_profile_id`. APP 010 does NOT reuse `RosterEditor`.

### 27.4 NEW primitives introduced by APP 010

Notification-specific; not cross-slice reusable in this wave (may be extracted in a future wave once patterns stabilize across delivery surfaces):

| Primitive | Purpose |
|---|---|
| `NotificationBell` | Bell icon + unread badge; top-bar mount; toggles Center |
| `NotificationCenter` | Popover body — sub-tabs, list, mark-all-read footer |
| `NotificationCard` | Row card in Inbox and Center; three variants (dense / default / expanded) |
| `NotificationBadge` | Numeric badge primitive; reusable on bell + NavRail |
| `InboxScreen` | Full-page Inbox at `/workspace/:ws_id/inbox` |
| `NotificationFilterBar` | Category / priority / source / date / project / actor filter chips |
| `NotificationTabStrip` | 6 tabs (All / Unread / Mentions / Assigned / Governance / Archived) |
| `NotificationEmptyState` | Empty-state art + copy per tab |
| `NotificationRow` | Compact inline row for Notification Center popover |
| `NotificationGroupHeader` | "Today" / "Yesterday" / etc. group headers |
| `NotificationStateChip` | State pill (`unread`, `read`, `dismissed`, `archived`) |
| `NotificationPriorityChip` | Priority chip with color tokens |
| `NotificationCategoryChip` | Category chip with icon |
| `ToastStack` | Rate-limited toast layer (max 3 concurrent — G-19) |
| `ToastCard` | Individual toast body |
| `useNotificationBadgeCount(wsId)` | Hook exported for NavRail bell |
| `useNotificationCenter(wsId)` | Hook for Center popover data |
| `useInbox(wsId, filters)` | Hook for Inbox screen data |
| `useMarkNotificationRead()` | Mutation hook |
| `useDismissNotification()` | Mutation hook |
| `useArchiveNotification()` | Mutation hook |
| `useMarkAllNotificationsRead()` | Mutation hook |
| `NotificationRef` | Inline notification reference component for cross-slice citation (`<NotificationRef id={id} />`) |

### 27.5 Extended primitives (backward-compatible)

- `useCopyLink` — `LinkKind` gains `'notification'`, `'inbox'`.
- `useWorkspaceHotkeys` — new handler slots per §27.1.
- `DeepLinkResolver` — 1 additive kind (`notification`).
- `CAPABILITY_KEYS` — 2 wired + 6 reserved (§19).
- `qk` — 7 new key builders (§17.1).
- `NavRail` — 1 new item ("Inbox") + workspace-scoped badge; no other slice's NavRail entries change.

### 27.6 AISlot primitives

Reserved (no wiring in APP 010 v1) — see §24.2:

- `<AISlot kind="notification-priority-explanation" />`
- `<AISlot kind="notification-summary" />`
- `<AISlot kind="notification-digest" />`
- `<AISlot kind="mention-context" />`

---

## 28. Open architectural decisions

Decisions taken during this freeze pass and questions deliberately deferred. Every decision may be overridden before implementation.

| # | Decision | Recommendation | Rationale |
|---|---|---|---|
| **G-1** | Single `notifications` table vs join to `activity_events` for rendering | **Separate `notifications` table with `source_event_id` FK** | Rendering stability (payload materialized at write time); per-recipient flags need per-row storage; join-only design would require synthetic per-user rows anyway; matches EVENT_MODEL.md §7.6 forward-reference to "per-user unread state deferred to P1" — this is that P1. |
| **G-2** | DB-trigger routing vs async worker | **DB-trigger for v1** with logging EXCEPTION handler | Transactional guarantee; no new infrastructure per EVENT_MODEL §1; low fan-out in v1 makes trigger cost acceptable; EXCEPTION-caught to avoid rolling back workflow. Reconsider in v1.1 for high-fan-out events. |
| **G-3** | Notification vs preferences separation | **Preferences deferred to a future `notification_preferences` table** | v1 has no per-user muting; simplifies scope; reserved name-lock preserves upgrade path. |
| **G-4** | Per-channel delivery join vs channel array column | **`channels_attempted text[]` column for v1; `notification_deliveries` join reserved** | v1 is in-app only; the array degenerates to `{in_app}`; when non-in-app channels ship, the join table adds per-attempt provenance without breaking v1 shape. |
| **G-5** | Read / dismissed / archived — three orthogonal flags or single lifecycle | **Three orthogonal `timestamptz` flags; lifecycle for aggregation only** | Enables per-flag semantics (mark-unread reversal, dismiss-hides-but-keeps, archive-forever) without a fragile state enum; audit-friendly. |
| **G-6** | Badge count derivation — from notifications table only, not workflow | **Yes; single source of truth is `notifications`** | Consistency across slices; no double-counting; NavRail per-slice badges continue to use their own frozen `get_*_inbox_count` RPCs but the bell + Inbox badge is notification-derived. |
| **G-7** | Dedup rule | **Unique index on `(source_event_id, recipient_profile_id)`; router uses `ON CONFLICT DO NOTHING`** | Prevents multiple rules producing duplicate rows; enforced at DB level; router body simplifies. |
| **G-8** | Self-exclusion — actor never notified about own action | **Yes; enforced in the router body via `WHERE recipient_profile_id != actor_profile_id`** | Standard UX; noise reduction; explicit exclusion is cheaper than post-hoc filtering. |
| **G-9** | Notification retention | **90 days for read; forever for unread; dismissed 30 days; archived forever** | Product-standard retention; unread never auto-purged (avoids silent loss); retention job deferred (no v1 emitter). |
| **G-10** | Mark-all-read atomicity | **Single UPDATE ... WHERE `recipient_profile_id = auth.uid()` AND `workspace_id = :ws_id` AND `read_at IS NULL`** | Atomic; O(unread count) scan bounded by the partial index (§26.7); no Undo in v1 for the bulk path (documented limitation). |
| **G-11** | Cascade on user deletion | **Profiles are soft-deleted (no hard-delete in v1); notifications preserved; `recipient_profile_id` FK ON DELETE SET NULL for future hard-delete scenario** | Audit integrity; matches APP 008 §5.4 / APP 009 G-37 orphaned-originator posture. |
| **G-12** | Cross-project inbox | **Workspace-scoped inbox only in v1; project filter is a URL param** | Users think of "my inbox" as a person-scoped concept; workspace scope is the natural aggregation; per-project inbox route can be added later additively. |
| **G-13** | Category enum vs tags | **Enum via `text` + CHECK for v1; tags reserved but not shipped** | Simple filter chips; single-valued mental model; tags add complexity without v1 payoff. |
| **G-14** | Priority enum values | **`critical / high / medium / low / informational`** | Mirrors APP 008 requirement `priority` naming for platform-wide terminology consistency. |
| **G-15** | No notifications for the actor of the event | **Enforced in the router (see G-8)** | Same recommendation, called out explicitly for cross-reference from §9.8. |
| **G-16** | No "notification of notification" | **Router does not consume `notification.*` events** | Prevents infinite loops; reserved `notification.*` names are for AI-slice consumption, not APP 010's own router. |
| **G-17** | Reserved future events | **`notification.ai_prioritized`, `notification.ai_summarized`, `notification.digest_sent`** | Locks past-tense grammar (per APP 006 F-4.2 / APP 007 §21); pre-registers vocabulary for AI/cron slices. |
| **G-18** | Batching for high-volume events | **No v1 batching; per-event notifications only** | Simplicity; the router runs synchronously in the workflow transaction; batching adds delay and complexity; reconsider in v1.1 for broadcast events > 500 recipients. |
| **G-19** | Rate limiting for toast presentation | **Max 3 concurrent toasts on desktop / tablet; max 1 on mobile; overflow suppressed to Notification Center** | UX guardrail; prevents toast flooding during bursts. |
| **G-20** | Email-ready payload shape | **`payload jsonb` includes rendering-ready fields (`email_subject_line`, `email_body_snippet`, `email_cta_url`, `email_cta_label`) when `channels_attempted` includes `email_payload`; separate rendering service (not owned by APP 010) consumes** | Payload contract only; no SMTP in APP 010; downstream worker responsibility. |
| **G-21** | Push-ready payload shape | **Same posture as G-20; `payload.push_title / push_body / push_data` populated when `channels_attempted` includes `push_payload`** | No APNS/FCM in APP 010; payload contract only. |
| **G-22** | Notification-of-notification loop guard | **`notification.*` events are ignored by the router (§20.6 "unknown event types")** — even if they appear in `activity_events`, no notification produced | Defense-in-depth against G-16 violation. |
| **G-23** | Deep-link kind ownership | **Every deep-link kind referenced by a notification is owned by the source slice; APP 010 owns only `notification` kind** | Deep-link registry stays centralized in APP 002; APP 010 does not fragment. |
| **G-24** | Whether `notification.view` and `notification.manage` should be one capability or two | **Two, but grant both to every authenticated user by default** | Preserves future flexibility (a read-only mode for compliance/observation could grant `.view` without `.manage`); the current grant is uniform. |
| **G-25** | Order of tabs on Inbox | **All / Unread / Mentions / Assigned / Governance / Archived** | "All" is the safe default; "Unread" is the most-used; "Mentions" and "Assigned" are the most-actionable; "Governance" is the most-serious; "Archived" is the archive. Left-to-right reflects usage frequency. |
| **G-26** | Whether the Design Workspace RightPanel gains a Notifications tab | **No** | Bell + Center popover cover the need; RightPanel real estate is scarce (§21.4). |
| **G-27** | AI capability + event names reserved now | **Yes: `notification.ai_prioritize / .ai_summarize / .ai_digest` capabilities; `notification.ai_prioritized / .ai_summarized / .digest_sent` events; `ai.suggestion / ai.summary / ai.digest` notification types** | Locks vocabulary before AI slice starts. |
| **G-28** | Actor-of-event muting configurability | **Deferred — v1 has no preferences** | Per G-3; reserved to preferences slice. |
| **G-29** | Realtime for notifications table | **Remains OUT of publication; polling fallback (60s)** | Preserves REALTIME 001 boundary; APP 011 re-freeze required to change. |
| **G-30** | Mark-read optimistic; mark-all-read non-optimistic | **Yes** | Single-row mutations are safe; bulk operations wait for server truth (per APP 009 G-30 precedent). |
| **G-31** | Print / export view for Inbox | **Deferred to v2** | Not v1 scope; reserved. |
| **G-32** | `target_notification_id` on `comments` | **Do NOT add** | Notifications are not commentable per §27.2. |
| **G-33** | Roster / participant table on notifications | **Do NOT add** | Notifications have exactly one recipient by construction; no roster shape. |
| **G-34** | Notification-of-notification (recursion / echo suppression) | **See G-16 and G-22** — the router does not process `notification.*` events even if they land in `activity_events` | Same recommendation, cross-referenced. |
| **G-35** | Delivery to sub-audiences (e.g., only project leads on approval outcomes) | **Multi-recipient rules compose in the router; dedup via unique index handles collisions** | Per §9 rule composition. |
| **G-36** | Interaction with future digest slice | **APP 010 v1 provides no digest; digests are a future cron/AI slice that consumes `notifications` rows to produce `notification.digest_sent`** | Deferred. |
| **G-37** | Orphaned actor policy (`actor_profile_id` on notification) | **FK `ON DELETE SET NULL`; UI renders "Former member" or "System"** | Matches APP 009 G-37. |
| **G-38** | Notification display code / stable identifier | **None — notifications identified by UUID only; no `NF-NNN` per-project code** | Notifications are ephemeral (retention-limited); a stable code adds noise. |
| **G-39** | Payload size limit | **Soft 4 KB; hard 16 KB per row** | Prevents runaway payload sizes; enforced by CHECK on jsonb length. |
| **G-40** | Whether an archived notification can be un-archived | **No in v1; reserved future RPC `unarchive_notification`** | One-way to keep archive tab semantics simple. |
| **G-41** | Notification hard-delete | **Never in v1; retention job (reserved) may purge old rows via service_role** | Retention integrity. |
| **G-42** | Cross-workspace notifications | **Structurally impossible — every notification carries `workspace_id`, and cross-workspace membership is a separate model** | Preserves tenant boundary. |
| **G-43** | Compliance-audit read (support agent reads user X's inbox) | **v2 via reserved `notification.view_any` capability + audit trail** | Not v1 scope. |
| **G-44** | Whether APP 010 v1 requires any workflow-slice re-freeze | **No — APP 010 v1 is fully additive on top of the frozen event vocabulary** | Purest additive slice; zero re-freeze cost. |
| **G-45** | Reviewer / observer role and notifications | **Both roles get `notification.view` + `notification.manage`** | Every authenticated user has their own inbox. |
| **G-46** | Whether the router should notify on `activity_events` for events on soft-deleted subjects | **No — recipient set is filtered to active memberships at router time** | Prevents ghost notifications. |
| **G-47** | Whether `mark_all_notifications_read` should include informational notifications | **Yes — includes every unread regardless of priority** | User expectation of "mark all read" is total. |
| **G-48** | Idempotency of `mark_notification_read` on an already-read row | **RPC returns no-op success (rows-affected=0)** | Standard idempotent behavior. |
| **G-49** | Interaction with `activity_events.subject_snapshot` extensions | **Router reads only keys documented in the source slice's freeze index; unknown keys ignored** | Additive-consumer contract per APP 006 §17.1 precedent. |
| **G-50** | Payload jsonb format sanitization | **Server-produced payload is trusted; client sanitizes at render for XSS defense (`preview_snippet` is text, escaped on render)** | Standard XSS discipline. |
| **G-51** | Whether the router should log every skipped (feed-only) event | **No — silent skip; too verbose for the audit log** | Feed-only events are the vast majority; logging every skip would swamp logs. |
| **G-52** | Preservation of notifications after project archive | **Preserved; RLS still permits recipient read if `lign_is_project_participant(project_id)` remains true (archived projects retain participation)** | Historical record. |
| **G-53** | Notification for the event `workspace.member.invited` (pre-profile invitee) | **Email-ready payload only; no in-app row (invitee has no profile)** | Matches EVENT_MODEL.md §7.6; enables invitation email. |
| **G-54** | Whether Inbox has a "Star" / bookmark affordance | **No in v1; use `user_bookmarks` (APP 006) at the source-subject level instead** | Notifications are delivery records; bookmarks live on the workflow subject. |
| **G-55** | Whether the Notification Center can search | **No in v1; search lives in the Inbox screen (deferred; not v1)** | Deferred. |
| **G-56** | Whether notifications trigger native browser notifications (`Notification.requestPermission`) | **Deferred to APP 011 (push channel)** | Requires realtime + user consent flow; not v1 scope. |
| **G-57** | Reactive re-computation of `payload` on subject rename | **No — payload is immutable; the notification records what the subject looked like at event time** | Matches EVENT_MODEL.md §8 snapshot immutability. |
| **G-58** | Whether the recipient's own subsequent action on the subject dismisses the notification automatically | **No in v1; explicit dismiss required** | Preserves audit trail of "I saw this and acted"; auto-dismiss could hide the record too aggressively. Reconsider in v1.1 with per-user preference. |
| **G-59** | Whether a notification's `payload` includes the source event's full `subject_snapshot` verbatim | **No — payload materializes only the small rendering-required subset** | Size discipline; matches EVENT_MODEL §5 minimalism. |
| **G-60** | Cross-tab BroadcastChannel usage | **Name-reserved (`lign-notifications`); no v1 implementation** | Optional post-v1; polling covers the base case. |

---

## 29. Freeze checklist / non-goals

### 29.1 In scope for APP 010 v1

- Inbox screen (`/workspace/:ws_id/inbox`) with 6 tabs, filter bar, cursor pagination.
- Notification Center popover (bell-icon dropdown) with 2 sub-tabs and mark-all-read.
- Bell-icon unread badge (workspace-scoped).
- Toast presentation layer (rate-limited to 3 concurrent).
- `notifications` table (new; §4.1).
- Read / unread / dismissed / archived per-user flags (§11).
- 6 read RPCs + 8 write RPCs (§26.3, §26.4).
- Event-to-notification router trigger on `activity_events` insert (§20).
- Recipient-resolution rules (direct-actor, owner, requester, project-broadcast, project-leads, invitee-by-email) with dedup + self-exclusion.
- Email-ready payload contract (payload only — no SMTP; §10.4).
- Push-ready payload contract (payload only — no APNS/FCM; §10.4).
- 2 wired capabilities (`notification.view`, `notification.manage`).
- 6 reserved capability names (§19.3).
- 3 reserved event names in the `notification.*` namespace (§26.6).
- 4 reserved table names (§4.4).
- Deep-link kind `notification` + `/deep/notification/:id` route.
- `useCopyLink` extension (`LinkKind` `'notification'`, `'inbox'`).
- `useWorkspaceHotkeys` extension (`N`, `Shift+N`, `E`, `Backspace`).
- Reusable primitives per §27.4.
- Polling fallback (60s) for badge / list freshness.
- All existing APP 001–009 contracts preserved byte-for-byte.

### 29.2 Explicitly out of scope for APP 010 v1

Per the user brief:

- **SMS delivery.** No SMS provider integration; no SMS payload contract.
- **Scheduled cron / digests.** No cron emitter for daily/weekly digests; no `notification.digest_sent` emitter.
- **AI-generated notifications.** Reserved seams only (§24); zero wiring.
- **Digest generation.** Deferred to a future digest slice.
- **Escalation workflows** (e.g., "if not read in 2 hours, escalate to manager"). Deferred.
- **Webhooks** (external HTTP delivery). No webhook payload contract; no webhook worker.
- **Realtime transport** (websocket / SSE push of notifications). APP 011 territory; polling fallback in v1.
- **Per-user notification preferences** (per-category muting, per-channel selection). Reserved table (§4.4); no v1 UI, no v1 RPC.
- **SMTP sending.** APP 010 produces email-ready payloads only; the send is a downstream worker (deferred).
- **APNS/FCM push sending.** APP 010 produces push-ready payloads only; the send is a downstream worker (deferred).
- **Compliance-mode / admin read of another user's inbox.** Reserved capability (`notification.view_any`) only; no v1 wiring.
- **Retention purge job.** `deleted_at` column reserved; no cron emitter.
- **Search within Inbox** (full-text over payload). Deferred (G-55).
- **Native browser notifications** (Web Notifications API). Deferred (G-56).
- **Cross-tab BroadcastChannel sync.** Deferred (G-60).
- **Star / bookmark on notifications.** Deferred (G-54).
- **Auto-dismiss on user's own action on the subject.** Deferred (G-58).
- **Notification analytics** (delivery rate, open rate, click rate). No v1 metrics.
- **Print / PDF export of Inbox.** Deferred (G-31).
- **Any modification to APP 001–009 tables, RPCs, capabilities, events, routes, or components** — all APP 010 additions are additive.
- **Any new workflow event type** — APP 010 emits no workflow events, only consumes.
- **Any modification to `activity_events` schema.**
- **Adding `notifications` to the `supabase_realtime` publication** — REALTIME re-freeze (§25.2).

---

## 30. Cross-slice compatibility matrix

| Slice | Interaction with APP 010 | Direction |
|---|---|---|
| APP 001 (Domain) | Reads: `profiles`, `workspace_members`, `project_participants` (recipient resolution). Doc-only additive: `Notification` entity added to DOMAIN_MODEL.md. | Consume-only (+ doc-additive) |
| APP 002 (Application shell) | Extends: `qk` namespace, `DeepLinkResolver` kinds (`notification`), `CAPABILITY_KEYS` (2 wired + 6 reserved), `NavRail` items (1 new: Inbox), hotkey slots (`N`, `Shift+N`, `E`, `Backspace`). All additive. | Extend additively |
| APP 003 (Projects & Design Workspace) | Reads: `project_participants` for project-broadcast recipient rule. No Design Workspace changes (G-26). | Consume-only |
| APP 004 (Files & Viewer) | No interaction (notifications never render files; deep-link takes over). | None |
| APP 005 (Comments & Annotations) | Consumes: `comment.mentioned` (in-app notify), `annotation.resolved` (owner notify). Extends: `useCopyLink` (2 new `LinkKind` values). Does NOT add `target_notification_id` (G-32). | Extend additively (small surface) |
| APP 006 (Reviews) | Consumes: 4 P0 `review.*` events. Reserved future consumers: `review.deadline_approached / _passed`, `review.reviewer_removed / _reassigned`. Reads: `reviews`, `review_participants`. Does not mutate. | Consume-only |
| APP 007 (Approvals) | Consumes: all 6 P0 `approval.*` events. Reserved future consumer: `approval.deadline_approached`. Reads: `approval_requests`, `approval_request_approvers`. Does not mutate. | Consume-only |
| APP 008 (Requirements) | Consumes: **zero** `requirement.*` events in v1 (all feed-only per EVENT_MODEL §4.14 + APP 008 certification). Reserved future consumers: `requirement.assigned_to_you`, `.your_requirement_updated`, `.critical_regressed`, `.assessed_by_you_stale`. | Consume-only (reserved) |
| APP 009 (Releases) | Consumes: `release.finalized`, `release.withdrawn`. Reserved future consumers: `release.scheduled / .superseded / .recalled / .notes_updated / .ai_suggested / .ai_classified`. Reads: `releases`, `release_items` for project-broadcast recipient rule. Does not mutate. | Consume-only |
| APP 010 (this) | Owner | Owner |
| APP 011 (Realtime, not yet frozen) | Reserved dependency: adds `notifications` to `supabase_realtime`; wires `useNotificationRealtimeSubscription`. Polling fallback in v1. | Reserved (future) |
| STORAGE (STORAGE 001–004) | Untouched. | None |
| AUTHORIZATION (AUTH 001+) | Extends: PERMISSIONS.md §5 role preset table gains `notification.view` + `notification.manage` for every role. Additive. | Extend additively |
| REQUIREMENTS (REQUIREMENTS 001–005) | Untouched at the backend layer; consumed at the event layer (see APP 008 row above). | None (frozen backend); consume-only (events) |

---

**APP 010 Freeze Index ready for Backend Proposal.**
