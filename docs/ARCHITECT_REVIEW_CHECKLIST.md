# LIGN Architect Review Checklist

**Independent architectural review checklist. Every future APP slice must pass every item before permanent freeze.**

Read [PLATFORM_BASELINE.md](PLATFORM_BASELINE.md) first for context. Every check below is traceable to a specific lesson learned during APP 006–APP 009 certifications.

**How to use.** Each item is `[ ]` by default. A reviewer marks `[✓]` only when the pass criteria are empirically verified against the deployed system (not the proposal or the implementation report). Any `[✗]` blocks freeze until resolved. Cite the finding origin (e.g., "APP 007 F-1.1") in the review report when a check fails.

**Non-negotiable.** This checklist is mandatory. It replaces no other review — it is the minimum bar.

---

## 1. Architecture

### A-1. Slice boundary honored
- **Why.** APP 001–009 established one-way dependency flow; later slices never modify earlier slices.
- **Pass.** Zero modifications to any file under a prior slice's freeze scope. Frozen migration SHA hashes match pre-slice values. Frozen RPC signatures, capability role maps, RLS policies, event names, routes, `qk` keys, and component APIs byte-identical.
- **Fail.** Any prior-slice file modified, or any frozen surface renamed/dropped/narrowed.

### A-2. Governance pipeline respected
- **Why.** `Requirements → Reviews → Approvals → Releases` is the platform's canonical flow (PLATFORM_BASELINE §3).
- **Pass.** New slice consumes upstream via read-only RPCs; exposes downstream via read-only RPCs; never mutates upstream tables.
- **Fail.** Direct table write across slice boundary, or upstream RPC called via `SECURITY INVOKER` bypass.

### A-3. Industry-neutral core preserved
- **Why.** No profession-specific vocabulary in core domain (memory `project_lign_overview.md`).
- **Pass.** No new table, column, capability, event, or RPC name references `Architect`, `Client`, `Vendor`, `Drawing`, `FloorPlan`, or any profession-specific term. Such terms appear only as UI labels or tag metadata.
- **Fail.** Any profession-specific term hard-coded in schema/RPC/event/capability.

### A-4. Additive-only evolution
- **Why.** Established across APP 006–009 as the foundational rule.
- **Pass.** Every new column is nullable with a default OR the migration includes a data backfill. Every enum widening preserves legacy values. Every RPC extension uses Option A additive-tail or single-function `CREATE OR REPLACE` with default-tail.
- **Fail.** Any frozen column renamed, dropped, or narrowed. Any frozen CHECK narrowed. Any frozen enum value removed.

### A-5. Reserved surfaces remain inert
- **Why.** Reserved names are name-locks for future waves; wiring them prematurely breaks the reservation contract (APP 006 `review.deadline_approached`, APP 007 `approval.deadline_approached`, APP 008 reserved capabilities, APP 009 6 reserved capabilities + 7 reserved events).
- **Pass.** Every reserved capability key has zero role grants; every reserved event name has no emitter in any RPC body; every reserved RPC name pattern is unimplemented.
- **Fail.** Any reserved capability appears in a role's grant array. Any reserved event is emitted. Any reserved RPC name is implemented.

---

## 2. Schema

### S-1. Every new FK covered by an index in the same migration
- **Why.** Uncovered FKs make DELETE and cascade operations O(N) on the child table (memory `project_lign_schema_v1_lock.md`; APP 006/007/008/009 all obey).
- **Pass.** `pg_indexes` shows a matching index for every new FK; the leading column of the index matches the FK's leading column. Partial indexes are acceptable when the FK is `ON DELETE RESTRICT/SET NULL` and the child column is nullable (Supabase advisor may not credit partial coverage — APP 009 F-B1).
- **Fail.** Any new FK without a covering index. Note: the Supabase `unindexed_foreign_keys` advisor is INFO-only when partial coverage is intentional and documented.

### S-2. Composite tenancy on cross-tenant FKs
- **Why.** Prevents cross-workspace or cross-project data mixing at the DB boundary (APP 007 §3, APP 008 §5, APP 009 §5).
- **Pass.** Every cross-tenant FK is composite `(child_col, workspace_id) → parent(id, workspace_id)`; include `project_id` where the parent has it (APP 009 chain FKs).
- **Fail.** Any cross-tenant FK on the id alone.

### S-3. Composite FK target column names verified against frozen schema
- **Why.** APP 008 F-3.1-H1 — proposal cited `workspace_members(profile_id, workspace_id)` but the frozen column is `user_id`; the composite unique key that satisfies the FK is `(workspace_id, user_id)`.
- **Pass.** Every composite FK target column exists in the frozen schema (verify via `information_schema.columns`); the composite unique key that satisfies the FK exists (verify via `pg_constraint`).
- **Fail.** Any FK target references a non-existent column, or the composite unique key is not present in the target table.

### S-4. NULL-permissive CHECKs on additive enum columns
- **Why.** Additive enum-like columns must not break inserts of pre-existing rows (APP 006/007/008/009 all obey).
- **Pass.** Every new CHECK on an additive column is of the form `col IS NULL OR col IN (...)`.
- **Fail.** `col IN (...)` alone (rejects NULLs on legacy rows).

### S-5. Enum widening preserves legacy values
- **Why.** APP 007 F-2.1 — widening `approval_responses.decision` to add `abstained` had to preserve `changes_requested` even though the frozen `respond_to_approval` treated it as a negative vote. Aliasing new semantics onto a legacy value silently flips behavior.
- **Pass.** Widened enum CHECK includes every legacy value verbatim. New values are semantically distinct — never an alias for a legacy value. RPC input validation may reject legacy values from new code paths, but the enum itself preserves them for read compatibility.
- **Fail.** Any legacy enum value removed. Any new value silently aliased to a legacy value in a display layer.

### S-6. Frozen partial-unique index compatibility with new workflows
- **Why.** APP 007 F-1.1 — the frozen `approval_requests_active_target_key` partial unique on `(design_asset_id, version_id) WHERE status IN ('pending','in_progress')` nearly blocked same-version supersession. Every new supersede/publish workflow must reason about interactions with frozen partial uniques.
- **Pass.** Every frozen partial unique on a modified table is enumerated in the proposal; the new workflow's INSERT/UPDATE ordering is documented to avoid conflict.
- **Fail.** New workflow silently violates a frozen partial unique at some point in its transaction ordering.

### S-7. Chain columns have correct ON DELETE semantics
- **Why.** APP 006/007/009 all use `ON DELETE RESTRICT` on chain columns (root/supersedes) to prevent broken chains.
- **Pass.** Chain columns are `ON DELETE RESTRICT`. Non-chain optional FKs (e.g., `related_review_id`) may be `ON DELETE SET NULL`.
- **Fail.** Chain column with `ON DELETE CASCADE` or `SET NULL`.

---

## 3. RPCs

### R-1. `SECURITY DEFINER` hardening on every write RPC
- **Why.** Uniform security posture across all slices.
- **Pass.** Every write RPC has `SECURITY DEFINER`, `SET search_path = ''`, `REVOKE ALL ON FUNCTION ... FROM public, anon, authenticated`, `GRANT EXECUTE ... TO authenticated, service_role`.
- **Fail.** Any missing attribute; any grant to `public` or `anon`; any RPC without `search_path=''`.

### R-2. Inline capability re-check
- **Why.** Defense in depth over RLS; matches the PLATFORM_BASELINE principle "capabilities authorize."
- **Pass.** Every write RPC calls `lign_has_capability(...)` inline before performing the mutation; every read RPC that returns capability-gated data re-checks before returning.
- **Fail.** RPC relies solely on RLS for authorization; any capability enforcement omission.

### R-3. Single canonical event per successful mutation
- **Why.** `activity_events` audit spine expects one event per state-changing action (PLATFORM_BASELINE §4).
- **Pass.** Every write RPC emits exactly one past-tense event on success. Failure paths emit no event.
- **Fail.** Multiple events per success; missing event; event emitted before the mutation transaction commits.

### R-4. Additive-tail extensions on frozen RPCs
- **Why.** APP 006/007/008/009 all use Option A additive-tail; APP 009 F-2 required single-function `CREATE OR REPLACE` when overload ambiguity would arise from named-argument dispatch.
- **Pass.** Frozen RPC extensions either (a) append parameters with `DEFAULT` to the frozen signature (Option A distinct-arity), or (b) use single-function `CREATE OR REPLACE` and drop any frozen overload that would cause named-argument ambiguity.
- **Fail.** Frozen RPC signature changed positionally; multiple overloads coexist where named-argument dispatch matches more than one.

### R-5. Named-argument dispatch unambiguous
- **Why.** APP 009 F-2 — dual overloads of `finalize_release` and `withdraw_release` caused `function is not unique` on any PostgREST named-arg call.
- **Pass.** For every RPC name, `SELECT count(*) FROM pg_proc WHERE proname='<name>' AND pronamespace='public'::regnamespace` = 1, OR the multiple overloads have strictly distinct arities such that named-argument calls resolve uniquely.
- **Fail.** Any named-argument call to a frozen or extended RPC raises `function is not unique`.

### R-6. Positional compatibility preserved on frozen callers
- **Why.** APP 009 F-2 — dropping frozen overloads is safe only if extended single-function accepts the frozen argument count via default-tail.
- **Pass.** Every frozen positional call to the RPC (via all pre-slice callers) still binds correctly to the extended signature.
- **Fail.** Any frozen positional caller now raises "function does not exist" or binds to a different function.

### R-7. Return shapes precisely specified
- **Why.** APP 007 F-3.3 — `get_approval_readiness` return shape was described as `text` in the proposal but the frozen schema returned `jsonb`. APP 008 F-3.3-L1 — `assessment_coverage` shape was ambiguous between `numeric` and `{coverage_pct, applicable_count, satisfied_count}`.
- **Pass.** Every read RPC return shape is enumerated key-by-key with type; every consumer parses the specified keys.
- **Fail.** Return shape stated as `jsonb` without key enumeration; consumers assume additional keys not in the spec.

### R-8. Cross-slice RPC signatures verified against `pg_proc`
- **Why.** Documentation drifts; the deployed signature is ground truth.
- **Pass.** Before the proposal is written, the deployed shapes of every consumed cross-slice RPC are verified via `SELECT proname, pg_get_function_arguments(oid), pg_get_function_result(oid) FROM pg_proc WHERE proname IN (...)`. The proposal cites the verified signatures.
- **Fail.** Proposal invents or mis-states a cross-slice RPC signature.

### R-9. Inline parameter parsing avoided
- **Why.** APP 008 F-3.3-L2 — `?view=saved:<uuid>` inline-encoded in a text param created a parsing smell inside SQL.
- **Pass.** Distinct semantic inputs are separate parameters. `p_view text` + `p_saved_view_id uuid default null` is the pattern; not `p_view = 'saved:<uuid>'`.
- **Fail.** Text parameter carries composite semantic value (prefix + payload) that SQL must parse.

### R-10. Row-level lock on supersede/state-transition RPCs
- **Why.** APP 009 F-3 — supersede without `SELECT ... FOR UPDATE` on the prior row races opaquely under concurrency.
- **Pass.** Any RPC that transitions a prior-row state before inserting a successor uses `SELECT ... FOR UPDATE` on the prior row and validates state after acquiring the lock.
- **Fail.** Concurrent supersede/publish/finalize calls can produce opaque errors instead of clean "already superseded" messages.

---

## 4. Triggers

### T-1. Chain-init discipline (APP 006 T-CRIT-1)
- **Why.** APP 006's `create_review` originally INSERTed with `root_review_id = NULL` then UPDATEd to self; the chain-immutability trigger rejected the initialization UPDATE and required an emergency fix.
- **Pass.** Every RPC that creates a chain-rooted row pre-computes the id via `gen_random_uuid()` and INSERTs with `root_*` set inline in one statement. No post-INSERT UPDATE of chain columns anywhere in the codebase.
- **Fail.** Any RPC body contains `INSERT INTO <chain_table> (...)` followed by `UPDATE ... SET root_* = ...` on the just-inserted row.

### T-2. Asymmetric chain-immutability contract for supersedes columns
- **Why.** APP 009 F-1 — the initial chain-immutability trigger rejected `NULL → uuid` writes on `superseded_by_release_id`, which is the legitimate initial supersession write.
- **Pass.** Chain trigger permits `NULL → uuid` exactly once on supersedes columns; rejects `uuid → uuid` and `uuid → NULL`. Root columns remain fully immutable after INSERT.
- **Fail.** Trigger rejects the initial supersession write; or trigger permits mutation of a supersedes column after it has been set once; or trigger permits any change to root columns.

### T-3. Row-local triggers are NOT `SECURITY DEFINER`
- **Why.** APP 009 F-6 — row-local triggers that inspect only OLD/NEW columns do not need to bypass caller RLS; adding DEFINER widens attack surface without benefit. Matches frozen `enforce_release_status_via_rpc` non-DEFINER precedent.
- **Pass.** Row-local triggers are `LANGUAGE plpgsql` with `SET search_path = ''`, `REVOKE ALL FROM public, anon, authenticated`, no GRANT, and `prosecdef=false` in `pg_proc`.
- **Fail.** `prosecdef=true` on a row-local trigger function.

### T-4. Cross-table triggers use `SECURITY DEFINER` with the standard REVOKE
- **Why.** APP 007 `approval_responses_slot_coherence` reads `approval_request_approvers` — requires DEFINER to bypass caller RLS. APP 008 `requirements_default_owner_on_insert` reads `NEW.created_by_profile_id` only (row-local, not DEFINER).
- **Pass.** Cross-table trigger functions are `SECURITY DEFINER` + `SET search_path=''` + REVOKE from public/anon/authenticated + no GRANT.
- **Fail.** Cross-table trigger without DEFINER (silently fails under RLS); or DEFINER without `search_path=''` (search-path injection risk).

### T-5. Trigger firing order verified
- **Why.** APP 007 F-2.4 — no-self-approve smoke test tripped `slot_coherence` instead of the intended trigger because the fixture wasn't constructed to bind the slot to the requester's profile. Alphabetical trigger firing order means naming affects which trigger raises first.
- **Pass.** For every table with multiple triggers, the firing order (alphabetical) is documented in the review. Empirical smoke tests construct fixtures that specifically exercise each trigger's rejection path — not just the first-alphabetical one.
- **Fail.** A trigger claimed to enforce an invariant is never empirically fired because another alphabetically-earlier trigger always raises first.

### T-6. Frozen triggers preserved and enabled
- **Why.** Any migration that touches a frozen table risks accidentally disabling or replacing a frozen trigger.
- **Pass.** After every migration, `SELECT tgname, tgenabled FROM pg_trigger WHERE tgrelid='<table>'::regclass` shows every frozen trigger with `tgenabled='O'`. Frozen trigger function bodies unchanged.
- **Fail.** Any frozen trigger disabled, dropped, or its function replaced.

### T-7. Trigger dependencies on RPC-populated columns are documented
- **Why.** APP 008 F-3.7-L1 — `requirements_default_owner_on_insert` reads `NEW.created_by_profile_id`; this is populated by the frozen RPC at insert time but would silently no-op for a raw service-role INSERT bypassing the RPC.
- **Pass.** Every row-local trigger that reads a column populated by an RPC layer documents the dependency explicitly. Behavior when the RPC layer is bypassed is stated (fall-through, raise, no-op).
- **Fail.** Trigger behavior is undefined for service-role or migration-time INSERTs that bypass the RPC layer.

### T-8. Redundant triggers not created
- **Why.** APP 007 F-7.2 — proposal added a response-immutability trigger that duplicated the frozen `enforce_approval_response_immutable`. Redundancy is not benign; it doubles error paths and creates false-positive test-noise.
- **Pass.** Every proposed new trigger is checked against the frozen trigger set; if a frozen trigger already covers the invariant, no new trigger is added.
- **Fail.** New trigger duplicates a frozen trigger's guarantee.

---

## 5. Events

### E-1. Past-tense verb discipline
- **Why.** EVENT_MODEL.md convention; APP 006/007/008/009 all obey (`review.completed`, `approval.superseded`, `release.finalized`, `requirement.archived`).
- **Pass.** Every new emitted event name uses a past-tense verb. RESERVED names use past-tense (APP 007 F-4.2 corrected `deadline_approaching` → `deadline_approached`).
- **Fail.** Present-tense or gerund (`approving`, `finalizing`); ambiguous verb form.

### E-2. Reuse frozen event vocabulary before adding new
- **Why.** APP 007 F-4.1 — proposal listed `approval.approved` / `approval.rejected` as "new" but they were already emitted by frozen AUTH 007. Additive payload extension is preferred over new event types.
- **Pass.** For every proposed new event name, the reviewer verifies the frozen event set does not already emit it. Extension to an existing frozen event's payload is preferred over a new event.
- **Fail.** Proposal introduces a new event name that duplicates or shadows an existing frozen name.

### E-3. Payload extensions are additive only
- **Why.** Consumers may assume any key present is stable; changing a key's meaning silently breaks consumers.
- **Pass.** Every payload extension adds new keys; every frozen key preserved verbatim with the same meaning; no key removed or renamed.
- **Fail.** Any frozen payload key removed, renamed, or its type/meaning changed.

### E-4. No review-borrowed keys in unrelated modules
- **Why.** APP 007 F-4.3 — `round_number: null` was proposed for approval payloads but approvals have no rounds. Cross-module payload key leakage pollutes the vocabulary.
- **Pass.** Every payload key is semantically owned by the emitting slice; no key from an unrelated module appears null-padded.
- **Fail.** Payload contains a key with `null` value whose meaning belongs to another slice.

### E-5. `subject_kind` matches the affected entity
- **Why.** Consumers filter events by `subject_kind` (APP 009 L-2 concrete filter uses this).
- **Pass.** Every event's `subject_kind` matches the entity mutated by the emitting RPC. Compound entities (parent + item) use the appropriate `subject_kind` per event (e.g., `release` vs `release_item`).
- **Fail.** `subject_kind` inconsistent with the mutated entity, or reused across events with different targets.

### E-6. RESERVED event names registered in EVENT_MODEL.md at freeze time
- **Why.** APP 009 F-5 — proposal claimed reserved names were "already registered" but they were absent from EVENT_MODEL.md. Vocabulary lock must be real from day one.
- **Pass.** Every reserved event name is registered in EVENT_MODEL.md as part of the Wave 1 documentation diff. `grep '<name>' docs/EVENT_MODEL.md` returns a match.
- **Fail.** Reserved name claimed but absent from EVENT_MODEL.md at freeze certification.

### E-7. Stale event-payload claims verified
- **Why.** APP 008 F-3.4-M1 — proposal claimed `superseded_by_code` was a future addition, but it was already emitted by the frozen `supersede_requirement` RPC.
- **Pass.** For every claim about an event payload key, verify against the actual RPC body (`SELECT prosrc FROM pg_proc WHERE proname='<rpc>'`). If a key is already emitted, document it as frozen, not as a future addition.
- **Fail.** Proposal understates or overstates the frozen event payload surface.

---

## 6. Capabilities

### C-1. Capability naming discipline
- **Why.** PERMISSIONS.md convention; every capability is `<module>.<verb>`.
- **Pass.** Every new capability key uses `<module>.<verb>` format; module prefix matches the owning slice (`requirement.*`, `release.*`, etc.).
- **Fail.** Ambiguous prefix, mixed case, non-verb suffix, or cross-module prefix.

### C-2. Frozen capability role maps preserved byte-identical
- **Why.** APP 006/007/008/009 all preserved every prior role map byte-identically when reissuing `lign_has_capability`.
- **Pass.** After reissuing `lign_has_capability` with new keys, every prior role's array is byte-identical to the frozen version. Verify by diffing the function body against the pre-slice version.
- **Fail.** Any role's frozen key list has drifted (order, spelling, or membership).

### C-3. Reserved capability keys have zero role grants
- **Why.** APP 008/009 established that reserved capability names are inert placeholders until a future wave wires them.
- **Pass.** Every reserved capability key appears in the `lign_has_capability` body as a comment or unreachable case; no role's array includes it; `lign_has_capability(any_project, any_role, '<reserved>')` returns `false`.
- **Fail.** Any role grants a reserved capability; or the key is missing from the frozen registration ledger.

### C-4. Frontend `CAPABILITY_KEYS` matches backend
- **Why.** Silent divergence between frontend and backend capability sets causes UI to gate on non-existent keys or miss existing ones.
- **Pass.** `app/src/types/capabilities.ts` `CAPABILITY_KEYS` contains every backend key currently wired; reserved backend-only keys are omitted from the frontend enum.
- **Fail.** Frontend references a capability not registered in `lign_has_capability`, or vice versa for wired keys.

### C-5. Extend-before-duplicate rule
- **Why.** PERMISSIONS.md convention: prefer extending an existing capability's grant range over introducing a new key.
- **Pass.** For every proposed new capability, the review checks whether an existing key already covers the intended action. New key added only when the semantic separation is real.
- **Fail.** New capability duplicates an existing key's intent.

---

## 7. RLS

### RL-1. Every user-facing table has RLS enabled
- **Why.** DATABASE_SCHEMA.md invariant.
- **Pass.** `SELECT relrowsecurity FROM pg_class WHERE relname='<table>'` returns `true` for every table exposed to `authenticated`.
- **Fail.** Any user-facing table without RLS enabled.

### RL-2. Frozen RLS policies preserved byte-identical
- **Why.** APP 006/007/008/009 preserve every frozen policy verbatim.
- **Pass.** After any migration, `SELECT polname, polcmd, pg_get_expr(polqual, polrelid) FROM pg_policy WHERE polrelid='<table>'::regclass` matches the frozen definition for every frozen policy.
- **Fail.** Any frozen policy renamed, dropped, or its predicate altered.

### RL-3. SELECT policies gate on `lign_has_capability`
- **Why.** Uniform authorization; matches AUTHORIZATION_ARCHITECTURE.md.
- **Pass.** Every SELECT policy on a user-facing table calls `lign_has_capability(...)` with the appropriate key. No direct role membership checks in policies.
- **Fail.** Policy predicate uses raw `auth.uid()` comparisons or role-name checks instead of capability functions.

### RL-4. Writes are RPC-only for governance tables
- **Why.** Governance tables (reviews, approvals, requirements, releases) have write policies denied to `authenticated`; all writes flow through `SECURITY DEFINER` RPCs.
- **Pass.** Governance tables have no INSERT/UPDATE/DELETE policy for `authenticated`; write RPCs bypass via `SECURITY DEFINER`.
- **Fail.** Any user-facing INSERT/UPDATE/DELETE policy allowing `authenticated` on a governance table.

### RL-5. DELETE denied on immutable-history tables
- **Why.** `activity_events`, `requirements`, `version_requirement_assessments`, `releases`, `release_items` all deny DELETE.
- **Pass.** No DELETE policy exists for any immutable-history table; direct DELETE by any client role raises.
- **Fail.** Any DELETE policy on an immutable-history table.

---

## 8. Frontend

### F-1. Route additions non-colliding
- **Why.** Router must not shadow prior-slice routes.
- **Pass.** New routes namespaced under `/workspace/:ws_id/…` and `/workspace/:ws_id/project/:proj_id/…` with a slice-specific segment. Deep-link routes at `/deep/<kind>/:id` with a unique kind.
- **Fail.** Route pattern collides with a prior slice's path or resolver kind.

### F-2. Query keys namespaced and additive
- **Why.** APP 006–009 all use `qk.<module>*` prefixes; collisions break cache invalidation.
- **Pass.** All new keys under `qk.<module>*`; no overlap with `qk.review*`, `qk.approval*`, `qk.requirement*`, `qk.release*`, `qk.comment*`, `qk.annotation*`, `qk.bookmarks`, `qk.savedViews`.
- **Fail.** New key shares a prefix with an owning slice.

### F-3. URL parameter ownership respected
- **Why.** PLATFORM_CHEATSHEET §"URL parameter ownership" enumerates ownership.
- **Pass.** New URL params do not collide with `?discipline` (APP 003), `?comment/annotation/comments` (APP 005), `?review/participant` (APP 006), `?approval/participant` (APP 007), `?priority/source/category/scope/code/compose` (APP 008), `?view/status/type/tab/q/compose` (APP 009 dashboards).
- **Fail.** Any new param collides with a prior slice's ownership.

### F-4. Deep-link resolver returns real navigation
- **Why.** APP 007/008/009 all replaced APP 002 stubs with real resolvers.
- **Pass.** Every registered `kind` in `DeepLinkResolver` returns a real `<Navigate>` to the correct workspace-scoped detail route. No `kind` returns a placeholder in shipped waves.
- **Fail.** Deep-link kind advertised but resolves to a placeholder or throws.

### F-5. Every mutation calls the correct invalidator
- **Why.** Stale cache is a silent-bug class; APP 006/007/008/009 all use `invalidate<Module>Lists`, `invalidate<Module>`, `invalidate<Module>Inbox` helpers.
- **Pass.** Every mutation in `features/<module>/mutations.ts` invokes the appropriate invalidator combination — list-scope, detail, inbox, readiness, bookmark/saved-view keys where relevant.
- **Fail.** Ad-hoc `queryClient.invalidateQueries` calls on module-owned keys; missing invalidations after successful mutations.

### F-6. Reused primitives are consumed unchanged
- **Why.** APP 006 `RosterEditor`, APP 005 `CommentsPanel`, APP 002 `NavRail/DeepLinkResolver`, APP 006 `user_bookmarks/user_saved_views` are cross-slice primitives; modifying them for one slice regresses others.
- **Pass.** Reused primitives are composed unchanged; slice-specific behavior is added via props or wrapping components, not by modifying the primitive.
- **Fail.** A cross-slice primitive is edited to fit a single slice's need.

### F-7. Slice discipline in feature dir
- **Why.** APP 006 `features/reviews/`, APP 007 `features/approvals/`, APP 008 `features/requirements/`, APP 009 `features/releases/` — one dir per slice.
- **Pass.** All new UI files live under `app/src/features/<module>/`; no cross-slice leakage. Cross-slice consumption via public hooks/queries only.
- **Fail.** UI file for slice N lives under `features/M/` for M ≠ N.

### F-8. Typecheck and build pass with no new warnings
- **Why.** Every APP 006–009 shipped with clean typecheck and build.
- **Pass.** `npm run typecheck` — zero errors. `npm run build` — pass; no new warning classes beyond baseline (pre-existing "chunks larger than 500 kB" is OK).
- **Fail.** Any new typecheck error, build error, or new warning class.

---

## 9. Cross-slice compatibility

### X-1. Read-only consumption via RPCs
- **Why.** PLATFORM_BASELINE §8 — slices interact only via public RPCs.
- **Pass.** New slice reads upstream state via `SECURITY DEFINER` RPCs owned by the upstream slice. Never queries upstream tables directly.
- **Fail.** Direct SELECT on another slice's tables from the new slice's RPC bodies or frontend queries.

### X-2. Cross-slice RPC signatures verified via `pg_proc`
- **Why.** APP 007/008/009 all verified cross-slice signatures against the deployed system, not the documentation.
- **Pass.** Every consumed cross-slice RPC's signature is captured in the review via `SELECT proname, pg_get_function_arguments(oid), pg_get_function_result(oid) FROM pg_proc`. The new slice calls with matching argument names/types.
- **Fail.** Cross-slice call uses wrong argument name/type or assumes a return shape not verified from `pg_proc`.

### X-3. Terminal-state clarity for cross-slice consumers
- **Why.** APP 007 F-10.1 — the ambiguity about whether `approved` requests could be superseded left APP 009's readiness gate undefined. Clarifying terminality unblocks downstream.
- **Pass.** Every state machine explicitly documents which states are terminal-immutable and which permit further transitions. Downstream consumers rely only on documented terminal states.
- **Fail.** Any state machine leaves terminality ambiguous.

### X-4. No accidental modification to reused shared files
- **Why.** APP 006–009 all touched `queryKeys.ts`, `invalidate.ts`, `DeepLinkResolver.tsx`, `StateBadge.tsx`, `useCopyLink.ts`, `router.tsx`, `capabilities.ts` — but only additively.
- **Pass.** Every edit to a cross-slice shared file adds an entry to a union/array without removing or reordering existing entries.
- **Fail.** Existing entry removed, reordered, or its type narrowed.

### X-5. XOR CHECK widening preserves the frozen predicate shape
- **Why.** APP 008 widened `comments_target_xor_check` from 7 arms → 8 arms while preserving the frozen `= 1` (exactly-one) predicate shape.
- **Pass.** Every XOR CHECK widening preserves the frozen predicate exact form (`= 1`, not `>= 0` or `<= 1`); the widening adds an additional column to the coalesce/count expression.
- **Fail.** Predicate shape changed (`= 1` → `>= 0` or similar); or the widening drops a legacy arm.

### X-6. Frozen migration SHA integrity
- **Why.** APP 009 records SHA1 of frozen release migrations in its Implementation Report and Final Certification.
- **Pass.** Every prior slice's frozen migration files SHA-verified byte-identical after the new slice's migrations are applied.
- **Fail.** Any frozen migration file byte-modified.

---

## 10. Performance

### P-1. Cursor pagination on all list RPCs
- **Why.** APP 006/007/008/009 all use server-opaque cursor tuples `(sort_col, id)`.
- **Pass.** Every list RPC accepts `p_cursor_*` parameters + `p_limit`; server never accepts offset. Cursor payload is opaque to clients.
- **Fail.** Offset-based pagination; client-constructed cursor payload.

### P-2. Advisor: no new issue class beyond baseline
- **Why.** APP 006/007/008/009 all confirmed no new advisor issue classes vs the prior slice's baseline.
- **Pass.** `mcp__claude_ai_Supabase__get_advisors` for security + performance — every new WARN falls into a pre-existing class (`authenticated_security_definer_function_executable`, `unindexed_foreign_keys` for partial-index-covered FKs, `unused_index` for freshly-deployed indexes).
- **Fail.** Any new advisor issue class not covered by a documented waiver.

### P-3. Bundle-size delta reported and reasonable
- **Why.** APP 007 (+36 kB), APP 008 (+43 kB), APP 009 (+31 kB) — deltas are recorded per slice.
- **Pass.** Implementation Report cites before/after/delta bundle sizes; delta is proportional to the added surface. No new build warning classes.
- **Fail.** Bundle delta unreported or drastically disproportionate.

### P-4. Denormalized dashboard counts flagged for future optimization
- **Why.** APP 007 F-8.2 — `list_approvals_dashboard` per-row subselects are O(N·M); flagged as v2 materialized-view candidate.
- **Pass.** Dashboard RPCs that compute counts via per-row subselects note the O(N·M) cost and mark as v2 optimization candidate.
- **Fail.** Unbounded per-row subselects with no scale plan.

### P-5. Trigram indexes in `extensions` schema
- **Why.** APP 008 initially installed `pg_trgm` in `public` and had to relocate it via a fix migration. Convention: extensions live in `extensions` schema.
- **Pass.** Any new extension (`pg_trgm`, etc.) is installed in the `extensions` schema; operator classes referenced qualified (`extensions.gin_trgm_ops`).
- **Fail.** Extension installed in `public`; operator class referenced unqualified.

---

## 11. Governance

### G-1. Full 7-stage cycle documented
- **Why.** APP 006–009 all completed the cycle: Freeze Index → Backend Proposal → Backend Re-freeze Review → Backend Re-freeze Report → Implementation → Implementation Report → Final Architecture Audit → Final Certification.
- **Pass.** Every stage produced a document on disk under `docs/APP_00N_*.md` or `docs/freeze/APP_00N_FINAL_CERTIFICATION.md`. Every stage's output feeds the next.
- **Fail.** Any stage skipped or its output missing.

### G-2. Final Architecture Audit performs empirical verification
- **Why.** APP 007/008/009 all caught bugs the implementation report missed by empirically querying the deployed DB, not trusting documentation.
- **Pass.** Audit report cites `pg_proc`, `pg_trigger`, `pg_indexes`, `pg_constraint`, `information_schema.columns`, `pg_publication_tables` query results as evidence. Every claim about the deployed system has a query result behind it.
- **Fail.** Audit relies on the Implementation Report's claims without independent verification.

### G-3. Findings classified and every CRITICAL/HIGH resolved before freeze
- **Why.** APP 007/008/009 all applied every accepted CRITICAL and HIGH finding before certification.
- **Pass.** Every CRITICAL and HIGH finding from the Backend Re-freeze Review is applied to the proposal before implementation begins. Every finding surfaced by the Final Architecture Audit is either resolved or explicitly recorded as non-blocking with justification.
- **Fail.** Any CRITICAL or HIGH finding shipped unresolved.

### G-4. Non-blocking observations recorded in the certification
- **Why.** APP 007 F-1..F-5, APP 008 F-1..F-5, APP 009 F-B1/F-B2/F-TD1 all recorded in their certifications for future housekeeping.
- **Pass.** Certification §"Non-blocking observations" enumerates every audit finding not resolved before freeze, with severity and rationale.
- **Fail.** Non-blocking observation silently omitted from the certification.

### G-5. Schema-lock memory updated
- **Why.** `project_lign_schema_v1_lock.md` records every frozen slice's surface. Updates are the durable record.
- **Pass.** After certification, the schema-lock memory has a new bullet enumerating the slice's tables, columns, indexes, constraints, triggers, RPCs, capabilities, events, and preservation guarantees. Cite migration numbers or file names.
- **Fail.** Certification complete but schema-lock memory not updated.

### G-6. Amendment path documented
- **Why.** PLATFORM_BASELINE §9 — post-certification changes require an amendment cycle, not silent edits.
- **Pass.** Any change to a frozen slice after certification triggers a new Freeze Index amendment + re-freeze review + re-certification. Cite the amendment when the change lands.
- **Fail.** Silent edit to a frozen migration, RPC, event, or capability without an amendment cycle.

### G-7. Reference to prior findings in review reports
- **Why.** APP 008 review cited APP 007 F-1.1 as a precedent; APP 009 review cited APP 006 T-CRIT-1. Cross-referencing prior lessons prevents recurrence.
- **Pass.** Every architect review report cites the finding IDs of relevant prior-slice lessons (e.g., "F-1 mirrors APP 006 T-CRIT-1 pattern").
- **Fail.** Recurring bug shipped because prior lesson not cited.

### G-8. Target project verified
- **Why.** Memory rule: LIGN = `hsfporioghapwghrvvzd`; nuesync = `vzgoobyltkgfrtycvtiz` — never touch nuesync.
- **Pass.** Every `apply_migration` / `execute_sql` call targets `hsfporioghapwghrvvzd`. Verified in the review.
- **Fail.** Any operation against a non-LIGN project.

---

## Freeze Blocker Summary

If **any** CRITICAL check fails, freeze is blocked. Produce an **Implementation Blocker Report** identifying:
- The failed check ID (e.g., `T-1` chain-init, `R-5` named-argument ambiguity, `S-3` FK column-name)
- The specific evidence of failure (SQL query, file citation, error message)
- The frozen contract clause the failure violates
- Whether the fix is additive or requires a contract amendment

Do **not** silently paper over blocker findings. Do **not** invent a workaround.

---

This checklist is versioned with the platform. Add new checks only when a new class of failure is discovered and certified. Never remove a check.
