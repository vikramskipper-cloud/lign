# APP 011 — Implementation Report

**Date:** 2026-09-18
**Scope:** waves 1A (live invalidation), 1B (notifications publication), 2 (presence).
**Superseded by:** `docs/freeze/APP_011_FINAL_CERTIFICATION.md`, which covers all three waves. This report remains the detailed record of wave 1A and of the grants finding in §3.
**Predecessors:** `APP_011_FREEZE_INDEX.md`, `APP_011_BACKEND_DELTA.md`.

---

## 1. What shipped

```
src/features/realtime/
  channels.ts            channel names (absorbs APP 010 §25.3 reservations)
  coalesce.ts            keyed 250 ms trailing coalescer
  handlers.ts            8 table -> invalidation mappings
  RealtimeProvider.tsx   channel lifecycle + connection state
  RealtimeIndicator.tsx  advisory status; renders nothing when healthy
```

Wired additively: `RealtimeProvider` in `RootLayout`, `RealtimeIndicator` in `TopBar`.

**Deviation from Freeze Index §5.2** (corrected in that document): the provider mounts in `RootLayout`, not beside `SessionProvider`. `ws_id` comes from `useParams`, which only resolves inside the router, and `SessionProvider` is a sibling of `RouterProvider` rather than an ancestor of any route. `RootLayout` wraps every authenticated route, so the lifetime is equivalent — it is the same mechanism `NotificationBell` already depends on.

Build: typecheck PASS, build PASS. Bundle 1,005.04 → 1,010.14 kB (**+5.10 kB raw, +1.57 kB gzip, +0.51%**).

---

## 2. Verification

### 2.1 Mapping logic — 27 tests, mutation-proven

`vitest` was added (no test runner existed in this project before today). Tests assert the **effect**, not the call: each seeds real entries into a real `QueryClient`, feeds a synthetic payload through the handler, then asserts which cache entries actually became invalidated. Spying on `invalidateQueries` would only prove a function was called.

Coverage includes all 8 XOR comment arms, every per-table mapping, the null-`root_*` skip, the §6.1 no-fan-out rule, and specificity (an unrelated cache entry is never touched).

**Passing tests prove nothing unless they fail on broken code**, so the suite was mutation-tested. Four deliberate defects, each caught by exactly one test, green again after each revert:

| Mutation | Result |
|---|---|
| comments review-arm points at the wrong key | 1 failed |
| reviews invalidates the chain when `root_review_id` is null | 1 failed |
| `approval_responses` fans out to release readiness (§6.1 violation) | 1 failed |
| coalescing bypassed | 1 failed |

### 2.2 Live transport — G-6 closed

Freeze Index §6.2 required confirming against a **live payload**, not schema nullability, because Realtime delivers rows RLS-filtered per subscriber. `tests/realtime/payload_shape_probe.mjs` signs in as a real user, subscribes to the published tables under a `workspace_id` filter, writes rows through PostgREST, and inspects what arrives.

Run against the **local replay stack**, never production:

```
comments      INSERT: 17 cols, all required present
annotations   INSERT: 13 cols, all required present
design_assets INSERT: 14 cols, all required present
RESULT: PASS
```

**G-6 is closed.** Every column `handlers.ts` reads is present in a live payload.

---

## 3. Finding: the migration set does not carry table privileges

The probe initially failed — not on payload shape, but with HTTP 403 / SQLSTATE `42501` on every write. Investigation produced a finding well outside APP 011's scope.

| Role | Production | Pristine 67-migration replay |
|---|---|---|
| `anon` | DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE | REFERENCES, TRIGGER, TRUNCATE |
| `authenticated` | (same full set) | REFERENCES, TRIGGER, TRUNCATE |
| `service_role` | (same full set) | REFERENCES, TRIGGER, TRUNCATE |

Measured on a clean `supabase db reset`: **96 grant pairs (32 tables × 3 roles), zero holding SELECT.** Production holds SELECT/INSERT/UPDATE/DELETE on all 96.

Those GRANTs are Supabase **platform state applied at project creation**, not emitted by any migration.

### 3.1 Why it matters

A database rebuilt from `supabase/migrations/` alone — disaster recovery, staging, a new environment, onboarding a second developer — would reject **every** application request with `42501` *before RLS is ever consulted*. The app would be entirely non-functional, and nothing in the existing verification would have caught it.

### 3.2 It qualifies an earlier claim

`RECONCILIATION.md` and `MIGRATION_ARTIFACT_AMENDMENT.md` stated that replay reproduces production "exactly", on the strength of 590/590 objects matching. That comparison covered tables, policies, triggers, functions and indexes. **It did not compare privileges, and privileges differ.** Both documents have been corrected; the 590/590 result stands for what it measured.

### 3.3 Tooling fixed

`ops/schema_inventory.sql` now emits `GRANT` rows, and `ops/compare_inventories.py` reports them, so any future replay check surfaces this class of drift instead of silently passing.

### 3.4 Open decision for the architect

Add a grants migration so the set is self-contained, or document platform grants as out-of-band. **Recommendation: add the migration.** It is idempotent against production (those grants already exist, so applying it changes nothing) and it is the difference between a migration set that can and cannot rebuild the system. It must grant exactly what production has and no more.

Not done here: it is a privilege change to production and belongs to the migration/re-freeze process, not to an APP 011 frontend wave.

### 3.5 Security observation

Production grants full DML to `anon` on all 32 tables. This is standard Supabase posture — RLS is the authorization boundary and every table has RLS enabled with policies — but it means **RLS is entirely load-bearing, with no defense-in-depth at the grant layer**. Freeze Index F-4 ("no DELETE policy, so clients cannot delete") remains correct, but RLS alone enforces it.

---

## 4. Not verified

- **End-to-end in a browser.** No test asserts that a change by user A visibly refreshes user B's screen. The mapping and the transport are each verified; their composition in a live React tree is not.
- **Reconnect sweep under real network loss.** §7.2's behaviour is implemented and reviewed but not exercised against an actual dropped socket.
- **`reviews`, `review_participants`, `approval_requests`, `approval_responses` payload shapes.** The probe covered `comments`, `annotations` and `design_assets`; the other four were not written to, because doing so requires driving their RPC workflows to produce valid rows. Their required columns are all `NOT NULL` in schema, so the risk is low, but it is inference rather than observation.

---

## 5. Housekeeping

`npm audit` reports one high-severity advisory: `nanoid < 3.3.18`, reached via `vite → postcss`. **Pre-existing** — it was in the committed lockfile before `vitest` was added, and it is a dev-time dependency. Not addressed here; flagged rather than silently folded into this change.
