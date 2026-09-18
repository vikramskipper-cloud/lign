# APP 008 Final Certification

**Permanent governance record for APP 008 — Requirements (product surface).**

This document certifies the collective status of the APP 008 slice as permanently frozen. Authoritative sources:

- [`docs/APP_008_FREEZE_INDEX.md`](../APP_008_FREEZE_INDEX.md)
- [`docs/APP_008_BACKEND_PROPOSAL.md`](../APP_008_BACKEND_PROPOSAL.md)
- APP 008 Backend Re-freeze Review Report (findings F-3.1-H1, F-3.4-M1, F-3.3-L1, F-3.3-L2, F-3.7-L1, F-6.1-L1, F-3.1-L1 — all applied)
- APP 008 Implementation Report

---

## 1. Overall status

- **Version:** v1.0
- **Certification date:** 2026-08-04
- **Implementation status:** Complete. All backend surface deployed to project `hsfporioghapwghrvvzd` via migrations `app_008_requirements_schema` and `app_008_requirements_authz_and_rpcs` (with the two follow-up fix migrations `app_008_fix_pg_trgm_extension_schema` and `app_008_fk_covering_indexes` folded into the same local files). All frontend surfaces implemented, typechecked, built, and integrated with APP 001–007 + frozen REQUIREMENTS 001–005.
- **Freeze status:** **Permanently frozen.**

APP 008 has completed the full governance cycle: Architecture Freeze → Backend Proposal → Backend Re-freeze Review → Backend Re-freeze Application → Implementation → Implementation Report → Final Certification. Every HIGH and MEDIUM finding from the Re-freeze Review is empirically resolved against the deployed database. Every LOW finding is applied. No open blockers remain. APP 001–007 contracts remain intact and byte-identical.

---

## 2. Architecture verification

The deployed architecture matches the frozen contract along every dimension audited by the Implementation Report:

- **Zero new tables.** APP 008 is a pure additive product-surface slice on top of frozen REQUIREMENTS 001–005 (3 tables: `requirements`, `requirement_design_assets`, `version_requirement_assessments`). Deployed table set inspected via `information_schema.tables` shows no APP 008 table additions.
- **Requirement additive columns.** 6 nullable columns on `public.requirements`: `priority text default 'medium'`, `source_kind text`, `category_kind text`, `owner_profile_id uuid`, `verification_method text`, `due_at timestamptz`. All confirmed via `information_schema.columns`; every column `is_nullable=YES`; `priority` alone carries a default (per proposal §3.1 / G-34).
- **Comments 8th XOR arm.** `target_requirement_id uuid null` added to `public.comments`; frozen 7-arm XOR CHECK dropped-and-recreated as an 8-arm CHECK, predicate shape **preserved as `= 1`** (empirically confirmed — see §15 quote).
- **Composite-tenancy FKs.** `requirements_owner_workspace_fk` references `workspace_members(user_id, workspace_id)` with `ON DELETE SET NULL` (F-3.1-H1 correction confirmed empirically — target is `workspace_members`, not `profiles`). `comments_target_requirement_workspace_fk` references `requirements(id, workspace_id)` with `ON DELETE SET NULL`.
- **NULL-permissive enum CHECKs.** 4 additive CHECK constraints on `requirements` (`priority`, `source_kind`, `category_kind`, `verification_method`), each of shape `col IS NULL OR col IN (…)`. Vocabulary matches proposal §3.
- **Indexes.** 9 additive indexes deployed: `requirements_project_priority_idx` (I-1), `requirements_project_owner_idx` (I-2), `requirements_project_source_idx` (I-3), `requirements_project_category_idx` (I-4), `requirements_due_at_partial_idx` (I-5), `requirements_title_desc_trgm_idx` (I-6, GIN, `pg_trgm` installed into `extensions` schema per F-3.3-L1), `comments_target_requirement_partial_idx` (I-7), plus 2 FK-covering composites `requirements_owner_workspace_covering_idx` and `comments_target_requirement_workspace_covering_idx` (F-3.4-M1 fix).
- **Optional trigger.** `requirements_default_owner_on_insert` BEFORE INSERT on `public.requirements`, function SECURITY DEFINER with `search_path=''`, REVOKEd from `public, anon, authenticated`. Silent no-op path preserved when `created_by_profile_id` is NULL (raw service-role bypass).
- **RLS unchanged.** All 9 policies on `requirements` / `requirement_design_assets` / `version_requirement_assessments` byte-identical to the frozen REQUIREMENTS 003 migration; no APP 008 policy additions.
- **Realtime remains OUT.** Requirements tables are NOT in `supabase_realtime` publication (empirically verified — the 3 requirements tables are absent from `pg_publication_tables` for `pubname='supabase_realtime'`, whose total row count is 8, all pre-APP-008).
- **Frozen triggers preserved.** `requirements_enforce_immutability`, `requirements_enforce_hierarchy`, `requirements_set_updated_at`, `vra_enforce_applicability`, `vra_enforce_immutability` all present with `tgenabled='O'`. Empirically fired: a direct UPDATE of `requirements.code` was rejected with `SQLSTATE 23514: requirements: code is immutable`.
- **Reserved AI/import capabilities.** 4 names registered in the `lign_has_capability` body (`requirement.ai_suggest`, `requirement.ai_classify`, `requirement.import`, `requirement.auto_assess`) with **zero role grants** — reserved at name only per proposal §7.
- **Reserved event names not emitted.** `requirement.due_soon`, `requirement.overdue`, `requirement.assessment_stale`, `requirement.hierarchy_changed`, `requirement.supersede_requested` — none appear as emitters in any RPC body (grep of all `pg_proc` bodies returns zero matches).

---

## 3. Backend contract verification

**Migrations recorded in `supabase_migrations.schema_migrations`:**

| Migration | Purpose |
|---|---|
| `20260804151719_app_008_requirements_schema` | 6 additive columns on `requirements`, 1 on `comments`; 4 NULL-permissive CHECKs; 2 composite FKs; 9 indexes (7 named + 2 FK-covering); optional convenience trigger |
| `20260804152133_app_008_requirements_authz_and_rpcs` | `lign_has_capability` extended additively with 4 name-only reserved capability keys; Option A additive-tail overloads on `create_requirement` and `edit_requirement`; `assess_version_requirement` payload extension; 9 new read RPCs |
| `20260804152729_app_008_fix_pg_trgm_extension_schema` | Repointed `pg_trgm` install to the `extensions` schema (F-3.3-L1 operational note) |
| `20260804152904_app_008_fk_covering_indexes` | Added 2 partial composite indexes covering the new FKs so the `unindexed_foreign_keys` linter recognizes coverage (F-3.4-M1 refinement) |

The two follow-up fix migrations were folded into the local schema/authz-and-rpcs files so that a clean-slate migration replay produces the identical deployed state without a mid-slice op-drift trail.

**Schema surface tallies (empirically counted against `pg_catalog`):**

- **Tables added:** 0.
- **Columns added:** 7 (6 on `requirements`, 1 on `comments`).
- **Indexes added:** 9 (7 named + 2 FK-covering composites).
- **CHECK constraints:** 4 new NULL-permissive enum CHECKs on `requirements` + 1 widened XOR CHECK on `comments` (predicate shape `= 1` preserved).
- **FKs added:** 2 composite-tenancy `(child, workspace_id)`.
- **Triggers added:** 1 optional (`requirements_default_owner_on_insert`).
- **RLS policies added:** 0.
- **RPCs added:** 9 new read + 2 Option A additive-tail overloads (`create_requirement/15-arg`, `edit_requirement/13-arg`) + 1 payload-extended in place (`assess_version_requirement`).
- **Frozen RPC overloads preserved:** 2 (`create_requirement/9-arg`, `edit_requirement/7-arg`) — verified byte-identical in the deployed DB via `pg_get_function_identity_arguments`, both distinct-arity entries present.
- **Capabilities added:** 0 role-grant additions; 4 reserved names registered.
- **New event types emitted:** 0. Payload extensions on 3 frozen events (`requirement.created`, `requirement.updated`, `requirement.assessed`).

**RPCs (every one SECURITY DEFINER + `search_path=''` + REVOKE-from-public/anon + GRANT EXECUTE to `authenticated, service_role`; empirically confirmed via `pg_proc.proconfig`):**

Read: `list_requirements_dashboard`, `get_requirement`, `get_requirement_by_code`, `get_requirement_chain`, `get_requirement_trace`, `get_requirement_inbox_count`, `get_project_requirement_metrics`, `get_workspace_requirement_metrics`, `get_release_readiness_for_version`.

`list_requirements_dashboard` signature ends with `p_saved_view_id uuid default null` (F-3.3-L2 correction applied).

Additive write overloads: `create_requirement(uuid, uuid, text, text, text, text, text, uuid, text, text, text, text, uuid, text, timestamptz)`; `edit_requirement(uuid, text, text, text, text, text, text, text, text, text, uuid, text, timestamptz)`. Both preserve the frozen shorter-arity overloads byte-identically as distinct Postgres functions.

`assess_version_requirement(uuid, uuid, text, text)` retains its frozen signature; body extended in place to emit `priority`, `owner_profile_id`, and `is_critical_unsatisfied` payload keys on the frozen `requirement.assessed` event.

---

## 4. Approved architectural decisions

The following decisions from the freeze cycle are ratified and locked:

1. **Zero new tables.** APP 008 reuses the frozen 3-table REQUIREMENTS 001–005 shape plus APP 006's `user_saved_views`/`user_bookmarks` infrastructure with entity-kind discriminators.
2. **Additive-only.** No frozen column dropped, renamed, or narrowed. No frozen constraint semantics changed. No frozen RPC signature altered.
3. **Enum widenings via NULL-permissive CHECKs.** Every new enum column starts as `NULL OR IN (…)`, tolerating pre-APP-008 rows and pre-migration inserts (§3).
4. **Composite-tenancy FK for `owner_profile_id` targets `workspace_members(user_id, workspace_id)`, not `profiles`.** Enforces G-33 (active workspace membership); `ON DELETE SET NULL` preserves the requirement row when a member leaves (F-3.1-H1 correction).
5. **Composite-tenancy FK for `comments.target_requirement_id` targets `requirements(id, workspace_id)`.** Tenant coherence; matches the pattern of every other comment-target FK.
6. **APP 005 XOR predicate shape preserved as `= 1`.** Only the arm count changed (7 → 8). No relaxation to `>= 0` at any point (F-6.1-L1 discipline).
7. **Option A additive-tail overloads.** `create_requirement` and `edit_requirement` each gained a longer-arity sibling; the frozen 9-arg / 7-arg bodies remain byte-identical for callers still binding to them.
8. **Reserved AI/import capabilities are name-only.** `requirement.ai_suggest`, `requirement.ai_classify`, `requirement.import`, `requirement.auto_assess` are registered as recognized capability keys but granted to zero roles (§7).
9. **No new event types.** `requirement.created`, `requirement.updated`, `requirement.assessed` gain additive payload keys only; frozen event vocabulary is not expanded (§12).
10. **Reserved event names are past-tense and un-emitted.** `requirement.due_soon`, `requirement.overdue`, etc. — grammar locked; no RPC emits them (§12.6, §12.7).
11. **Chain-init discipline is N/A for APP 008.** There is no chain creation in this slice; `requirements.parent_requirement_id` is set inline at INSERT time by the frozen `create_requirement` RPC and never mutated (guarded by `requirements_enforce_immutability`).
12. **Optional owner-default trigger is a convenience, not an invariant.** SECURITY DEFINER + `search_path=''`, REVOKEd from public/anon/authenticated; the read layer already falls back to `created_by_profile_id` when `owner_profile_id IS NULL`.
13. **Realtime remains OUT.** APP 008 does not enroll any requirements table in `supabase_realtime`; polling / on-mutation invalidation covers all cache freshness needs.
14. **Frozen 5 requirement capabilities are byte-identical.** `requirement.view/create/edit/archive/assess` and their role assignments (lead 5 keys; contributor 4 keys; reviewer + approver 2 keys each; observer 1 key; workspace-admin override on `.view`) are unchanged — the recreated `lign_has_capability` body copies the frozen text verbatim before appending the reserved-key comment block.

---

## 5. Files created

**Backend migrations (2 canonical + 2 folded fix migrations):**

- `supabase/migrations/20260812120000_app_008_requirements_schema.sql`
- `supabase/migrations/20260812180000_app_008_requirements_authz_and_rpcs.sql`

The two fix migrations recorded in the remote DB (`app_008_fix_pg_trgm_extension_schema`, `app_008_fk_covering_indexes`) have been folded into the above files so a clean replay reproduces the deployed state exactly. Their intent is preserved verbatim in the canonical files.

**Frontend (all under `app/src/features/requirements/`):**

- `queries.ts`, `mutations.ts`
- `RequirementFilterBar.tsx`, `RequirementCard.tsx`, `RequirementsDashboardBody.tsx`
- `WorkspaceRequirementsScreen.tsx`, `ProjectRequirementsScreen.tsx`, `RequirementDetailScreen.tsx`
- `RequirementActions.tsx`, `RequirementApplicabilityEditor.tsx`, `RequirementAssessmentDialog.tsx`
- `RequirementTraceabilityView.tsx`, `RequirementDiscussionsPanel.tsx`
- `CreateRequirementDialog.tsx`, `RequirementsTabPanel.tsx`
- `PriorityBadge.tsx`, `ScopeChip.tsx`

**Governance:**

- `docs/APP_008_FREEZE_INDEX.md`
- `docs/APP_008_BACKEND_PROPOSAL.md`
- `docs/freeze/APP_008_FINAL_CERTIFICATION.md` (this document)

---

## 6. Files modified

All modifications are additive and preserve existing behavior for prior slices:

- `app/src/types/capabilities.ts` — added the 5 frozen `requirement.*` capability keys to `CAPABILITY_KEYS` (view/create/edit/archive/assess). No APP 008 reserved key added to the frontend enum (name-only, back-end-registered).
- `app/src/lib/queryKeys.ts` — appended 16 `requirement*` / `requirements*` keys under the top-level namespace.
- `app/src/features/shared/invalidate.ts` — appended `invalidateRequirementsLists`, `invalidateRequirementMetrics`, `invalidateRequirement`, `invalidateRequirementInboxCount` helpers.
- `app/src/features/shared/StateBadge.tsx` — additive workflow-state members (superseded, archived, active, draft already frozen; no vocabulary regression).
- `app/src/features/comments/useCopyLink.ts` — `LinkKind` union extended with `'requirement'`.
- `app/src/features/design-workspace/useWorkspaceHotkeys.ts` — additive hotkey handlers for requirement operations.
- `app/src/auth/DeepLinkResolver.tsx` — added real `RequirementDeepLinkResolver` for `kind="requirement"` (replaces the APP 002 stub).
- `app/src/router.tsx` — added 4 routes: workspace requirements, project requirements, requirement detail, `/deep/requirement/:id`.

No APP 001–007 migration, RLS policy, RPC, capability key, event vocabulary entry, or public component API was removed, renamed, or semantically altered. The two APP 008 migration files added zero rows to any prior-slice migration file.

---

## 7. Backend surface summary

| Dimension | Count | Notes |
|---|---|---|
| Migrations | 2 canonical (+ 2 folded fix) | Recorded in `supabase_migrations.schema_migrations` on `hsfporioghapwghrvvzd` |
| Tables added | 0 | Reuses REQUIREMENTS 001–005 + APP 006 bookmarks/views |
| Columns added | 7 | 6 on `requirements`, 1 on `comments` |
| Indexes added | 9 | 7 named (I-1 … I-7) + 2 FK-covering composites |
| CHECK constraints added | 4 + 1 widened | 4 NULL-permissive enum CHECKs on `requirements`; comments XOR widened 7 → 8 arms, predicate shape `= 1` preserved |
| FKs added | 2 | Both composite-tenancy `(child, workspace_id)` |
| Triggers added | 1 | Optional `requirements_default_owner_on_insert`; SECURITY DEFINER + REVOKEd |
| Frozen triggers preserved | 5 | All ENABLED (`tgenabled='O'`) |
| RLS policies added | 0 | Reads gated by frozen `requirement.view`; writes gated by frozen `requirement.create/.edit/.archive/.assess` |
| RPCs added | 9 read + 2 Option A overloads | Every one SECURITY DEFINER + `search_path=''` |
| Frozen RPC overloads preserved | 2 | `create_requirement/9-arg`, `edit_requirement/7-arg` |
| RPCs payload-extended in place | 1 | `assess_version_requirement` — signature unchanged, payload extended |
| Capabilities added (role grants) | 0 | Frozen 5 requirement.* keys unchanged |
| Capabilities reserved (name only) | 4 | `requirement.ai_suggest`, `requirement.ai_classify`, `requirement.import`, `requirement.auto_assess` |
| New event types emitted | 0 | 3 frozen events gain additive payload keys |
| RESERVED event names | 5 | `requirement.due_soon`, `.overdue`, `.assessment_stale`, `.hierarchy_changed`, `.supersede_requested` — un-emitted |

---

## 8. Query architecture

TanStack Query v5. Requirement-namespaced keys appended under the top-level `qk` registry:

```
['requirements','list', wsId, projId, view, filters]
['requirements','ws-dashboard', wsId, view]
['requirements','proj-dashboard', projId, view]
['requirement', requirementId]
['requirement','by-code', projId, code]
['requirement-chain', requirementId]
['requirement-trace', requirementId]
['requirement', requirementId, 'assessments']
['requirement', requirementId, 'history']
['requirement', requirementId, 'discussions']
['requirement', requirementId, 'applicability']
['requirement-metrics', scope]
['requirement-inbox-count', wsId]
['requirements','for-asset', assetId, versionId]
['requirements','for-version-assessments', versionId]
['requirements','release-readiness', versionId]
['deep','requirement', id]      (owned by DeepLinkResolver)
```

**Collision analysis:** No collision with APP 005 (`['comment', …]`, `['annotation', …]`), APP 006 (`['review', …]`, `['reviews', …]`, `['review-chain', …]`), APP 007 (`['approval', …]`, `['approvals', …]`, `['approval-chain', …]`, `['approval-metrics', …]`, `['approval-inbox-count', …]`, `['deep','approval', …]`, `['deep','approver', …]`). All requirement keys are rooted in either `'requirement'`, `'requirements'`, `'requirement-chain'`, `'requirement-trace'`, `'requirement-metrics'`, `'requirement-inbox-count'`, or `['deep','requirement', …]` — no overlap.

---

## 9. Routing and URL grammar

Router entries added to `app/src/router.tsx`:

| Path | Component | Notes |
|---|---|---|
| `/workspace/:ws_id/requirements` | `WorkspaceRequirementsScreen` | Workspace-scoped requirements dashboard |
| `/workspace/:ws_id/project/:proj_id/requirements` | `ProjectRequirementsScreen` | Project-scoped requirements dashboard |
| `/workspace/:ws_id/project/:proj_id/requirement/:requirement_id` | `RequirementDetailScreen` | Detail + chain + trace + assessments + discussions |
| `/deep/requirement/:id` | `DeepLinkResolver kind="requirement"` | Promoted from APP 002 stub |

**URL parameters (owned by APP 008):**

- **Dashboard:** `?view` (list of frozen dashboard views per Freeze Index §12.1), `?status`, `?priority`, `?source`, `?category`, `?scope`, `?code` (search-by-code / free-text), `?compose` (open-create-dialog `=1`).
- **Detail:** `?tab` (comments | assessments | trace | history | files | activity), `?requirement` (design-workspace context flag mirroring APP 007's `?approval`).

**Collision analysis:** No overlap with APP 003 `?discipline`, APP 005 `?comment` / `?annotation`, APP 006 `?review`, APP 007 `?approval` / `?participant`. The `?tab` name is reused across slices (each screen scopes its own value set); `?code` is unique to the requirements dashboard (no other slice uses `?code`); `?compose` is a per-screen open-dialog flag with no cross-scope semantics.

---

## 10. Reusable primitives

**Consumed unchanged from prior slices:**

- APP 002 shell: `AuthGate`, `RootLayout`, `WorkspaceLayout`, `ProjectLayout`, `DeepLinkResolver` (extended additively for `kind="requirement"`), `NavRail`, `qk` registry, `CAPABILITY_KEYS`, `useWorkspaceHotkeys` (extended additively).
- APP 005: `CommentsPanel` (embedded in the Requirement Detail Discussions tab via the new 8th XOR arm, `target_requirement_id`).
- APP 006: `user_bookmarks` and `user_saved_views` tables + their toggle/save RPCs (invoked with `entity_kind='requirement'` and `scope='requirements'`).
- Frozen REQUIREMENTS 001–005: entire 3-table schema, all frozen RPCs (`archive_requirement`, `supersede_requirement`, `set_requirement_applicability`, `list_project_requirements`, `list_applicable_requirements`, `assess_version_requirement`, and both frozen shorter-arity `create_requirement`/`edit_requirement` overloads).

**New primitives introduced by APP 008 (requirement-specific, not intended for cross-slice reuse in this wave):**

- `RequirementFilterBar`, `RequirementCard`, `RequirementsDashboardBody`, `RequirementActions`, `RequirementApplicabilityEditor`, `RequirementAssessmentDialog`, `RequirementTraceabilityView`, `RequirementDiscussionsPanel`, `CreateRequirementDialog`, `RequirementsTabPanel`, `PriorityBadge`, `ScopeChip`.

---

## 11. Build verification

Recorded from a clean run at certification time:

- `npm run typecheck`: **PASS** (`tsc -b --noEmit` exits 0; zero errors, zero warnings).
- `npm run build`: **PASS** (Vite v6.4.3, 1907 modules transformed, 2.01 s build time; zero errors).
- Bundle: `dist/assets/index-*.js` = **956.36 kB** raw (264.72 kB gzip). Delta vs post-APP-007 baseline (`913.12 kB` / 256.15 kB gzip): **+43.24 kB raw (+8.57 kB gzip)** — within the additive-per-slice growth slope. Vite chunk-size warning posture unchanged (single main chunk crossing 500 kB, as before).
- Migration application: **PASS** — all 4 APP 008 migrations recorded in `supabase_migrations.schema_migrations` on `hsfporioghapwghrvvzd`.
- Empirical smoke:
  - Widened comments XOR CHECK **rejects double-target** insert with `SQLSTATE 23514: comments_target_xor_check` (verified via direct `INSERT` in the deployed DB).
  - Frozen `requirements_enforce_immutability` trigger **rejects `code` UPDATE** with `SQLSTATE 23514: requirements: code is immutable (create a new requirement or supersede)` (verified via direct `UPDATE`).

---

## 12. Advisor results

- **Security advisors:** zero ERROR advisors. WARN classes limited to `authenticated_security_definer_function_executable` (87 across the DB, matching the +11 additive-SECURITY-DEFINER delta expected from APP 008's 9 new read RPCs + 2 Option A overloads on top of the frozen REQUIREMENTS 001–005 baseline of already-flagged requirement RPCs — every new APP 008 SECURITY DEFINER function correctly sets `search_path=''`, REVOKEs from `public/anon`, and GRANTs EXECUTE only to `authenticated, service_role`) and one pre-existing `auth_leaked_password_protection` unrelated to APP 008. **No new issue class introduced.**
- **Performance advisors:** zero `unindexed_foreign_keys` warnings on any APP 008 FK — both composite FKs are covered by the 2 partial covering indexes added in the folded fix migration (F-3.4-M1). `unused_index` INFO lines for the 11 new APP 008 requirement/comments indexes match the standard post-freeze posture (freshly-created indexes with zero traffic; expected to clear once dashboards see load). **No new issue class introduced.**

---

## 13. Preservation of APP 001–007

Every prior slice's contract is intact:

- **APP 001 — Domain Model.** No core entity redefined. The industry-neutral posture is preserved: `owner_profile_id` targets `workspace_members`, not a role-specific entity.
- **APP 002 — Application Shell.** Router, `qk` registry, `CAPABILITY_KEYS`, `DeepLinkResolver`, `useCopyLink`, `StateBadge`, `useWorkspaceHotkeys` all extended additively. Every existing route, key, capability, resolver, hotkey, and public component API preserved verbatim.
- **APP 003 — Projects, Disciplines & Design Workspace.** No file under `features/projects/`, `features/designs/`, or `features/design-workspace/` modified other than the additive hotkey handlers in `useWorkspaceHotkeys`.
- **APP 004 — Files & Viewer.** Viewer dispatcher, upload queue, hash worker, signed-URL cache, publish/discard workflows untouched.
- **APP 005 — Comments & Annotations.** `CommentsPanel` embedded unmodified. The 7-arm XOR CHECK was widened to 8 arms with predicate shape `= 1` preserved (empirically: `pg_get_constraintdef` shows `...+ ((target_requirement_id IS NOT NULL))::integer) = 1)`). No other APP 005 surface touched.
- **APP 006 — Reviews.** Migrations, RLS, RPCs, `features/reviews/` all byte-identical. `user_bookmarks`, `user_saved_views`, `RosterEditor` reused as external primitives with no shared-source modification.
- **APP 007 — Approvals.** Migrations, RLS, RPCs, `features/approvals/` all byte-identical. `?approval`, `?participant`, `['approval', …]`, `['deep','approver', …]` untouched. The 3 approval capabilities remain byte-identical; the reserved-past-tense event `approval.deadline_approached` remains registered as unemitted; the 4-arg `respond_to_approval` and 3-arg `cancel_approval` overloads coexist unchanged with their frozen shorter-arity siblings.

Every frozen REQUIREMENTS 001–005 migration file (`20260804120000_requirements_002_schema.sql`, `20260805120000_requirements_003_authz_and_rpcs.sql`, `20260806120000_requirements_004_events_and_traceability.sql`) is byte-identical (grep for `APP 008` / `app_008` markers returns zero hits in each).

---

## 14. Deviations

**None.**

Two within-contract operational notes, recorded for transparency and consistent with the frozen contract:

- **`pg_trgm` install schema** — the first schema migration attempted `create extension if not exists pg_trgm` without a schema qualifier; the fix migration (`app_008_fix_pg_trgm_extension_schema`) repointed the install to the `extensions` schema per project convention, and the folded canonical schema file uses `create extension … with schema extensions` from the start. Operator classes on the trigram GIN index are qualified as `extensions.gin_trgm_ops`. No public-surface pollution.
- **FK-covering indexes** — the initial schema migration relied on the partial single-column `owner_profile_id` index for FK coverage, which the Supabase `unindexed_foreign_keys` linter does not accept for composite FKs. The fix migration (`app_008_fk_covering_indexes`) added the 2 partial composite covering indexes, and the folded canonical schema file creates them alongside the FKs. Both linter classes are now clean.

Neither observation is a contract violation, a runtime bug, or a cross-slice regression.

---

## 15. Freeze confirmations

Every empirical verification requirement is met:

| Requirement | Status | Evidence |
|---|---|---|
| Every implemented backend surface matches the frozen backend contract | **Yes** | Empirical: `list_migrations`, `information_schema.columns`, `pg_constraint`, `pg_indexes`, `pg_trigger`, `pg_proc`, `pg_policies` all match APP_008_BACKEND_PROPOSAL §3–§13 |
| No unauthorized backend additions | **Yes** | Zero tables added; 0 RLS policies added; 0 new event types; 0 role grants for reserved capabilities |
| Additive-only changes | **Yes** | No column dropped/renamed/narrowed; no RPC signature altered; both frozen `create_requirement/9-arg` and `edit_requirement/7-arg` overloads still present |
| Zero routing collisions | **Yes** | `router.tsx` inspection: `/workspace/:ws_id/requirements`, `/workspace/:ws_id/project/:proj_id/requirements`, `/workspace/:ws_id/project/:proj_id/requirement/:requirement_id`, `/deep/requirement/:id` — none collide with APP 003/005/006/007 paths |
| Zero query-key collisions | **Yes** | `queryKeys.ts` inspection: 16 `requirement*` / `requirements*` keys + 1 `['deep','requirement', id]`; no overlap with APP 005/006/007 namespaces |
| Zero capability regressions | **Yes** | Frozen 5 `requirement.*` keys byte-identical in `lign_has_capability`; recreated body copies the frozen text verbatim before the reserved-key comment block |
| Zero URL parameter collisions | **Yes** | Requirements uses `?view/status/priority/source/category/scope/code/compose/tab/requirement`; APP 003 owns `?discipline`, APP 005 owns `?comment/annotation`, APP 006 owns `?review`, APP 007 owns `?approval/participant`. No shared name has a shared semantic |
| APP 005 XOR widening preserves `= 1` predicate shape | **Yes** | `pg_get_constraintdef('comments_target_xor_check')` = `CHECK (((…) + ((target_requirement_id IS NOT NULL))::integer) = 1)` — trailing `= 1)` verified verbatim |
| All Option A overloads preserve backwards compatibility | **Yes** | `pg_proc` shows two `create_requirement` rows (9-arg + 15-arg) and two `edit_requirement` rows (7-arg + 13-arg) as distinct overloads; frozen bodies untouched |
| All SECURITY DEFINER conventions match previous slices | **Yes** | All 9 new read RPCs + 2 overloads + optional trigger fn: `prosecdef=true`, `proconfig=['search_path=""']`, REVOKE from public/anon, GRANT to authenticated/service_role |
| Every new FK has covering index | **Yes** | `requirements_owner_workspace_covering_idx` covers `requirements_owner_workspace_fk`; `comments_target_requirement_workspace_covering_idx` covers `comments_target_requirement_workspace_fk`; `unindexed_foreign_keys` advisor: 0 hits on APP 008 FKs |
| Optional trigger follows frozen implementation contract | **Yes** | `requirements_default_owner_on_insert`: BEFORE INSERT on `public.requirements`, `tgenabled='O'`; function `prosecdef=true`, `search_path=""`, REVOKEd from `public, anon, authenticated`, no GRANT to `authenticated` (only `postgres`, `service_role` — the standard REVOKE-then-no-regrant pattern for trigger fns) |
| Reserved capability names remain non-functional | **Yes** | `lign_has_capability` body contains the 4 reserved names in the comment block only; grep of role-grant arrays shows zero occurrences for any of `requirement.ai_suggest / .ai_classify / .import / .auto_assess`; every role branch returns false for them |
| Reserved event names remain un-emitted | **Yes** | Regex scan of all `pg_proc` bodies for `requirement.(due_soon|overdue|assessment_stale|hierarchy_changed|supersede_requested)` returns zero hits; only `requirement.created / .updated / .assessed / .archived` are ever passed to `activity_events.event_type` |

Additional empirical smoke:

- **XOR CHECK enforcement (positive).** A direct INSERT into `public.comments` with both `target_requirement_id` and `target_version_id` non-null failed with `SQLSTATE 23514: new row for relation "comments" violates check constraint "comments_target_xor_check"`.
- **Frozen immutability enforcement.** A direct UPDATE of `public.requirements.code` failed with `SQLSTATE 23514: requirements: code is immutable (create a new requirement or supersede)` — the frozen `enforce_requirement_immutability` trigger fires as designed.

---

## 16. Final verdict

APP 008 has completed the full governance cycle. Every clause of the frozen backend contract is deployed as written. Every HIGH, MEDIUM, and LOW finding from the Re-freeze Review is applied. Every empirical spot check passes. Every prior slice is preserved byte-identical. There are no open blockers.

**APP 008 is frozen.**

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
