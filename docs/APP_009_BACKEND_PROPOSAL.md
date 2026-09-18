# APP 009 Backend Proposal (Re-freeze Applied)

## APP 009 Backend Re-freeze Report

### 1. Verdict

**APP 009 Backend is frozen.** All accepted findings from the Backend Re-freeze Review have been applied. Two CRITICAL, two HIGH, two MEDIUM, and two LOW corrections applied. Zero new backend surface introduced (no new tables, RPCs, capabilities, event types, or columns beyond those already in the proposal). Scope unchanged; F-4 removes one tail parameter from `finalize_release` and F-2 collapses two "dual overload" representations into single-function `CREATE OR REPLACE` extensions — both are representation changes, not scope changes.

### 2. Corrections applied

| Finding | Severity | Location(s) updated | Rationale | Exact contract change | Compatibility impact | Applied |
|---|---|---|---|---|---|---|
| F-1 | CRITICAL | §0 chain-init discipline; §5.1, §5.2 FK notes; §3.4 semantic clarification; §9.1 (rewritten); §14.9 supersede RPC; §14.11 chain-init reprise | The prior `enforce_release_chain_immutable` trigger rejected any `IS DISTINCT FROM` change on `superseded_by_release_id`, making the reserved `create_release_superseding` RPC unimplementable (its step-5 `NULL → uuid` write on the prior release would raise). | Chain-immutability trigger now uses **exactly-once initialization** for `superseded_by_release_id` (`NULL → uuid` permitted once; `uuid → uuid` and `uuid → NULL` rejected). `root_release_id` remains **fully immutable after INSERT** (all transitions rejected). No signature or column change; only trigger predicate refinement. | Chain integrity preserved (both columns effectively write-once). APP 006 T-CRIT-1 discipline preserved for `root_release_id`. `create_release_superseding` becomes implementable. ON DELETE RESTRICT still stands on both self-FKs. | Yes |
| F-2 | CRITICAL | §0 Conventions (Option A discipline); §14.5 (`finalize_release`); §14.8 (`withdraw_release`); §8 narrative; §11.4, §11.5, §12.1 emitter references; §12.5; §14.10; §16.2; §21.1; §1 table row; Wave 1 & priority tables | The prior proposal declared two Postgres overloads per frozen RPC (`finalize_release(uuid)` + `finalize_release(uuid, text, boolean)`; `withdraw_release(uuid, text)` + `withdraw_release(uuid, text, boolean)`). Named-argument calls like `finalize_release(p_release_id => X)` match BOTH overloads via defaults and raise `function is not unique`. | Rewrote §14.5 and §14.8 to use the APP 008 pattern: single-function `CREATE OR REPLACE` with default-tail params. `finalize_release(p_release_id uuid, p_release_type text default null)`; `withdraw_release(p_release_id uuid, p_reason text, p_admin_override boolean default false)`. No dual overloads. | Both positional and named-argument callers of the frozen signatures resolve unambiguously to the single replaced function. Frozen 1-arg / 2-arg positional calls unchanged. No runtime "function is not unique" trap. | Yes |
| F-3 | HIGH | §14.9 `create_release_superseding` step 2; §14.11 chain-init reprise | Concurrent supersede calls on the same prior release could race the chain-immutability trigger and produce opaque errors. | Step 2 now reads the prior release with `SELECT ... FOR UPDATE` and verifies `status='released' AND superseded_by_release_id IS NULL`. Losing calls receive a clean `SQLSTATE 22023` "release already superseded" error. | Serializes concurrent supersede calls on the same prior release. No signature change. | Yes |
| F-4 | HIGH | §14.5 `finalize_release`; §1 table row; §11.4 (via §14.5 wording); §18 / Wave 1 tables | The `p_capture_evidence=false` pathway allowed released rows with permanent NULL `evidence_snapshot`, undermining the immutability guarantee. No live use case existed. | Dropped `p_capture_evidence boolean` from `finalize_release`. Evidence capture is **always** performed at finalization. `enforce_release_evidence_immutable` trigger logic unchanged. | Eliminates the NULL-evidence trap. One tail parameter removed from the extended signature; frozen positional 1-arg call still binds unchanged. | Yes |
| F-5 | MEDIUM | §12.2 (rewritten header + Wave 1 doc-diff commitment); Wave 1 item added; Wave 3 item removed; §16.1 doc-diff note; wave tally note | The prior §12.2 header implied all 7 reserved event names were already registered in EVENT_MODEL.md — only `release.scheduled` and `release.superseded` are (as MVP-removed). The other 5 are new reservations, and the "documentation updates for reserved names" item was scheduled to Wave 3, so the vocabulary lock would not be real until then. | Rewrote §12.2 header to state precisely which names are already present and which are new-in-this-proposal; commits the EVENT_MODEL.md doc-diff to Wave 1 alongside Migration A. Moved the doc-diff item from Wave 3 to Wave 1. | Vocabulary lock is real from Wave 1. Downstream waves and slices can bind fixed strings immediately. No emitter added. | Yes |
| F-6 | MEDIUM | §0 Conventions (SECURITY DEFINER rationale); §9.1, §9.2, §9.3 trigger attributes | New trigger functions were declared `SECURITY DEFINER` but only inspect OLD/NEW columns of the trigger's own row — no cross-table read requires bypassing caller RLS. This diverged from the frozen `enforce_release_status_via_rpc` non-DEFINER precedent. | Removed `SECURITY DEFINER` from all three new trigger functions (`enforce_release_chain_immutable`, `enforce_release_evidence_immutable`, `enforce_release_type_immutable_when_released`). Kept `SET search_path = ''` and REVOKE-from-public/anon/authenticated + no-GRANT discipline. | Matches frozen precedent at `supabase/migrations/20260801220000_auth_008_release_rls.sql` L38. No behavior change; triggers still fire under the row-writer's context. | Yes |
| L-1 | LOW | §14.4 `publish_release` sequence steps 2 & 6 | Publish had a standalone step-2 UPDATE of `release_type` and a separate step-6 status/evidence UPDATE. Two UPDATEs meant `releases_set_updated_at` fired twice per publish. | Folded `release_type = coalesce(p_release_type, release_type)` into the single atomic transition UPDATE (new step 5), which also transitions status, freezes evidence, and records publisher. Type-immutability trigger inspects `OLD.status` (still `'draft'` at UPDATE time), so the change is permitted. Steps renumbered (2–6 → 2–6 with previous 2 removed and previous 6 merged). | Single UPDATE per publish; `releases_set_updated_at` fires exactly once. Atomic transition preserved. | Yes |
| L-2 | LOW | §13.6 `list_release_activity` filter description | The filter clause "`subject_id = p_release_id` (or item IDs belonging to the release)" was ambiguous. | Replaced with the concrete predicate: `(subject_kind = 'release' AND subject_id = p_release_id) OR (subject_kind = 'release_item' AND subject_id IN (SELECT id FROM release_items WHERE release_id = p_release_id))`. | No signature or index change. | Yes |

### 3. Final backend surface summary

| Kind | Count | Note |
|---|---|---|
| Additive columns on `releases` | 7 | Unchanged from proposal. |
| New tables in Wave 1 | 0 | Unchanged; 3 reserved (`release_distributions`, `release_templates`, `release_audit_exports`). |
| Additive indexes | 7 | Unchanged (4 btree + 2 partial + 1 unique partial). GIN on `evidence_snapshot` remains Future. |
| New CHECK constraints | 1 | Unchanged: `releases_release_type_check`. |
| New composite FKs | 3 | Unchanged: 2 self-FKs on `releases` (chain) + 1 cross-table FK to `profiles`. |
| Read RPCs | 13 | Unchanged. |
| Frozen write RPCs extended via `CREATE OR REPLACE` + default-tail | 2 | Was represented as "dual overloads" — collapsed per F-2 into single-function `CREATE OR REPLACE`. `finalize_release` gains 1 tail param (was 2; `p_capture_evidence` removed per F-4). `withdraw_release` gains 1 tail param. |
| New write RPCs | 6 | Unchanged (draft composition + publish wrapper + soft-discard + reorder). |
| Reserved write RPCs | 3 | Unchanged: `schedule_release`, `create_release_superseding`, `export_release_audit`. |
| Reserved capabilities | 6 | Unchanged; zero role grants. |
| Defense-in-depth triggers | 3 | Unchanged count. F-1 refines `enforce_release_chain_immutable` semantics (asymmetric write-once). F-6 removes `SECURITY DEFINER` attribute from all three. |
| New emitted event types | 0 | Unchanged. |
| Reserved event names | 7 | Unchanged; per F-5 all 7 committed to Wave 1 EVENT_MODEL.md doc-diff. |
| Additive payload keys on frozen `release.*` events | 5 events touched | Unchanged. |

### 4. Final implementation waves

- **Wave 1 — Critical (20 items).** Every Critical schema/RPC item plus the EVENT_MODEL.md doc-diff registering all 7 reserved event names (moved in from Wave 3 per F-5).
- **Wave 2 — High (11 items).** Unchanged.
- **Wave 3 — Medium (7 items).** Unchanged except item 8 (docs for reserved names) removed and moved to Wave 1 per F-5. Item 7 now covers AI-seam reserved-capability documentation in PERMISSIONS.md only; the reserved AI event names are already covered by the Wave 1 EVENT_MODEL.md doc-diff.
- **Wave 4 — Future (33 items).** Unchanged.

Wave item-count tally: 20 + 11 + 7 + 33 = 71 backend surface items + 1 Wave 1 doc-diff deliverable.

### 5. Cross-slice compatibility guarantee

- **APP 001 (Auth/bootstrap):** Frozen contracts intact. No `auth.*` object touched. No frozen `lign_has_capability` key modified.
- **APP 002 (Workspaces/projects):** Frozen contracts intact. `qk`, `DeepLinkResolver`, `CAPABILITY_KEYS`, `NavRail` extended additively.
- **APP 003 (Design Workspace):** Frozen contracts intact. `RightPanel` gains a Releases tab (additive); consumes read RPCs only.
- **APP 004 (Files/viewer):** Frozen contracts intact. No mutation.
- **APP 005 (Comments/annotations):** Frozen contracts intact. Per G-32, does NOT add `target_release_id` to `comments`.
- **APP 006 (Reviews):** Frozen contracts intact. Read-only consumption via evidence snapshot. `user_bookmarks` and `user_saved_views` reused with `entity_kind='release'` / `scope='releases'`.
- **APP 007 (Approvals):** Frozen contracts intact. Hard read consumption of `get_approval_readiness(p_version_id uuid) → jsonb` returning `{ has_approved, latest_outcome, blocking_requests }`. No mutation.
- **APP 008 (Requirements):** Frozen contracts intact. Hard read consumption of `get_release_readiness_for_version(p_asset_version_id uuid) → jsonb` returning the 7-key readiness shape. No mutation.
- **APP 009 (this):** Owner. Frozen releases baseline (`supabase/migrations/20260729230000_releases.sql`, `supabase/migrations/20260801220000_auth_008_release_rls.sql`) preserved byte-identically. No APP 001–008 file modified. Frozen releases migrations byte-identical.
- **APP 010 (Notifications, not yet frozen):** Consumes frozen `release.*` events plus additive payload keys.
- **APP 011 (Realtime, not yet frozen):** Release tables **REMAIN OUT** of `supabase_realtime`. Realtime remains OUT.

### 6. Freeze checklist

| Check | Status |
|---|---|
| Frozen Migration 008 byte-identical | Yes |
| Frozen AUTH 008 byte-identical | Yes |
| Frozen 4-capability set preserved (`release.view`, `release.create`, `release.finalize`, `release.withdraw`) | Yes |
| Frozen 5-event vocabulary preserved | Yes |
| Frozen `finalize_release(uuid)` positional call binds unchanged | Yes (`CREATE OR REPLACE` default-tail per F-2) |
| Frozen `withdraw_release(uuid, text)` positional call binds unchanged | Yes (`CREATE OR REPLACE` default-tail per F-2) |
| Named-argument callers of frozen signatures resolve unambiguously | Yes (single function, no dual overloads — F-2) |
| Chain-immutability trigger permits legitimate supersede step-5 write | Yes (F-1 exactly-once initialization for `superseded_by_release_id`) |
| `root_release_id` is fully immutable after INSERT (APP 006 T-CRIT-1) | Yes (F-1) |
| Every released row has non-NULL `evidence_snapshot` | Yes (F-4 removed the bypass) |
| Concurrent supersede on same prior release raises clean 22023 | Yes (F-3 `SELECT ... FOR UPDATE`) |
| Row-local trigger functions are not `SECURITY DEFINER` | Yes (F-6) |
| Publish issues a single atomic UPDATE (one `updated_at` bump) | Yes (L-1) |
| Reserved event names locked in EVENT_MODEL.md from Wave 1 | Yes (F-5) |
| Zero new tables, capabilities wired, or emitted event types added in Wave 1 | Yes |
| Cross-slice reads are read-only | Yes |
| Realtime remains OUT | Yes |

### 7. Final freeze contract

This document is the authoritative backend contract for APP 009. It supersedes the pre-review proposal and is the input to Migration A + Migration B implementation. Future changes require an amendment and re-freeze.

**APP 009 Backend is frozen.**

---

# APP 009 — Backend Proposal (Releases Product Surface)

**Design proposal only. No SQL, no implementation, no migrations.** Every backend addition required to support the frozen APP 009 architecture, mapped to the Freeze Index sections and prioritized for a phased re-freeze. This document is the authoritative pre-review backend contract; a Backend Re-freeze Review cycle will follow.

**Companion documents:**
- [`APP_009_FREEZE_INDEX.md`](APP_009_FREEZE_INDEX.md) — the frozen architecture this proposal supports. §27 (backend-delta preview) is the authoritative scope anchor.
- [`APP_008_BACKEND_PROPOSAL.md`](APP_008_BACKEND_PROPOSAL.md) — primary pattern reference: additive-only extension of a frozen product-surface baseline; Option-A tail-param discipline; reserved-name registration.
- [`APP_007_BACKEND_PROPOSAL.md`](APP_007_BACKEND_PROPOSAL.md) — secondary pattern reference: chain-init discipline (T-CRIT-1), dashboard readiness RPC pattern, coverage matrix shape.
- [`APP_006_BACKEND_PROPOSAL.md`](APP_006_BACKEND_PROPOSAL.md) — original chain-init pattern (T-CRIT-1: pre-computed UUID + inline INSERT chain columns).
- [`freeze/APP_008_FINAL_CERTIFICATION.md`](freeze/APP_008_FINAL_CERTIFICATION.md) — governance shape for the Backend Re-freeze cycle.
- [`SCHEMA_V1_LOCK.md`](SCHEMA_V1_LOCK.md) — schema lock; APP 009 extends it additively only.
- [`PERMISSIONS.md`](PERMISSIONS.md) — capability catalog; six reserved-only keys documented here (no wiring in v1).
- [`EVENT_MODEL.md`](EVENT_MODEL.md) — event vocabulary; seven RESERVED names + additive payload keys on five frozen events.
- [`STATE_MACHINES.md`](STATE_MACHINES.md) §15 — release lifecycle; APP 009 does not activate reserved `scheduled`/`superseded` states.
- [`AUTHORIZATION_ARCHITECTURE.md`](AUTHORIZATION_ARCHITECTURE.md) — capability check discipline.

**Frozen invariants cited by this proposal (Migration 008 + AUTH 008; MUST NOT modify):**

- `supabase/migrations/20260729230000_releases.sql` L72–L110 — `public.releases` table definition (columns, `releases_status_check`, `releases_released_metadata_check`, `releases_withdrawn_metadata_check`, composite anchor uniques `(id, project_id, workspace_id)` and `(id, workspace_id)`).
- `supabase/migrations/20260729230000_releases.sql` L120–L132 — frozen indexes on `releases`: `releases_project_workspace_idx`, `releases_created_by_profile_id_idx (partial)`, `releases_project_status_released_idx`, `releases_workspace_status_idx`.
- `supabase/migrations/20260729230000_releases.sql` L145–L205 — `public.release_items` table definition (composite FKs, `release_items_release_version_key`, `release_items_release_sort_order_key`).
- `supabase/migrations/20260729230000_releases.sql` L211–L258 — `enforce_release_items_parent_draft_mutation` trigger + function (BEFORE INSERT/UPDATE/DELETE; SECURITY DEFINER; REVOKEd from public/anon/authenticated; blocks mutation unless parent `releases.status = 'draft'`).
- `supabase/migrations/20260729230000_releases.sql` L274–L344 — `enforce_release_finalization_prerequisites` trigger + function (BEFORE INSERT + BEFORE UPDATE OF status; SECURITY DEFINER; universally requires ≥ 1 item + every-item-approved on transition to `released`).
- `supabase/migrations/20260729230000_releases.sql` L356–L363 — completed deferred FK `decisions.resulting_release_id → releases(id, workspace_id) ON DELETE RESTRICT`.
- `supabase/migrations/20260801220000_auth_008_release_rls.sql` L38–L76 — `enforce_release_status_via_rpc` trigger + function (BEFORE UPDATE; immutability for `id`/`workspace_id`/`project_id`/`created_by_profile_id`; RPC-only writes for `status`/`released_at`/`withdrawn_at`/`withdrawn_reason` gated by `lign.allow_release_status_write` GUC).
- `supabase/migrations/20260801220000_auth_008_release_rls.sql` L82–L147 — `finalize_release(p_release_id uuid) → uuid` frozen RPC (SECURITY DEFINER, `search_path=''`, `release.finalize` capability check, emits `release.finalized` with `subject_snapshot={name, item_count, channel}`).
- `supabase/migrations/20260801220000_auth_008_release_rls.sql` L153–L211 — `withdraw_release(p_release_id uuid, p_reason text default null) → uuid` frozen RPC (SECURITY DEFINER, `search_path=''`, `release.withdraw` capability check, emits `release.withdrawn` with `subject_snapshot={reason}`).
- `supabase/migrations/20260801220000_auth_008_release_rls.sql` L217–L296 — frozen RLS on `releases` (SELECT gated by `release.view`; INSERT requires `release.create` + `created_by_profile_id = auth.uid()` + `status='draft'`; UPDATE gated by `release.create`; no DELETE policy) and on `release_items` (SELECT/INSERT/UPDATE/DELETE all gated by parent's `release.view` / `release.create`).
- Frozen capability keys `release.view`, `release.create`, `release.finalize`, `release.withdraw` — registered in `lign_has_capability` per AUTH 001 role map; PERMISSIONS.md §2.12 / §5.
- Frozen event names `release.created`, `release.item_added`, `release.item_removed`, `release.finalized`, `release.withdrawn` — EVENT_MODEL.md §4.12 L185–L189. Only `release.finalized` and `release.withdrawn` have shipped emitters (AUTH 008); the other three are name-frozen but emitters are proposed here as **[additive]** in the new draft-composition RPCs (§14).
- Realtime publication boundary — REALTIME 001: releases tables are **OUT** of `supabase_realtime`. Any change is a REALTIME re-freeze, not an APP 009 concern.
- `supabase/migrations/20260812180000_app_008_requirements_authz_and_rpcs.sql` L1332–L1404 — `get_release_readiness_for_version(p_asset_version_id uuid) → jsonb` (APP 009 hard-consumer; returns `{applicable_count, satisfied_count, partial_count, not_satisfied_count, unassessed_count, critical_unsatisfied_count, critical_unassessed_count}` per Freeze Index §9.5).
- APP 007 `get_approval_readiness(p_version_id uuid) → jsonb` — returns `{ has_approved bool, latest_outcome jsonb, blocking_requests uuid[] }` where `latest_outcome = { status text, outcome_at timestamptz, request_id uuid }` per APP_007_BACKEND_PROPOSAL.md §7.5.

---

## Executive summary

- **Scope anchor.** This proposal implements the backend surface delta enumerated in `APP_009_FREEZE_INDEX.md` §27. That preview is authoritative: 7 additive columns on `releases`, 0 new tables in v1 (3 reserved), 13 additive read RPCs, 6 new write RPCs plus `CREATE OR REPLACE` single-function additive-tail extensions to 2 frozen write RPCs (`finalize_release`, `withdraw_release`), 0 new capability keys wired (6 reserved names), 0 new emitted event types (5 frozen events cover every transition; 7 reserved names committed to Wave 1 EVENT_MODEL.md doc-diff), ~7 additive indexes, 3 defense-in-depth triggers, additive payload keys on all 5 frozen events.
- **Additive-only guarantee.** No frozen RPC signature is renamed or removed. Both frozen write RPCs (`finalize_release`, `withdraw_release`) preserve their existing positional call sites byte-for-byte; extensions are Option-A default-tail params delivered via `CREATE OR REPLACE FUNCTION` on the single frozen function (no dual overloads — see §0 Conventions), so both positional and named-argument callers of the frozen signatures work unchanged. No frozen event name changes. No frozen capability role map changes. No frozen table RLS policy is weakened. No frozen trigger modified. No frozen CHECK narrowed. No frozen composite FK altered. No frozen anchor unique key touched.
- **Frozen releases baseline preserved.** Migration 008 (`20260729230000_releases.sql`) and AUTH 008 (`20260801220000_auth_008_release_rls.sql`) remain byte-identical. Every extension is delivered by two new migrations (§16) that only add columns, indexes, triggers, and RPCs; they never `ALTER` a frozen column, `DROP` a frozen constraint, or `CREATE OR REPLACE` a frozen function.
- **Zero new tables in v1.** The frozen 2-table backbone (`releases`, `release_items`) plus additive nullable columns expresses every product surface enumerated in the Freeze Index. Three reserved-only table names (`release_distributions`, `release_templates`, `release_audit_exports`) are recorded here so future waves can bind against fixed strings without renaming.
- **Chain-init discipline is mandatory.** Two chain columns (`superseded_by_release_id`, `root_release_id`) are introduced. Following the APP 006 T-CRIT-1 remediation verbatim: the RPC layer pre-computes `release.id` via `gen_random_uuid()`, INSERTs with `root_release_id` set inline (self for chain roots; the prior release's `root_release_id` — or the prior release's `id` if the prior was itself a root — for supersessions), and does not post-INSERT-UPDATE either chain column. A dedicated `enforce_release_chain_immutable` trigger (§9) blocks any UPDATE of these columns, so a NULL → self UPDATE would raise. Chain-init happens inside the deferred `create_release_superseding` RPC (§14) which is reserved-only in v1.
- **Evidence snapshot is jsonb; immutable once written.** The Freeze Index §6 mandates that publish-time evidence is captured as a `jsonb` snapshot on the release row (G-7 decision). A defense-in-depth `enforce_release_evidence_immutable` trigger (§9) blocks any UPDATE of `evidence_snapshot` when the release is `released` or `withdrawn`, mirroring the frozen `enforce_release_status_via_rpc` pattern for RPC-only writes.
- **Release type is enum; frozen once released.** The **[additive]** `release_type text` column carries a 7-value CHECK (`internal | preview | client | regulatory | final | patch | hotfix`) per Freeze Index §9.1. The frozen `channel` free-text column is preserved for human labels. `enforce_release_type_immutable_when_released` (§9) freezes the type at `released` transition per Freeze Index §9.7.
- **Per-release-type policy is RPC-layer defense-in-depth.** The frozen `enforce_release_finalization_prerequisites` trigger is universal (every item's version must have an approved `approval_requests` row) and cannot be loosened. The **[additive]** `publish_release` wrapper (§14) layers per-type checks by consuming `get_approval_readiness` and `get_release_readiness_for_version`, raising early with clearer error messages. It never weakens the trigger — it only adds hard blocks for `regulatory` / `final`, soft warnings for `client`, and advisories for the rest.
- **Frozen 4-capability set covers every action.** No new capability keys are wired in v1. Six reserved names (`release.schedule`, `release.supersede`, `release.ai_suggest`, `release.ai_classify`, `release.audit_export`, `release.recall`) are registered in PERMISSIONS.md by name only — zero role grants — per Freeze Index §19.3 and G-24.
- **Frozen 5-event vocabulary covers every transition.** No new event types are emitted in v1. Seven reserved names are registered in EVENT_MODEL.md by name only — no emitter — per Freeze Index §20.5 and G-25. Payload extensions on all five frozen events add contextual keys (`release_type`, `published_by_profile_id`, `code`, `approved_request_ids[]`, `requirement_readiness`, `review_count`) — additive-only; consumers ignore unknown keys per the APP 007 §17.1 precedent.
- **Release display code (`R-NNN` per project).** The **[additive]** `code text` column carries a per-project partial unique index. Code generation uses an advisory-lock xact-scoped ordinal pattern (mirroring APP 008 `create_requirement`'s `R-NNN` generation). Codes are stable deep-link targets and never renumber when drafts are discarded.
- **Soft-discard for draft cleanup.** Per Freeze Index G-4 (Option B), the **[additive]** `discarded_at timestamptz` column allows soft-discard of empty drafts. No DELETE RLS policy is proposed. `discard_release_draft` (§14) sets `discarded_at = now()` and preserves the audit trail.
- **Publisher attribution.** The **[additive]** `published_by_profile_id uuid` FK ON DELETE SET NULL captures who published, distinct from the frozen `created_by_profile_id` (creator). Both may be NULL if the profile is later removed (matches APP 008 G-37 orphaned-originator posture).
- **Composite tenancy on every new FK.** `(superseded_by_release_id, project_id, workspace_id) → releases(id, project_id, workspace_id)` and `(root_release_id, project_id, workspace_id) → releases(id, project_id, workspace_id)` both reuse the frozen composite anchor unique key `releases_id_project_workspace_key` (Migration 008 L108). `published_by_profile_id → profiles(id) ON DELETE SET NULL` mirrors the frozen `created_by_profile_id` pattern (Migration 008 L84).
- **Zero realtime changes.** Release tables remain OUT of `supabase_realtime`. Any change is a REALTIME re-freeze, not an APP 009 concern. Query-invalidation only (per Freeze Index §23 and G-29).
- **Publish is non-optimistic.** `finalize_release` and `publish_release` are server-authoritative — the trigger may raise, and the evidence snapshot is server-computed. Frontend never speculates on the outcome (per Freeze Index G-23 / G-30).
- **Cross-slice reads (hard).** `publish_release` and `get_release_readiness_for_publish` consume APP 007 `get_approval_readiness(version_id)` and APP 008 `get_release_readiness_for_version(version_id)`. Both consumers are read-only; APP 009 never mutates approvals, approval responses, requirements, or assessments.
- **Wave plan.** Wave 1 Critical (schema + chain triggers + core RPCs); Wave 2 High (dashboards, metrics, evidence, comparison, reserved-name registration); Wave 3 Medium (saved-view / bookmark reuse wiring, AI-seam reserved-name registration); Wave 4 Future (reserved capabilities, reserved events, reserved RPCs, multi-asset bundle advanced UX, release channels/distribution, release templates).
- **Backwards-compat closure.** After this proposal lands: every APP 001–008 contract byte is preserved. Migration 008 and AUTH 008 are byte-identical. Callers of `finalize_release(uuid)` and `withdraw_release(uuid, text)` continue to compile and execute unchanged; new callers additionally pass the tail params.

---

## 0. Conventions

Every proposed change carries four attributes.

- **Why:** the concrete user-facing behavior or invariant it enables.
- **Freeze Index section:** the APP 009 Freeze Index section (`§n`) or governance-decision ID (`G-n`) that requires it.
- **Priority:** `Critical` | `High` | `Medium` | `Future`.
- **Blocks implementation?** `yes` (v1 cannot ship without it) or `no` (v1 works without; polish or deferred).

Priority tiers:

| Tier | Meaning |
|---|---|
| **Critical** | v1 cannot ship at all without this. Must land in the first re-freeze wave. |
| **High** | v1 can start but a major feature is degraded or stubbed. First or second wave. |
| **Medium** | Polish / enterprise-adjacent; v1 works without it. Third wave. |
| **Future** | v2 territory; explicitly out of APP 009 v1 shipping scope. |

House rules (repeated verbatim from APP 006 / APP 007 / APP 008 backend proposals so this document stands alone):

- **Additive-only.** No column is renamed. No column is dropped. No CHECK is narrowed. No enum value is removed. Every new column is nullable, every new CHECK either applies only to the new column or is a widening.
- **Option A tail params via `CREATE OR REPLACE`.** Extensions to frozen RPCs always append parameters with `DEFAULT NULL` (or a value-preserving default such as `default false`) to the tail of the frozen signature and are delivered via `CREATE OR REPLACE FUNCTION` on the single function — **not** as a separate overload. A caller who passes only the original argument set observes byte-identical behavior (defaults fill the new positions); named-argument callers of the frozen parameter names also resolve unambiguously against the single replaced function. Frozen `finalize_release(uuid)` and `withdraw_release(uuid, text)` positional call sites remain callable verbatim. This matches the APP 008 §9.1 / §9.2 discipline (`create_requirement` 15-arg and `edit_requirement` 13-arg, both delivered as `CREATE OR REPLACE` on the frozen function with default-tail parameters) — not a dual-overload pattern. Dual overloads (frozen 1-arg + extended 3-arg coexisting as distinct signatures) would trigger `function is not unique` under named-argument resolution because the frozen signature would still match the default-filled call. This proposal therefore uses single-function `CREATE OR REPLACE` throughout.
- **SECURITY DEFINER + `SET search_path = ''`.** Every new RPC is `SECURITY DEFINER` with `SET search_path = ''`. Every RPC is `REVOKE`d from `public`/`anon` and `GRANT`ed to `authenticated, service_role`. Trigger functions are `SECURITY DEFINER` **only** when they perform cross-table reads that require bypassing caller RLS; row-local trigger functions (inspecting only OLD/NEW columns of the trigger's own row) are NOT `SECURITY DEFINER`, matching the frozen `enforce_release_status_via_rpc` non-DEFINER precedent (`supabase/migrations/20260801220000_auth_008_release_rls.sql` L38). Every trigger function sets `SET search_path = ''` and is `REVOKE`d from `public`/`anon`/`authenticated` with no `GRANT` (trigger functions fire under the row-writer's transaction context and never need `EXECUTE`).
- **Composite tenancy.** Every new FK is composite. For same-table self-FKs into `releases`, both new chain FKs use the frozen composite anchor unique `releases_id_project_workspace_key (id, project_id, workspace_id)` (Migration 008 L108). For cross-table FKs, `(target_id, workspace_id)` at minimum; where `project_id` exists, include it too. This matches SCHEMA_V1_LOCK's house rule.
- **Covering index on every new FK.** No new FK ships without a matching btree index on the FK columns. Partial-index predicates (`WHERE col IS NOT NULL`) are used when the FK is nullable to keep the index small.
- **Capability naming per PERMISSIONS.md.** Dot-separated `subject.verb` (e.g. `release.schedule`, `release.ai_suggest`). Every capability key is registered in PERMISSIONS.md §5 (role map) and mirrored in `CAPABILITY_KEYS` TypeScript constants.
- **Event naming per EVENT_MODEL.md.** Past-tense (`release.created`, `release.finalized`, `release.scheduled`, `release.superseded`, `release.recalled`, `release.audit_exported`). Never future-tense. Never bare verbs. Every new event name is either emitted-in-this-slice or explicitly reserved with the RESERVED annotation and no emitter.
- **RESERVED event names.** A RESERVED name is a name-only lock in EVENT_MODEL.md. No emitter exists in APP 009; APP 010 / cron / AI slice fills them later against the fixed strings.
- **RESERVED capability keys.** A RESERVED capability is a name-only lock in PERMISSIONS.md. No role grants exist in APP 009's `lign_has_capability` extension; `lign_has_capability(project_id, workspace_id, 'release.schedule')` returns `false` for every caller in v1.
- **Chain-init discipline (APP 006 T-CRIT-1).** For any RPC that creates a release with a non-NULL `root_release_id` or that sets `superseded_by_release_id` on a prior release:
  1. Pre-compute the new UUID (`v_new_id := gen_random_uuid()`).
  2. Compute `root_release_id` for the new row: if the prior release's `root_release_id` is not NULL, reuse it (extend chain); else use `prior_release_id` (start chain from prior root).
  3. INSERT the new release row with `id = v_new_id`, `superseded_by_release_id = NULL`, and `root_release_id` set inline.
  4. UPDATE the prior release setting `superseded_by_release_id = v_new_id` (this is a `NULL → uuid` initial write on a different row; permitted by the chain-immutability trigger's exactly-once contract for that column — see §9.1).
  5. Both writes happen in the same transaction inside the single RPC.
  6. **No post-INSERT UPDATE of `root_release_id` on any row.** `root_release_id` is fully immutable after INSERT — the chain-immutability trigger rejects any change (`23514`); a NULL → self UPDATE would raise. This mirrors APP 006 T-CRIT-1 remediation verbatim.
  7. `superseded_by_release_id` is write-once (`NULL → uuid` permitted exactly once via the prior-release UPDATE in step 4; any `uuid → uuid` change or `uuid → NULL` clear is rejected by the same trigger).
- **`COMMENT ON COLUMN` house pattern.** Every new column ships with a `COMMENT ON COLUMN` in the same migration (APP 006 house pattern; APP 007 F-1.4; APP 008 §0). Not enumerated per column below.
- **Advisory-lock code generation.** `code` values follow the APP 008 `R-NNN` advisory-lock pattern: `pg_advisory_xact_lock(hashtext('release_code:' || project_id::text))` prior to computing `max(code_ordinal) + 1`. Ensures no code collision under concurrent draft creation.
- **Composite tenant integrity is authoritative.** No RPC or trigger bypasses the frozen composite-FK invariants. Cross-project chain pointers are structurally impossible because both new chain FKs include `(project_id, workspace_id)`.

---

## 1. Executive summary of surface additions

Consolidated view of what this proposal adds, mirrored from `APP_009_FREEZE_INDEX.md` §27 and expanded per section below.

| Kind | Count (v1) | Reserved-only | Notes |
|---|---|---|---|
| New tables | 0 | 3 | Every join deferred: `release_distributions`, `release_templates`, `release_audit_exports` (see §2). |
| New columns on frozen tables | 7 | 0 | All on `releases`: `release_type`, `evidence_snapshot`, `superseded_by_release_id`, `root_release_id`, `published_by_profile_id`, `discarded_at`, `code`. |
| New indexes | 7 | 0 (GIN deferred) | 4 btree + 2 partial (1 partial unique) + 1 unique partial per §6. |
| New CHECK constraints | 1 | 0 | `releases_release_type_check` (7-value enum, NULL-permissive). |
| New composite FK constraints | 2 self-FKs + 1 cross-table FK | 0 | `superseded_by_release_id → releases(id, project_id, workspace_id)`; `root_release_id → releases(id, project_id, workspace_id)`; `published_by_profile_id → profiles(id) ON DELETE SET NULL`. |
| Enum widenings | 0 | 0 | No frozen enum touched. Frozen `releases_status_check` (5 values) preserved byte-identically. |
| New capabilities (wired) | 0 | 6 | `release.schedule`, `release.supersede`, `release.ai_suggest`, `release.ai_classify`, `release.audit_export`, `release.recall` (name-only). |
| New read RPCs | 13 | 0 | See §13. |
| New write RPCs | 6 | 3 | See §14. Frozen `finalize_release`/`withdraw_release` extended via `CREATE OR REPLACE` single-function default-tail params (no dual overloads — see §0 Conventions); reserved: `schedule_release`, `create_release_superseding`, `export_release_audit`. |
| Tail params on frozen RPCs (single-function `CREATE OR REPLACE`) | 1 on `finalize_release` (`p_release_type text default null`); 1 on `withdraw_release` (`p_admin_override boolean default false`) | 0 | Delivered via `CREATE OR REPLACE` on the single frozen function; both positional and named-argument callers of the frozen signatures work unchanged. |
| New emitted event types | 0 | 7 (Wave 1 doc-diff registers all 7 in EVENT_MODEL.md) | `release.scheduled`, `release.superseded`, `release.notes_updated`, `release.audit_exported`, `release.recalled`, `release.ai_suggested`, `release.ai_classified` (see §12). Frozen `release.created`, `release.item_added`, `release.item_removed` gain their emitters in **[additive]** RPCs (§14) — the *names* were already frozen in EVENT_MODEL.md §4.12 L185–L187. |
| Payload-key additions to frozen events | 5 events touched | 0 | All 5 frozen `release.*` events gain contextual keys per §11. |
| New triggers | 3 | 0 | `enforce_release_chain_immutable`, `enforce_release_evidence_immutable`, `enforce_release_type_immutable_when_released`. |
| RLS policies added | 0 | 0 | No policy change on frozen tables; new columns fall under existing SELECT policy. |
| Realtime publication changes | 0 | 0 | Release tables remain OUT per Freeze Index §23.1 and G-29. |

---

## 2. New tables

**None in v1.** The Freeze Index §27.2 statement is honored: zero new tables. The frozen 2-table backbone (`releases`, `release_items`) plus 7 additive nullable columns expresses every v1 product surface. Every proposal that would introduce a table is deferred to a future re-freeze:

| Reserved table | Purpose | Freeze Index section | Reserved-only rationale |
|---|---|---|---|
| `release_distributions(release_id, channel_id, ...)` | Per-release external distribution list (email / webhook per release type) | §22.2 | Notifications slice (APP 010) owns; deferred. |
| `release_templates(id, workspace_id, name, payload_jsonb)` | Composer "create from template" for standard release types | Deferred | Adds a distinct authoring surface; deferred. |
| `release_audit_exports(release_id, format, storage_object_id, ...)` | Audit-export history + reusable exports | §25.5, G-31, G-44 | Requires storage + PDF/CSV rendering; v2. |

- **Why (deferral).** Every table above adds new RLS surface, at least one new capability key, and at least one new event or invalidation edge. The Freeze Index scoped v1 to what the frozen 2-table backbone plus additive columns can express.
- **Freeze Index section:** §27.2 (explicit "None required for v1").
- **Priority:** N/A (deferred).
- **Blocks implementation?** No.

---

## 3. New columns on frozen tables

Seven **[additive]** nullable columns on `public.releases`. Zero columns on `public.release_items` (frozen shape is sufficient for v1; per-item notes and sort order already exist). All new columns are nullable, defaulted to `NULL`, and covered by the existing frozen `releases_select` policy (Freeze Index §27.9).

### 3.1 `public.releases.release_type text NULL`

- **Purpose.** Bounded enum dimension for dashboards, filters, per-type policy, and metrics rollups. The frozen `channel text` column is preserved for free-form human labels; `release_type` layers a controlled vocabulary over it (mirrors APP 008 `source_kind` pattern per Freeze Index §9.2, G-11).
- **Why.** Dashboards need to filter and aggregate on a bounded value space. Free-text `channel` cannot back saved-view chips or metric buckets. Enum captures the primary type cleanly.
- **CHECK.** `releases_release_type_check`: `release_type IS NULL OR release_type IN ('internal','preview','client','regulatory','final','patch','hotfix')`. NULL-permissive so legacy pre-migration rows load without violation.
- **Freeze Index section:** §5.3, §9.1, §27.1, G-11.
- **Priority:** Critical (blocks dashboard filter, publish gate, per-type policy).
- **Blocks implementation?** Yes.

### 3.2 `public.releases.evidence_snapshot jsonb NULL`

- **Purpose.** Frozen bundle of approval + review + requirement evidence captured atomically inside `publish_release` (or the extended `finalize_release` overload). Immutability enforced by trigger (§9.2). Contents documented in Freeze Index §6.1.
- **Shape.** JSON object with these top-level keys (locked by this proposal for consumer stability):
  - `version` — schema version (`"1"` in v1).
  - `captured_at` — timestamptz string.
  - `published_by_profile_id` — uuid.
  - `release_type` — text (mirrors column).
  - `channel` — text (mirrors column).
  - `items[]` — array; each element: `{ release_item_id, design_asset_id, design_asset_name, version_id, version_sequence, version_published_at, approval_request_id, approval_outcome, approval_outcome_at, approver_count, approved_count, has_veto_cast, requirement_readiness: {applicable_count, satisfied_count, partial_count, not_satisfied_count, unassessed_count, critical_unsatisfied_count, critical_unassessed_count}, review_ids[], completed_review_count }`.
  - `approval_request_ids[]` — flat array of unique approval-request UUIDs across items (indexed via reserved GIN — see §6).
- **Why.** Immutability by construction; single-row read; small (typical ≤ 8 KB per Freeze Index §6.2); no join tables required.
- **Freeze Index section:** §5.3, §6, §27.1, G-7.
- **Priority:** Critical (Evidence tab depends on it).
- **Blocks implementation?** Yes.

### 3.3 `public.releases.superseded_by_release_id uuid NULL`

- **Purpose.** Chain pointer to the release that supersedes this one. One release may be superseded at most once (§6.5 partial unique).
- **FK.** Composite `(superseded_by_release_id, project_id, workspace_id) → releases(id, project_id, workspace_id) ON DELETE RESTRICT`, reusing frozen `releases_id_project_workspace_key` (Migration 008 L108). Cross-project chains are structurally impossible.
- **Chain-init.** Populated inline at INSERT by the reserved `create_release_superseding` RPC (deferred; §14). In v1 the column exists but no shipping RPC writes it. Chain-immutability trigger (§9.1) blocks post-INSERT UPDATE.
- **Freeze Index section:** §5.3, §8, §27.1, G-9, G-10.
- **Priority:** High (schema + trigger + column ship in Wave 1; chain-init RPC deferred to Wave 4).
- **Blocks implementation?** No (v1 can ship without any writer, but the schema slot must exist so future waves do not require a re-freeze).

### 3.4 `public.releases.root_release_id uuid NULL`

- **Purpose.** Chain head pointer for O(1) chain-head lookup without walking backwards.
- **FK.** Composite `(root_release_id, project_id, workspace_id) → releases(id, project_id, workspace_id) ON DELETE RESTRICT`, reusing frozen `releases_id_project_workspace_key`.
- **Chain-init.** Set inline at INSERT time inside the `create_release_superseding` RPC per the APP 006 T-CRIT-1 discipline (see §0 Conventions and §9.1). NULL for chain heads; non-NULL for chain members (self-referencing for the chain root — that is, the root release row *may* be UPDATEd once to set `root_release_id = self.id`, but the trigger explicitly forbids this; instead, roots are identified by `root_release_id IS NULL` and the join walks accordingly. See §9.1 for the trigger contract.).
- **Semantic clarification.** Per Freeze Index §8.1 chain walk semantics, a release is considered a chain member iff `root_release_id IS NOT NULL`. Chain roots leave `root_release_id` NULL and are identified by "no row points to me via `superseded_by_release_id`". This preserves chain-init as a single INSERT+UPDATE pair inside `create_release_superseding` (the new release INSERTs with `root_release_id = coalesce(prior.root_release_id, prior.id)`; the prior release's `superseded_by_release_id` UPDATE fires exactly once via the trigger's `NULL → uuid` exception per §9.1; nothing else mutates).
- **Freeze Index section:** §5.3, §8, §27.1, G-9.
- **Priority:** High.
- **Blocks implementation?** No (schema slot only in v1).

### 3.5 `public.releases.published_by_profile_id uuid NULL`

- **Purpose.** Attribution of who invoked `publish_release` (or extended `finalize_release`), distinct from the frozen `created_by_profile_id` (creator of the draft). May differ when a lead publishes a draft another contributor composed.
- **FK.** `published_by_profile_id → profiles(id) ON DELETE SET NULL`. Mirrors frozen `created_by_profile_id` pattern (Migration 008 L84). Both may be NULL post-removal; product renders "Former member" (per APP 008 G-37 orphaned-originator posture; APP 009 §28 G-37).
- **Set by.** Extended `finalize_release` overload (§14.5) and `publish_release` wrapper (§14.4) — both set `published_by_profile_id = auth.uid()` at publish time.
- **Freeze Index section:** §5.3, §27.1, G-37.
- **Priority:** High (Release Detail header renders publisher).
- **Blocks implementation?** No (frontend falls back to `created_by_profile_id` when NULL per Freeze Index §5.4).

### 3.6 `public.releases.discarded_at timestamptz NULL`

- **Purpose.** Soft-discard timestamp for empty drafts (Freeze Index G-4 Option B). Preserves audit trail without introducing a DELETE RLS policy or losing history.
- **Set by.** `discard_release_draft` RPC (§14.6). Idempotent: repeated calls raise "release already discarded".
- **Interaction with filters.** All dashboard read RPCs default to excluding rows with `discarded_at IS NOT NULL` unless the caller passes `p_include_discarded boolean default false` (Wave 2).
- **Freeze Index section:** §5.3, §27.1, G-4.
- **Priority:** Medium (v1 works without soft-discard; drafts simply accumulate. But cheap to ship.).
- **Blocks implementation?** No.

### 3.7 `public.releases.code text NULL`

- **Purpose.** Per-project stable display code (format `R-NNN`) for deep-link resolution (`/deep/release/:code`) and human-readable identifiers throughout the UI.
- **Generation.** Server-computed at draft creation time inside `create_release_draft` (§14.1) using the advisory-lock pattern: `pg_advisory_xact_lock(hashtext('release_code:' || v_project_id::text))` → `SELECT coalesce(max((regexp_match(code,'R-([0-9]+)'))[1]::int),0) + 1 FROM public.releases WHERE project_id = v_project_id;` → `v_code := 'R-' || lpad(v_ordinal::text, 3, '0')`. Mirrors APP 008 `create_requirement` code generation.
- **Uniqueness.** Partial unique index `(project_id, code) WHERE code IS NOT NULL` (see §6). Pre-migration rows tolerated with NULL.
- **Immutability.** Not explicitly enforced by trigger; the code is set once at INSERT and never rewritten (RLS UPDATE would permit change, but no RPC does it). If future policy requires immutability, add a trigger check in a later re-freeze.
- **Freeze Index section:** §5.3, §15.4, §27.1, G-21, G-38.
- **Priority:** Critical (deep links depend on it).
- **Blocks implementation?** Yes.

### 3.8 Reserved-only columns (not shipped in Wave 1)

None. Every column enumerated in Freeze Index §27.1 ships in v1. Additional reserved-only columns proposed here for name-locking (defer to §20):

- Reserved-only names for future waves: `distribution_channels text[]` (release channels, Freeze Index §22.2), `scheduled_at timestamptz` (scheduled-publish, §3.2 reserved lifecycle), `recall_reason text` (recall variant, G-35), `template_id uuid` (from-template creation).

These are documented here for vocabulary stability. They are not added to the schema in Wave 1.

---

## 4. New constraints

Only one CHECK is added; every other invariant is enforced by trigger (§9) rather than by CHECK, because triggers can inspect other rows (chain uniqueness, evidence immutability by status, type immutability by status).

### 4.1 `releases_release_type_check`

- **Definition.** `CHECK (release_type IS NULL OR release_type IN ('internal','preview','client','regulatory','final','patch','hotfix'))`.
- **Why NULL-permissive.** Legacy rows (pre-migration) must load without violation; also, a draft may be created without a type set and typed later during composition.
- **Freeze Index section:** §9.1, §27.1, G-11.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 4.2 No frozen CHECK narrowed

Explicitly stated: frozen `releases_status_check` (5-value enum `'draft','scheduled','released','superseded','withdrawn'`) is preserved byte-identically. Reserved values `scheduled` and `superseded` remain in the CHECK but are not exercised in v1 per Freeze Index §3.2 / G-1. Frozen `releases_released_metadata_check` and `releases_withdrawn_metadata_check` are unchanged.

### 4.3 No new UNIQUE constraints

The uniqueness invariants added by this proposal are all partial (project-scoped `code` uniqueness, single-parent chain-uniqueness), best expressed as partial unique indexes (§6) rather than table-level UNIQUE constraints.

### 4.4 No frozen composite anchor unique changed

Frozen `releases_id_project_workspace_key (id, project_id, workspace_id)` and `releases_id_workspace_key (id, workspace_id)` are preserved. The new chain FKs reuse `releases_id_project_workspace_key` verbatim.

---

## 5. New foreign keys

Three new FKs. All are composite where semantically meaningful. Both chain FKs are subject to the chain-init discipline (§0 Conventions and §9.1).

### 5.1 `releases_superseded_by_fk` — composite self-FK

- **Definition.** `FOREIGN KEY (superseded_by_release_id, project_id, workspace_id) REFERENCES public.releases (id, project_id, workspace_id) ON DELETE RESTRICT`. `ON DELETE RESTRICT` remains in force so a released row cannot be deleted while another release points to it.
- **Why composite.** Enforces "the release that supersedes me lives in my same project and workspace" — cross-project chains are structurally impossible.
- **Reuses.** Frozen `releases_id_project_workspace_key` anchor unique (Migration 008 L108).
- **Chain column — chain-init discipline applies.** Any RPC that populates this column must UPDATE the prior release with `superseded_by_release_id = v_new_id` in the same transaction that INSERTs the new release (§0 Conventions and §14.9). The `enforce_release_chain_immutable` trigger (§9.1) permits this initial `NULL → uuid` transition **exactly once** per row and rejects every subsequent change (`uuid → uuid` or `uuid → NULL`). No shipping RPC writes this column in v1 (Wave 4 reserved).
- **Freeze Index section:** §5.3, §8, §27.1, G-9.
- **Priority:** High (schema ships in Wave 1; writer deferred).
- **Blocks implementation?** No.

### 5.2 `releases_root_release_fk` — composite self-FK

- **Definition.** `FOREIGN KEY (root_release_id, project_id, workspace_id) REFERENCES public.releases (id, project_id, workspace_id) ON DELETE RESTRICT`. `ON DELETE RESTRICT` prevents deletion of a chain root while any member still points to it.
- **Why composite.** Same rationale: cross-project chains impossible.
- **Reuses.** Frozen `releases_id_project_workspace_key`.
- **Chain column — fully immutable after INSERT.** Set inline at INSERT of the superseding release via the APP 006 T-CRIT-1 pre-compute-UUID discipline. The chain-immutability trigger (§9.1) rejects **any** change to `root_release_id` (`NULL → uuid`, `uuid → uuid`, `uuid → NULL`). A NULL → self UPDATE attempt to "convert" an existing chain root to a member is forbidden and raises `23514`. This matches APP 006 T-CRIT-1 remediation verbatim.
- **Freeze Index section:** §5.3, §8, §27.1, G-9.
- **Priority:** High.
- **Blocks implementation?** No.

### 5.3 `releases_published_by_profile_fk`

- **Definition.** `FOREIGN KEY (published_by_profile_id) REFERENCES public.profiles (id) ON DELETE SET NULL`.
- **Why non-composite.** Mirrors the frozen `created_by_profile_id → profiles(id) ON DELETE SET NULL` pattern (Migration 008 L84). Profiles are workspace-transcendent; no composite scope applies.
- **Freeze Index section:** §5.3, §27.1, G-37.
- **Priority:** High.
- **Blocks implementation?** No.

### 5.4 No FK on `discarded_at`, `code`, `release_type`, `evidence_snapshot`

These columns are scalar or JSON; no FK applies. `release_type` is enum-CHECKed (§4.1). `evidence_snapshot` contains pointer UUIDs but they are not enforced as FKs (would require snapshot rewrites when upstream rows are deleted — contradicts immutability guarantee per Freeze Index §6.3).

---

## 6. New indexes

Seven indexes. Every new FK gets a covering index; every dashboard-supporting filter gets a partial or full index. GIN on `evidence_snapshot` is proposed as Future (not v1) per Freeze Index §27.7.

| # | Index | Table | Definition | Purpose | Priority |
|---|---|---|---|---|---|
| I-1 | `releases_project_release_type_released_idx` | `releases` | `(project_id, release_type, released_at desc)` | Type-filtered released list; primary dashboard scan for "released `client` in Q1" style filters. | Critical |
| I-2 | `releases_project_published_by_released_idx` | `releases` | `(project_id, published_by_profile_id, released_at desc) WHERE published_by_profile_id IS NOT NULL` | "Published by me" view; personal-scope dashboard. | High |
| I-3 | `releases_project_code_unique_idx` | `releases` | `UNIQUE (project_id, code) WHERE code IS NOT NULL` | Deep-link resolver (`/deep/release/:code`) + code uniqueness per project. | Critical |
| I-4 | `releases_root_release_idx` | `releases` | `(root_release_id) WHERE root_release_id IS NOT NULL` | Chain-head lookup: "give me all releases in this chain". | High |
| I-5 | `releases_superseded_by_unique_idx` | `releases` | `UNIQUE (superseded_by_release_id) WHERE superseded_by_release_id IS NOT NULL` | Chain uniqueness invariant per G-10 — at most one release may supersede a given release. | High |
| I-6 | `releases_project_discarded_at_idx` | `releases` | `(project_id, discarded_at) WHERE discarded_at IS NOT NULL` | Discarded-drafts view (rare); supports "restore discarded" if future policy allows. | Medium |
| I-7 | `releases_project_release_type_status_idx` | `releases` | `(project_id, release_type, status)` | Metrics strip: "count releases by type × status" for the per-project metrics RPC. | Medium |

**Reserved (deferred):**

- **I-R1** `releases_evidence_snapshot_gin_idx` — `USING gin ((evidence_snapshot -> 'approval_request_ids'))`. Reverse lookup: "does any release cite this approval?" Deferred to v1.1 (per Freeze Index §27.7) — v1 needs are covered by direct joins from `evidence_snapshot -> 'items'`.

Reused frozen indexes (no change; enumerated for completeness):

- `releases_project_workspace_idx (project_id, workspace_id)` — Migration 008 L120–L121.
- `releases_created_by_profile_id_idx (created_by_profile_id) WHERE created_by_profile_id IS NOT NULL` — Migration 008 L123–L125.
- `releases_project_status_released_idx (project_id, status, released_at desc)` — Migration 008 L128–L129.
- `releases_workspace_status_idx (workspace_id, status)` — Migration 008 L131–L132.
- `release_items_release_project_workspace_idx`, `release_items_version_project_idx`, `release_items_version_asset_idx` — Migration 008 L191–L198.

**Coverage rule.** Every new FK has a matching covering btree index:

- FK `releases_superseded_by_fk (superseded_by_release_id, project_id, workspace_id)` → covered by I-5 on `superseded_by_release_id` (unique + partial); the composite target uniqueness is enforced by the frozen `releases_id_project_workspace_key`, not by the covering index.
- FK `releases_root_release_fk (root_release_id, project_id, workspace_id)` → covered by I-4 on `root_release_id` (partial).
- FK `releases_published_by_profile_fk (published_by_profile_id)` → covered by I-2 leading column (partial).

- **Why (index count).** Matches Freeze Index §27.7's ~5 additive index estimate expanded to 7 with the discarded-drafts and per-type-status support indexes.
- **Freeze Index section:** §17, §27.7.
- **Priority per row.** Enumerated above.
- **Blocks implementation?** Critical rows yes; others no.

---

## 7. RLS impact

**Zero changes to frozen table RLS.** Every extension is delivered under the existing frozen policies documented in AUTH 008 L217–L296.

### 7.1 Frozen policies preserved byte-identically

- `releases_select` — SELECT gated by `lign_has_capability(project_id, workspace_id, 'release.view')`. AUTH 008 L217–L220.
- `releases_insert` — INSERT gated by `release.create` + `created_by_profile_id = (select auth.uid())` + `status = 'draft'`. AUTH 008 L222–L229.
- `releases_update` — UPDATE gated by `release.create`. AUTH 008 L235–L239. Immutability of `id`/`workspace_id`/`project_id`/`created_by_profile_id`/`status`/`released_at`/`withdrawn_at`/`withdrawn_reason` is enforced by the frozen `enforce_release_status_via_rpc` trigger; RLS is deliberately loose because the trigger is authoritative.
- No DELETE policy on `releases`.
- `release_items_select` / `_insert` / `_update` / `_delete` — all gated by parent's `release.view` / `release.create`, with the frozen `enforce_release_items_parent_draft_mutation` trigger enforcing draft-time-only mutation. AUTH 008 L247–L296.

### 7.2 New columns are covered by existing SELECT policy

The 7 additive columns (`release_type`, `evidence_snapshot`, `superseded_by_release_id`, `root_release_id`, `published_by_profile_id`, `discarded_at`, `code`) are columns on `public.releases` and are governed by `releases_select`. No new SELECT policy required. This mirrors the APP 008 §10.4 pattern for `requirements` additive columns.

### 7.3 New columns are covered by existing UPDATE policy (with trigger-level immutability)

`releases_update` permits UPDATE on any release column granted the caller has `release.create`. Immutability of the new columns after certain lifecycle points is enforced by the three new triggers (§9), not by RLS. This mirrors the frozen pattern for `status`/`released_at` — RLS is loose, triggers are authoritative.

### 7.4 Write RPCs run as SECURITY DEFINER and bypass write RLS

All new write RPCs (§14) use `SECURITY DEFINER` with `SET search_path = ''`. They re-check `lign_has_capability` inline in the function body before mutating. This matches the frozen `finalize_release` / `withdraw_release` pattern (AUTH 008 L114 / L184).

### 7.5 No new tables → no new RLS surface

Zero new tables (§2) means zero new RLS policies. If any of the reserved tables (§2) is added in a future re-freeze, it will require its own SELECT/INSERT/UPDATE/DELETE policies gated on the appropriate capability (e.g., `release.audit_export` for `release_audit_exports`).

### 7.6 No DELETE policy proposed in v1

Per Freeze Index G-4 (Option B chosen), soft-discard via `discarded_at` replaces hard-delete. Freeze Index §27.9 Option A (creator-only + status='draft' + zero-items DELETE policy) is explicitly not adopted. Rationale: preserves audit trail; matches APP 008 archive-not-delete posture.

### 7.7 No frozen policy weakened

Explicit statement: `releases_select`, `releases_insert`, `releases_update`, `release_items_select`, `release_items_insert`, `release_items_update`, `release_items_delete` are byte-identical to the AUTH 008 definitions. This proposal does not `DROP POLICY` any of them, nor does it `CREATE POLICY … OR REPLACE` any of them.

---

## 8. RPC surface — narrative overview

APP 009's RPC surface splits into three groups:

1. **Read RPCs (13 new).** Every read RPC is `SECURITY DEFINER`, `SET search_path = ''`, `REVOKE` from public/anon, `GRANT EXECUTE` to `authenticated, service_role`, and gates on `release.view` (via `lign_has_capability(project_id, workspace_id, 'release.view')`). Every read either returns `jsonb` (single-row detail, metrics) or `setof` (dashboard, activity, item list). Cursor pagination on set-returning RPCs uses `(released_at DESC NULLS LAST, id DESC)` as the server-opaque tuple (§15).
2. **Write RPCs (6 new + 2 frozen extended via `CREATE OR REPLACE`).** New write RPCs cover draft composition (`create_release_draft`, `add_release_item`, `remove_release_item`, `reorder_release_items`, `discard_release_draft`, `edit_release_metadata`, `publish_release`). Frozen `finalize_release(uuid)` is extended in place via `CREATE OR REPLACE FUNCTION public.finalize_release(p_release_id uuid, p_release_type text default null)` per Freeze Index §27.4. Frozen `withdraw_release(uuid, text)` is extended in place via `CREATE OR REPLACE FUNCTION public.withdraw_release(p_release_id uuid, p_reason text, p_admin_override boolean default false)`. Both extensions use single-function default-tail params (no dual overloads); the frozen positional call sites and any named-argument callers of the frozen parameters continue to work unchanged. Every write RPC re-checks capability inline, sets `lign.allow_release_status_write = 'true'` transaction-local *only if it needs to change status* (frozen invariant), and emits exactly one canonical event per successful mutation.
3. **Reserved RPCs (3 name-only).** `schedule_release`, `create_release_superseding`, `export_release_audit` — reserved for Wave 4. Not implemented in v1.

**Chain-init discipline (§0 Conventions and §9.1).** Any RPC that creates a release with a non-NULL chain column pre-computes `release.id` via `gen_random_uuid()`, INSERTs with chain columns set inline, and does not post-INSERT-UPDATE either chain column. Post-INSERT UPDATE is blocked by the `enforce_release_chain_immutable` trigger (§9.1) — a NULL → self UPDATE raises. This is repeated in each affected RPC description (§14.9).

**Option A discipline for frozen write RPC extensions.** Both frozen `finalize_release(uuid)` and `withdraw_release(uuid, text)` continue to compile and execute unchanged. Extensions are delivered via `CREATE OR REPLACE FUNCTION` on the single frozen function with default-tail parameters — **not** as separate overloads. Dual overloads would trigger `function is not unique` under named-argument resolution (both signatures would match the default-filled call). Single-function `CREATE OR REPLACE` with default-tail params is the APP 008 §9.1 / §9.2 pattern (`create_requirement`-15-arg, `edit_requirement`-13-arg); this proposal follows it verbatim.

**Reserved RPC name patterns for future waves.**

- `schedule_release(release_id, effective_at)` — Freeze Index §27.4 reserved.
- `create_release_superseding(prior_release_id, name, notes, channel, release_type)` — Freeze Index §27.4 reserved; chain-init discipline applies when wired.
- `export_release_audit(release_id, format text)` — Freeze Index §27.4, §25.5, G-31, G-44 reserved.

---

## 9. Trigger surface

Three defense-in-depth triggers on `public.releases`. All are `SECURITY DEFINER`, `SET search_path = ''`, and are `REVOKE`d from `public` / `anon` / `authenticated` with no `GRANT` (trigger functions fire under the row-writer's transaction context and never need `EXECUTE`).

### 9.1 `enforce_release_chain_immutable` — BEFORE UPDATE

- **Purpose.** Enforces the asymmetric write-once contract for the two chain columns on `public.releases`. Chain integrity is preserved (both columns effectively write-once) while the supersede RPC remains implementable.
- **Invariants (exact predicate logic).** For each row-level BEFORE UPDATE:
  1. **`root_release_id`: fully immutable after INSERT.** Raise `23514` if `NEW.root_release_id IS DISTINCT FROM OLD.root_release_id`. Every transition is rejected — `NULL → uuid`, `uuid → uuid`, and `uuid → NULL`. In particular, a `NULL → self` UPDATE attempting to "convert" an existing chain root to a member is rejected. The value must be set inline at INSERT via the APP 006 T-CRIT-1 pre-compute-UUID discipline.
  2. **`superseded_by_release_id`: exactly-once initialization.** Permit `OLD.superseded_by_release_id IS NULL AND NEW.superseded_by_release_id IS NOT NULL` (initial supersession pointer write on the prior release, driven by `create_release_superseding` step 5). Raise `23514` for `OLD IS NOT NULL AND NEW IS NOT NULL AND NEW IS DISTINCT FROM OLD` (change of an already-set pointer) and for `OLD IS NOT NULL AND NEW IS NULL` (clearing an already-set pointer).
- **Why asymmetric.** `root_release_id` is deterministic at INSERT (computed as `coalesce(prior.root_release_id, prior.id)` when creating a superseding release; NULL for chain roots) — no legitimate post-INSERT write exists. `superseded_by_release_id`, by contrast, is set on the *prior* release after the new release row exists; this is a single legitimate `NULL → uuid` write per prior release, and the reserved `create_release_superseding` RPC (§14.9) is unimplementable without permitting exactly that transition.
- **Chain-init statement.** The RPC layer pre-computes `release.id` via `gen_random_uuid()` and INSERTs with `root_release_id` set inline (NULL for chain roots by convention; `coalesce(prior.root_release_id, prior.id)` for supersessions). The new row's `superseded_by_release_id` is INSERTed as NULL. On the *prior* release, `superseded_by_release_id` transitions `NULL → v_new_id` exactly once via step 5 of `create_release_superseding` (§14.9); this transition is the sole permitted write of the column. This matches APP 006 T-CRIT-1 remediation verbatim while making the supersede RPC implementable.
- **Interaction with `enforce_release_status_via_rpc`.** The two triggers coexist. The frozen status-via-rpc trigger blocks status/id/workspace/project/created_by changes; the chain-immutability trigger governs the two chain columns. They fire independently.
- **Row-local read only.** The trigger function inspects only OLD/NEW columns of the trigger's own row; no cross-table read is required. Therefore it is **NOT** `SECURITY DEFINER` — this matches the frozen `enforce_release_status_via_rpc` non-DEFINER precedent (`supabase/migrations/20260801220000_auth_008_release_rls.sql` L38).
- **Attributes.** `language plpgsql`, `set search_path = ''`, not `security definer`.
- **Grants.** `REVOKE ALL FROM public, anon, authenticated`. No `GRANT`.
- **Freeze Index section:** §8.3, §27.8, G-9, G-10.
- **Priority:** High (ships in Wave 1; chain writer deferred but trigger must exist so the contract is authoritative if the writer is ever added).
- **Blocks implementation?** No.

### 9.2 `enforce_release_evidence_immutable` — BEFORE UPDATE

- **Purpose.** Once `evidence_snapshot` is written for a release in `released` or `withdrawn` status, it cannot be mutated. Preserves the Freeze Index §6.3 immutability guarantee against RLS-layer UPDATE bypass.
- **Behavior.** Raises `23514` if `NEW.evidence_snapshot IS DISTINCT FROM OLD.evidence_snapshot` AND `OLD.status IN ('released','withdrawn')`. While the release is `draft`, `evidence_snapshot` mutation is permitted (in practice the snapshot is written exactly once, inside the publish transaction, before status flips to `released`).
- **Interaction with publish.** `publish_release` and the extended `finalize_release` write `evidence_snapshot` in the same transaction that flips `status = 'released'`. The trigger's OLD row at UPDATE time still has `status = 'draft'` and `OLD.evidence_snapshot IS NULL`, so the `NULL → jsonb` write is permitted. Any subsequent UPDATE (e.g., admin fat-finger) is rejected because `OLD.status` is then `released` or `withdrawn`.
- **Row-local read only.** The trigger inspects only OLD/NEW columns of its own row; no cross-table read requires bypassing caller RLS. Therefore it is **NOT** `SECURITY DEFINER` — matches the frozen `enforce_release_status_via_rpc` non-DEFINER precedent (`supabase/migrations/20260801220000_auth_008_release_rls.sql` L38).
- **Attributes.** `language plpgsql`, `set search_path = ''`, not `security definer`.
- **Grants.** `REVOKE ALL FROM public, anon, authenticated`. No `GRANT`.
- **Freeze Index section:** §6.3, §27.8.
- **Priority:** Critical (evidence must never rewrite silently).
- **Blocks implementation?** Yes.

### 9.3 `enforce_release_type_immutable_when_released` — BEFORE UPDATE

- **Purpose.** Once `status = 'released'`, `release_type` becomes immutable per Freeze Index §9.7. During `draft`, the composer may change `release_type` freely (subject to `release.create` capability at RLS).
- **Behavior.** Raises `23514` if `NEW.release_type IS DISTINCT FROM OLD.release_type` AND `OLD.status IN ('released','withdrawn')`.
- **Rationale.** A released release's evidence bundle was assembled per the type policy in effect at publish time; retroactively re-typing it would break the per-type policy invariant.
- **Row-local read only.** The trigger inspects only OLD/NEW columns of its own row; no cross-table read requires bypassing caller RLS. Therefore it is **NOT** `SECURITY DEFINER` — matches the frozen `enforce_release_status_via_rpc` non-DEFINER precedent (`supabase/migrations/20260801220000_auth_008_release_rls.sql` L38).
- **Attributes.** `language plpgsql`, `set search_path = ''`, not `security definer`.
- **Grants.** `REVOKE ALL FROM public, anon, authenticated`. No `GRANT`.
- **Freeze Index section:** §9.7, §27.8.
- **Priority:** High.
- **Blocks implementation?** No (product surface hides the edit UI post-release per Freeze Index G-2, so the trigger is defense-in-depth only).

### 9.4 Frozen triggers preserved unchanged

Explicitly cited to underscore the additive-only guarantee:

- `enforce_release_finalization_prerequisites_insert` / `_update` — Migration 008 L336–L344. Universally requires ≥ 1 item + every-item-approved on transition to `released`. Never loosened by APP 009. Freeze Index §27.10.
- `enforce_release_items_parent_draft_mutation` — Migration 008 L255–L258. Rejects item mutation while parent is not `draft`. Never loosened.
- `enforce_release_status_via_rpc` — AUTH 008 L73–L76. RPC-only status writes gated by `lign.allow_release_status_write` GUC + immutability of `id`/`workspace_id`/`project_id`/`created_by_profile_id`. Never loosened.
- `releases_set_updated_at` (Migration 008 L134–L137), `release_items_set_updated_at` (L200–L203) — standard timestamp maintenance.

### 9.5 Publisher-must-not-approve separation-of-duties trigger — NOT PROPOSED

The Freeze Index does not require publisher/approver separation of duties. `finalize_release` does not check the caller against the approvers list. This aligns with the frozen governance surface: `release.finalize` is a `lead`-only capability (per Freeze Index §19.2 default role map) and represents the authoritative publish action; the approval step is upstream. Adding SoD would require a re-freeze; explicitly not proposed here.

---

## 10. Capability additions

**Zero new capability keys wired in v1.** The 4 frozen keys (`release.view`, `release.create`, `release.finalize`, `release.withdraw`) cover every product action per Freeze Index §19.3 / G-24. No proposal modifies the frozen role map (Freeze Index §19.2):

| Capability | `lead` | `contributor` | `reviewer` | `approver` | `observer` | Workspace admin |
|---|---|---|---|---|---|---|
| `release.view` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (override) |
| `release.create` | ✓ | ✓ | — | — | — | — |
| `release.finalize` | ✓ | — | — | — | — | — |
| `release.withdraw` | ✓ | — | — | — | — | — |

### 10.1 Reserved-only capability keys (name-locked; zero role grants)

Registered in PERMISSIONS.md §2.12 by string only. `lign_has_capability(project_id, workspace_id, 'release.schedule')` returns `false` for every caller in v1 (no grant). AUTH extension migration (§16 Migration B) enumerates them as reserved values in the capability catalog so that PERMISSIONS.md and the runtime constant table stay in sync; the role map contains no row for any of these keys.

| # | Capability | Purpose | Wave |
|---|---|---|---|
| C-R1 | `release.schedule` | Gate for future `schedule_release(release_id, effective_at)` RPC transitioning `draft → scheduled` (Freeze Index §3.2). | Future |
| C-R2 | `release.supersede` | Gate for future `create_release_superseding(prior_release_id, ...)` RPC that chains a new release from a prior one (Freeze Index §8.2). | Future |
| C-R3 | `release.ai_suggest` | Reserved for AI-assisted release-notes generation + comparison-narrative (Freeze Index §21). | Future |
| C-R4 | `release.ai_classify` | Reserved for AI-assisted `release_type` classification (Freeze Index §21). | Future |
| C-R5 | `release.audit_export` | Reserved for PDF/CSV export of the evidence bundle (Freeze Index §25.5, G-44). | Future |
| C-R6 | `release.recall` | Reserved for the recall variant of withdrawal — distinct from `withdraw` for audit tone + notification fan-out (Freeze Index G-35). | Future |

**Extend-before-duplicate rule (PERMISSIONS.md).** Every reserved key uses the frozen `release.*` prefix rather than introducing a parallel subject. `release.recall` is deliberately distinct from `release.withdraw` (not an overload) because it carries a stronger notification fan-out and audit-tone semantics per G-35; the two capabilities may be granted independently in a future re-freeze.

- **Why (reserved-only in v1).** The Freeze Index §27.5 explicitly ships zero new wired capabilities. Locking the names now prevents rename churn when future waves activate them.
- **Freeze Index section:** §19.3, §21, §27.5, G-24, G-27, G-35.
- **Priority:** Future (all).
- **Blocks implementation?** No.

---

## 11. Event payload extensions

Five frozen events (`release.created`, `release.item_added`, `release.item_removed`, `release.finalized`, `release.withdrawn`) each gain **[additive]** payload keys. Consumers ignore unknown keys per the APP 007 §17.1 precedent. No key is removed; no key is renamed; no `event_type` string is changed.

### 11.1 `release.created`

Emitted by **[additive]** `create_release_draft` RPC (§14.1). The event *name* is frozen (EVENT_MODEL.md §4.12 L185) but the emitter is new in APP 009. Payload:

- **Frozen keys:** `{name}`.
- **[additive] keys:** `release_type`, `code`, `created_by_profile_id`, `channel` (if set at draft creation).

Backwards-compat: consumers that only read `name` continue to work.

### 11.2 `release.item_added`

Emitted by **[additive]** `add_release_item` RPC (§14.2). Payload:

- **Frozen keys:** `{release_id, asset_id, asset_name, version_id, version_sequence}`.
- **[additive] keys:** `release_type` (parent release's type at add time), `item_id` (the new `release_items.id`), `sort_order`, `notes_snippet` (first 200 chars of item notes if any).

### 11.3 `release.item_removed`

Emitted by **[additive]** `remove_release_item` RPC (§14.3). Payload:

- **Frozen keys:** `{release_id, asset_id, version_id}`.
- **[additive] keys:** `release_type`, `item_id` (the removed `release_items.id`).

### 11.4 `release.finalized`

Emitted by the `CREATE OR REPLACE`-extended `finalize_release` (§14.5; frozen positional 1-arg call binds unchanged) AND by the **[additive]** `publish_release` wrapper (§14.4). Both emitters use the same event name and preserve every frozen key. Payload:

- **Frozen keys:** `{name, item_count, channel}`.
- **[additive] keys:** `release_type`, `published_by_profile_id`, `approved_request_ids[]` (from evidence snapshot), `requirement_readiness` (aggregate from evidence snapshot: `{applicable_count, satisfied_count, partial_count, not_satisfied_count, unassessed_count, critical_unsatisfied_count, critical_unassessed_count}` summed across items), `review_count` (completed reviews across items), `superseded_prior_release_id` (populated only if the release was created via chain — Wave 4 only; NULL in v1).

Backwards-compat: existing consumers reading `{name, item_count, channel}` continue to work. New consumers may read the enriched keys.

### 11.5 `release.withdrawn`

Emitted by the `CREATE OR REPLACE`-extended `withdraw_release` (§14.8; frozen positional 2-arg call binds unchanged). Payload:

- **Frozen keys:** `{reason}`.
- **[additive] keys:** `release_type`, `withdrawn_by_profile_id` (= `auth.uid()` at withdraw time — new; the frozen RPC does not currently capture this in the snapshot), `admin_override` (mirrors the `p_admin_override` tail param).

Note: `p_admin_override boolean default false` on the extended function does NOT flip the event name to `release.recalled` in v1. `release.recalled` is reserved-only (§12.5); flipping the emitter is a Wave 4 concern once the recall UX and notification fan-out are wired.

### 11.6 Backwards-compat statement

- Every frozen key on every frozen event is preserved byte-for-byte.
- Every additive key is nullable in the JSON snapshot (may be absent for pre-migration rows or for RPCs invoked in the frozen non-extended form).
- No event type string is changed.
- No `subject_kind` is changed (`release` for release-scoped events; `release_item` for item-scoped events per Freeze Index §20.3).
- No `subject_id` semantic is changed.

---

## 12. Event vocabulary

**Zero new emitted event types in Wave 1.** The 5 frozen events cover every state transition per Freeze Index §27.6. The three frozen events with previously-unshipped emitters (`release.created`, `release.item_added`, `release.item_removed`) receive their emitters here (§14) — the *names* were already frozen in EVENT_MODEL.md §4.12 L185–L187.

### 12.1 Frozen event vocabulary (preserved)

| Event | Emitter in v1 | Freeze Index |
|---|---|---|
| `release.created` | **[additive]** `create_release_draft` (§14.1) — name frozen in EVENT_MODEL.md L185 | §20.1 |
| `release.item_added` | **[additive]** `add_release_item` (§14.2) — name frozen in EVENT_MODEL.md L186 | §20.1 |
| `release.item_removed` | **[additive]** `remove_release_item` (§14.3) — name frozen in EVENT_MODEL.md L187 | §20.1 |
| `release.finalized` | `CREATE OR REPLACE`-extended `finalize_release` (§14.5; frozen positional 1-arg call binds unchanged) + `publish_release` wrapper (§14.4) | §20.1 |
| `release.withdrawn` | `CREATE OR REPLACE`-extended `withdraw_release` (§14.8; frozen positional 2-arg call binds unchanged) | §20.1 |

### 12.2 Reserved event names (name-locked by this proposal; no emitter in APP 009)

The following event names are **reserved by this proposal** and will be registered in `EVENT_MODEL.md` in the Wave 1 documentation diff that accompanies Migration A. Until that registration lands, no emitter is defined; the names are name-locked here for future waves and will not be used by APP 009. Per RESERVED discipline: every name is past-tense, `subject_kind = 'release'` for release-scoped events (`subject_kind = 'release_item'` where applicable), and zero emitters exist in APP 009's migrations.

Of the seven names below, two (`release.scheduled`, `release.superseded`) already appear in EVENT_MODEL.md as MVP-removed reservations (§D3, §D7 of EVENT_MODEL.md); the Wave 1 doc-diff reaffirms them and their reserved payload shape. The remaining five (`release.notes_updated`, `release.audit_exported`, `release.recalled`, `release.ai_suggested`, `release.ai_classified`) are **not yet present** in EVENT_MODEL.md and are introduced as name-only reservations by the Wave 1 doc-diff.

| # | Event | Purpose (future) | Wave | Registration status |
|---|---|---|---|---|
| E-R1 | `release.scheduled` | Reserved for future scheduled-publish workflow (§3.2). | Future | Present in EVENT_MODEL.md §D3 as MVP-removed; Wave 1 doc-diff reaffirms. |
| E-R2 | `release.superseded` | Reserved for automatic release supersession (§3.2, §8.4). | Future | Present in EVENT_MODEL.md §D7 as MVP-removed; Wave 1 doc-diff reaffirms. |
| E-R3 | `release.notes_updated` | Reserved for post-release note edits (§10.3 Notes tab v2). | Future | New reservation added by Wave 1 doc-diff. |
| E-R4 | `release.audit_exported` | Reserved for PDF/CSV export of evidence (Freeze Index §25.5). | Future | New reservation added by Wave 1 doc-diff. |
| E-R5 | `release.recalled` | Reserved for the recall variant of withdrawal (G-35). | Future | New reservation added by Wave 1 doc-diff. |
| E-R6 | `release.ai_suggested` | Reserved for AI-assisted release-notes generation. | Future | New reservation added by Wave 1 doc-diff. |
| E-R7 | `release.ai_classified` | Reserved for AI-assisted `release_type` classification. | Future | New reservation added by Wave 1 doc-diff. |

**Vocabulary lock is real from Wave 1.** The EVENT_MODEL.md doc-diff registering all seven names lands in Wave 1 alongside Migration A, so downstream waves and slices can bind to fixed strings immediately. No emitter, no fan-out entry, no payload shape enforcement is added in APP 009 — only the name lock.

### 12.3 Past-tense discipline

All event names use past-tense verbs: `created`, `added`, `removed`, `finalized`, `withdrawn`, `scheduled`, `superseded`, `notes_updated`, `audit_exported`, `recalled`, `ai_suggested`, `ai_classified`. Every reserved name conforms.

### 12.4 No metadata-edit event in v1

Per Freeze Index G-26, no event fires on `draft`-time metadata edits (name/notes/channel/effective_at/release_type UPDATE). Rationale: drafts are ephemeral; per-field diff events would overwhelm the activity feed. Post-release note edits (if that policy ever loosens) would fire `release.notes_updated`.

### 12.5 `p_admin_override` does not flip the event in v1

The `CREATE OR REPLACE`-extended `withdraw_release(uuid, text, boolean)` accepts `p_admin_override boolean default false` for forward compatibility. In v1 the emitter always fires `release.withdrawn` regardless of `p_admin_override`. Wave 4 will introduce a distinct code path that fires `release.recalled` when `p_admin_override = true` (or under a purpose-built recall RPC). Locking the argument shape now avoids a re-freeze of the RPC signature later.

### 12.6 Event fan-out

Per Freeze Index §20.7 and EVENT_MODEL.md §12:

- Project-level release events (`release.finalized`, `release.withdrawn`) fan out to workspace `owner`/`admin` and active `project_participants` of that project.
- Draft-time events (`release.created`, `release.item_added`, `release.item_removed`) are audit-only per EVENT_MODEL.md §11; no notification fan-out.

APP 010 (Notifications) implements the fan-out. APP 009 emits only.

---

## 13. Read RPCs

Thirteen new read RPCs. Every one is `SECURITY DEFINER`, `SET search_path = ''`, `REVOKE`d from `public`/`anon`, `GRANT EXECUTE` to `authenticated, service_role`, and gates on `release.view` via `lign_has_capability(project_id, workspace_id, 'release.view')` for the resolved scope. Every set-returning RPC uses cursor pagination on `(released_at DESC NULLS LAST, id DESC)` (§15).

### 13.1 `get_release(p_release_id uuid) → jsonb`

- **Purpose.** Release Detail read: metadata + item summary + chain position + evidence summary (not the full snapshot — see §13.4 for that).
- **Return shape.** `{ id, workspace_id, project_id, name, notes, channel, release_type, status, code, effective_at, released_at, withdrawn_at, withdrawn_reason, created_by_profile_id, published_by_profile_id, created_at, updated_at, discarded_at, superseded_by_release_id, root_release_id, item_count, chain_length, chain_position }`.
- **Capability check.** `release.view` on `(project_id, workspace_id)` resolved from the release row.
- **Freeze Index section:** §10, §27.3.
- **Priority:** Critical.
- **Blocks implementation?** Yes (Release Detail page cannot render).

### 13.2 `get_release_by_code(p_project_id uuid, p_ws_id uuid, p_code text) → jsonb`

- **Purpose.** Deep-link resolver for `/deep/release/:code`. Returns the same shape as §13.1 or `null` if the code is not found in the project.
- **Uniqueness backing.** Index I-3 (`releases_project_code_unique_idx`).
- **Capability check.** `release.view` on `(p_project_id, p_ws_id)`.
- **Freeze Index section:** §15.1, §16.3, §27.3, G-20.
- **Priority:** Critical.
- **Blocks implementation?** Yes (deep links).

### 13.3 `get_release_chain(p_release_id uuid) → jsonb`

- **Purpose.** Supersession chain (root → head). Returns ordered array of per-node metadata: `{ release_id, code, name, release_type, status, released_at, withdrawn_at, is_root, is_head }`.
- **Algorithm.** Walk from the given release's `root_release_id` (or the release itself if it is a root, i.e., `root_release_id IS NULL AND no other row points to me via superseded_by`), then follow `superseded_by_release_id` forward until NULL.
- **Capability check.** `release.view` on `(project_id, workspace_id)` resolved from the release row.
- **Freeze Index section:** §8, §8.6, §27.3.
- **Priority:** High (Wave 4 chain writer means chains are usually singletons in v1, but the RPC ships in Wave 2 so the UI never crashes).
- **Blocks implementation?** No.

### 13.4 `get_release_evidence(p_release_id uuid) → jsonb`

- **Purpose.** Evidence tab bundle: returns the frozen `evidence_snapshot` verbatim plus a side-by-side "current-state" delta computed live for each snapshotted approval / requirement / review.
- **Return shape.** `{ snapshot: <full evidence_snapshot jsonb>, live_delta: { items: [ { release_item_id, approval_current: {status, outcome_at}, requirement_delta: {satisfied_delta, critical_unsatisfied_delta, ...}, review_current: {status} } ] }, has_deltas: boolean }`.
- **Live delta source.** Cross-slice reads: APP 007 `get_approval_readiness(version_id)` per item; APP 008 `get_release_readiness_for_version(version_id)` per item; direct SELECT on `reviews` per snapshotted `review_ids[]`.
- **Empty-state handling.** If `evidence_snapshot IS NULL`, returns `{ snapshot: null, live_delta: <full live computation as if publishing now>, has_deltas: false }` with the "live re-compute" flag set (Freeze Index §5.4 fallback rendering).
- **Capability check.** `release.view` on release + implicit `approval.view` / `requirement.view` on same project (all project participants hold these by default per PERMISSIONS.md).
- **Freeze Index section:** §6, §27.3.
- **Priority:** Critical (Evidence tab).
- **Blocks implementation?** Yes.

### 13.5 `get_release_comparison(p_release_id uuid, p_compare_to_release_id uuid default null) → jsonb`

- **Purpose.** Comparison vs. a prior release in the chain (or arbitrary release per caller choice). If `p_compare_to_release_id IS NULL`, defaults to walking one step back in the chain via `superseded_by_release_id` reverse-lookup.
- **Return shape.** `{ this_release: <get_release shape>, compare_to: <get_release shape or null>, item_diff: { added: [ {version_id, asset_name, ...} ], removed: [...], changed_version: [ {asset_id, this_version_id, compare_version_id} ] }, approval_diff: {this_count, compare_count}, requirement_readiness_diff: {satisfied_delta, ...} }`.
- **Capability check.** `release.view` on both releases (must be same project).
- **Freeze Index section:** §10.3 Comparison tab, §27.3.
- **Priority:** High.
- **Blocks implementation?** No (v1 can ship with just the current release rendered; comparison is polish).

### 13.6 `list_release_activity(p_release_id uuid, p_cursor_at timestamptz default null, p_cursor_id uuid default null, p_limit integer default 25) → setof`

- **Purpose.** History tab: paginated activity events scoped to the given release and its items. Concrete filter predicate: `(subject_kind = 'release' AND subject_id = p_release_id) OR (subject_kind = 'release_item' AND subject_id IN (SELECT id FROM release_items WHERE release_id = p_release_id))`.
- **Cursor.** `(occurred_at DESC, id DESC)` server-opaque tuple.
- **Capability check.** `release.view` on `(project_id, workspace_id)` resolved from the release row.
- **Freeze Index section:** §10.3 History tab, §27.3.
- **Priority:** High.
- **Blocks implementation?** No (Wave 2).

### 13.7 `list_release_items(p_release_id uuid) → setof`

- **Purpose.** Overview + composer body: enumerate items with denormalized asset + version metadata.
- **Return columns.** `release_item_id, design_asset_id, design_asset_name, version_id, version_sequence, version_published_at, notes, sort_order, approval_state, requirement_readiness_summary`.
- **Ordering.** `sort_order asc, created_at asc` (matches the frozen composer expectation).
- **Capability check.** `release.view` on `(project_id, workspace_id)` resolved from the release row.
- **Freeze Index section:** §10.3 Overview tab, §27.3.
- **Priority:** Critical (Overview tab + composer).
- **Blocks implementation?** Yes.

### 13.8 `list_releases_dashboard(p_ws_id uuid, p_proj_id uuid default null, p_view text default 'all', p_status_filter text[] default null, p_release_type_filter text[] default null, p_published_by_ids uuid[] default null, p_search text default null, p_include_discarded boolean default false, p_cursor_released_at timestamptz default null, p_cursor_id uuid default null, p_limit integer default 25, p_saved_view_id uuid default null) → setof`

- **Purpose.** Paginated dashboard read for both workspace and project scopes. Powers the 11 views enumerated in Freeze Index §11.1. `p_saved_view_id` per APP 008 F-3.3-L2 discipline: distinct additive tail param resolving a persisted view definition (Wave 3).
- **View strings.** `all`, `draft`, `released`, `withdrawn`, `published_by_me`, `discarded`, `by_type:internal`, `by_type:client`, `by_type:regulatory`, `by_type:final`, `by_type:hotfix` (approximated by combining `p_view='all'` with `p_release_type_filter`).
- **Cursor.** `(released_at DESC NULLS LAST, id DESC)` — server-opaque tuple encoded as two params.
- **Capability check.** For workspace scope: `release.view` on at least one project in the workspace (checked via subquery); rows filtered by per-project `release.view` inline. For project scope: `release.view` on `(p_proj_id, p_ws_id)` directly.
- **Freeze Index section:** §11, §15, §27.3.
- **Priority:** Critical.
- **Blocks implementation?** Yes (dashboard cannot render).

### 13.9 `get_release_inbox_count(p_ws_id uuid) → jsonb`

- **Purpose.** NavRail badge count. Returns `{ workspace_released_trailing_30d integer, workspace_draft_count integer, per_project: [ {project_id, released_trailing_30d} ] }`.
- **Rationale per Freeze Index G-18.** Trailing-30-day released count is informational (not "unread"-style inbox). Empty badge is acceptable.
- **Capability check.** `release.view` filtered per project inline.
- **Freeze Index section:** §11.5, §27.3, G-18.
- **Priority:** Medium (badge is polish; NavRail renders without it).
- **Blocks implementation?** No.

### 13.10 `get_project_release_metrics(p_project_id uuid) → jsonb`

- **Purpose.** Metrics strip on the project Release dashboard.
- **Return shape.** `{ total_draft integer, total_released integer, total_withdrawn integer, released_trailing_30d integer, released_trailing_90d integer, by_type: { internal, preview, client, regulatory, final, patch, hotfix }, chain_head_count integer, discarded_count integer }`.
- **Capability check.** `release.view` on `(p_project_id, workspace_id)` resolved from projects.
- **Freeze Index section:** §11.8, §18, §27.3.
- **Priority:** Medium.
- **Blocks implementation?** No.

### 13.11 `get_workspace_release_metrics(p_ws_id uuid) → jsonb`

- **Purpose.** Metrics strip on the workspace Release dashboard.
- **Return shape.** Same shape as §13.10 aggregated across projects in the workspace; adds `per_project_top5: [ {project_id, released_trailing_30d} ]`.
- **Capability check.** `release.view` filtered per project inline; projects without the capability are excluded from aggregates (matches APP 008 pattern).
- **Freeze Index section:** §11.8, §18, §27.3.
- **Priority:** Medium.
- **Blocks implementation?** No.

### 13.12 `list_releases_for_asset(p_design_asset_id uuid) → setof`

- **Purpose.** Design Workspace Releases tab (asset scope): list every release that includes any version of this asset.
- **Return columns.** `release_id, code, name, release_type, status, released_at, version_id, version_sequence`.
- **Ordering.** `released_at DESC NULLS LAST, id DESC`.
- **Capability check.** `release.view` on `(project_id, workspace_id)` resolved from the asset row.
- **Freeze Index section:** §12.1, §13.4, §27.3.
- **Priority:** High.
- **Blocks implementation?** No.

### 13.13 `list_releases_for_version(p_version_id uuid) → setof`

- **Purpose.** Design Workspace Releases tab (version scope): list every release that includes exactly this version.
- **Return columns.** Same as §13.12.
- **Capability check.** `release.view` on `(project_id, workspace_id)` resolved from the version row.
- **Freeze Index section:** §12.4, §13.4, §27.3.
- **Priority:** High.
- **Blocks implementation?** No.

### 13.14 `get_release_readiness_for_publish(p_design_asset_id uuid, p_version_id uuid, p_release_type text) → jsonb`

- **Purpose.** Governance-evidence preflight consumed by the Release composer publish button before invoking `publish_release`. Consumes APP 007 `get_approval_readiness(version_id)` and APP 008 `get_release_readiness_for_version(version_id)` and applies the per-release-type policy (Freeze Index §9.3) to compute a hard `can_publish` boolean.
- **Return shape.** `{ can_publish boolean, blocking_conditions jsonb[] (each entry: {code text, message text, source text -- 'approval'|'requirement'|'review'|'evidence'}), approval_evidence jsonb (= get_approval_readiness output), requirement_evidence jsonb (= get_release_readiness_for_version output), review_evidence jsonb (aggregate count of completed reviews for this version) }`.
- **Per-release-type policy applied here (not in the DB trigger).** For `regulatory` and `final`: `can_publish = false` if any critical requirement is unsatisfied. For `client`: soft warning only (`blocking_conditions` may include warnings even when `can_publish = true`). For `internal`, `preview`, `patch`, `hotfix`: advisory only.
- **Cross-slice.** This is APP 009's hard-consumption point for APP 007 and APP 008 read RPCs. Both consumers are read-only.
- **Capability check.** `release.view` on `(project_id, workspace_id)` resolved from the asset.
- **Freeze Index section:** §9.3, §9.4, §9.5, §27.3, G-12.
- **Priority:** Critical (composer publish button + `publish_release` share this preflight logic).
- **Blocks implementation?** Yes.

### 13.15 Notes on shape stability

- Every `jsonb`-returning RPC's shape is locked by this proposal. Future waves may add keys additively (never rename or remove).
- Every `setof`-returning RPC returns a `TABLE(...)` with a stable column list; adding columns requires a re-freeze.

### 13.16 Deferred read RPCs (not proposed for v1)

- `search_releases(p_ws_id, p_query, p_limit, p_proj_id default null)` — search across name/notes/code. Deferred to Wave 3; v1 uses `p_search` on `list_releases_dashboard`.
- `get_release_notes(p_release_id uuid)` — dedicated Notes-tab read. Not needed in v1; `get_release(...).notes` is sufficient. Reserved for Wave 4 when the `release.notes_updated` event ships and the tab needs a dedicated stream.

Both are name-locked here but not implemented in v1. See §13.16 notes.

---

## 14. Write RPCs

Six new write RPCs plus additive-tail overloads on the two frozen write RPCs. Every new RPC: `SECURITY DEFINER`, `SET search_path = ''`, `REVOKE` from `public`/`anon`, `GRANT EXECUTE` to `authenticated, service_role`, capability re-check inline in the function body, exactly one canonical event per successful mutation, and — where a status write is required — sets `lign.allow_release_status_write = 'true'` transaction-local per the frozen `enforce_release_status_via_rpc` contract (AUTH 008 L54, L125, L187).

### 14.1 `create_release_draft(p_project_id uuid, p_name text, p_notes text default null, p_channel text default null, p_release_type text default null) → uuid`

- **Purpose.** Create a `status='draft'` release with server-generated `code` (`R-NNN` per project via advisory lock).
- **Capability check.** `release.create` on `(p_project_id, workspace_id)` (workspace resolved from project).
- **CHECK enforcement.** `p_release_type` validated against the CHECK enum before INSERT (raises clearly if invalid).
- **Code generation.** `pg_advisory_xact_lock(hashtext('release_code:' || p_project_id::text))` → compute next ordinal → `code := 'R-' || lpad(...)`.
- **INSERT.** `created_by_profile_id = auth.uid()`, `status = 'draft'`, `release_type = p_release_type`, all chain columns NULL.
- **Emits.** `release.created` with `subject_kind='release'`, `subject_id=v_new_id`, `subject_label=p_name`, `subject_snapshot={ name, release_type, code, created_by_profile_id, channel }`, `payload={}`.
- **Return.** New release UUID.
- **No chain-init.** Drafts start with NULL chain columns. Chain-init happens only in the reserved `create_release_superseding` RPC (§14.9).
- **Freeze Index section:** §5.3, §10.5, §27.4.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 14.2 `add_release_item(p_release_id uuid, p_design_asset_id uuid, p_version_id uuid, p_notes text default null, p_sort_order integer default null) → uuid`

- **Purpose.** Attach a `release_items` row while the parent is `draft`. If `p_sort_order` is NULL, computes `max(sort_order) + 1` for the release (respects the frozen `release_items_release_sort_order_key` uniqueness).
- **Capability check.** `release.create` on parent's `(project_id, workspace_id)`.
- **Trigger interaction.** Frozen `enforce_release_items_parent_draft_mutation` fires and blocks if the parent has left `draft`. This RPC's inline check reproduces that error early with a clearer message.
- **Emits.** `release.item_added` with `subject_kind='release_item'`, `subject_id=v_new_item_id`, `subject_snapshot={ release_id, asset_id, asset_name, version_id, version_sequence, release_type, item_id, sort_order, notes_snippet }`.
- **Return.** New release_item UUID.
- **Freeze Index section:** §10.3 Overview / composer, §27.4.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 14.3 `remove_release_item(p_release_id uuid, p_version_id uuid) → uuid`

- **Purpose.** Detach a `release_items` row while parent is `draft`. Identifies the item by `(release_id, version_id)` (matches the frozen `release_items_release_version_key`).
- **Capability check.** `release.create` on parent's `(project_id, workspace_id)`.
- **Trigger interaction.** Frozen `enforce_release_items_parent_draft_mutation` enforces the draft-time invariant.
- **Emits.** `release.item_removed` with `subject_kind='release_item'`, `subject_id=v_item_id`, `subject_snapshot={ release_id, asset_id, version_id, release_type, item_id }`.
- **Return.** The removed release_item UUID.
- **Freeze Index section:** §10.3 composer, §27.4.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 14.4 `publish_release(p_release_id uuid, p_release_type text default null) → uuid`

- **Purpose.** APP 009-owned publish wrapper that layers per-release-type policy on top of the frozen `finalize_release` invariants. Captures the evidence snapshot before flipping status.
- **Sequence.**
  1. Resolve release row `FOR UPDATE`; verify `status='draft'`; verify capability `release.finalize`.
  2. Iterate items; for each, call `get_release_readiness_for_publish(design_asset_id, version_id, coalesce(p_release_type, release_type))`; if any returns `can_publish = false`, RAISE with `blocking_conditions` in the error message. Hard-block for `regulatory` and `final` release types.
  3. Build `evidence_snapshot` jsonb per §3.2 shape.
  4. `perform set_config('lign.allow_release_status_write', 'true', true)`.
  5. **Single atomic transition UPDATE.** `UPDATE releases SET status='released', released_at=now(), published_by_profile_id=auth.uid(), evidence_snapshot=<computed>, release_type = coalesce(p_release_type, release_type) WHERE id = p_release_id;` — one statement transitions status, freezes evidence, records publisher, and sets `release_type` in one shot. This fires `releases_set_updated_at` exactly once per publish. The type-immutability trigger (§9.3) inspects `OLD.status`, which is still `'draft'` at UPDATE time, so a `release_type` change is permitted; the trigger only rejects `release_type` mutation when `OLD.status IN ('released','withdrawn')`. Frozen `enforce_release_finalization_prerequisites_update` fires and re-verifies ≥ 1 item + every-item-approved; frozen `enforce_release_status_via_rpc` permits the status write (GUC set); new `enforce_release_evidence_immutable` permits the snapshot write (OLD.status = 'draft', OLD.evidence_snapshot IS NULL).
  6. INSERT `activity_events` with `event_type='release.finalized'`, `subject_snapshot={ name, item_count, channel, release_type, published_by_profile_id, approved_request_ids, requirement_readiness, review_count, superseded_prior_release_id }`.
- **Capability check.** `release.finalize` inline.
- **Emits.** `release.finalized` — same event name as the frozen `finalize_release` emitter. Payload extends per §11.4.
- **Return.** `p_release_id`.
- **Non-optimistic.** Server-authoritative per Freeze Index G-30. Frontend never speculates on outcome.
- **Chain-init discipline.** N/A — this RPC does not create a new release row and does not write chain columns. `superseded_prior_release_id` in the emitted event is populated only when the release was itself created via `create_release_superseding` (Wave 4) — in v1 always NULL.
- **Freeze Index section:** §9.3, §10.8, §27.4, G-12.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 14.5 `finalize_release(p_release_id uuid, p_release_type text default null) → uuid` — `CREATE OR REPLACE` single-function extension

- **Purpose.** Additive-tail extension of the frozen `finalize_release(uuid)` (AUTH 008 L82), delivered via `CREATE OR REPLACE FUNCTION` on the single function — not as a separate overload. Adds one tail parameter carrying the Freeze Index §27.4 release-type disposition without touching the frozen body semantics.
- **Signature after CREATE OR REPLACE.** `public.finalize_release(p_release_id uuid, p_release_type text default null) returns uuid`. The function retains the frozen name, return type, `SECURITY DEFINER`, `SET search_path = ''`, and REVOKE/GRANT posture (AUTH 008 L145–L147).
- **Backwards-compat.** The frozen positional 1-arg call `finalize_release(some_uuid)` binds unchanged (the default fills `p_release_type`). Named-argument calls `finalize_release(p_release_id => some_uuid)` also bind unambiguously to the single replaced function — there is no sibling overload to compete. This mirrors the APP 008 §9.1 `create_requirement`-15-arg / §9.2 `edit_requirement`-13-arg discipline: single function, default-tail params, no dual overloads (which would raise `function is not unique` under named-argument resolution).
- **Extended behavior.** Mirrors `publish_release` (§14.4) end-to-end: resolves the release `FOR UPDATE`, verifies `status='draft'` and `release.finalize` capability, runs the same per-item readiness check with `coalesce(p_release_type, release_type)`, computes the evidence snapshot, sets the RPC-only status GUC, and issues the same single atomic transition UPDATE (`status='released', released_at=now(), published_by_profile_id=auth.uid(), evidence_snapshot=<computed>, release_type = coalesce(p_release_type, release_type)`) so `releases_set_updated_at` fires once. **Evidence capture is always performed** — no bypass parameter exists; every released row carries a non-NULL `evidence_snapshot`.
- **Capability check.** `release.finalize` inline.
- **Emits.** `release.finalized` (same event; extended payload per §11.4).
- **Freeze Index section:** §27.4.
- **Priority:** Critical.
- **Blocks implementation?** Yes.

### 14.6 `discard_release_draft(p_release_id uuid) → uuid`

- **Purpose.** Soft-discard an empty draft (or a draft with items — product surface warns before calling, but the RPC does not require zero items; the invariant enforced is `status='draft'` only).
- **Capability check.** `release.create` on `(project_id, workspace_id)`.
- **Behavior.** UPDATE `releases SET discarded_at = now()` where `id = p_release_id AND status = 'draft' AND discarded_at IS NULL`. Raises `23514` if `status <> 'draft'` or already discarded (idempotency check — repeat calls fail loudly rather than silently succeeding).
- **No event.** Draft discard is not in the frozen event vocabulary and Freeze Index §20.6 explicitly excludes metadata-edit events in v1. If future policy adds `release.discarded`, it will be reserved and emitted in a later wave.
- **Return.** `p_release_id`.
- **Freeze Index section:** §3.7, §27.4, G-4.
- **Priority:** Medium.
- **Blocks implementation?** No.

### 14.7 `reorder_release_items(p_release_id uuid, p_ordered_version_ids uuid[]) → integer`

- **Purpose.** Update `sort_order` deterministically for all items in the release. Accepts an array of version UUIDs in the desired order.
- **Capability check.** `release.create` on parent's `(project_id, workspace_id)`.
- **Trigger interaction.** Frozen `enforce_release_items_parent_draft_mutation` enforces draft-time-only mutation.
- **Behavior.** For each version_id in `p_ordered_version_ids`, UPDATE `release_items SET sort_order = <array_index>` where `release_id = p_release_id AND version_id = <element>`. Raises `23514` if the array does not exactly match the current item set (all-or-nothing invariant to prevent partial reorders).
- **No event.** Per Freeze Index §20.6 no metadata-edit events fire in v1.
- **Return.** Count of items reordered.
- **Freeze Index section:** §10.3 composer, §27.4.
- **Priority:** Medium.
- **Blocks implementation?** No.

### 14.8 `withdraw_release(p_release_id uuid, p_reason text, p_admin_override boolean default false) → uuid` — `CREATE OR REPLACE` single-function extension

- **Purpose.** Additive-tail extension of the frozen `withdraw_release(uuid, text)` (AUTH 008 L153), delivered via `CREATE OR REPLACE FUNCTION` on the single function — not as a separate overload. Adds `p_admin_override boolean default false` per Freeze Index §27.4 for forward-compatible recall/admin semantics.
- **Signature after CREATE OR REPLACE.** `public.withdraw_release(p_release_id uuid, p_reason text, p_admin_override boolean default false) returns uuid`. The function retains the frozen name, return type, `SECURITY DEFINER`, `SET search_path = ''`, and REVOKE/GRANT posture (AUTH 008 L209–L211). Note the frozen `p_reason text default null` default is preserved on the middle parameter to keep the frozen positional 2-arg call working.
- **Backwards-compat.** The frozen positional 2-arg call `withdraw_release(some_uuid, 'reason')` binds unchanged (the default fills `p_admin_override`). The frozen 1-arg call `withdraw_release(some_uuid)` also binds (both `p_reason` and `p_admin_override` default). Named-argument calls resolve unambiguously against the single replaced function. This mirrors the APP 008 `CREATE OR REPLACE`-with-default-tail discipline (no dual overloads).
- **Extended behavior.** In v1 the extended function behaves identically to the frozen semantics for both `p_admin_override` values: the emitter always fires `release.withdrawn`; `p_admin_override` is captured in the emitted payload as `admin_override boolean` for future consumer distinction but does not flip the event name and does not skip capability checks. Wave 4 introduces the `release.recalled` event and may branch the emitter on `p_admin_override` (a re-freeze).
- **Capability check.** `release.withdraw` inline.
- **Emits.** `release.withdrawn` with `subject_snapshot={ reason, release_type, withdrawn_by_profile_id, admin_override }` (extended per §11.5).
- **Freeze Index section:** §27.4, G-35.
- **Priority:** High.
- **Blocks implementation?** No (the frozen positional 2-arg call covers the v1 UX; the 3rd parameter is forward-compatibility).

### 14.9 Reserved write RPCs (name-locked; not shipped in Wave 1)

Enumerated for vocabulary stability. Chain-init discipline documented in each entry.

- **`schedule_release(p_release_id uuid, p_effective_at timestamptz) → uuid`.** Gates on reserved capability `release.schedule` (C-R1). Transitions `draft → scheduled` (activating the frozen reserved state). Emits reserved `release.scheduled`. Requires re-freeze of `enforce_release_status_via_rpc` to permit the `scheduled` value in the GUC-gated set. Freeze Index §3.2, §27.4.
- **`create_release_superseding(p_prior_release_id uuid, p_name text, p_notes text default null, p_channel text default null, p_release_type text default null) → uuid`.** Gates on reserved capability `release.supersede` (C-R2). Chain-init discipline:
  1. Pre-compute `v_new_id := gen_random_uuid()`.
  2. **Read prior release with `SELECT ... FOR UPDATE`**; verify `status='released'` **and** `superseded_by_release_id IS NULL`, and confirm same project/workspace as the caller. The `FOR UPDATE` row lock serializes concurrent supersede calls on the same prior release: the losing call awakens after commit and observes `superseded_by_release_id IS NOT NULL`, receiving a clean `SQLSTATE 22023` "release already superseded" error instead of an opaque `NULL → uuid` write racing against the chain-immutability trigger's exactly-once contract.
  3. Compute `v_root := coalesce(v_prior.root_release_id, v_prior.id)`.
  4. INSERT new release with `id = v_new_id`, `status='draft'`, `root_release_id = v_root`, `superseded_by_release_id = NULL`, `release_type = coalesce(p_release_type, v_prior.release_type)`, generated `code`, `created_by_profile_id = auth.uid()`.
  5. UPDATE prior release setting `superseded_by_release_id = v_new_id`. The chain-immutability trigger (§9.1) permits this write because it is a `NULL → uuid` initial transition on the `superseded_by_release_id` column of the prior row — exactly the exactly-once initialization the trigger's asymmetric contract carves out.
  6. Both writes are in the single RPC transaction; the `FOR UPDATE` lock is released at commit.
  7. **No post-INSERT UPDATE of `root_release_id` on any row.** The `enforce_release_chain_immutable` trigger rejects such attempts (fully immutable). Matches APP 006 T-CRIT-1 remediation verbatim.
  Emits `release.created` on the new row (per §14.1) plus reserved `release.superseded` (deferred to Wave 4 wiring) on the prior. Freeze Index §8.2, §27.4.
- **`export_release_audit(p_release_id uuid, p_format text) → uuid`.** Gates on reserved capability `release.audit_export` (C-R5). Creates a row in reserved `release_audit_exports` table (§2). Emits reserved `release.audit_exported`. Freeze Index §25.5, §27.4, G-31, G-44.
- **`edit_release_metadata(p_release_id uuid, p_name text default null, p_notes text default null, p_channel text default null, p_release_type text default null, p_effective_at timestamptz default null) → uuid`.** Not reserved but not implemented in Wave 1: the frozen RLS UPDATE policy on `releases` already permits direct client-side UPDATE of `name`/`notes`/`channel`/`effective_at` when `release.create` is held (AUTH 008 L235–L239). A thin RPC wrapper is called out in Freeze Index §27.4 for future event-emission needs (e.g., if `release.notes_updated` ships for post-release edits). Reserved for Wave 4 in v1.

### 14.10 Summary: canonical event per RPC

| Write RPC | Canonical event | Notes |
|---|---|---|
| `create_release_draft` (§14.1) | `release.created` | Name frozen (EVENT_MODEL.md L185); emitter new in APP 009. |
| `add_release_item` (§14.2) | `release.item_added` | Name frozen (L186); emitter new. |
| `remove_release_item` (§14.3) | `release.item_removed` | Name frozen (L187); emitter new. |
| `publish_release` (§14.4) | `release.finalized` | Same event as frozen `finalize_release`. |
| `finalize_release(uuid, text)` (§14.5) | `release.finalized` | `CREATE OR REPLACE`-extended frozen RPC; same event. Frozen 1-arg positional call binds unchanged. |
| `discard_release_draft` (§14.6) | (none in v1) | Per Freeze Index §20.6. |
| `reorder_release_items` (§14.7) | (none in v1) | Per Freeze Index §20.6. |
| `withdraw_release(uuid, text, boolean)` (§14.8) | `release.withdrawn` | `CREATE OR REPLACE`-extended frozen RPC; same event. Frozen 2-arg positional call binds unchanged. `p_admin_override` captured in payload only. |

### 14.11 Chain-init discipline is MANDATORY — reprised

Repeating for emphasis, and stating the two chain-column invariants precisely:

1. **`root_release_id` is set inline at INSERT via a pre-computed UUID.** The RPC pre-computes `v_new_id := gen_random_uuid()` and INSERTs the new release with `root_release_id = coalesce(prior.root_release_id, prior.id)` set in the same statement. The `enforce_release_chain_immutable` trigger (§9.1) rejects any post-INSERT UPDATE of `root_release_id` (fully immutable — `NULL → uuid`, `uuid → uuid`, and `uuid → NULL` all raise `23514`). This mirrors APP 006 T-CRIT-1 remediation verbatim.
2. **`superseded_by_release_id` is set exactly once via the supersede RPC after the new release is inserted.** Step 5 of `create_release_superseding` (§14.9) issues `UPDATE prior SET superseded_by_release_id = v_new_id`. The `enforce_release_chain_immutable` trigger permits this specific `NULL → uuid` initial transition — that is the exactly-once carve-out its asymmetric contract exists for — and rejects every subsequent change (`uuid → uuid` or `uuid → NULL`).
3. Serialization of concurrent supersessions on the same prior release is handled by the `SELECT ... FOR UPDATE` row lock in step 2 of `create_release_superseding` (§14.9). Losing callers observe `superseded_by_release_id IS NOT NULL` after the lock releases and raise `SQLSTATE 22023` "release already superseded" — the trigger never sees a `uuid → uuid` race.
4. The `enforce_release_chain_immutable` trigger (§9.1) is the enforcement authority; RPC-side checks are for clean error messaging only.
5. Function comment convention for any RPC that writes chain columns: **"Chain-init discipline: pre-compute UUID; INSERT `root_release_id` inline; write `superseded_by_release_id` exactly once via `NULL → uuid` on the prior release under `SELECT ... FOR UPDATE`. See APP 006 T-CRIT-1 lesson."**

No shipping RPC in Wave 1 exercises this discipline; the reserved `create_release_superseding` (§14.9) is where it applies. Ships in Wave 4.

---

## 15. Query support

Dashboard queries lean on `list_releases_dashboard` (§13.8) and per-scope helpers (`list_releases_for_asset` §13.12; `list_releases_for_version` §13.13). Search is filter-based in v1 via `p_search` (ILIKE on `name` + `code`); dedicated `search_releases` deferred.

### 15.1 Cursor pagination discipline

- **Cursor tuple.** `(released_at DESC NULLS LAST, id DESC)` — server-opaque. Encoded as two RPC parameters (`p_cursor_released_at timestamptz`, `p_cursor_id uuid`).
- **Rationale.** `released_at` is the primary sort dimension across every view; NULLS LAST places drafts (which have NULL `released_at`) at the end of any released-first view. `id` is the tiebreaker for the deterministic cursor.
- **First page.** Both cursor params NULL.
- **End-of-set.** RPC returns fewer than `p_limit` rows.

### 15.2 Draft-view sort order

For `p_view='draft'`, the sort tuple flips to `(updated_at DESC, id DESC)` (drafts have no `released_at`). Same cursor tuple shape; drivers must not conflate the two.

### 15.3 Discarded-drafts view

`p_view='discarded'` filters `WHERE discarded_at IS NOT NULL`; sorts by `(discarded_at DESC, id DESC)`. Index I-6 covers.

### 15.4 Search

- **In v1.** `p_search text default null` on `list_releases_dashboard` performs `name ILIKE '%' || p_search || '%' OR code ILIKE '%' || p_search || '%'`.
- **In Wave 3.** GIN trigram index on `releases(name)` may be added (analogous to APP 008 I-6). Reserved index name: `releases_name_desc_trgm_idx`. Not shipped in v1.

### 15.5 Deep-link resolver

`get_release_by_code` (§13.2) is the sole deep-link resolver. Uses I-3 (unique partial `(project_id, code)`).

### 15.6 Filter set

Supported filters on `list_releases_dashboard`:

| Filter param | Backing index |
|---|---|
| `p_status_filter text[]` | Frozen `releases_project_status_released_idx` + I-7 |
| `p_release_type_filter text[]` | I-1 |
| `p_published_by_ids uuid[]` | I-2 (leading column) |
| `p_search text` | Sequential scan in v1; trigram in Wave 3 |
| `p_include_discarded boolean` | I-6 (when true) |
| `p_saved_view_id uuid` | Resolved to a saved filter set (Wave 3) |

---

## 16. Migration scope

Two-migration split following APP 006 / APP 007 / APP 008 pattern.

### 16.1 Migration A — schema

- **Filename.** `20260814120000_app_009_releases_schema.sql` (implementer's final timestamp is authoritative).
- **Contents.**
  - `ALTER TABLE public.releases ADD COLUMN release_type text NULL;`
  - `ALTER TABLE public.releases ADD COLUMN evidence_snapshot jsonb NULL;`
  - `ALTER TABLE public.releases ADD COLUMN superseded_by_release_id uuid NULL;`
  - `ALTER TABLE public.releases ADD COLUMN root_release_id uuid NULL;`
  - `ALTER TABLE public.releases ADD COLUMN published_by_profile_id uuid NULL;`
  - `ALTER TABLE public.releases ADD COLUMN discarded_at timestamptz NULL;`
  - `ALTER TABLE public.releases ADD COLUMN code text NULL;`
  - `ALTER TABLE public.releases ADD CONSTRAINT releases_release_type_check CHECK (release_type IS NULL OR release_type IN ('internal','preview','client','regulatory','final','patch','hotfix'));`
  - `ALTER TABLE public.releases ADD CONSTRAINT releases_superseded_by_fk FOREIGN KEY (superseded_by_release_id, project_id, workspace_id) REFERENCES public.releases (id, project_id, workspace_id) ON DELETE RESTRICT;`
  - `ALTER TABLE public.releases ADD CONSTRAINT releases_root_release_fk FOREIGN KEY (root_release_id, project_id, workspace_id) REFERENCES public.releases (id, project_id, workspace_id) ON DELETE RESTRICT;`
  - `ALTER TABLE public.releases ADD CONSTRAINT releases_published_by_profile_fk FOREIGN KEY (published_by_profile_id) REFERENCES public.profiles (id) ON DELETE SET NULL;`
  - Indexes I-1 through I-7 (§6).
  - `COMMENT ON COLUMN` for every new column.
  - Triggers `enforce_release_chain_immutable`, `enforce_release_evidence_immutable`, `enforce_release_type_immutable_when_released` (§9) — function bodies (all three `language plpgsql`, `set search_path = ''`, **NOT** `security definer` — row-local, matching the frozen `enforce_release_status_via_rpc` precedent at `supabase/migrations/20260801220000_auth_008_release_rls.sql` L38) + `REVOKE`s + trigger DDL.
- **Companion documentation diff (Wave 1, per F-5).** Alongside Migration A, an EVENT_MODEL.md doc-diff registers the 7 reserved release event names (§12.2) as name-only reservations. No emitter, no fan-out entry, no payload shape. This makes the vocabulary lock real from day one so downstream waves and slices can bind to fixed strings.
- **Frozen preservation.** No `ALTER` on any frozen column. No `DROP` on any frozen constraint. No `CREATE OR REPLACE` on any frozen function. Migration is purely additive.

### 16.2 Migration B — authz + RPCs

- **Filename.** `20260814180000_app_009_releases_authz_and_rpcs.sql` (implementer's final timestamp).
- **Contents.**
  - `CREATE OR REPLACE FUNCTION public.lign_has_capability(...)` extended additively with reserved-only entries for `release.schedule`, `release.supersede`, `release.ai_suggest`, `release.ai_classify`, `release.audit_export`, `release.recall` (all return `false` for every role in v1 — zero grants). The frozen 4 keys (`release.view`, `release.create`, `release.finalize`, `release.withdraw`) and their role grants are preserved byte-identically.
  - All 13 read RPCs from §13.
  - All 6 new write RPCs from §14.1–§14.7.
  - The 2 `CREATE OR REPLACE` single-function extensions of the frozen write RPCs from §14.5 and §14.8. Each is delivered by `CREATE OR REPLACE FUNCTION` on the frozen function name with default-tail parameters; the frozen positional and named-argument call sites bind unchanged. No sibling overload is created.
  - `REVOKE` from `public`/`anon` + `GRANT EXECUTE` to `authenticated, service_role` on every new RPC and reissued on the two extended frozen RPCs (matching the frozen REVOKE/GRANT posture at AUTH 008 L145–L147, L209–L211).
- **Frozen preservation.** No `DROP FUNCTION` on any frozen RPC. `CREATE OR REPLACE FUNCTION` is used on `finalize_release` and `withdraw_release` to append default-tail parameters — this is the same discipline APP 008 §9.1 / §9.2 uses for `create_requirement` / `edit_requirement` and does not change the frozen call semantics.
- **Ordering.** Migration B must apply after Migration A (columns must exist before RPCs reference them). The two timestamps enforce this.

### 16.3 No third migration

Unlike APP 006/007 (which had auth-fix follow-ups), APP 009 needs no post-hoc trigger-fix migration. The trigger surface is entirely additive and self-contained in Migration A.

### 16.4 Rollback discipline

Every migration is designed to be additive-only. If a wave needs to be rolled back:

- Rolling back Migration B: drop the new RPCs (per catalogued name list). The frozen RPCs remain fully functional; the UI must degrade gracefully to the frozen surface (no dashboard, no Detail page richness).
- Rolling back Migration A: drop the new indexes + triggers + FKs + CHECK + columns (in reverse dependency order). The frozen surface is unchanged. Data loss: any populated `evidence_snapshot` / `code` / `release_type` values are lost.

Rollback is intentionally not automated; it is a governance-approved manual procedure.

---

## 17. Cross-slice compatibility

Per-slice statement. Every claim is explicit.

### 17.1 APP 001 (Auth / bootstrap)

Frozen contracts intact. No `auth.*` object touched. No `lign_has_capability` frozen key modified. New reserved-only entries added additively.

### 17.2 APP 002 (Workspaces / projects)

Frozen contracts intact. `qk` namespace extends additively with `release.*` keys. `DeepLinkResolver` extends with `release` and `release-code` kinds. `CAPABILITY_KEYS` extends with the 6 reserved names. `NavRail` extends with the Releases entry (per Freeze Index §14.1). No frozen APP 002 file byte-modified.

### 17.3 APP 003 (Projects & Design Workspace)

Frozen contracts intact. `RightPanel` gains a Releases tab (Freeze Index §12.1); version cards gain a Released chip (§12.3). Consumes `list_releases_for_asset` (§13.12) and `list_releases_for_version` (§13.13). No APP 003 table or route modified.

### 17.4 APP 004 (Files / viewer)

Frozen contracts intact. Consumes version context in Release Detail item cards; `useSignedUrl` for previews. No mutation. Reserved future consumer via `export_release_audit` attaching PDFs (Wave 4).

### 17.5 APP 005 (Comments / annotations)

Frozen contracts intact. Reuses `StateBadge`, `useCopyLink`, `useWorkspaceHotkeys`, design tokens — all additive consumption. Per Freeze Index G-32: **does NOT** add `target_release_id` to `comments`. `CommentsPanel` is NOT reused (releases do not collect discussion).

### 17.6 APP 006 (Reviews)

Frozen contracts intact. Loose linkage via evidence snapshot pointing to `review_ids[]` and `completed_review_count` per item. `get_release_evidence` (§13.4) reads `reviews` to compute the live delta; no mutation. `user_bookmarks` reused with `entity_kind='release'`; `user_saved_views` reused with `scope='releases'`. Timeline component and dashboard shell pattern reused. Does not mutate reviews.

### 17.7 APP 007 (Approvals)

Frozen contracts intact. **Hard consumption** via `get_approval_readiness(p_version_id uuid) → jsonb` in `get_release_readiness_for_publish` (§13.14) and inside `publish_release` (§14.4). READs `approval_requests` and `approvals` for the Evidence tab (indirectly through the snapshot). Frozen `enforce_release_finalization_prerequisites` trigger already reads `approval_requests.status = 'approved'` at the DB boundary (Migration 008 L308–L323). Does not mutate approvals, approval responses, or approvers.

### 17.8 APP 008 (Requirements)

Frozen contracts intact. **Hard consumption** via `get_release_readiness_for_version(p_asset_version_id uuid) → jsonb` in `get_release_readiness_for_publish` (§13.14) and inside `publish_release` (§14.4). READs `requirements` and `version_requirement_assessments` for the Evidence tab (indirectly through the snapshot). Per Freeze Index G-36: never mutates requirements or assessments.

### 17.9 APP 009 (this)

Owner. Frozen releases baseline (Migration 008 + AUTH 008) preserved byte-identically.

### 17.10 APP 010 (Notifications, not yet frozen)

Consumes frozen `release.*` events plus the additive payload keys per §11. Recipient rules per Freeze Index §22.1. Reserved event names (§12.2) become emit points once APP 010 activates them. APP 009 provides the event contract only; APP 010 owns fan-out.

### 17.11 APP 011 (Realtime, not yet frozen) — REMAINS OUT

Release tables remain OUT of `supabase_realtime` per Freeze Index §23.1, G-29. Adding release tables to the publication requires a REALTIME re-freeze; explicitly not proposed here. Query-invalidation is the sole cache-refresh mechanism in v1. Six reserved realtime channel names are noted for future REALTIME re-freeze (Freeze Index §23.3).

### 17.12 Cross-slice cache invalidation

Per Freeze Index §18. Owned matrix:

- **On `release.finalized`:** invalidate `qk.release.detail(release_id)`, `qk.release.dashboard(*)`, `qk.release.inbox(*)`, `qk.release.metrics(*)`, `qk.release.forAsset(design_asset_id)`, `qk.release.forVersion(version_id)`. Cross-slice: invalidate APP 003 version card chip queries.
- **On `release.withdrawn`:** same as above (post-withdraw the release is still in `list_releases` under a different filter).
- **On `release.created` / `release.item_added` / `release.item_removed`:** invalidate `qk.release.detail(release_id)`, `qk.release.dashboard(*)`.
- **Reverse (upstream → APP 009):** APP 007 `approval.decided` and APP 008 `requirement.assessed` events invalidate `qk.release.evidence(release_id)` for any release whose evidence snapshot references the changed record. Implementation: subscribe to those events in the release query-key layer.

---

## 18. Priority classification

Consolidated tag table. Every proposed item has an explicit priority.

| # | Item | Section | Priority | Blocks impl? |
|---|---|---|---|---|
| 1 | `releases.release_type text NULL` | §3.1 | Critical | Yes |
| 2 | `releases.evidence_snapshot jsonb NULL` | §3.2 | Critical | Yes |
| 3 | `releases.superseded_by_release_id uuid NULL` | §3.3 | High | No |
| 4 | `releases.root_release_id uuid NULL` | §3.4 | High | No |
| 5 | `releases.published_by_profile_id uuid NULL` | §3.5 | High | No |
| 6 | `releases.discarded_at timestamptz NULL` | §3.6 | Medium | No |
| 7 | `releases.code text NULL` | §3.7 | Critical | Yes |
| 8 | CHECK `releases_release_type_check` | §4.1 | Critical | Yes |
| 9 | FK `releases_superseded_by_fk` | §5.1 | High | No |
| 10 | FK `releases_root_release_fk` | §5.2 | High | No |
| 11 | FK `releases_published_by_profile_fk` | §5.3 | High | No |
| 12 | Index I-1 `releases_project_release_type_released_idx` | §6 | Critical | Yes |
| 13 | Index I-2 `releases_project_published_by_released_idx` | §6 | High | No |
| 14 | Index I-3 `releases_project_code_unique_idx` | §6 | Critical | Yes |
| 15 | Index I-4 `releases_root_release_idx` | §6 | High | No |
| 16 | Index I-5 `releases_superseded_by_unique_idx` | §6 | High | No |
| 17 | Index I-6 `releases_project_discarded_at_idx` | §6 | Medium | No |
| 18 | Index I-7 `releases_project_release_type_status_idx` | §6 | Medium | No |
| 19 | Trigger `enforce_release_chain_immutable` | §9.1 | High | No |
| 20 | Trigger `enforce_release_evidence_immutable` | §9.2 | Critical | Yes |
| 21 | Trigger `enforce_release_type_immutable_when_released` | §9.3 | High | No |
| 22 | RPC `get_release` | §13.1 | Critical | Yes |
| 23 | RPC `get_release_by_code` | §13.2 | Critical | Yes |
| 24 | RPC `get_release_chain` | §13.3 | High | No |
| 25 | RPC `get_release_evidence` | §13.4 | Critical | Yes |
| 26 | RPC `get_release_comparison` | §13.5 | High | No |
| 27 | RPC `list_release_activity` | §13.6 | High | No |
| 28 | RPC `list_release_items` | §13.7 | Critical | Yes |
| 29 | RPC `list_releases_dashboard` | §13.8 | Critical | Yes |
| 30 | RPC `get_release_inbox_count` | §13.9 | Medium | No |
| 31 | RPC `get_project_release_metrics` | §13.10 | Medium | No |
| 32 | RPC `get_workspace_release_metrics` | §13.11 | Medium | No |
| 33 | RPC `list_releases_for_asset` | §13.12 | High | No |
| 34 | RPC `list_releases_for_version` | §13.13 | High | No |
| 35 | RPC `get_release_readiness_for_publish` | §13.14 | Critical | Yes |
| 36 | RPC `create_release_draft` | §14.1 | Critical | Yes |
| 37 | RPC `add_release_item` | §14.2 | Critical | Yes |
| 38 | RPC `remove_release_item` | §14.3 | Critical | Yes |
| 39 | RPC `publish_release` | §14.4 | Critical | Yes |
| 40 | RPC `finalize_release(uuid, text)` `CREATE OR REPLACE` extension | §14.5 | Critical | Yes |
| 41 | RPC `discard_release_draft` | §14.6 | Medium | No |
| 42 | RPC `reorder_release_items` | §14.7 | Medium | No |
| 43 | RPC `withdraw_release(uuid, text, boolean)` `CREATE OR REPLACE` extension | §14.8 | High | No |
| 44 | Payload extension `release.created` | §11.1 | Critical | Yes |
| 45 | Payload extension `release.item_added` | §11.2 | Critical | Yes |
| 46 | Payload extension `release.item_removed` | §11.3 | Critical | Yes |
| 47 | Payload extension `release.finalized` | §11.4 | Critical | Yes |
| 48 | Payload extension `release.withdrawn` | §11.5 | High | No |
| 49 | Reserved capability `release.schedule` | §10.1 C-R1 | Future | No |
| 50 | Reserved capability `release.supersede` | §10.1 C-R2 | Future | No |
| 51 | Reserved capability `release.ai_suggest` | §10.1 C-R3 | Future | No |
| 52 | Reserved capability `release.ai_classify` | §10.1 C-R4 | Future | No |
| 53 | Reserved capability `release.audit_export` | §10.1 C-R5 | Future | No |
| 54 | Reserved capability `release.recall` | §10.1 C-R6 | Future | No |
| 55 | Reserved event `release.scheduled` | §12.2 E-R1 | Future | No |
| 56 | Reserved event `release.superseded` | §12.2 E-R2 | Future | No |
| 57 | Reserved event `release.notes_updated` | §12.2 E-R3 | Future | No |
| 58 | Reserved event `release.audit_exported` | §12.2 E-R4 | Future | No |
| 59 | Reserved event `release.recalled` | §12.2 E-R5 | Future | No |
| 60 | Reserved event `release.ai_suggested` | §12.2 E-R6 | Future | No |
| 61 | Reserved event `release.ai_classified` | §12.2 E-R7 | Future | No |
| 62 | Reserved RPC `schedule_release` | §14.9 | Future | No |
| 63 | Reserved RPC `create_release_superseding` | §14.9 | Future | No |
| 64 | Reserved RPC `export_release_audit` | §14.9 | Future | No |
| 65 | Reserved RPC `edit_release_metadata` | §14.9 | Future | No |
| 66 | Reserved table `release_distributions` | §2 | Future | No |
| 67 | Reserved table `release_templates` | §2 | Future | No |
| 68 | Reserved table `release_audit_exports` | §2 | Future | No |
| 69 | Deferred index I-R1 GIN on `evidence_snapshot` | §6 | Future | No |
| 70 | Deferred RPC `search_releases` | §13.16 | Future | No |
| 71 | Deferred RPC `get_release_notes` | §13.16 | Future | No |

**Priority tally.** **19 Critical / 11 High / 8 Medium / 33 Future.**

---

## 19. Implementation waves

Four-wave plan. Item counts per wave sum to the priority tally above.

### Wave 1 — Critical (Backend Re-freeze target) — 20 items

Blocks v1 shipping. Every Critical item lands here, plus the EVENT_MODEL.md doc-diff for reserved event names (moved from Wave 3 per F-5 so the vocabulary lock is real from day one).

| # | Item | Section |
|---|---|---|
| 1 | `releases.release_type text NULL` | §3.1 |
| 2 | `releases.evidence_snapshot jsonb NULL` | §3.2 |
| 3 | `releases.code text NULL` | §3.7 |
| 4 | CHECK `releases_release_type_check` | §4.1 |
| 5 | Index I-1 `releases_project_release_type_released_idx` | §6 |
| 6 | Index I-3 `releases_project_code_unique_idx` | §6 |
| 7 | Trigger `enforce_release_evidence_immutable` | §9.2 |
| 8 | RPC `get_release` | §13.1 |
| 9 | RPC `get_release_by_code` | §13.2 |
| 10 | RPC `get_release_evidence` | §13.4 |
| 11 | RPC `list_release_items` | §13.7 |
| 12 | RPC `list_releases_dashboard` | §13.8 |
| 13 | RPC `get_release_readiness_for_publish` | §13.14 |
| 14 | RPC `create_release_draft` | §14.1 |
| 15 | RPC `add_release_item` | §14.2 |
| 16 | RPC `remove_release_item` | §14.3 |
| 17 | RPC `publish_release` | §14.4 |
| 18 | RPC `finalize_release(uuid, text)` `CREATE OR REPLACE` extension | §14.5 |
| 19 | Payload extensions on `release.created`, `release.item_added`, `release.item_removed`, `release.finalized` | §11.1–§11.4 |
| 20 | EVENT_MODEL.md doc-diff registering all 7 reserved release event names (name-only lock; no emitter) | §12.2 |

### Wave 2 — High — 11 items

Dashboard + metrics + evidence + comparison + chain trigger + published_by column + reserved-name registration.

| # | Item | Section |
|---|---|---|
| 1 | `releases.superseded_by_release_id uuid NULL` | §3.3 |
| 2 | `releases.root_release_id uuid NULL` | §3.4 |
| 3 | `releases.published_by_profile_id uuid NULL` | §3.5 |
| 4 | FKs `releases_superseded_by_fk`, `releases_root_release_fk`, `releases_published_by_profile_fk` | §5 |
| 5 | Indexes I-2, I-4, I-5 | §6 |
| 6 | Trigger `enforce_release_chain_immutable` | §9.1 |
| 7 | Trigger `enforce_release_type_immutable_when_released` | §9.3 |
| 8 | RPCs `get_release_chain`, `get_release_comparison`, `list_release_activity` | §13.3, §13.5, §13.6 |
| 9 | RPCs `list_releases_for_asset`, `list_releases_for_version` | §13.12, §13.13 |
| 10 | RPC `withdraw_release(uuid, text, boolean)` `CREATE OR REPLACE` extension | §14.8 |
| 11 | Payload extension `release.withdrawn` | §11.5 |

### Wave 3 — Medium — 7 items

Polish; dashboard metrics; soft-discard; saved views + bookmarks reuse wiring; reserved-capability documentation for AI (event-name registration moved to Wave 1 per F-5).

| # | Item | Section |
|---|---|---|
| 1 | `releases.discarded_at timestamptz NULL` | §3.6 |
| 2 | Indexes I-6, I-7 | §6 |
| 3 | RPCs `get_release_inbox_count`, `get_project_release_metrics`, `get_workspace_release_metrics` | §13.9–§13.11 |
| 4 | RPC `discard_release_draft` | §14.6 |
| 5 | RPC `reorder_release_items` | §14.7 |
| 6 | Saved-view / bookmark reuse wiring (consumer of frozen APP 006 primitives with `entity_kind='release'`, `scope='releases'`) | §17.6 |
| 7 | AI-seam reserved-capability documentation (`release.ai_suggest`, `release.ai_classify`) in PERMISSIONS.md — reserved AI event names were registered in Wave 1's EVENT_MODEL.md doc-diff per F-5 | §10.1 |

### Wave 4 — Future — 33 items

Intentionally unimplemented. Catalogues the reserved surface for future re-freezes.

| # | Item | Section |
|---|---|---|
| 1 | Reserved capabilities `release.schedule`, `release.supersede`, `release.ai_suggest`, `release.ai_classify`, `release.audit_export`, `release.recall` | §10.1 |
| 2 | Reserved events `release.scheduled`, `release.superseded`, `release.notes_updated`, `release.audit_exported`, `release.recalled`, `release.ai_suggested`, `release.ai_classified` | §12.2 |
| 3 | Reserved RPCs `schedule_release`, `create_release_superseding`, `export_release_audit`, `edit_release_metadata` | §14.9 |
| 4 | Reserved tables `release_distributions`, `release_templates`, `release_audit_exports` | §2 |
| 5 | Deferred index I-R1 GIN on `evidence_snapshot` | §6 |
| 6 | Deferred RPCs `search_releases`, `get_release_notes` | §13.16 |
| 7 | Multi-asset bundle advanced UX | Freeze Index G-8, G-34 |
| 8 | Release channels / distribution lists | Freeze Index §22.2 |
| 9 | Release templates | Freeze Index §23 deferred |
| 10 | Rich text release notes | Freeze Index G-14 |
| 11 | Print/export view | Freeze Index G-31 |
| 12 | Recall variant end-to-end (event flip on `p_recall`) | Freeze Index G-35 |
| 13 | Post-release notes edits with `release.notes_updated` | Freeze Index G-26 |
| 14 | Realtime publication for release tables | Freeze Index G-29 |

**Wave item-count tally.** Wave 1: 20 items (was 19; +1 EVENT_MODEL.md reserved-name doc-diff moved in from Wave 3 per F-5). Wave 2: 11 items. Wave 3: 7 items (was 8; -1 moved out per F-5). Wave 4: 33 items. Total: 71 backend surface items enumerated in §18 plus 1 documentation deliverable (the Wave 1 doc-diff).

---

## 20. Coverage matrix

Every Freeze Index section mapped to backend items. Coverage column: **Fully covered** (every backend hook exists in v1), **Partially covered** (some hooks in v1; rest deferred), **Deferred to Future** (no v1 hook; reserved surface only).

| Freeze Index § | Topic | Backend items | Coverage |
|---|---|---|---|
| §1 Purpose | Framing | (narrative only) | Fully covered |
| §2 Domain boundaries | Ownership | Reused frozen entities + additive columns | Fully covered |
| §3 Release lifecycle | 3-state MVP | Frozen triggers preserved; new triggers additive | Fully covered |
| §3.2 Reserved states | `scheduled`, `superseded` | Reserved capability `release.schedule` (C-R1), `release.supersede` (C-R2); reserved event `release.scheduled` (E-R1), `release.superseded` (E-R2); reserved RPC `schedule_release`, `create_release_superseding` (§14.9) | Deferred to Future |
| §4 State machine | Legal transitions | Frozen `enforce_release_status_via_rpc` preserved | Fully covered |
| §5 Release model | Columns | §3 additive columns + §4 CHECK + §5 FKs + §9 triggers | Fully covered |
| §5.6 `released_version_ref` | Do not add | Explicitly not proposed (G-6) | Fully covered (by absence) |
| §5.7 Immutability rules | Trigger contracts | §9.1, §9.2, §9.3 new triggers + frozen triggers preserved | Fully covered |
| §6 Release evidence | jsonb snapshot | §3.2 `evidence_snapshot` column + §9.2 immutability trigger + §13.4 `get_release_evidence` + §14.4 `publish_release` builder | Fully covered |
| §7 Version relationship | Cardinality | Frozen `release_items` + composite FKs preserved | Fully covered |
| §8 Previous release chain | Supersession | §3.3, §3.4 chain columns + §5.1, §5.2 chain FKs + §6 chain indexes + §9.1 chain-immutability trigger + §13.3 `get_release_chain` + §14.9 reserved `create_release_superseding` | Partially covered (schema + trigger + read RPC in Wave 1–2; writer deferred to Wave 4) |
| §9 Release types | Enum + policy | §3.1 `release_type` column + §4.1 CHECK + §9.3 type-immutability trigger + §13.14 readiness RPC + §14.4 `publish_release` per-type policy | Fully covered |
| §9.6 Reserved release types | `staged`, `snapshot`, `demo` | Name-locked in Freeze Index; not in v1 CHECK enum | Deferred to Future |
| §10 Release Detail architecture | Detail page | §13.1, §13.4, §13.5, §13.6, §13.7 read RPCs | Fully covered |
| §11 Dashboard architecture | Dashboard | §13.8 `list_releases_dashboard` + §13.9 inbox + §13.10 / §13.11 metrics | Fully covered |
| §12 Design Workspace integration | RightPanel + chips | §13.12 / §13.13 for-asset / for-version RPCs | Fully covered |
| §13 Version interaction | Version selector | §13.13 `list_releases_for_version` + APP 003 additive chip | Fully covered |
| §14 Navigation | NavRail | §13.9 `get_release_inbox_count` powers badge | Fully covered |
| §15 Deep links | `/deep/release/:code` | §3.7 `code` column + §6 I-3 unique index + §13.2 `get_release_by_code` | Fully covered |
| §16 URL grammar | Filter params | §13.8 filter params | Fully covered |
| §17 Query architecture | qk namespace | §17.12 cross-slice invalidation | Fully covered |
| §18 Cache ownership | Invalidation matrix | §17.12 | Fully covered |
| §19 Capability model | 4 frozen + 6 reserved | §10.1 reserved-only registration | Fully covered |
| §20 Event ownership | 5 frozen + 7 reserved + payload extensions | §11 payload extensions + §12 reserved names | Fully covered |
| §21 AI extension seams | AISlot kinds | §10.1 C-R3 / C-R4 + §12.2 E-R6 / E-R7 reserved | Deferred to Future (reserved surface only) |
| §22 Notification contracts | Recipient rules | Event contract in §11 / §12; APP 010 owns fan-out | Fully covered (contract; delivery deferred to APP 010) |
| §23 Realtime boundaries | OUT of publication | Explicit statement in §17.11 | Fully covered (by exclusion) |
| §24 Loading/error states | Skeleton shapes | Frontend concern; backend supplies stable RPC shapes | Fully covered (RPC shapes) |
| §25 Desktop/mobile | Responsive | Frontend concern | Fully covered (RPC shapes) |
| §25.5 Print / export | PDF / CSV | Reserved capability `release.audit_export` (C-R5) + reserved event `release.audit_exported` (E-R4) + reserved RPC `export_release_audit` (§14.9) + reserved table `release_audit_exports` (§2) | Deferred to Future |
| §26 Reusable primitives | Component reuse | Backend agnostic | Fully covered |
| §27 Backend delta preview | THIS PROPOSAL | All §3–§14 items | Fully covered |
| §28 Open architectural decisions | G-1 through G-50 | Every G-* cited inline throughout | Fully covered (all decisions honored) |
| §29 Freeze checklist / non-goals | Scope | §17 cross-slice + §19 waves | Fully covered |
| §30 Cross-slice compatibility matrix | Per-slice | §17 | Fully covered |

**Coverage summary.** 100% of Freeze Index sections have an explicit disposition. Every §-reference is either Fully covered (v1 backend hook exists) or Deferred to Future (reserved surface only). No section is left as "Partially covered" without an explicit statement of what ships and what defers.

---

## 21. Backwards-compat guarantees

Explicit statement covering every dimension of the frozen surface.

### 21.1 No frozen RPC signature is broken

- `finalize_release(p_release_id uuid)` — the frozen positional 1-arg call binds byte-identically. AUTH 008 L82. Extension is via `CREATE OR REPLACE FUNCTION public.finalize_release(p_release_id uuid, p_release_type text default null)` on the single frozen function (no sibling overload); the default fills the tail param for frozen positional callers, and named-argument calls (`finalize_release(p_release_id => X)`) also bind unambiguously to the single replaced function. Both call styles observe zero behavior change from the caller's perspective for the pre-existing surface.
- `withdraw_release(p_release_id uuid, p_reason text default null)` — the frozen positional call sites (1-arg and 2-arg) bind byte-identically. AUTH 008 L153. Extension is via `CREATE OR REPLACE FUNCTION public.withdraw_release(p_release_id uuid, p_reason text, p_admin_override boolean default false)` on the single frozen function (no sibling overload). The frozen middle-param default (`p_reason text default null`) is preserved so the 1-arg call still binds; the added `p_admin_override` default fills for 2-arg callers.
- No other frozen RPC in the release surface exists; both frozen release write RPCs are covered above.
- Frozen read RPCs consumed: `get_approval_readiness(uuid)` (APP 007) and `get_release_readiness_for_version(uuid)` (APP 008) — both consumed read-only; neither is redefined.

### 21.2 No frozen event name is changed

- `release.created`, `release.item_added`, `release.item_removed`, `release.finalized`, `release.withdrawn` — every name preserved byte-identically in EVENT_MODEL.md §4.12 L185–L189.
- Payload extensions per §11 are additive keys only.
- No `subject_kind`, `subject_id`, or scope semantic is changed.

### 21.3 No frozen capability role map is changed

- `release.view`, `release.create`, `release.finalize`, `release.withdraw` role grants (Freeze Index §19.2) preserved byte-identically in `lign_has_capability`.
- Reserved-only additions (§10.1) have zero role grants and therefore cannot affect any existing caller's capability resolution.

### 21.4 No frozen table RLS policy is changed

- `releases_select`, `releases_insert`, `releases_update` on `public.releases` preserved byte-identically (AUTH 008 L217–L239).
- `release_items_select`, `release_items_insert`, `release_items_update`, `release_items_delete` on `public.release_items` preserved byte-identically (AUTH 008 L247–L296).
- New columns fall under the existing SELECT policy.
- No DELETE policy on `releases` added (soft-discard via `discarded_at` per G-4).

### 21.5 No frozen trigger is modified

- `enforce_release_finalization_prerequisites` (Migration 008 L274–L344) — preserved byte-identically. Universal invariant (≥ 1 item + every-item-approved) intact.
- `enforce_release_items_parent_draft_mutation` (Migration 008 L211–L258) — preserved byte-identically.
- `enforce_release_status_via_rpc` (AUTH 008 L38–L76) — preserved byte-identically.
- `releases_set_updated_at`, `release_items_set_updated_at` — preserved.
- The three new triggers (§9.1, §9.2, §9.3) are additive and fire on distinct column changes; they do not overlap or compete with the frozen triggers.

### 21.6 No frozen CHECK is narrowed

- `releases_status_check` — 5-value enum preserved. Reserved values `scheduled` and `superseded` still permitted at the CHECK level but not exercised by v1 RPCs.
- `releases_released_metadata_check`, `releases_withdrawn_metadata_check` — preserved.
- `release_items_sort_order_check` — preserved.
- New `releases_release_type_check` is a widening on a net-new column; no frozen CHECK is narrowed.

### 21.7 No frozen composite FK is altered

- `releases_project_fk`, `release_items_release_fk`, `release_items_version_project_fk`, `release_items_version_asset_fk`, `decisions_resulting_release_fk` — all preserved byte-identically.
- New composite FKs (§5) reference the frozen anchor unique keys (`releases_id_project_workspace_key`) without altering them.

### 21.8 No frozen anchor unique is dropped

- `releases_id_project_workspace_key (id, project_id, workspace_id)` — preserved. Reused by new chain FKs.
- `releases_id_workspace_key (id, workspace_id)` — preserved. Reused by `decisions.resulting_release_fk`.
- `release_items_release_version_key (release_id, version_id)` — preserved.
- `release_items_release_sort_order_key (release_id, sort_order)` — preserved.

### 21.9 No Migration 008 or AUTH 008 file byte-modified

Migration timestamps `20260729230000_releases.sql` and `20260801220000_auth_008_release_rls.sql` remain byte-identical. All extensions are delivered by two new migrations (§16.1, §16.2) that only add columns, indexes, triggers, and RPCs.

### 21.10 No conflict with Freeze Index scope

Every item in §27 of the Freeze Index has a proposed disposition. No item exceeds §27's authorized scope. Where the Freeze Index says "reserved-only" this proposal registers the name and grants no role / defines no emitter.

### 21.11 No conflict with SCHEMA_V1_LOCK

Additive columns on `releases` and additive-trigger DDL are permitted extensions under SCHEMA_V1_LOCK provided no frozen column is renamed or dropped. This proposal satisfies that discipline.

### 21.12 No conflict with STORAGE 001–004, REALTIME 001–002, AUTH 001–009

- STORAGE: no storage bucket touched; `export_release_audit` (reserved) will consume STORAGE 003 upload/finalize when wired in Wave 4.
- REALTIME: release tables remain OUT of `supabase_realtime`. No publication change proposed.
- AUTH: `lign_has_capability` extended additively only; frozen 4 keys preserved.

### 21.13 No conflict with APP 001–008 domain, tables, RPCs, events, capabilities, routes, or components

Cross-slice consumption is read-only. No mutation of any APP 001–008 owned entity. Extensions to consumed slices are additive contract-extensions only (e.g., adding a `Releases` tab to APP 003's RightPanel does not modify APP 003 tables or routes).

---

## 22. Applied review-finding pattern

Populated by the Backend Re-freeze Review cycle. See the Backend Re-freeze Report at the head of this document for full rationale, contract change, and compatibility impact per finding. Format follows APP 008's §25 pattern:

| Finding ID | Severity | Applied? | Sections touched | One-line summary |
|---|---|---|---|---|
| F-1 | CRITICAL | Yes | §0, §3.4, §5.1, §5.2, §9.1, §14.9, §14.11 | Chain-immutability trigger uses exactly-once initialization for `superseded_by_release_id`; `root_release_id` fully immutable — makes `create_release_superseding` implementable. |
| F-2 | CRITICAL | Yes | §0, §1, §8, §11.4, §11.5, §12.1, §12.5, §14.5, §14.8, §14.10, §16.2, §21.1, §18/§19 | Collapsed dual overloads into single-function `CREATE OR REPLACE` with default-tail params per APP 008 pattern; eliminates named-argument `function is not unique` trap. |
| F-3 | HIGH | Yes | §14.9 step 2, §14.11 | `SELECT ... FOR UPDATE` on prior release in supersede; concurrent calls get clean 22023 error. |
| F-4 | HIGH | Yes | §14.5, §1 table, §18/§19 | Removed `p_capture_evidence` from `finalize_release`; evidence always captured — no NULL-evidence released rows. |
| F-5 | MEDIUM | Yes | §12.2, §16.1, Wave 1 & Wave 3 tables | Rewrote reserved-name wording; committed EVENT_MODEL.md doc-diff to Wave 1 for real vocabulary lock. |
| F-6 | MEDIUM | Yes | §0, §9.1, §9.2, §9.3 | Removed `SECURITY DEFINER` from row-local trigger functions; matches frozen `enforce_release_status_via_rpc` precedent. |
| L-1 | LOW | Yes | §14.4 sequence | Folded `release_type` write into single atomic publish UPDATE; one `updated_at` bump. |
| L-2 | LOW | Yes | §13.6 | Concrete filter predicate for `list_release_activity` (`subject_kind = 'release' OR release_item ...`). |

**Review scope.** The Backend Re-freeze Review will scrutinize this proposal for:

- Frozen-surface preservation (byte-identical Migration 008 + AUTH 008).
- Chain-init discipline correctness (APP 006 T-CRIT-1 lesson applied verbatim to `create_release_superseding` reservation).
- Trigger interaction correctness (new triggers do not conflict with frozen triggers on the same table).
- Cross-slice consumption safety (read-only from APP 006, APP 007, APP 008).
- RPC signature discipline (Option A tail params; distinct overloads for frozen extensions).
- Capability naming (dot-separated `subject.verb`; extend-before-duplicate rule).
- Event naming (past-tense; reserved-only discipline for zero-emitter names).
- Index coverage (every new FK has a covering btree index).
- CHECK / FK / UNIQUE additive-only discipline.
- Priority tag consistency (Critical items block implementation; Future items are reserved-only).
- Wave item counts summing to the priority tally.
- Coverage matrix completeness (every Freeze Index § mapped).

Any CRITICAL findings from the Review must land in a revised proposal before Backend Freeze. HIGH / MEDIUM / LOW findings may be applied inline in the same document; the review report enumerates each disposition.

---

**APP 009 Backend is frozen.**
