# APP 011 — Backend Delta + Review

**Compressed governance artifact.** `PLATFORM_CHEATSHEET.md` rule 19 specifies Backend Proposal → Re-freeze Review → Re-freeze Report as three documents. APP 011's entire backend surface is **one line of SQL**, so those three steps are merged here with the architect's approval (2026-09-18). Everything rule 19 requires is present: the delta, the review of it, and the decision record.

**Predecessor:** `APP_011_FREEZE_INDEX.md` (approved 2026-09-18, with G-1 = yes, G-2 = wave 2).

---

## 1. The entire backend delta

```sql
alter publication supabase_realtime add table public.notifications;
```

That is all. No table, column, index, constraint, policy, trigger, function, RPC, capability, event, or grant.

**Wave:** 1B. Deliberately sequenced *after* wave 1A (frontend against the existing 8-table publication) so the transport is proven before the database is touched at all.

---

## 2. Review of the delta

| Question | Finding |
|---|---|
| Does it widen read access? | **No.** Publication membership controls what Realtime *streams*, not what a client may *read*. Realtime v2 re-runs the SELECT policy per subscriber per WAL record. |
| Is `notifications` SELECT already correctly scoped? | **Yes.** Policy `notifications_select` gates on `recipient_profile_id = auth.uid()` plus the `notification.view` capability plus the project-participant helper. A subscriber can only ever receive their own rows. |
| Can a client write via this channel? | **No.** `notifications_insert` is deny; `notifications_update` requires the RPC-only-write GUC; `notifications_delete` is deny. Realtime is read-only transport regardless. |
| Does it affect the router? | **No.** The `activity_events` AFTER INSERT bridge is untouched. Publication membership is orthogonal to trigger execution. |
| Replica identity? | `default` (primary key), consistent with the other 8. Irrelevant here: APP 011 subscribes to INSERT/UPDATE only (Freeze Index F-4), and `notifications` has no DELETE policy either. |
| Volume risk? | Bounded. Each subscriber receives only rows where they are the recipient. The router already dedups via the I-7 partial unique index, so re-fires produce no extra rows. |
| Does it reopen an APP 010 freeze? | **Yes, narrowly.** APP 010 §25.2 states adding `notifications` to the publication is a REALTIME re-freeze event and names APP 011 as the authority. This document is that re-freeze. APP 010's schema, RLS, RPCs and router are byte-unchanged. |

**Verdict: approved.** No new issue class. The migration is additive, reversible (`alter publication ... drop table`), and touches no frozen object.

---

## 3. Migration discipline

Per `supabase/migrations/RECONCILIATION.md`, this must be applied **from a file**, never by pasting into `execute_sql`:

1. Write `supabase/migrations/<ts>_realtime_003_notifications_publication.sql`.
2. Apply that file's exact contents.
3. Re-run `ops/verify_migrations.sh` — expect 68/68 byte-identical.
4. Re-run `ops/audit_schema_provenance.py` and `ops/replay_check.sh`.
5. Append a re-freeze note to `docs/freeze/APP_010_FINAL_CERTIFICATION.md`.

---

## 4. Frontend implementation contract (wave 1A)

Frozen here so implementation has no latitude to invent surface.

### 4.1 Module

```
src/features/realtime/
  channels.ts           channel-name constants (also absorbs APP 010 §25.3 — see §5)
  RealtimeProvider.tsx  mounts beside SessionProvider; owns the channel lifecycle
  useRealtimeConnection.ts   { status: 'connecting'|'live'|'offline' }
  handlers.ts           the 8 table → invalidation mappings
  coalesce.ts           250 ms trailing, keyed
```

### 4.2 Invariants

- **Zero new `qk` keys.** Every handler calls an existing helper from `features/shared/invalidate.ts`.
- **Never** call `supabase.realtime.setAuth()` — the client does it (Freeze Index F-5).
- Subscribe to **INSERT and UPDATE only** (F-4).
- Channel torn down **before** `queryClient.clear()` on `SIGNED_OUT`.
- On every `SUBSCRIBED` **after the first**, run a full invalidation sweep (F-7: no replay).
- Socket failure is silent; the app behaves exactly as today (poll floor is never removed).

### 4.3 `comments` dispatch

All eight `target_*` columns are nullable because exactly one is set (`comments_target_xor_check`, verified 8-way). The handler switches on whichever is non-null:

| Non-null column | Invalidates |
|---|---|
| `target_version_id` | `invalidateCommentsForVersion(v)` |
| `target_annotation_id` | `qk.commentsForAnnotation(a)` |
| `target_review_id` | `qk.review(r)` |
| `target_approval_request_id` | `qk.approvalRequest(a)` |
| `target_requirement_id` | `qk.requirementDiscussions(r)` |
| `target_design_asset_id` | `qk.asset(a)` |
| `target_change_id` / `target_decision_id` | no live surface in v1 — no-op |

`root_review_id` and `root_approval_request_id` are nullable; when absent the chain key is skipped, not guessed.

---

## 5. APP 010 amendments required

Two, both approved with the Freeze Index (G-5):

1. **Channel constants move.** APP 010 §25.3 places them in `src/features/notifications/realtime.ts`, a file that was never created. All channel naming now lives in `src/features/realtime/channels.ts`. APP 010 §25.3 gets a pointer; the old path is not resurrected.
2. **The `routing.ts` mirror requirement is withdrawn.** APP 010 §8.2 and certification observation T-5 call for a TypeScript mirror of the SQL router's routing table, kept in sync by a future linter. That file was never created, and building it now would create a second source of truth — precisely the drift T-5 warned about. The SQL router is authoritative; the frontend renders `notification_type` and needs no routing rules. **T-5 is closed as "will not fix, requirement withdrawn."**

---

## 6. Non-goals (restated, permanent)

Collaborative editing, CRDTs, operational transforms, cursor sharing, live locks, offline queues, subscribing to `activity_events`, and any realtime-triggered mutation.
