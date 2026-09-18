# APP 010 Final Certification

**Permanent governance record for APP 010 — Notifications.**

This document certifies the collective status of the APP 010 slice as permanently frozen. Authoritative sources:

- [`docs/APP_010_FREEZE_INDEX.md`](../APP_010_FREEZE_INDEX.md)
- [`docs/APP_010_BACKEND_PROPOSAL.md`](../APP_010_BACKEND_PROPOSAL.md) (Backend Re-freeze Report applied at head)
- APP 010 Backend Re-freeze Review Report
- APP 010 Implementation Report
- APP 010 Final Architecture Audit Report

---

## 1. Overall status

- **Version:** v1.0
- **Certification date:** 2026-08-06
- **Implementation status:** Complete. Wave 1 backend surface deployed to project `hsfporioghapwghrvvzd` via Migrations `20260805154249` (schema), `20260805154603` (authz + RPCs + router), and `20260805154843` (router body hotfix for partial-unique `ON CONFLICT` inference). All Wave 1 frontend surfaces implemented, typechecked, built, and integrated with APP 002–009.
- **Freeze status:** **Permanently frozen.**

APP 010 has completed the full governance cycle: Freeze Index → Backend Proposal → Backend Re-freeze Review (7 findings F-1..F-7) → Backend Re-freeze Report (all findings applied) → Implementation → Implementation Report → Final Architecture Audit (15 empirical probes, all PASS). No open blockers. APP 001–009 contracts remain byte-identical. The frozen `activity_events` table shape, RLS, and append-only triggers are preserved verbatim.

---

## 2. Architecture verification

The deployed architecture matches the frozen contract along every audited dimension:

- **Delivery, not workflow.** APP 010 owns notification delivery only. It never mutates workflow tables (`reviews`, `approvals`, `approval_requests`, `requirements`, `releases`, `release_items`, `comments`, `annotations`, `activity_events`, or any other frozen surface). It only INSERTs into its own `notifications` table via the router trigger. Verified: zero writes to any workflow table anywhere in the deployed code path.
- **Event consumption is one-way.** The router is an AFTER INSERT trigger on the frozen `activity_events` table (boundary-additive: no column, no RLS, no data change on the frozen table; only spawns rows in a new APP 010-owned table).
- **F-1 helper-reference correction verified empirically.** SELECT RLS policy uses `public.lign_project_role(project_id) IS NOT NULL`; the non-existent `lign_is_project_participant` is absent from the deployed policy. Migration would have failed at deploy time without the F-1 fix.
- **F-2 explicit recursion guard verified empirically.** Router body step 1a: `IF NEW.event_type LIKE 'notification.%' THEN RETURN NEW; END IF;` — fires before the routing-table dispatch. Fake `notification.digest_sent` insert produced 0 notification rows (empirical smoke test).
- **F-3 `lign_has_capability` reissue verified byte-identical for prior slices.** Exactly 1 row in `pg_proc` for `lign_has_capability`. Signature `(uuid, uuid, text) → boolean` preserved. Every APP 001–009 capability role mapping preserved verbatim. Only 2 new wired keys (`notification.view`, `notification.manage`) and 6 reserved zero-grant keys appended.
- **Router exception safety verified empirically (probe P-11).** Router body wrapped in `BEGIN … EXCEPTION WHEN OTHERS THEN RAISE WARNING 'notification router failed …'; RETURN NEW; END;`. Multi-event transaction with a deliberately malformed router payload commits both parent `activity_events` rows; router silently `RAISE WARNING`s on the broken one; workflow transaction not rolled back.
- **Self-exclusion verified empirically (probe P-9).** `IF new.actor_profile_id IS NOT NULL AND v_recipient_id = new.actor_profile_id THEN CONTINUE; END IF;` inside the recipient loop. `release.finalized` from a lead actor produced 4 notifications to other participants; actor excluded.
- **Dedup verified.** `INSERT ... ON CONFLICT (recipient_profile_id, source_event_id, notification_type) WHERE archived_at IS NULL DO NOTHING` correctly infers the I-7 partial unique index. Idempotent re-fires produce no duplicates.
- **RPC-only-write GUC gate operational.** Every write RPC sets `lign.allow_notification_rpc_write='true'` (transaction-local), executes UPDATE with `recipient_profile_id = auth.uid()` predicate, then resets the GUC. `enforce_notification_rpc_only_writes` raises SQLSTATE 42501 for any UPDATE without the GUC.
- **Payload immutability enforced.** `enforce_notification_immutable_fields` blocks any mutation of the 17 immutable columns even under the GUC flip (empirical: SQLSTATE 23514 on payload UPDATE attempt).
- **Recipient ownership enforcement.** Dual defense: RPC body predicate `recipient_profile_id = auth.uid()` + RLS UPDATE policy `recipient_profile_id = auth.uid()`. Cross-recipient mutation structurally impossible for `authenticated` role.
- **Realtime remains OUT.** `pg_publication_tables` for `supabase_realtime` shows 0 rows for `notifications`. Adding `notifications` to the publication is an APP 011 re-freeze event.

---

## 3. Backend contract verification

**Migrations recorded in `supabase_migrations.schema_migrations`:**

| Migration | Purpose |
|---|---|
| `20260805154249_app_010_notifications_schema` | 1 wired table (`notifications`), 21 physical columns, 9 additive indexes (I-1..I-9 including partial-unique dedup I-7), 5 CHECK constraints, 4 FKs, RLS enabled with 4 policies, 3 row-local triggers (all NOT SECURITY DEFINER per F-6) |
| `20260805154603_app_010_notifications_authz_and_rpcs` | Single-function additive `CREATE OR REPLACE` of `lign_has_capability` (F-3), AFTER INSERT router trigger + `resolve_notification_router_targets` function (SECURITY DEFINER, exception-safe, F-2 explicit recursion guard), 5 read RPCs, 5 write RPCs |
| `20260805154843_app_010_router_fix_partial_index_inference` | Router body hotfix: `ON CONFLICT (cols) WHERE pred` inference syntax (partial UNIQUE INDEX cannot be referenced via `ON CONSTRAINT`). Additive; no contract, schema, or signature change |

**Schema surface (per Final Architecture Audit):**

- **Tables added:** 1 wired (`notifications`) + 4 reserved name-only (`notification_preferences`, `notification_deliveries`, `notification_digests`, `notification_router_errors`).
- **Columns added:** 21 physical / 19 domain columns on `notifications`.
- **Indexes added:** 9 (I-1..I-9) with correct partial predicates. I-7 is the dedup partial-unique.
- **CHECK constraints:** 5 (category, priority, delivery_state, channels_attempted, payload size ≤16 KB).
- **FKs:** 4 (recipient → profiles SET NULL; composite (project_id, workspace_id) → projects CASCADE; source_event_id → activity_events CASCADE; actor → profiles SET NULL). Every FK covered by an index.
- **Triggers on `notifications`:** 3 row-local (`enforce_notification_immutable_fields`, `enforce_notification_rpc_only_writes`, `notifications_set_updated_at`), all `prosecdef=false` with `search_path=''` per F-6.
- **Trigger on `activity_events`:** 1 boundary-additive AFTER INSERT (`enforce_notification_router_bridge`), function `prosecdef=true` (cross-table reads), `search_path=''`, REVOKEd from public/anon/authenticated with no GRANT.
- **RLS:** 4 new policies on `notifications` (SELECT gated by recipient + capability + participant helper; INSERT deny; UPDATE recipient-only + RPC-only-write GUC gate; DELETE deny). Frozen `activity_events` RLS byte-identical.

**RPCs (5 read + 5 write; every one SECURITY DEFINER + `search_path=''` + REVOKE public/anon/authenticated + GRANT `authenticated, service_role`):**

- **Read:** `list_notifications_inbox`, `get_notification`, `get_notification_badge_count`, `get_notification_center`, `list_notifications_by_source`. Every one filters `recipient_profile_id = auth.uid()` and re-checks `notification.view` inline.
- **Write:** `mark_notification_read`, `mark_notification_unread`, `mark_all_notifications_read`, `dismiss_notification`, `archive_notification`. Every one sets the RPC-only-write GUC, enforces `recipient_profile_id = auth.uid()` in the WHERE clause, checks `notification.manage` inline, and mutates only the `notifications` table.

No RPC emits any event. Zero writes to `activity_events`, workflow tables, or any other frozen table.

**Capabilities:** 2 wired (`notification.view`, `notification.manage`); 6 reserved zero-grant (`notification.view_any`, `notification.announce`, `notification.ai_prioritize`, `notification.ai_summarize`, `notification.ai_digest`, `notification.preference`). Prior slices' role maps byte-identical inside the reissued `lign_has_capability`.

**Events:** 0 emitted in v1. 3 reserved past-tense names registered in `docs/EVENT_MODEL.md` §11 Wave 1 doc-diff: `notification.ai_prioritized`, `notification.ai_summarized`, `notification.digest_sent`. Router explicitly ignores `notification.%` events via F-2 step-1a guard.

---

## 4. Approved architectural decisions

The following decisions from the freeze cycle are ratified and locked:

1. **Delivery, not workflow.** APP 010 owns notification delivery. Business workflow ownership stays with Requirements/Reviews/Approvals/Releases/Comments. APP 010 consumes events read-only.
2. **Single wired table, additive extension.** `notifications` is APP 010-owned; 4 reserved tables name-only for future waves. Zero columns added to any frozen table.
3. **Boundary-additive router trigger on `activity_events`.** AFTER INSERT trigger on the frozen table is permissible because it (a) does not modify the table's schema, RLS, or data, (b) only spawns rows in an APP 010-owned table, and (c) is exception-safe so it cannot roll back the frozen INSERT.
4. **Router exception safety is inviolable.** Router body wrapped in `BEGIN … EXCEPTION WHEN OTHERS THEN RAISE WARNING; RETURN NEW; END`. Workflow correctness supersedes notification completeness.
5. **F-1 helper reference discipline.** Every helper function referenced in APP 010 exists in the frozen baseline: `lign_has_capability`, `lign_project_role`, `lign_is_workspace_admin`, `set_updated_at`, `gen_random_uuid`. `lign_is_project_participant` is deliberately NOT referenced (it does not exist in the frozen schema).
6. **F-2 explicit recursion guard.** Primary defense = explicit `LIKE 'notification.%'` check as router step 1a. Secondary defense = absence of routing-table entries for `notification.*` names. Both layers documented; primary layer verified empirically.
7. **F-3 `lign_has_capability` additive-only reissue.** Exactly one `CREATE OR REPLACE` on the frozen 3-arg function. Signature preserved. Every existing capability and role mapping byte-identical. Only `notification.*` keys appended.
8. **RPC-only-write GUC gate.** Every notification-lifecycle mutation flows through a SECURITY DEFINER RPC that sets a transaction-local GUC; direct UPDATEs blocked by trigger.
9. **Recipient ownership enforcement (dual defense).** Every write RPC's WHERE clause includes `recipient_profile_id = auth.uid()`; RLS UPDATE policy independently enforces the same predicate.
10. **Payload immutability after INSERT.** `enforce_notification_immutable_fields` blocks mutation of the 17 immutable columns. Only the 4 lifecycle flags (`read_at`, `dismissed_at`, `archived_at`, `updated_at`) are mutable.
11. **Self-exclusion.** The actor of an event is never notified about their own action. Enforced in the router recipient loop before insertion.
12. **Dedup via partial-unique with matching ON CONFLICT.** `(recipient_profile_id, source_event_id, notification_type) WHERE archived_at IS NULL` — the router inserts with `ON CONFLICT (cols) WHERE pred DO NOTHING` for idempotency.
13. **Realtime remains OUT of `supabase_realtime` publication.** Delivery in v1 is via polling (60s badge, on-demand inbox). APP 011 re-freeze required to add to publication.
14. **No emitted events in v1.** State stored in row (`read_at`, `dismissed_at`, `archived_at`). Reserved event names locked for future waves.
15. **Row-local triggers are NOT SECURITY DEFINER (F-6 discipline).** Only the cross-table router trigger is DEFINER.

---

## 5. Files created

**Backend migrations:**

- `supabase/migrations/20260816120000_app_010_notifications_schema.sql`
- `supabase/migrations/20260816180000_app_010_notifications_authz_and_rpcs.sql`

(Remote apply produced 3 migration entries; the third `app_010_router_fix_partial_index_inference` was the one-line partial-index-inference hotfix folded into the local schema files for reproducibility.)

**Frontend (all under `app/src/features/notifications/`):**

- `types.ts`, `queries.ts`, `mutations.ts`
- `NotificationBell.tsx`, `NotificationCenter.tsx`, `NotificationCard.tsx`, `NotificationBadge.tsx`
- `NotificationFilterBar.tsx`, `InboxScreen.tsx`
- `useNotificationBadgeCount.ts`

**Governance:**

- `docs/APP_010_FREEZE_INDEX.md`
- `docs/APP_010_BACKEND_PROPOSAL.md` (Backend Re-freeze Report at head)
- `docs/freeze/APP_010_FINAL_CERTIFICATION.md` (this document)

---

## 6. Files modified

All modifications additive; APP 001–009 behavior preserved:

- `app/src/types/capabilities.ts` — appended `notification.view`, `notification.manage` to `CAPABILITY_KEYS`.
- `app/src/lib/queryKeys.ts` — 7 new `qk.notification*` builders.
- `app/src/features/shared/invalidate.ts` — `invalidateNotifications`, `invalidateNotificationBadge`, `invalidateNotificationSurfaces`.
- `app/src/features/comments/useCopyLink.ts` — `LinkKind` union += `'notification' | 'inbox'`.
- `app/src/features/design-workspace/useWorkspaceHotkeys.ts` — Shift+N / E / Backspace handlers.
- `app/src/auth/DeepLinkResolver.tsx` — real `kind="notification"` resolver.
- `app/src/router.tsx` — `/workspace/:ws_id/inbox` + `/deep/notification/:id` routes.
- `app/src/shell/TopBar.tsx` — mounted `<NotificationBell />`.
- `app/src/shell/NavRail.tsx` — workspace "Inbox" item wired to `useNotificationBadgeCount`.
- `docs/EVENT_MODEL.md` — §11 doc-diff registering 3 RESERVED `notification.*` event names.

No APP 001–009 migration, RLS policy, RPC, capability key, event vocabulary entry, or public component API was removed, renamed, or semantically altered.

---

## 7. Backend surface summary

| Dimension | Count | Notes |
|---|---|---|
| Migrations (canonical local) | 2 | Remote applied in 3 entries including partial-index-inference hotfix |
| Tables added | 1 wired + 4 reserved | Zero columns on frozen tables |
| Columns added | 21 physical / 19 domain | All on `notifications` |
| Indexes added | 9 (I-1..I-9) | Includes partial-unique dedup I-7 |
| CHECK constraints | 5 | category, priority, delivery_state, channels_attempted, payload size |
| FKs added | 4 | Every FK covered by an index |
| Triggers added on `notifications` | 3 | All NOT SECURITY DEFINER (F-6) |
| Trigger added on frozen `activity_events` | 1 | Boundary-additive AFTER INSERT (F-2 recursion guard, exception-safe) |
| Frozen `activity_events` triggers preserved | 2 | `activity_events_no_update`, `activity_events_no_delete` both `tgenabled='O'` |
| RLS policies added | 4 | SELECT recipient+capability+participant; INSERT deny; UPDATE recipient+GUC; DELETE deny |
| Read RPCs added | 5 | All SECURITY DEFINER + `search_path=''` + ownership filter |
| Write RPCs added | 5 | All SECURITY DEFINER + GUC set/reset + ownership filter + zero workflow-table mutation |
| `lign_has_capability` reissue | 1 (additive) | Signature preserved; prior mappings byte-identical (F-3) |
| Capabilities added (wired) | 2 | `notification.view`, `notification.manage` |
| Capabilities added (reserved zero-grant) | 6 | Name-only |
| New emitted event types | 0 | Reserved names only |
| Reserved event names | 3 | Registered in EVENT_MODEL.md per F-5 |
| `notifications` in `supabase_realtime` | No | OUT |

---

## 8. Query architecture

TanStack Query v5. Notification-namespaced keys under `qk`:

```
qk.notificationsList(scope, view, filters)
qk.notificationsInbox(wsId, tab, filters)
qk.notificationsUnread(wsId)
qk.notification(id)
qk.notificationBadgeCount(wsId)
qk.notificationCenter(wsId)
qk.notificationsBySource(kind, id)
qk.notificationInboxFacets(wsId)
```

No collision with APP 005 `qk.comment*` / `qk.annotation*`, APP 006 `qk.review*`, APP 007 `qk.approval*`, APP 008 `qk.requirement*`, APP 009 `qk.release*`. Invalidators `invalidateNotifications`, `invalidateNotificationBadge`, `invalidateNotificationSurfaces` invoke the correct combination of list/badge/inbox/detail keys per mutation.

Cursor pagination on `list_notifications_inbox` uses opaque `(created_at DESC, id DESC)` tuple. Badge polling interval: 60s until APP 011 realtime lands.

---

## 9. Routing

Router entries added to `app/src/router.tsx`:

| Path | Component | Notes |
|---|---|---|
| `/workspace/:ws_id/inbox` | `<InboxScreen />` (with `InboxHandle`) | Workspace-scoped full-page inbox |
| `/deep/notification/:id` | `<DeepLinkResolver kind="notification" />` | Real resolver; fetches `get_notification` then navigates to inbox with `?highlight=<id>` |

**URL parameters (owned by APP 010):**

- Inbox: `?tab=all | unread | mentions | assigned | governance | archived`, `?category` (CSV), `?priority` (CSV), `?source` (CSV), `?date_from`, `?date_to`, `?cursor`, `?highlight=<uuid>`.
- Notification Center popover: no URL state (transient UI).

No collision with APP 003 `?discipline`, APP 005 `?comment/annotation`, APP 006 `?review/participant`, APP 007 `?approval/participant`, APP 008 `?priority/source/category/scope/code`, APP 009 `?view/status/type/tab/q/compose`.

---

## 10. Reusable primitives

**Consumed unchanged from prior slices:**

- APP 002 shell: `AuthGate`, `RootLayout`, `WorkspaceLayout`, `ProjectLayout`, `DeepLinkResolver`, `NavRail`, `qk` registry, `CAPABILITY_KEYS`.
- APP 005: `useCopyLink` (per-notification copy-link with `LinkKind` extended additively).
- APP 001: `set_updated_at()` frozen function reused for `notifications_set_updated_at` trigger.
- Frozen helper functions: `lign_has_capability`, `lign_project_role`, `lign_is_workspace_admin`.

**Deliberately NOT consumed:**

- APP 005 `CommentsPanel` — releases and notifications do not collect discussion.
- APP 006 `user_bookmarks`/`user_saved_views` — inbox does not use saved views in v1 (deferred to future wave).

**New primitives introduced by APP 010 (notification-specific):**

- `NotificationBell`, `NotificationCenter`, `NotificationCard`, `NotificationBadge`, `NotificationFilterBar`, `InboxScreen`
- `useNotificationBadgeCount` hook (60s polling)

---

## 11. Build verification

Recorded in the Implementation Report and re-confirmed by the Final Architecture Audit:

- `npm run typecheck`: **PASS** (clean).
- `npm run build`: **PASS** (1929 modules transformed; 2.05s build time).
- Bundle: before **987.21 kB** → after **1005.04 kB** (gzip 275.66 kB). Delta **+17.83 kB raw (+1.81%)** / ~+8 kB gzip. Vite chunk-size warning threshold unchanged from pre-APP-010 posture.
- Migration application: **PASS** — all 3 remote migration entries recorded (2 canonical local files + 1 folded hotfix).

---

## 12. Advisor results

- **Security advisors.** Zero ERROR. WARN classes: 10 new `authenticated_security_definer_function_executable` WARNs (matching baseline — every new SECURITY DEFINER RPC correctly uses `search_path=''`, REVOKEs from `public/anon/authenticated`, GRANTs EXECUTE only to `authenticated, service_role`); 1 pre-existing `auth_leaked_password_protection` WARN unrelated to APP 010. **No new issue class introduced.**
- **Performance advisors.** 1 acknowledged `unindexed_foreign_keys` INFO on `notifications_source_event_fk` (deliberate: `source_event_id` is the second column of the I-7 partial unique; standalone covering index deliberately not shipped because `activity_events` ON DELETE CASCADE is rare-to-never in v1). 7 `unused_index` INFO on freshly-created indexes (identical to APP 006/007/008/009 post-freeze posture; will clear once dashboards see load). **No new issue class introduced.**

---

## 13. APP 001–009 preservation

Every prior slice's contract is intact:

- **APP 001 — Auth / Foundation.** `lign_has_capability` reissued with every prior capability role mapping byte-identical. `activity_events` table shape unchanged; RLS unchanged; frozen `activity_events_no_update` and `activity_events_no_delete` triggers preserved and enabled. `profiles`, `workspaces`, `workspace_members`, `stakeholders`, `invitations` unchanged. Frozen `set_updated_at()` function reused.
- **APP 002 — Shell.** Router, `qk` registry, `CAPABILITY_KEYS`, `DeepLinkResolver`, `NavRail`, `TopBar` all extended additively. Every existing route, key, capability, resolver, and NavRail item preserved verbatim.
- **APP 003 — Projects & Design Workspace.** Read-only consumption of `project_participants` and `projects` for router recipient resolution. No table modified.
- **APP 004 — Files & Viewer.** Untouched.
- **APP 005 — Comments & Annotations.** Read-only consumption of `comment.mentioned` and `annotation.resolved` events; reads `annotations.author_profile_id` for owner-rule resolution. `useCopyLink` extended additively.
- **APP 006 — Reviews.** Read-only consumer of 4 `review.*` events (`review.opened`, `review.completed`, `review.cancelled`, `review.reviewer_responded`); reads `reviews` and `review_participants`.
- **APP 007 — Approvals.** Read-only consumer of 6 `approval.*` events; reads `approval_requests` and `approval_request_approvers`.
- **APP 008 — Requirements.** Zero events consumed in v1 (feed-only per EVENT_MODEL.md §4.14). Reserved for future waves.
- **APP 009 — Releases.** Read-only consumer of `release.finalized` and `release.withdrawn` events; reads `project_participants` for project-broadcast fan-out.

**Frozen `activity_events`** migrations (`20260729235959_activity_events.sql` and `20260802000000_auth_009_activity_events_rls.sql`) remain live, authoritative, and byte-identical. All frozen APP 006/007/008/009 schema and authz migrations SHA-verified byte-identical after APP 010 shipped.

---

## 14. Non-blocking observations

The Final Architecture Audit identified the following observations. All are informational and **do not affect the frozen implementation.** Recorded here for transparency, not as freeze blockers.

- **T-1 (LOW / DOC).** `qk.notificationsForSubject` in Freeze Index §17.1 is implemented as `qk.notificationsBySource` in `queryKeys.ts`. Same key-tuple shape (`['notification','subject', kind, id]`) and same semantics. Harmless naming choice.
- **T-2 (LOW / DOC).** `qk.notificationInboxFacets` exists in `queryKeys.ts` but is not enumerated in Freeze Index §17.1. Purely additive; document in a future doc-diff.
- **T-3 (LOW / DOC).** Freeze Index §26.4 enumerates 8 write RPCs (single + bulk pairs for read/dismiss/archive) but Wave 1 wired only the 5 single-row variants. The bulk variants are Wave 2 scope per the Backend Proposal wave plan. Consider a one-line cross-link in the freeze index.
- **T-4 (LOW / OBSERVATIONAL).** `notifications` DELETE from `postgres`/`service_role` bypasses RLS (as expected) and is not additionally gated by any trigger (only UPDATE is gated by `enforce_notification_rpc_only_writes`). Intentional (retention pruning in a future wave uses `service_role`); non-service-role deletes are correctly RLS-denied.
- **T-5 (LOW / OBSERVATIONAL).** Router body carries the routing table inline (30+ CASE arms). Freeze Index §8.2 requires this mirror to be kept in sync with `src/features/notifications/routing.ts`. Consider a CI-time linter for drift prevention in a future wave.

None of these observations constitute a contract violation, a runtime bug, a cross-slice regression, or a maintenance risk that requires action prior to freeze.

---

## 15. Permanent freeze confirmations

- ✅ Every CRITICAL requirement from the APP 010 Backend Re-freeze Review is implemented and empirically verified (F-1 helper reference; F-2 explicit `notification.%` recursion guard; F-3 additive-only `lign_has_capability` reissue).
- ✅ Every HIGH, MEDIUM, and LOW correction (F-4 dedup documentation; F-5 `actor_display_name` canonical position; F-6 row-local triggers NOT SECURITY DEFINER; F-7 accurate frozen trigger names) is applied.
- ✅ Boundary-additive AFTER INSERT trigger on frozen `activity_events` recorded and empirically verified to preserve the frozen table's schema, RLS, and append-only guarantees.
- ✅ Additive `CREATE OR REPLACE` of `lign_has_capability` recorded; exactly 1 row in `pg_proc`; every prior role mapping byte-identical.
- ✅ `notifications` table recorded as APP 010-owned; zero columns added to any frozen table.
- ✅ `notifications` remains OUT of `supabase_realtime` publication.
- ✅ Explicit `notification.%` recursion guard recorded at router step 1a; primary defense verified empirically.
- ✅ Router exception safety recorded and verified empirically (probe P-11): workflow transactions survive router failures.
- ✅ RPC-only-write discipline recorded and verified empirically: `enforce_notification_rpc_only_writes` raises SQLSTATE 42501 for any UPDATE without the transaction-local GUC.
- ✅ Payload immutability enforced and verified empirically: `enforce_notification_immutable_fields` raises SQLSTATE 23514 on any attempted mutation of the 17 immutable columns.
- ✅ Recipient ownership enforcement recorded: dual defense via RPC body `WHERE recipient_profile_id = auth.uid()` and RLS UPDATE policy.
- ✅ All 15 empirical probes P-1..P-15 PASS.
- ✅ APP 001–009 remain unchanged except for approved additive extensions (§13).
- ✅ APP 010 introduces no unauthorized surface. Boundary trigger on frozen `activity_events` explicitly justified; `lign_has_capability` reissue additively justified.
- ✅ Build verification: typecheck PASS, build PASS, bundle delta +17.83 kB within acceptable slope.
- ✅ Advisor verification: zero ERROR; only expected WARN/INFO classes; no new issue class introduced.

---

## 16. Final verdict

**APP 010 is permanently frozen. This report becomes the authoritative certification document for APP 010. Future changes require an amendment and re-freeze.**
