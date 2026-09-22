# APP 011 Final Certification

**Permanent governance record for APP 011 — Realtime.**

- **Certification date:** 2026-09-18 (amended same day — §7, §8)
- **Implementation status:** Complete — waves 1A, 1B and 2 all shipped.
- **Freeze status:** **Frozen, with behavioural sign-off explicitly deferred** (see §7).

Authoritative sources: `docs/APP_011_FREEZE_INDEX.md`, `docs/APP_011_BACKEND_DELTA.md`, `docs/APP_011_IMPLEMENTATION_REPORT.md`.

---

## 1. Scope delivered

| Wave | Content | Migration |
|---|---|---|
| **1A** | Live cache invalidation for the 8 REALTIME 002 tables | none |
| **1B** | `notifications` added to the publication; bell updates live | **one** |
| **2** | Version presence — "who else is viewing this version" | none |

```
src/features/realtime/
  channels.ts            channel names + published-table scope
  coalesce.ts            keyed 250 ms trailing coalescer
  handlers.ts            9 table -> invalidation mappings
  RealtimeProvider.tsx   channel lifecycle + connection state
  RealtimeIndicator.tsx  advisory status (renders nothing when healthy)
  usePresence.ts         ephemeral version presence
  PresenceStack.tsx      stacked avatars
  __tests__/             30 tests
```

Additive wiring only: `RealtimeProvider` → `RootLayout`, `RealtimeIndicator` → `TopBar`, `PresenceStack` → `VersionBar`.

## 2. Backend contract

One migration, `realtime_003_notifications_publication`:

```sql
alter publication supabase_realtime add table public.notifications;
```

- Publication now carries **9** tables.
- Local file **byte-identical** to the applied statement (`md5 8ebf2746…`).
- `ops/verify_migrations.sh`: **68/68 PASS**, 0 drifted, 0 missing, 0 unapplied.
- No table, column, index, constraint, policy, trigger, function, RPC, capability, event or grant was added.
- Reversible: `alter publication supabase_realtime drop table public.notifications;`

**Authorization unchanged.** Publication membership controls what Realtime *streams*, not what a client may *read*; RLS re-runs per subscriber per WAL record. `notifications_select` was already scoped to `recipient_profile_id = auth.uid()`.

## 3. Architectural invariants held

- **Zero new query keys.** Every handler calls a helper that pre-dated APP 011.
- **No payload is ever written into the cache** — only read for the identifiers needed to invalidate (Freeze Index §2).
- `realtime.setAuth()` is never called by app code; `supabase-js` 2.109.0 does it (F-5, verified in `dist/`).
- **INSERT/UPDATE only.** No DELETE policy exists on any published table, and all have `replica identity = default` (F-3, F-4).
- No mutation, no event emission, no capability, no workflow logic anywhere in the module.
- Socket failure is silent; the polling floor is never removed (§7.4).
- Presence is ephemeral — never touches Postgres, never a source of truth.

## 4. Verification evidence

| Check | Result |
|---|---|
| Unit tests | **30 passed** |
| Mutation testing | **6 deliberate defects, all caught**, green after each revert |
| Live payload probe (G-6) | PASS — comments 17 cols, annotations 13, design_assets 14; every column `handlers.ts` reads present |
| Migration byte-identity | 68/68 |
| Typecheck / build | PASS / PASS |
| Bundle delta | 1,005.04 → 1,012.18 kB (**+7.14 kB raw, +2.19 kB gzip, +0.71%**) |
| Security advisors | 0 ERROR; 2 WARN classes, **byte-identical to the pre-APP-011 baseline** — no new issue class |

Mutations caught: wrong dispatch key; chain invalidated when `root_review_id` is null; `approval_responses` fanning out to release readiness (§6.1 violation); coalescing bypassed; notifications handler removed; notifications not coalesced.

## 5. APP 001–010 preservation

Every prior slice's contract is intact. Only three files outside `features/realtime/` changed, all additively: `RootLayout.tsx`, `TopBar.tsx`, `VersionBar.tsx`. No frozen migration was modified (`verify_migrations.sh` proves it). No RPC signature, policy, capability or query key was altered.

Two approved APP 010 amendments are recorded in `APP_011_BACKEND_DELTA.md` §5: channel constants live in the realtime module, and the `routing.ts` mirror requirement is **withdrawn** (building it would create the second source of truth observation T-5 warned about). **T-5 closed as will-not-fix.**

## 6. Deviations from the Freeze Index

All three recorded in the source documents:

1. **§5.2 mount point.** `RealtimeProvider` mounts in `RootLayout`, not beside `SessionProvider` — `ws_id` comes from `useParams`, which only resolves inside the router. Freeze Index corrected.
2. **Reconnect scope.** Detection is scoped to the channel instance, so a workspace switch does not trigger the §7.2 sweep.
3. **§8 presence payload.** Carries `email`, not `display_name`/`avatar_url`. Nothing in the shell fetches `profiles` today (`UserMenu` derives initials from email); adding a query for cosmetics was out of proportion. Name/avatar resolution belongs to the UI/UX pass.

## 7. What is NOT certified

This certification covers **construction and unit-level behaviour**. It does **not** assert that the feature works end to end in a browser. Deferred by plan to the UI/UX polish + testing phase that follows APP 012:

- **Browser end-to-end.** Nothing confirms that user A's change visibly refreshes user B's screen, or that two users see each other in the presence stack.
- **Payload shape for 3 of 9 tables.** `asset_versions`, `approval_requests` and `approval_responses` were not written to. Their required columns are `NOT NULL` in schema, so this is inference, not observation.

**Closed since first issue (2026-09-18):**
- ~~Reconnect sweep under real network loss.~~ **Verified.** Killing the realtime container mid-subscription produced `SUBSCRIBED → CHANNEL_ERROR → SUBSCRIBED`, so the §7.2 sweep does fire (`tests/realtime/reconnect_probe.mjs`).
- ~~Payload shape for 5 of 9 tables.~~ Now **6 of 9 observed**: `comments`, `annotations`, `design_assets`, `reviews` (INSERT+UPDATE), `review_participants`, `notifications`. The notification observation proves wave 1B end to end at the transport layer — review created → `activity_events` → router → notification row → delivered under the recipient filter.

**Any future claim that APP 011 "works" must cite a browser test, not this document.**

## 8. Adjacent item — closed

APP 011 testing exposed that the migration set carried no table privileges: a pristine replay granted `anon`/`authenticated`/`service_role` no SELECT/INSERT/UPDATE/DELETE on any of the 32 tables, so a rebuilt database would reject every request with `42501` before RLS ran.

**Closed** by migration `platform_001_role_grants` (2026-09-18). No production privilege changed — the function-ACL fingerprint is identical before and after, and all 27 deliberately-withheld EXECUTE grants remain withheld. A pristine replay now holds all 96 grant pairs and matches production's effective function privileges function by function. Detail in `APP_011_IMPLEMENTATION_REPORT.md` §3.4.

**A hazard remains open:** two `create_review` overloads make 9-arg PostgREST calls fail with `PGRST203`. Not a live bug (the app passes all 15 args), but the trap APP 009 removed for itself under F-2 and APP 006 did not. See report §5.

## 9. Permanent non-goals

Collaborative editing, CRDTs, operational transforms, cursor sharing, typing indicators, live locks, offline queues, subscribing to `activity_events`, and any realtime-triggered mutation.

## 10. Verdict

**APP 011 is frozen.** Waves 1A, 1B and 2 are complete and unit-verified. Behavioural sign-off is deferred to the UI/UX testing phase per §7. Future changes require an amendment and re-freeze.

---

## Amendment — 2026-09-22 — APP 005 embed-hint defect

Unrelated to APP 011, but found while verifying APP 013 and recorded here
because `features/participants/queries.ts` is consumed by the comment and
mention surfaces this slice invalidates.

`useProjectParticipants` embedded `workspace_members` and `stakeholders` using
the hints `project_participants_workspace_member_id_fkey` and
`project_participants_stakeholder_id_fkey`. **Neither constraint exists** — the
real names are `project_participants_workspace_member_fk` and
`project_participants_stakeholder_fk`. PostgREST rejected the entire select
with `PGRST200`, so the hook returned an error on every call and @-mentions
never populated.

It typechecked and built cleanly for the whole of APP 005–011, which is why
every certification passed over it: no static check can see a string that only
PostgREST resolves.

Fixed 2026-09-22. All nine FK hints in the frontend were then audited against
`pg_constraint`; the other seven were correct.
