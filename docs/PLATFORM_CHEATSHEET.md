# LIGN Platform Cheatsheet

One-page engineering reference. Distills [PLATFORM_BASELINE.md](PLATFORM_BASELINE.md). For daily use.

---

## Architecture

```
                        LIGN Platform (Supabase project: hsfporioghapwghrvvzd)

  ┌─────────────────────────────────────────────────────────────────────────┐
  │  Governance pipeline (write direction)                                  │
  │                                                                         │
  │   Requirements  ─►  Reviews  ─►  Approvals  ─►  Releases                │
  │      (APP 008)      (APP 006)    (APP 007)     (APP 009)                │
  │                                                                         │
  │  Each stage OWNS its state; each stage CONSUMES upstream evidence       │
  │  read-only via SECURITY DEFINER RPCs. No slice mutates another.         │
  └─────────────────────────────────────────────────────────────────────────┘

  Foundations: AUTH 001–009 · STORAGE 001–004 · REQUIREMENTS 001–005 (frozen backend)
  Shell:       APP 002 (routes, qk, nav, capabilities, deep links)
  Domain:      APP 001 (industry-neutral model)
```

## Dependency graph

`APP 001 → APP 002 → APP 003 → APP 004 → APP 005 → APP 006 → APP 007 → APP 008 → APP 009 → (APP 010 · APP 011 reserved)`

Dependencies flow one way only. Later slices never modify earlier slices.

## Module ownership

| Slice | Owns | Doesn't own |
|---|---|---|
| APP 001 | Domain model (industry-neutral), `activity_events` audit spine | Any UI, any RPC |
| APP 002 | App shell, router, `qk` registry, `CAPABILITY_KEYS`, `DeepLinkResolver`, `NavRail` | Feature UI |
| APP 003 | Projects, disciplines, Design Workspace, RightPanel | Feature domains |
| APP 004 | Files, viewer, version pipeline, storage integration | Discussion, review |
| APP 005 | Comments (8-way XOR; 7 arms from APP 005 + `target_requirement_id` from APP 008), annotations | Persistence of upstream discussion |
| APP 006 | Reviews (7-state, rounds, roster, dashboards) | Approvals, requirements |
| APP 007 | Approvals (8-state, chain, roster, veto, supersede) | Reviews, requirements |
| APP 008 | Requirements (draft/active/superseded/archived, assessments) | Approvals, releases |
| APP 009 | Releases (draft/released/withdrawn, evidence snapshot) | Discussion, votes, assessments |

## Capability naming

- Format: **`<module>.<verb>`** — always lowercase, always past-form for state or bare verb for action.
- Frozen prefixes: `project.*`, `workspace.*`, `review.*`, `approval.*`, `requirement.*`, `release.*`, `comment.*`, `annotation.*`, `version.*`, `discipline.*`.
- Enforcement: `lign_has_capability(p_project_id, p_capability_key)` — inline re-check in every write RPC even when RLS gates the read.
- Reserved keys have **zero role grants** and must not be wired.

## Event naming

- Format: **`<module>.<past-verb>`** — e.g. `review.completed`, `approval.superseded`, `release.finalized`.
- Emitted via `activity_events` insert in the same transaction as the mutation. `activity_events` is append-only (UPDATE + DELETE blocked at DB boundary).
- `subject_kind` matches the affected entity (`release`, `release_item`, `requirement`, `version_requirement_assessment`, etc.).
- Reserved event names must never be emitted; register in `EVENT_MODEL.md` when reserved (APP 009 F-5).

## RPC conventions

- Every write RPC: `SECURITY DEFINER`, `SET search_path = ''`, `REVOKE ALL FROM public, anon, authenticated`, `GRANT EXECUTE TO authenticated, service_role`.
- Read RPCs same discipline; return typed rows or `jsonb`.
- Frozen RPC extensions: single-function `CREATE OR REPLACE` + default-tail params. Drop the frozen overload if named-argument dispatch would become ambiguous.
- Every write RPC emits exactly one canonical past-tense event.
- Every RPC re-checks capability inline (defense in depth over RLS).
- Cursor pagination: server-opaque `(sort_col, id)` tuple. Clients never construct cursors.

## Migration rules

- Two-migration split per slice: `<slice>_schema` then `<slice>_authz_and_rpcs`.
- Additive-only. No frozen column renamed, dropped, or narrowed. No frozen RLS policy weakened.
- Every new FK gets a covering index **in the same migration**.
- NULL-permissive CHECKs on new enum-like columns: `col IS NULL OR col IN (...)`.
- Composite tenancy on cross-tenant FKs: `(child_col, workspace_id) → parent(id, workspace_id)`; include `project_id` where available.
- Frozen migration files are SHA-verified byte-identical after freeze.
- Never target project `vzgoobyltkgfrtycvtiz` (nuesync). LIGN = `hsfporioghapwghrvvzd`.

## Trigger rules

- **Row-local** triggers (inspect only OLD/NEW of the row): **NOT** `SECURITY DEFINER`. Keep `SET search_path=''` + REVOKE from public/anon/authenticated + no GRANT. (APP 009 F-6.)
- **Cross-table** triggers that need to bypass caller RLS: `SECURITY DEFINER` + `SET search_path=''` + same REVOKE.
- Chain-immutability triggers enforce APP 006 T-CRIT-1 discipline: reject any post-INSERT UPDATE of chain columns.
- Asymmetric chain columns: `root_*` fully immutable; `supersedes_*` permits `NULL → uuid` exactly once (APP 009 F-1).
- Frozen triggers remain `tgenabled='O'` after any migration.

## Route ownership

| Path prefix | Owner |
|---|---|
| `/workspace/:ws_id/…` | APP 002 shell + owning module |
| `/workspace/:ws_id/project/:proj_id/…` | APP 003 project shell + owning module |
| `/workspace/:ws_id/project/:proj_id/review/:review_id` | APP 006 |
| `/workspace/:ws_id/project/:proj_id/approval/:approval_id` | APP 007 |
| `/workspace/:ws_id/project/:proj_id/requirement/:requirement_id` | APP 008 |
| `/workspace/:ws_id/project/:proj_id/release/:release_id` | APP 009 |
| `/deep/<kind>/:id` | Owning module via `DeepLinkResolver kind="<kind>"` |

Deep-link kinds currently registered: `review`, `reviewer`, `approval`, `approver`, `comment`, `annotation`, `requirement`, `release`.

## Query-key ownership

| Namespace | Owner |
|---|---|
| `qk.review*` | APP 006 |
| `qk.approval*` | APP 007 |
| `qk.requirement*` | APP 008 |
| `qk.release*` | APP 009 |
| `qk.comment*` / `qk.annotation*` | APP 005 |
| `qk.bookmarks(wsId, entity_kind)` / `qk.savedViews(wsId, scope)` | APP 006 (reused) |

Every mutation calls the invalidator helper (`invalidate<Module>Lists`, `invalidate<Module>`, `invalidate<Module>Inbox`) — no ad-hoc `queryClient.invalidateQueries` on module-owned keys.

## URL parameter ownership

| Param | Owner |
|---|---|
| `?discipline` | APP 003 |
| `?comment`, `?annotation`, `?comments` | APP 005 |
| `?review`, `?participant` | APP 006 |
| `?approval`, `?participant` | APP 007 |
| `?priority`, `?source`, `?category`, `?scope`, `?code`, `?compose` | APP 008 |
| `?view`, `?status`, `?type`, `?tab`, `?q`, `?compose` | APP 009 (dashboards) |
| `?tab` on any detail route | Owning module |

New slices choose params that do not collide with the above.

## Chain-init checklist

When an RPC creates a new row with `root_*` or `supersedes_*` chain columns:

- [ ] Pre-compute the new row id: `v_id := gen_random_uuid();`
- [ ] INSERT with chain columns set inline in one statement (`root_<x>_id = v_id` for root; `supersedes_<x>_id = <parent_id>` for supersession child).
- [ ] Never issue a post-INSERT `UPDATE ... SET root_*` or supersedes columns — the chain-immutability trigger will reject.
- [ ] For supersede RPCs: `SELECT ... FOR UPDATE` on the prior row before transitioning it (APP 009 F-3).
- [ ] Transition the prior row to its superseded/terminal state **before** inserting the new row where a partial-unique index could conflict (APP 007 F-1.1).

## Code review checklist

- [ ] All new writes go through `SECURITY DEFINER` RPCs with `search_path=''` and inline capability check.
- [ ] Frozen RPC signatures preserved; extensions use single-function `CREATE OR REPLACE` + default-tail.
- [ ] Every new FK has a covering index in the same migration.
- [ ] New CHECKs on additive columns are NULL-permissive.
- [ ] New tables (if any) have RLS enabled with SELECT gated by `lign_has_capability`; writes RPC-only.
- [ ] New triggers: row-local NOT `SECURITY DEFINER`; cross-table triggers `SECURITY DEFINER` with the standard REVOKE discipline.
- [ ] Chain-init discipline honored (§Chain-init checklist).
- [ ] Every mutation emits exactly one canonical past-tense event; no new event name that isn't reserved or already frozen.
- [ ] `qk.*` additions namespaced under the owning module; no collision with prior slices.
- [ ] URL params, routes, and deep-link kinds do not collide with prior slices.
- [ ] Frontend mutations call the correct invalidator (list-scope, detail, inbox, readiness).
- [ ] No modification to any file under a prior slice's freeze scope (frozen migrations SHA-identical).
- [ ] Reserved capability keys have zero role grants; reserved event names have no emitter.
- [ ] Realtime publication (`supabase_realtime`) unchanged unless a REALTIME re-freeze accompanies the change.
- [ ] Advisors: no new issue class beyond baseline (SECURITY DEFINER lints on new RPCs are expected).
- [ ] Typecheck + build pass; bundle delta reported.

## Top 20 architectural rules

1. **Additive-only evolution.** Never rename, drop, or narrow a frozen surface.
2. **RPC-first writes.** Every user mutation goes through a `SECURITY DEFINER` RPC.
3. **RLS protects reads.** Every user-facing table has SELECT policies gated by `lign_has_capability`.
4. **Capabilities authorize.** Every RPC re-checks capability inline even when RLS gates the read.
5. **Events describe history.** Every state-changing RPC emits one past-tense event into `activity_events`.
6. **`activity_events` is append-only.** UPDATE + DELETE blocked at DB boundary.
7. **Chain-init discipline.** Pre-compute UUID, INSERT chain columns inline, never post-INSERT UPDATE (APP 006 T-CRIT-1).
8. **Asymmetric chain immutability.** `root_*` fully immutable; `supersedes_*` permits `NULL → uuid` exactly once (APP 009 F-1).
9. **`CREATE OR REPLACE` + default-tail** for frozen RPC extensions; drop frozen overload if named-arg dispatch would become ambiguous (APP 009 F-2).
10. **Every FK gets a covering index** in the same migration.
11. **`SECURITY DEFINER` hardening**: `search_path=''`, REVOKE public/anon/authenticated, GRANT authenticated + service_role.
12. **Trigger discipline**: row-local NOT `SECURITY DEFINER`; cross-table needs bypass = `SECURITY DEFINER` with the standard REVOKE.
13. **Composite tenancy on FKs**: `(child, workspace_id) → parent(id, workspace_id)`; add `project_id` where available.
14. **RESERVED vocabulary is name-locked**: zero grants, no emitter, no wiring.
15. **Server-opaque cursors** for all dashboard pagination.
16. **Cross-slice consumption is read-only.** Consume RPCs and events. Never mutate another slice's tables.
17. **No hidden coupling.** Slices interact only via public RPCs and events.
18. **Industry-neutral core.** No `Architect`/`Client`/`Drawing` as core entities; roles are capability sets, not titles.
19. **Governance cycle is mandatory**: Freeze Index → Backend Proposal → Re-freeze Review → Re-freeze Report → Implementation → Implementation Report → Final Audit → Final Certification.
20. **Frozen migration files SHA-verified byte-identical** after freeze; project `hsfporioghapwghrvvzd` only; never touch `vzgoobyltkgfrtycvtiz`.
