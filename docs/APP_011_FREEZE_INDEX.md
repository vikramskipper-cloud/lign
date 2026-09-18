# APP 011 — Freeze Index

**Canonical architecture reference for the Lign Realtime module.**

Implementation has not started. This document consolidates the APP 011 (Realtime transport) architecture into one navigational reference on top of the **frozen publication scope** shipped by REALTIME 002 and the **frozen query/invalidation architecture** of APP 002–010. It preserves every APP 001–010 contract; extension is additive only. Sections marked **[additive]** identify surface expansions a follow-on `APP_011_BACKEND_PROPOSAL.md` will elaborate — no SQL, no migration, no RPC bodies, no subscription code is proposed here.

**Foundational premise (non-negotiable):**

> **APP 011 owns TRANSPORT. It does NOT own state.**
>
> Every realtime event APP 011 receives is translated into a **cache invalidation** against an existing `qk.*` key, using the existing helpers in `src/features/shared/invalidate.ts`. APP 011 **never writes a realtime payload into the React Query cache**. It **never mutates a table**. It **never emits an event**. It owns exactly one thing: reducing the time between a change landing in Postgres and the UI asking for it again.
>
> The reason is structural, not stylistic — see §2.2. Every list and detail surface in this app is fed by an RPC returning a joined, computed DTO. A Postgres Changes payload is a single raw table row. A raw row can never correctly populate a DTO cache, so hydration is not a design option that was rejected; it is one that does not exist.

**Companion frozen inputs:**
- `supabase/migrations/20260803180000_realtime_002_publication_scope.sql` — the frozen 8-table publication. The entire realtime surface.
- `docs/FREEZE_INDEX.md` — APP 002 query architecture (`qk` registry, React Query defaults), cache-invalidation ownership.
- `docs/APP_010_FREEZE_INDEX.md` §25 — the realtime boundary APP 010 pre-declared and handed to APP 011 as its authority.
- `docs/AUTHORIZATION_ARCHITECTURE.md`, `docs/PERMISSIONS.md` — RLS is the realtime authorization boundary; APP 011 adds no capability.
- `docs/PLATFORM_CHEATSHEET.md` rule 20 + `supabase/migrations/RECONCILIATION.md` — migration discipline if §13 G-1 is answered "yes".
- `tests/realtime/` — the REALTIME 002 probe harness that empirically validated multiplexed subscription and cross-workspace isolation.

---

## 1. Purpose

Today every surface in the app is **poll-or-act**: React Query refetches on a 30 s `staleTime`, on window focus, on reconnect, and on explicit post-mutation invalidation. A change made by another person is invisible until one of those fires.

APP 011 closes that gap for the 8 collaboration tables already in the publication. It is a **latency improvement, not a feature**: after APP 011 no screen shows anything it could not already show, it simply stops showing it late.

**Scope owned:** the websocket lifecycle, channel topology, the event→invalidation mapping, reconnect recovery, and (wave 2) presence.

**Scope explicitly NOT owned:** see §4.

---

## 2. Transport, not state

### 2.1 The rule

| Realtime event arrives | APP 011 does | APP 011 never does |
|---|---|---|
| `INSERT` on `comments` | `invalidateCommentsForVersion(qc, versionId)` | `qc.setQueryData([...], payload.new)` |
| `UPDATE` on `reviews` | `invalidateReview(qc, id)` + `invalidateReviewsLists(qc, wsId)` | patch the cached review row |
| `INSERT` on `approval_responses` | `invalidateApproval(qc, requestId)` | append to a cached responses array |

### 2.2 Why hydration is impossible here, not merely discouraged

Three independent reasons, any one of which is sufficient:

1. **Shape mismatch.** `qk.reviewsList(...)` is fed by `list_reviews_dashboard`, an RPC returning a computed DTO (roster counts, readiness, derived status). The WAL payload is a `reviews` row. The fields the UI renders do not exist in it.
2. **Column-level RLS filtering.** Realtime delivers the row as the *subscriber* may see it. A payload is not guaranteed to be the whole row.
3. **Ordering and pagination.** Dashboard keys embed server-opaque cursors (`PLATFORM_CHEATSHEET.md` rule 15). Splicing a row into a cursor-paginated cache corrupts the cursor contract.

Invalidation has none of these problems: it re-asks the server through the same RPC that produced the cache, and RLS and capability checks re-run exactly as they did the first time.

### 2.3 Consequence for the freeze

APP 011 introduces **no new query key**. Its entire cache surface is the existing `invalidate*` helper set. This is what makes it safe to layer on top of ten frozen slices.

---

## 3. Verified substrate facts

Established empirically against `hsfporioghapwghrvvzd` and `app/node_modules` on **2026-09-18**. These are inputs to the design, not decisions of it.

| # | Fact | Consequence for APP 011 |
|---|---|---|
| F-1 | The publication contains exactly 8 tables: `comments`, `annotations`, `asset_versions`, `reviews`, `review_participants`, `approval_requests`, `approval_responses`, `design_assets`. | The live surface is fixed. Anything else stays poll-driven. |
| F-2 | RLS is the authorization boundary; Realtime v2 re-runs SELECT policies per subscriber per WAL record. | APP 011 adds **no** authorization logic. A client cannot receive a row it could not SELECT. |
| F-3 | All 8 tables have `replica identity = default (primary key)`. | DELETE payloads structurally cannot carry `workspace_id`, so no client-side filter can match one. |
| F-4 | **No `DELETE` policy exists on any of the 8 tables.** `authenticated` cannot hard-delete from them; the domain soft-deletes via `status`. | APP 011 subscribes to **`INSERT` and `UPDATE` only**. F-3 becomes moot. Recorded as decision D-1. |
| F-5 | `supabase-js` 2.109.0 propagates the JWT to the socket automatically — on construction, on `TOKEN_REFRESHED`, on `SIGNED_IN`, and clears on `SIGNED_OUT`. | APP 011 **must not** call `realtime.setAuth()` itself. Doing so would fight the client. |
| F-6 | `src/lib/supabase.ts` already sets `realtime.params.eventsPerSecond = 30` (APP 002). | The rate cap is a frozen APP 002 value. §7.3 budgets against it; changing it is an APP 002 re-freeze. |
| F-7 | Postgres Changes has **no replay**. Events occurring while the socket is down are lost permanently. | Reconnect requires a broad invalidation sweep, not a resume. See §7. |
| F-8 | The REALTIME 002 probes verified multiplexed subscription to all 8 tables on one channel under a `workspace_id=eq.<id>` filter, plus anon isolation and cross-workspace isolation. | The topology in §5 is already proven on this project, not merely plausible. |

---

## 4. What APP 011 does NOT own

- **No new tables, columns, RPCs, triggers, capabilities, or events.**
- **No publication change** unless §13 G-1 is answered yes, which is a REALTIME re-freeze.
- **No workflow.** APP 011 never causes a state transition. If a realtime event could trigger a mutation, that is a bug.
- **No optimistic UI.** Post-mutation invalidation stays owned by each slice's `mutations.ts`. APP 011 is strictly additive to it; both may fire for the same change and the second invalidation is a no-op against a fresh cache.
- **No offline queue, no CRDT, no collaborative editing.** Out of scope permanently, not deferred.
- **No `activity_events` subscription.** That table is deliberately excluded from the publication (REALTIME 002 comment). The notification router already bridges it.

---

## 5. Subscription topology

### 5.1 One channel per active workspace

```
channel name:  lign:ws:<workspace_id>
bindings:      8 × postgres_changes
               { event: 'INSERT' | 'UPDATE', schema: 'public',
                 table: <one of the 8>, filter: 'workspace_id=eq.<ws_id>' }
```

Rationale:
- Every one of the 8 tables carries `workspace_id`, so a single filter expression covers all bindings (F-8 proved this).
- The workspace is the tenant boundary; a user works in one at a time (`lign.lastWorkspaceId`, APP 002).
- One socket, one channel, 16 bindings (8 tables × 2 events) is well inside the transport budget.

**Rejected alternatives:** per-project channels (churn on every project switch, and workspace-level surfaces such as dashboards and inbox counts would be starved); per-screen channels (subscription storms during navigation, duplicate events).

### 5.2 Lifecycle

Mounted once, high in the tree, beside `SessionProvider`. Subscribe when a session **and** an active workspace both exist; unsubscribe on workspace change and on `SIGNED_OUT`.

`SessionProvider` already calls `queryClient.clear()` on `SIGNED_OUT` — APP 011 must tear the channel down **before** that clear so no in-flight event repopulates a cleared cache.

### 5.3 Filter is performance, not security

Per the REALTIME 002 migration comment: *"client-side filters are performance narrowing only."* Removing the filter would not leak data (RLS still applies); it would only waste frames. §5.1's filter must never be described as an access control.

---

## 6. Event → invalidation mapping  **[additive]**

Every row below maps to a helper that **already exists** in `src/features/shared/invalidate.ts`. No new helper is required for wave 1; where a row needs context the payload lacks, see §6.2.

| Table | Event | Invalidates |
|---|---|---|
| `comments` | INSERT, UPDATE | `invalidateCommentsForVersion(target_version_id)`; comment-on-requirement/review/approval targets bump the owning detail key |
| `annotations` | INSERT, UPDATE | `invalidateAnnotationsForVersion(asset_version_id)` |
| `asset_versions` | INSERT, UPDATE | `qk.assetVersions(design_asset_id)`, `qk.assetVersion(id)`, `invalidateAssetsForProject(project_id)` |
| `design_assets` | INSERT, UPDATE | `invalidateAssetsForProject(project_id)`, `qk.asset(id)`, `invalidateNeighborsForAsset(id)` |
| `reviews` | INSERT, UPDATE | `invalidateReview(id, root_review_id)`, `invalidateReviewsLists(ws, project_id)`, `invalidateReviewInbox(ws)` |
| `review_participants` | INSERT, UPDATE | `qk.reviewParticipants(review_id)`, `invalidateReviewInbox(ws)` |
| `approval_requests` | INSERT, UPDATE | `invalidateApproval(id, root_id, version_id)`, `invalidateApprovalsLists(ws, project_id)`, `invalidateApprovalInbox(ws)` |
| `approval_responses` | INSERT, UPDATE | `invalidateApproval(approval_request_id)`, `invalidateApprovalInbox(ws)` |

### 6.1 Cross-slice fan-out

An `approval_responses` INSERT can change release readiness (APP 009) and requirement assessment state (APP 008). APP 011 does **not** encode that knowledge. It invalidates the approval surfaces only; each slice's existing readiness key has its own `staleTime` and refetches on next observation. **Guessing at downstream fan-out is how a transport layer becomes a business-logic layer.**

### 6.2 Payload sufficiency — an open risk

The mapping above assumes each payload carries the foreign keys it needs (`target_version_id`, `design_asset_id`, `project_id`, `root_review_id`). This is *likely* — these are NOT NULL columns on most of the 8 — but **has not been verified per-table against a live payload**. The backend proposal must confirm column-by-column, because F-2 means a payload is only what the subscriber may SELECT.

Where a needed key is absent, the fallback is a **coarser** invalidation (the whole list for the workspace), never a lookup round-trip to resolve it.

---

## 7. Connection lifecycle and the replay gap

### 7.1 The gap (F-7)

Postgres Changes is fire-and-forget. A client disconnected for 8 seconds during a deploy misses every event in that window, permanently. A naive implementation is *silently and indefinitely stale* — strictly worse than polling, which at least self-heals.

### 7.2 Required recovery

On every transition to `SUBSCRIBED` **after the first**, APP 011 must perform a **full invalidation sweep** of the live surface — treat the reconnect as "everything may have changed." React Query's existing `refetchOnReconnect: true` covers browser-level offline/online, but not a websocket that dropped while the browser stayed online, which is the common case.

This makes realtime strictly additive to polling: the poll floor is never removed, it is merely rarely the thing that wins.

### 7.3 Storm control

`eventsPerSecond: 30` (F-6) is the server-side cap. Client-side, invalidations must be **coalesced on a short trailing window** (target ~250 ms, to be fixed in the backend proposal) so a bulk operation — a roster edit touching 12 `review_participants` rows — produces one invalidation per key, not twelve. Coalescing is per key, not global.

### 7.4 Degradation is silent and must stay safe

If the socket never connects — corporate proxy blocking websockets, for instance — the app must behave exactly as it does today. No error toast, no blocked render, no spinner. A connection-state indicator is §8.3, and is advisory only.

---

## 8. Presence — wave 2  **[additive]**

Presence is listed as APP 011's concern in `FREEZE_INDEX.md`. It is **deliberately deferred to wave 2** so wave 1 ships the latency win with near-zero risk.

- **Channel:** `lign:presence:version:<asset_version_id>`, joined only while the Design Workspace is open on that version.
- **Payload:** `{ profile_id, display_name, avatar_url, joined_at }`. Nothing else — presence state is not persisted and never becomes a source of truth.
- **Surface:** a stacked avatar cluster in `VersionBar` (APP 003 owns that component; APP 011 extends it additively).
- **Explicitly not in scope:** cursor tracking, live selection, typing indicators, "who is editing" locks. `FREEZE_INDEX.md` APP 001 lists collaborative locks as a deliberate v0 omission and APP 011 does not reopen it.

### 8.3 Connection indicator

A single unobtrusive state in `TopBar`: connected / reconnecting / offline. Advisory only, per §7.4.

---

## 9. Capability model

**APP 011 introduces no capability key.** Realtime visibility is exactly SELECT visibility, enforced by RLS (F-2). A user who can see a row in a list can see its live update, and vice versa. There is no `realtime.*` capability tier and none is reserved — introducing one would create a second authorization surface that could drift from RLS.

---

## 10. Cross-slice compatibility

| Slice | Impact |
|---|---|
| APP 002 Shell | Extends `SessionProvider` sibling tree with a provider. Consumes `qk`; adds no key. Ordering constraint in §5.2. |
| APP 003 Projects/Workspace | `VersionBar` gains a presence slot (wave 2). No contract change. |
| APP 004 Files | Untouched. `version_files` and `files` are not in the publication. |
| APP 005 Comments/Annotations | Primary beneficiary. Its invalidators are called by APP 011 rather than only by its own mutations. |
| APP 006 Reviews / APP 007 Approvals | Beneficiaries via existing invalidators. |
| APP 008 Requirements / APP 009 Releases | **No live surface in wave 1** — none of their tables are in the publication. They benefit only indirectly. Adding them is a REALTIME re-freeze, not an APP 011 default. |
| APP 010 Notifications | Blocked on §13 G-1. See §11. |

---

## 11. APP 010's handoff — two defects found

APP 010 §25 pre-declared this boundary and named APP 011 as its authority. Two things must be reconciled:

1. **`notifications` is out of the publication.** Adding it is a REALTIME re-freeze event and therefore a migration (§13 G-1). Until answered, the bell keeps APP 010's 60 s poll.
2. **The reserved placeholders were never shipped.** APP 010 §25.3 states it exports channel-name constants from `src/features/notifications/realtime.ts`, and §8.2 (and certification observation T-5) references `src/features/notifications/routing.ts`. **Neither file exists in the repository.** Verified 2026-09-18. T-5 therefore describes a drift risk between a SQL routing table and a file that was never created.

Neither is an APP 011 defect, but APP 011 is where they surface. Recorded as G-5.

---

## 12. Reserved names (name-locked, no implementation in wave 1)

| Name | Reserved for |
|---|---|
| `lign:ws:<workspace_id>` | wave 1 workspace channel (§5.1) |
| `lign:presence:version:<asset_version_id>` | wave 2 presence (§8) |
| `notifications:profile:<profile_id>` | APP 010 §25.3, pending G-1 |
| `notifications:workspace:<ws_id>` | APP 010 §25.3, pending G-1 |
| `src/features/realtime/` | module root |
| `useRealtimeConnection()` | connection state hook (§8.3) |
| `useVersionPresence(versionId)` | wave 2 |

---

## 13. Open architectural decisions

| # | Decision | Recommendation |
|---|---|---|
| **G-1** | Does APP 011 add `notifications` to the publication? It is the single highest-value live surface (the bell is the one thing users watch), but it requires a migration and a REALTIME re-freeze. | **Yes, in wave 1.** The migration is one `alter publication` line; `notifications` already has recipient-scoped RLS and RPC-only writes, so the security posture is unchanged. This contradicts the earlier claim that APP 011 adds no migrations — it does, if G-1 is yes. |
| **G-2** | Presence in wave 1 or wave 2? | **Wave 2**, per §8. |
| **G-3** | Coalescing window. | 250 ms trailing, per key. Fix in the backend proposal. |
| **G-4** | Multi-tab: one socket per tab, or a `BroadcastChannel` leader election? | **One socket per tab** in wave 1. Simpler, and the cost is bounded by §7.3. APP 010 §18.6 already reserves `BroadcastChannel` if this proves wasteful. |
| **G-5** | Who fixes APP 010's missing `realtime.ts` / `routing.ts` (§11)? | APP 011 creates `realtime.ts` since it is the consumer. `routing.ts` is an APP 010 amendment, not APP 011 scope. |
| **G-6** | Does §6.2 payload sufficiency hold for all 8 tables? | Must be verified empirically in the backend proposal before any mapping is frozen. |

---

## 14. Freeze checklist / non-goals

**Wave 1 ships when:**
- [ ] One workspace channel, 8 tables × {INSERT, UPDATE}, `workspace_id` filtered
- [ ] Every event maps to an existing `invalidate*` helper; zero new `qk` keys
- [ ] Reconnect performs a full sweep (§7.2)
- [ ] Invalidations coalesced per key (§7.3)
- [ ] Socket failure is silent and the app behaves exactly as today (§7.4)
- [ ] Channel torn down before `queryClient.clear()` on sign-out (§5.2)
- [ ] `realtime.setAuth()` is never called by app code (F-5)
- [ ] No mutation, no event emission, no capability, no workflow logic
- [ ] Typecheck + build pass; bundle delta reported

**Permanent non-goals:** collaborative editing, CRDTs, operational transforms, cursor sharing, offline queues, live locks, subscribing to `activity_events`.

---

## 15. Backend delta preview  **[additive]**

If G-1 is **yes**, exactly one migration:

```sql
alter publication supabase_realtime add table public.notifications;
```

plus a re-freeze note against REALTIME 002 and `docs/freeze/`. Nothing else: no policy, no column, no trigger, no RPC, no capability. `notifications` RLS already restricts SELECT to `recipient_profile_id = auth.uid()`, so the per-subscriber filter is already correct.

If G-1 is **no**, APP 011 ships **zero migrations** and is a pure frontend slice.

Per `supabase/migrations/RECONCILIATION.md`, any migration must be applied **from a file**, and `ops/verify_migrations.sh` re-run afterwards.
