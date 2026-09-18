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

### 3.4 Resolved — migration `platform_001_role_grants` (2026-09-18)

A grants migration was written, applied and verified.

- **Production impact: none.** Every privilege it grants already existed there. A function-ACL fingerprint taken before and after is **identical** (`4a9fe30d…`), and all 27 functions that withhold EXECUTE from `authenticated` still do.
- **Replay impact: decisive.** A pristine 69-migration replay now yields all 96 grant pairs holding SELECT (was 0), and effective function privileges match production **function by function** — `has_function_privilege` fingerprint `14f56a35…` identical on both, 133 executable / 27 not / 160 total.
- **Proof it produces a working system:** the payload probe now runs against a pristine replay with *only* an auth fixture applied — no harness grants — and passes.

**The migration deliberately does not grant EXECUTE on functions.** 27 of 160 withhold it on purpose (`enforce_requirement_hierarchy`, `resolve_notification_router_targets`, `handle_new_auth_user`, `list_purgeable_files`, …), each hardened by an explicit REVOKE. A blanket `grant execute on all functions … to authenticated` would have re-granted all 27 and silently undone hardening across AUTH, STORAGE, REQUIREMENTS and APP 006–010. `ALTER DEFAULT PRIVILEGES` is included and is safe precisely because it applies only to objects created after it runs, so it cannot affect an existing REVOKE.

### 3.5 Security observation

Production grants full DML to `anon` on all 32 tables. This is standard Supabase posture — RLS is the authorization boundary and every table has RLS enabled with policies — but it means **RLS is entirely load-bearing, with no defense-in-depth at the grant layer**. Freeze Index F-4 ("no DELETE policy, so clients cannot delete") remains correct, but RLS alone enforces it.

---

## 4. Verification, updated 2026-09-18

Live payloads now observed for **6 of 9** published tables, up from 3:

| Table | Observed |
|---|---|
| `comments` | INSERT, 17 cols |
| `annotations` | INSERT, 13 cols |
| `design_assets` | INSERT, 14 cols |
| `reviews` | INSERT + UPDATE, 22 cols |
| `review_participants` | INSERT, 14 cols |
| `notifications` | INSERT, 21 cols |

The notification observation is wave 1B proven end to end at the transport
layer: p_lead creates a review → `activity_events` INSERT → router trigger →
notification row for p_reviewer → Realtime delivers it under the recipient
filter. It required a second identity, because the router correctly excludes the
actor.

**Reconnect assumption verified** (`tests/realtime/reconnect_probe.mjs`). The
§7.2 sweep depends on supabase-js re-firing `SUBSCRIBED` after a drop; if it did
not, the sweep would never run and realtime would be permanently staler than the
polling it replaced. Killing the realtime container mid-subscription produced
`SUBSCRIBED → CHANNEL_ERROR → SUBSCRIBED`. **The sweep will fire.**

### 4.1 Still not verified

- **End-to-end in a browser.** No test asserts that a change by user A visibly refreshes user B's screen. The mapping and the transport are each verified; their composition in a live React tree is not.
- **Reconnect sweep under real network loss.** §7.2's behaviour is implemented and reviewed but not exercised against an actual dropped socket.
- **`asset_versions`, `approval_requests`, `approval_responses` payload shapes.** Driving their RPC workflows to produce valid rows was out of scope. Their required columns are all `NOT NULL` in schema, so the risk is low, but it is inference rather than observation.

---

## 5. Observation: `create_review` overload hazard

The probe's first RPC call failed with `PGRST203` — PostgREST cannot resolve
between the 9-arg and 15-arg `create_review` overloads. **This is not a live
bug:** `features/reviews/mutations.ts` passes all 15 arguments and resolves
correctly. But it is a latent trap for any future 9-arg caller, and it is
exactly the hazard APP 009 eliminated for itself under F-2 by dropping its
frozen overload. APP 006 did not. Dropping it is a re-freeze decision, not
recorded as a defect here — recorded as a hazard.

## 6. Housekeeping

`npm audit` reports one high-severity advisory: `nanoid < 3.3.18`, reached via `vite → postcss`. **Pre-existing** — it was in the committed lockfile before `vitest` was added, and it is a dev-time dependency. Not addressed here; flagged rather than silently folded into this change.
