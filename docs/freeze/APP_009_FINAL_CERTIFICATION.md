# APP 009 Final Certification

**Permanent governance record for APP 009 — Releases.**

This document certifies the collective status of the APP 009 slice as permanently frozen. Authoritative sources:

- [`docs/APP_009_FREEZE_INDEX.md`](../APP_009_FREEZE_INDEX.md)
- [`docs/APP_009_BACKEND_PROPOSAL.md`](../APP_009_BACKEND_PROPOSAL.md) (Backend Re-freeze Report applied at head)
- APP 009 Backend Re-freeze Review Report
- APP 009 Implementation Report
- APP 009 Final Architecture Audit Report

---

## 1. Overall status

- **Version:** v1.0
- **Certification date:** 2026-08-05
- **Implementation status:** Complete. All Wave 1–3 backend surface deployed to project `hsfporioghapwghrvvzd` via Migrations 042–050 (Migration A schema + Migration B authz/rpcs applied remotely in 9 chunks; 2 canonical local files at `20260814120000` and `20260814180000`). All frontend surfaces implemented, typechecked, built, and integrated with APP 002–008.
- **Freeze status:** **Permanently frozen.**

APP 009 has completed the full governance cycle: Architecture Freeze → Backend Proposal → Backend Re-freeze Review → Backend Re-freeze Report (F-1..F-6 + L-1/L-2 corrections applied) → Implementation → Implementation Report → Final Architecture Audit. Every CRITICAL, HIGH, MEDIUM, and LOW finding was resolved before implementation began; every empirical smoke test passed against the deployed database. No open blockers remain. APP 001–008 contracts and REQUIREMENTS 001–005 backend remain intact. The frozen releases baseline (`20260729230000_releases.sql` and `20260801220000_auth_008_release_rls.sql`) is preserved byte-identically.

---

## 2. Architecture verification

The deployed architecture matches the frozen contract along every dimension audited by the Final Architecture Audit Report:

- **Governance pipeline enforced.** Requirements → Reviews → Approvals → Release. Releases publish an already-governed version; do not collect discussion, votes, or requirement assessments. `get_release_readiness_for_publish` consumes APP 007 `get_approval_readiness(p_version_id uuid)` and APP 008 `get_release_readiness_for_version(p_asset_version_id uuid)` read-only.
- **Release lifecycle preserved.** Frozen 3-state enum `draft/released/withdrawn` reused; reserved `scheduled` and `superseded` name-locked (not exercised in v1). Frozen `enforce_release_status_via_rpc` guards direct-write attempts.
- **Chain model additive.** New columns `superseded_by_release_id` and `root_release_id` on `releases`, backed by the new `releases_chain_immutable` trigger.
- **Chain-init discipline honored (APP 006 T-CRIT-1).** `create_release_draft` pre-computes `gen_random_uuid()` and INSERTs; no post-INSERT UPDATE of chain columns.
- **F-1 asymmetric chain immutability empirically verified.** `superseded_by_release_id` permits `NULL → uuid` exactly once (initial supersession write); rejects `uuid → uuid` and `uuid → NULL`. `root_release_id` fully immutable after INSERT. All three transitions probed on the deployed DB with matching outcomes (SQLSTATE 23514 raises where expected).
- **F-2 CREATE OR REPLACE discipline honored.** `finalize_release` and `withdraw_release` each have exactly one entry in `pg_proc`. Named-argument dispatch (`p_release_id => X`) and positional dispatch (`uuid`, `(uuid, text)`) both resolve unambiguously — no `function is not unique` runtime errors.
- **F-3 supersession ordering.** Wave 4 `create_release_superseding` reserved-only; the chain-immutability trigger's asymmetric contract is ready to permit its `NULL → uuid` initial write when the reserved RPC ships in a future re-freeze.
- **F-4 evidence always captured.** `p_capture_evidence` parameter deliberately absent from `finalize_release`; no NULL-evidence released rows possible.
- **F-5 reserved event registration.** 7 reserved event names (2 reaffirmed + 5 new) registered in `EVENT_MODEL.md` in the Wave 1 doc-diff so the vocabulary lock is real from day one.
- **F-6 trigger discipline.** All three new triggers (`releases_chain_immutable`, `releases_evidence_immutable`, `releases_type_immutable_when_released`) are `prosecdef=false` (NOT SECURITY DEFINER) with `SET search_path=''`, matching the frozen non-DEFINER `enforce_release_status_via_rpc` precedent at AUTH 008 L38.
- **L-1 atomic publish.** `publish_release` uses a single UPDATE statement that transitions status + freezes evidence + sets release_type in one shot; `releases_set_updated_at` fires exactly once per publish.
- **L-2 concrete activity filter.** `list_release_activity` uses the exact predicate `(subject_kind='release' AND subject_id=p_release_id) OR (subject_kind='release_item' AND subject_id IN (SELECT id FROM release_items WHERE release_id=p_release_id))`.
- **Evidence immutability.** `evidence_snapshot` mutation rejected when `OLD.status IN ('released','withdrawn')`; permits `draft → released` initial jsonb set.
- **Release type immutability.** `release_type` mutation rejected under the same condition; `draft → released` transition sets it in the same atomic publish UPDATE (L-1).
- **Evidence bundle semantics.** Snapshot captures upstream state at publish time (approval_request_ids, review_ids, requirement_ids, version_id, published_by, timestamps). Once set at publish, immutable. Downstream renderers consume the snapshot as-is; live-delta views are served by `get_release_evidence` from current upstream tables.

---

## 3. Backend contract verification

**Migrations recorded in `supabase_migrations.schema_migrations`:**

| Migration | Purpose |
|---|---|
| `20260814120000_app_009_releases_schema` (Migration A) | 7 additive columns on `releases`, 1 NULL-permissive CHECK, 3 composite-tenancy FKs, 7 additive indexes, 3 new triggers (all NOT SECURITY DEFINER per F-6) |
| `20260814180000_app_009_releases_authz_and_rpcs` (Migration B; applied remotely in 8 chunks + 1 F-2 enforcement chunk) | `lign_has_capability` reissued with 4 frozen `release.*` keys byte-preserved + 6 reserved names (zero grants); 14 read RPCs; 6 new write RPCs; `CREATE OR REPLACE` extensions on frozen `finalize_release` and `withdraw_release`; F-2 enforcement drop of frozen 1-arg/2-arg overloads to eliminate named-argument dispatch ambiguity |

**Schema surface (per Final Architecture Audit):**

- **Tables added:** 0. Zero new tables (3 tables name-reserved for future waves per Freeze Index §27).
- **Columns added:** 7 (all on `public.releases`): `release_type`, `evidence_snapshot`, `superseded_by_release_id`, `root_release_id`, `published_by_profile_id`, `discarded_at`, `code`.
- **Indexes added:** 7 (I-1..I-7): project_release_type_released, project_published_by (partial), project_code (unique partial), root_release (partial), superseded_by (unique partial), project_discarded_at (partial), project_release_type_status.
- **CHECK constraints:** 1 additive (`releases_release_type_check` — 7-value enum, NULL-permissive).
- **FKs:** 3 (`releases_superseded_by_fk` and `releases_root_release_fk` — composite `(col, project_id, workspace_id) → releases(id, project_id, workspace_id) ON DELETE RESTRICT`; `releases_published_by_profile_fk → profiles(id) ON DELETE SET NULL`). All covered by the new indexes.
- **Triggers:** 3 new (`releases_chain_immutable`, `releases_evidence_immutable`, `releases_type_immutable_when_released`), all NOT SECURITY DEFINER, with `SET search_path=''` and REVOKE-from-public/anon/authenticated (no GRANT). Every frozen release trigger preserved and enabled.
- **RLS:** unchanged. Frozen SELECT policies on `releases` and `release_items` gated by `release.view`; writes RPC-only.

**RPCs (14 read + 6 new write + 2 CREATE OR REPLACE extensions on frozen writes; every one SECURITY DEFINER + `search_path=''` + REVOKE-from-public/anon/authenticated + GRANT EXECUTE to `authenticated, service_role`):**

- **Read:** `get_release`, `get_release_by_code`, `get_release_chain`, `get_release_evidence`, `get_release_comparison`, `list_release_activity` (L-2 concrete filter), `list_release_items`, `list_releases_dashboard` (with `p_saved_view_id` tail param), `get_release_inbox_count`, `get_project_release_metrics`, `get_workspace_release_metrics`, `list_releases_for_asset`, `list_releases_for_version`, `get_release_readiness_for_publish` (consumes APP 007 + APP 008 readiness RPCs).
- **New write:** `create_release_draft` (advisory-locked R-NNN codes; pre-computed UUID; INSERT chain columns inline per T-CRIT-1), `add_release_item`, `remove_release_item`, `reorder_release_items` (all-or-nothing array match), `discard_release_draft`, `publish_release` (L-1 single atomic UPDATE).
- **Frozen writes extended via `CREATE OR REPLACE` (F-2 single-function + default-tail):** `finalize_release(p_release_id uuid, p_release_type text DEFAULT NULL)` — F-4 evidence always captured, L-1 single atomic UPDATE. `withdraw_release(p_release_id uuid, p_reason text DEFAULT NULL, p_admin_override boolean DEFAULT false)`. Frozen 1-arg and 2-arg overloads dropped in the final Migration B chunk to eliminate named-argument dispatch ambiguity.

**Capabilities:** 4 frozen `release.*` keys preserved byte-identically (`release.view`, `release.create`, `release.finalize`, `release.withdraw`); 6 reserved names name-only with **zero role grants** (`release.schedule`, `release.supersede`, `release.ai_suggest`, `release.ai_classify`, `release.audit_export`, `release.recall`).

**Events:**

- **Emitted (frozen names byte-identical):** `release.created`, `release.item_added`, `release.item_removed`, `release.finalized`, `release.withdrawn`. All 5 payloads extended additively (all frozen keys preserved; new keys optional).
- **Reserved (registered in `EVENT_MODEL.md` per F-5; no emitter in APP 009):** `release.scheduled`, `release.superseded`, `release.notes_updated`, `release.audit_exported`, `release.recalled`, `release.ai_suggested`, `release.ai_classified`.

---

## 4. Approved architectural decisions

The following decisions from the freeze cycle are ratified and locked:

1. **Zero new tables.** APP 009 reuses the frozen 2-table releases surface (`releases` + `release_items`); 3 tables name-reserved for future waves.
2. **`root_release_id` fully immutable after INSERT.** Chain-init discipline mandates pre-computed UUID and inline INSERT — no post-INSERT UPDATE (APP 006 T-CRIT-1 precedent).
3. **`superseded_by_release_id` exactly-once initialization.** Asymmetric chain-immutability contract permits `NULL → uuid` exactly once (initial supersession write); rejects `uuid → uuid` and `uuid → NULL`.
4. **`released` and `withdrawn` are terminal-immutable.** Evidence snapshot and release_type cannot mutate once status is terminal. Supersession requires a new release.
5. **Evidence always captured at finalization.** No `p_capture_evidence` parameter; no NULL-evidence released rows possible.
6. **`CREATE OR REPLACE` + default-tail params for frozen RPC extensions.** Frozen 1-arg/2-arg overloads of `finalize_release` and `withdraw_release` dropped to eliminate named-argument dispatch ambiguity. Positional callers of frozen signatures still bind via defaults.
7. **Governance pipeline enforced.** Requirements → Reviews → Approvals → Release. Releases consume upstream governance evidence via read-only RPC calls; never mutate upstream slices.
8. **Release-readiness policy is per-release-type.** `get_release_readiness_for_publish` computes `can_publish` based on release_type-specific policy over approval + requirement + review evidence bundles. `internal` and `preview` types accept lighter evidence; `regulatory` and `final` require completed approvals.
9. **Releases never collect discussion.** No CommentsPanel on Release Detail. No Discussions tab.
10. **Releases never collect votes.** No roster on releases. No approval-response-style workflow.
11. **Releases never evaluate requirements.** No assessment RPCs on releases. Read-only requirement-evidence consumption via APP 008.
12. **All three new triggers are NOT SECURITY DEFINER.** Row-local triggers inspecting only OLD/NEW columns do not require caller-RLS bypass. Matches frozen `enforce_release_status_via_rpc` non-DEFINER precedent.
13. **`releases` and `release_items` remain OUT of `supabase_realtime` publication.** Reserved channel names for future re-freeze (`release:<id>`, `project:<id>:releases`).
14. **No optimistic cache mutation on publish/withdraw.** Governance sensitivity requires server-confirmed writes only.

---

## 5. Files created

**Backend migrations (2 canonical local files; Migration B applied remotely in 9 chunks):**

- `supabase/migrations/20260814120000_app_009_releases_schema.sql`
- `supabase/migrations/20260814180000_app_009_releases_authz_and_rpcs.sql`

**Frontend (all under `app/src/features/releases/`):**

- `queries.ts`, `mutations.ts`
- `WorkspaceReleasesScreen.tsx`, `ProjectReleasesScreen.tsx`, `ReleaseDetailScreen.tsx`
- `ReleasesDashboardBody.tsx`, `ReleaseFilterBar.tsx`, `ReleaseCard.tsx`, `ReleaseActions.tsx`
- `ReleaseEvidenceCard.tsx`, `ReleaseComparisonView.tsx`
- `CreateReleaseDialog.tsx`, `ReleaseNotesEditor.tsx`
- `ReleasesTabPanel.tsx`, `ReleaseHistoryList.tsx`

**Governance:**

- `docs/APP_009_FREEZE_INDEX.md`
- `docs/APP_009_BACKEND_PROPOSAL.md` (Backend Re-freeze Report at head)
- `docs/freeze/APP_009_FINAL_CERTIFICATION.md` (this document)

---

## 6. Files modified

All modifications are additive and preserve existing behavior for prior slices:

- `app/src/lib/queryKeys.ts` — appended 15 `qk.release*` keys.
- `app/src/features/shared/invalidate.ts` — appended `invalidateReleasesLists`, `invalidateRelease`, `invalidateReleaseInbox`.
- `app/src/router.tsx` — added 4 routes (2 dashboards, 1 detail, 1 deep-link); removed `ReleasesStub` / `ReleaseDetailStub` references.
- `app/src/auth/DeepLinkResolver.tsx` — added real `kind="release"` resolver.
- `docs/EVENT_MODEL.md` — F-5 doc-diff: additive payload keys on 5 frozen `release.*` events; 7 reserved event names registered (2 reaffirmed + 5 new).

No APP 001–008 migration, RLS policy, RPC, capability key, event vocabulary entry, or public component API was removed, renamed, or semantically altered.

---

## 7. Backend surface summary

| Dimension | Count | Notes |
|---|---|---|
| Migrations | 2 canonical local files (Migration B applied remotely in 9 chunks) | Timestamps `20260814120000` + `20260814180000` |
| Tables added | 0 | 3 reserved names for future waves |
| Columns added | 7 | All on `releases`, all nullable |
| Indexes added | 7 | I-1..I-7; every new FK covered |
| CHECK constraints | 1 | NULL-permissive 7-value enum |
| FKs added | 3 | 2 composite chain FKs ON DELETE RESTRICT; 1 profile FK ON DELETE SET NULL |
| Triggers added | 3 | All NOT SECURITY DEFINER per F-6 |
| Frozen triggers preserved | 5 | `releases_set_updated_at`, `releases_status_via_rpc`, `releases_finalization_prerequisites_insert`, `releases_finalization_prerequisites_update`, `release_items_parent_draft_mutation` — all enabled |
| RLS policies added | 0 | Reads gated by frozen `release.view`; writes RPC-only |
| Read RPCs added | 14 | All SECURITY DEFINER + `search_path=''` |
| New write RPCs added | 6 | All SECURITY DEFINER + `search_path=''` |
| Frozen RPCs extended via `CREATE OR REPLACE` + default-tail | 2 | `finalize_release`, `withdraw_release` — count(*)=1 each; frozen overloads dropped for F-2 |
| Capabilities added (wired) | 0 | 6 reserved name-only (zero grants); frozen 4 preserved byte-identically |
| New event types emitted | 0 | 5 frozen event names retained; additive payload keys only |
| Reserved event names | 7 | 2 reaffirmed + 5 new, registered in EVENT_MODEL.md per F-5 |

---

## 8. Query architecture

TanStack Query v5. Release-namespaced keys under `qk`:

```
qk.releasesList(scope, view, filters)
qk.releasesWorkspaceDashboard(wsId, view)
qk.releasesProjectDashboard(projId, view)
qk.release(id)
qk.releaseByCode(projId, code)
qk.releaseChain(id)
qk.releaseEvidence(id)
qk.releaseComparison(a, b)
qk.releaseActivity(id, cursor)
qk.releaseItems(id)
qk.releaseInboxCount(wsId)
qk.releaseMetrics(scope)
qk.releasesForAsset(assetId)
qk.releasesForVersion(versionId)
qk.releaseReadinessForPublish(assetId, versionId, releaseType)
```

No collision with APP 005 (`qk.comment*`, `qk.annotation*`), APP 006 (`qk.review*`), APP 007 (`qk.approval*`), or APP 008 (`qk.requirement*`). Invalidators `invalidateReleasesLists`, `invalidateRelease`, `invalidateReleaseInbox` invoke the correct combination of list-scope, detail, chain, evidence, comparison, inbox, and readiness keys per mutation.

---

## 9. Routing

Router entries added to `app/src/router.tsx`:

| Path | Component | Notes |
|---|---|---|
| `/workspace/:ws_id/releases` | `WorkspaceReleasesScreen` | Workspace-scoped dashboard |
| `/workspace/:ws_id/project/:proj_id/releases` | `ProjectReleasesScreen` | Project-scoped dashboard (replaced `ReleasesStub`) |
| `/workspace/:ws_id/project/:proj_id/release/:release_id` | `ReleaseDetailScreen` | Detail with tabs: Overview / Evidence / Comparison / History / Notes — no Discussions tab |
| `/deep/release/:id` | `DeepLinkResolver kind="release"` | Real resolver; not a stub |

**URL parameters (owned by APP 009):**

- Dashboard: `?view=all | draft | released | withdrawn | discarded | published_by_me`, `?q=<search>`, `?compose=1`.
- Detail: `?tab=overview | evidence | comparison | history | notes`.

No collision with APP 003 `?discipline`, APP 005 `?comment/annotation`, APP 006 `?review`, APP 007 `?approval/participant`, APP 008 `?priority/source/category/scope/code`.

---

## 10. Reusable primitives

**Consumed unchanged from prior slices:**

- APP 002 shell primitives: `AuthGate`, `RootLayout`, `WorkspaceLayout`, `ProjectLayout`, `DeepLinkResolver`, `NavRail`, `qk` registry, `CAPABILITY_KEYS`.
- APP 006 shared infrastructure: `user_bookmarks`, `user_saved_views` with `entity_kind='release'` and `scope='releases'`.
- APP 007 read consumer: `get_approval_readiness(p_version_id uuid) → jsonb` (positional call in `get_release_readiness_for_publish`).
- APP 008 read consumer: `get_release_readiness_for_version(p_asset_version_id uuid) → jsonb` (positional call in `get_release_readiness_for_publish`).

**Deliberately NOT consumed:** APP 005 `CommentsPanel` — releases never collect discussion (Freeze Index premise). No Discussions tab.

**New primitives introduced by APP 009 (release-specific, not intended for cross-slice reuse in this wave):**

- `ReleasesDashboardBody`, `ReleaseFilterBar`, `ReleaseCard`, `ReleaseActions`
- `ReleaseEvidenceCard`, `ReleaseComparisonView`, `ReleaseNotesEditor`, `ReleaseHistoryList`
- `CreateReleaseDialog`, `ReleasesTabPanel`

---

## 11. Build verification

Recorded in the Implementation Report and re-confirmed by the Final Architecture Audit:

- `npm run typecheck`: **PASS** (zero errors).
- `npm run build`: **PASS** (1921 modules transformed).
- Bundle: before `956.36 kB` → after `987.21 kB` (270.65 kB gzip). Delta **+30.85 kB raw** (~+8 kB gzip). Vite warning threshold unchanged from pre-APP-009 posture.
- Migration application: **PASS** — both canonical migrations recorded (Migration B split into 9 remote apply-chunks; all recorded).
- Frozen migration byte integrity: `20260729230000_releases.sql` SHA1 = `e4ea0fb1d38930c78fe203e099162079d29bd444` (unchanged); `20260801220000_auth_008_release_rls.sql` SHA1 = `acfa168c10d53eb22a70f59cbab24720b1d62031` (unchanged).

---

## 12. Advisor results

- **Security advisors:** zero ERROR advisors. WARN classes limited to `authenticated_security_definer_function_executable` (23 release-related lints — matching the baseline established since APP 001: every new SECURITY DEFINER RPC correctly uses `search_path=''`, REVOKEs from `public/anon/authenticated`, and GRANTs EXECUTE only to `authenticated, service_role`) and one pre-existing `auth_leaked_password_protection` unrelated to APP 009. **No new issue class introduced.**
- **Performance advisors:** three `unindexed_foreign_keys` INFO on the new FKs — all three FKs are actually covered by partial indexes (I-2, I-4, I-5) which the linter does not credit; for `ON DELETE RESTRICT` + partial predicate matching non-NULL child rows, partial coverage is sufficient. Five `unused_index` INFO on freshly-created indexes (identical to APP 006/007/008 post-freeze posture; expected to clear once dashboards see load). **No new issue class introduced.**

---

## 13. APP 001–008 preservation

Every prior slice's contract is intact:

- **APP 001 — Auth.** `lign_has_capability` reissued with every prior capability role map byte-identical. No CHECK, RLS, or capability key removed or renamed.
- **APP 002 — Workspaces / Projects.** Router, `qk` registry, `CAPABILITY_KEYS`, `DeepLinkResolver` all extended additively. Every existing route, key, capability, resolver, and hotkey handler preserved verbatim.
- **APP 003 — Projects, Disciplines & Design Workspace.** No file under `features/projects/`, `features/designs/`, or `features/design-workspace/` modified. Releases integrate into the workspace via a right-panel tab that composes `ReleasesTabPanel`.
- **APP 004 — Files & Viewer.** Viewer, upload queue, publish/discard flows untouched. Version reads consumed read-only by release evidence bundle.
- **APP 005 — Comments & Annotations.** No modification. Explicit exclusion: no `target_release_id` on comments.
- **APP 006 — Reviews.** No file modified. `user_bookmarks` / `user_saved_views` reused as external primitives with `entity_kind='release'` and `scope='releases'`. Review completion counts consumed read-only in evidence bundle.
- **APP 007 — Approvals.** No file modified. `get_approval_readiness(p_version_id uuid) → jsonb` consumed read-only by `get_release_readiness_for_publish` and `publish_release`. Frozen `enforce_release_finalization_prerequisites` trigger (which requires `approval_requests.status='approved'`) preserved and compatible with the new RPC-level readiness gate (RPC is a superset check; trigger never blocks a policy-satisfied publish).
- **APP 008 — Requirements.** No file modified. `get_release_readiness_for_version(p_asset_version_id uuid) → jsonb` consumed read-only by `get_release_readiness_for_publish` and `publish_release`. Frozen 5 requirement capabilities and 4 event names byte-identical.

The frozen releases baseline migrations (`20260729230000_releases.sql` and `20260801220000_auth_008_release_rls.sql`) remain live, authoritative, and SHA1-verified byte-identical. All frozen release triggers (`releases_set_updated_at`, `releases_status_via_rpc`, `releases_finalization_prerequisites_insert`, `releases_finalization_prerequisites_update`, `release_items_parent_draft_mutation`) are enabled (`tgenabled='O'`) and empirically fire as designed. Frozen `release.*` capability and event vocabulary preserved.

---

## 14. Non-blocking observations

The Final Architecture Audit identified the following observations. All are informational and **do not affect the frozen implementation.** They are recorded here for transparency, not as freeze blockers.

- **F-B1 (INFO):** Supabase performance advisor flags 3 `unindexed_foreign_keys` on the new release FKs. All three FKs are actually covered by partial indexes (I-2, I-4, I-5) which the linter does not credit. For `ON DELETE RESTRICT` FKs with predicates matching non-NULL child rows, partial coverage is sufficient. This is per-design (Freeze Index §6 — small indexes) and matches the intentional trade-off documented in the Backend Proposal.
- **F-B2 (INFO):** Supabase performance advisor flags 5 `unused_index` on freshly-deployed indexes. Expected pattern; matches APP 006/007/008 post-freeze posture. Will clear once dashboards see traffic.
- **F-TD1 (LOW):** The local repository contains 2 canonical APP 009 migration files, but the remote DB records Migration B as 9 chunked entries (a consequence of the resumed implementation session). A fresh `supabase db reset` reproduces production correctly from the 2 canonical local files; the chunked remote entries are a deployment artifact. A future housekeeping pass may regenerate the chunked copies or squash to a single file for repro-durability. Non-blocking.

None of these observations constitute a contract violation, a runtime bug, a cross-slice regression, or a maintenance risk that requires action prior to freeze. They may be addressed in a future housekeeping pass without amendment.

---

## 15. Permanent freeze confirmations

- ✅ Every CRITICAL requirement from the APP 009 Backend Re-freeze Report is implemented and empirically verified (F-1 asymmetric chain immutability; F-2 CREATE OR REPLACE + default-tail with frozen overloads dropped for named-arg unambiguity).
- ✅ Every HIGH requirement is implemented (F-3 supersession FOR UPDATE ordering reserved for Wave 4 RPC per proposal; F-4 evidence always captured).
- ✅ Every MEDIUM and LOW correction is applied (F-5 reserved event names registered in EVENT_MODEL.md; F-6 triggers NOT SECURITY DEFINER; L-1 atomic publish UPDATE; L-2 concrete activity filter predicate).
- ✅ Every backend contract item — schema, indexes, constraints, FKs, triggers, RLS, RPCs, capabilities, events — matches the frozen contract as verified by direct `pg_catalog` inspection.
- ✅ Every frontend contract item — routes, screens, primitives, query keys, mutations, URL parameters, deep links — matches the frozen contract as verified by file inspection.
- ✅ Every event vocabulary item matches the frozen contract. Past-tense verbs; `subject_kind='release'` or `'release_item'`; no `round_number` leakage; RESERVED names locked.
- ✅ Every capability matches the frozen contract. 4 frozen keys byte-identical; 6 reserved names zero-granted.
- ✅ Every RPC matches the frozen contract. SECURITY DEFINER + `search_path=''` + REVOKE/GRANT discipline verified on every function. Single-function `CREATE OR REPLACE` + default-tail eliminates named-argument dispatch ambiguity.
- ✅ APP 001–008 remain untouched except for approved additive extensions (§13).
- ✅ APP 009 introduces no unauthorized surface. No new tables. No unapproved capability keys. No unapproved event types. No route or query-key collisions.
- ✅ Empirical smoke tests pass: chain-immutability triggers fire with the F-1 asymmetric contract (NULL→uuid succeeds on `superseded_by_release_id`; uuid→uuid and uuid→NULL raise; any `root_release_id` change raises); named-argument and positional dispatch both resolve unambiguously on `finalize_release` and `withdraw_release`; evidence and release_type immutable after release; frozen release migrations SHA1-identical.
- ✅ Build verification: typecheck PASS, build PASS, bundle delta within acceptable slope, all migrations applied.
- ✅ Advisor verification: zero ERROR advisors; only expected WARN/INFO classes; no new issue class introduced by APP 009.
- ✅ Realtime remains OUT: `releases` and `release_items` NOT in `supabase_realtime` publication.

---

## 16. Final verdict

**APP 009 is permanently frozen. This report becomes the authoritative certification document for APP 009. Future changes require an amendment and re-freeze.**

---

## Amendment — 2026-09-18 — migration artifact reconciliation

This certification's claims about the **deployed database** are unchanged and
remain accurate. Separately, this slice's `.sql` files in
`supabase/migrations/` were replaced with the exact statements that were applied
to `hsfporioghapwghrvvzd`, because they had drifted from it (in some slices they
were missing entirely). No deployed object, policy, RPC, trigger, grant or row
was altered.

See [`MIGRATION_ARTIFACT_AMENDMENT.md`](MIGRATION_ARTIFACT_AMENDMENT.md) and
[`../../supabase/migrations/RECONCILIATION.md`](../../supabase/migrations/RECONCILIATION.md).
Rule 20 is now enforced by `ops/verify_migrations.sh`.
