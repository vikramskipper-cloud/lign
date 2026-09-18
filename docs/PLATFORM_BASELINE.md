# LIGN Platform Baseline

## 1. Purpose

This document is the **constitutional summary** of the LIGN platform as it stands after the frozen certification of APP 001 through APP 009. It is written for future developers, architects, AI agents, code reviewers, and contributors who need a single, load-bearing reference to the platform's non-negotiable shape.

- **What it is.** A distillation of already-frozen rules established across APP 001–APP 009 certifications, freeze indexes, and the underlying cross-slice architecture documents (`DOMAIN_MODEL.md`, `EVENT_MODEL.md`, `PERMISSIONS.md`, `STATE_MACHINES.md`, `DATABASE_SCHEMA.md`, `AUTHORIZATION_ARCHITECTURE.md`, `STORAGE_ARCHITECTURE.md`, `SCHEMA_V1_LOCK.md`, `FREEZE_INDEX.md`).
- **What it is not.** It is not an APP module, not a design proposal, not a redesign, not an introduction of new rules. It introduces nothing that is not already frozen.
- **Relationship to the certifications.** The final certifications under `docs/freeze/APP_00N_FINAL_CERTIFICATION.md` remain the sole authoritative record for each slice. This document ratifies and summarizes them; where any conflict arises, the certifications win.
- **Amendment path.** Anything summarized here changes only via the governance workflow of §9 applied to the originating slice.

---

## 2. Project philosophy

LIGN is a universal design collaboration platform. Its first customers are architecture, interior design, and design-build teams, but the core domain must generalize across product design, furniture, industrial design, engineering, graphic design, packaging, fashion, and UI/UX (memory `project_lign_overview.md`).

- **Industry-neutral core.** The core domain never hard-codes `Architect`, `Contractor`, `Client`, `Vendor`, `Drawing`, `FloorPlan`, or any other profession-specific entity. Such vocabulary lives only as UI labels or tag metadata.
- **Roles are capability sets.** Authorization is expressed in capability keys (`project.*`, `review.*`, `approval.*`, `requirement.*`, `release.*`, etc.), never in professional titles. Roles (`lead`, `contributor`, `reviewer`, `approver`, `observer` at project scope; `owner`, `admin`, `member` at workspace scope) are shorthand for capability bundles.
- **Everything additive.** Every slice extends prior slices without modifying them. No frozen column, constraint, RPC signature, capability key, event name, route, query key, or component API is ever renamed or removed.
- **Everything traceable.** Every mutation flows through a `SECURITY DEFINER` RPC that emits a past-tense event into `activity_events`. `ActivityEvent` is the single append-only history spine — per-entity history tables are not the pattern (`FREEZE_INDEX.md` APP 001).
- **Everything auditable.** Frozen migration files are SHA-verified byte-identical after freeze; frozen triggers remain `tgenabled='O'`; the `hsfporioghapwghrvvzd` project is the sole Supabase target (memory `project_lign_schema_v1_lock.md`).

---

## 3. Core pipeline

The platform's governance pipeline is `Requirements → Reviews → Approvals → Releases`. Each stage is owned by exactly one slice; each stage consumes upstream evidence read-only and exposes read-only readiness downstream.

### Requirements (APP 008, on frozen REQUIREMENTS 001–005)
- **Owns.** Requirement authoring, hierarchy (depth = 1), applicability to design assets, per-version compliance assessments, dashboard/detail/trace surfaces, priority/source/category/scope/verification metadata (APP 008 §2).
- **Does not own.** Discussion (delegated to APP 005 via the 8th XOR arm `target_requirement_id`), approvals, releases.
- **Consumes upstream.** Frozen REQUIREMENTS 001–005 schema (`requirements`, `requirement_design_assets`, `version_requirement_assessments`), APP 002 shell, APP 005 comments (via widened XOR).
- **Exposes downstream.** `get_release_readiness_for_version(p_asset_version_id uuid) → jsonb` consumed by APP 009 (APP 008 §3, APP 009 §10).

### Reviews (APP 006)
- **Owns.** Review lifecycle (7-state), review rounds (chain model with immutable columns), reviewer roster (member/stakeholder XOR), reviewer policies (parallel/sequential/quorum), review dashboards, Review Detail, review metrics, review capabilities (`review.coordinate`, `review.reopen`), review routing, review query keys, and 5 emitted review events (APP 006 §2).
- **Does not own.** Approvals, releases, requirement assessments, comment persistence.
- **Consumes upstream.** APP 002 shell, APP 004 viewer/`FilesPanel`, APP 005 `CommentsPanel`.
- **Exposes downstream.** `get_review_inbox_count`, `get_project_review_metrics`, `get_workspace_review_metrics`; `reviews.id` referenced by approvals via loose FK.

### Approvals (APP 007)
- **Owns.** Approval lifecycle (8-state enum `draft/pending/in_progress/approved/rejected/cancelled/expired/superseded`), approval chain (`supersedes_approval_request_id`, `root_approval_request_id`), approver roster (with `required`, `veto_power`, `removed_at`, `removed_reason`), response model (with additive `abstained`), 3 new capabilities (`approval.veto`, `approval.expire`, `approval.supersede`), approval dashboards + detail (APP 007 §2).
- **Does not own.** Rounds, coordinator role, reviews, requirements, releases.
- **Consumes upstream.** APP 006 chain-init pattern (T-CRIT-1 precedent), `related_review_id` loose FK to reviews.
- **Exposes downstream.** `get_approval_readiness(p_version_id uuid) → jsonb` consumed by APP 009.

### Releases (APP 009, on frozen releases baseline `20260729230000_releases.sql` + AUTH 008)
- **Owns.** Release lifecycle (3-state `draft/released/withdrawn` + reserved `scheduled`, `superseded`), release chain (`superseded_by_release_id`, `root_release_id`), evidence snapshot (jsonb, immutable after release), release_type (7-value enum), release dashboards + detail with tabs `overview | evidence | comparison | history | notes` (APP 009 §2).
- **Does not own.** Discussion (no CommentsPanel; no `target_release_id` on comments), votes (no roster on releases), requirement assessments (no assessment RPCs on releases).
- **Consumes upstream.** `get_approval_readiness` (APP 007) and `get_release_readiness_for_version` (APP 008) via `get_release_readiness_for_publish`, read-only.
- **Exposes downstream.** Reserved event and capability names for future waves; no current consumer.

---

## 4. Platform principles

Every rule below is already frozen. The principles are enumerated once here and enforced everywhere.

- **Additive-only evolution.** No frozen column dropped, renamed, or narrowed; no frozen RPC signature altered; no capability key or event name renamed (APP 006 §3, APP 007 §13, APP 008 §4, APP 009 §13).
- **No breaking contracts.** Later slices never modify earlier slices' migrations, RLS, RPCs, capability role maps, event vocabulary, routes, query keys, or public component APIs.
- **No hidden coupling.** Slices interact only via public RPCs and public events. Direct table mutation across slice boundaries is forbidden.
- **RPC-first writes.** Every user-visible mutation flows through a `SECURITY DEFINER` RPC. Write RLS policies are RPC-only; direct DML by client roles is denied on governance tables.
- **RLS protects reads.** Every user-facing table has RLS enabled with SELECT policies gated by a capability-check function.
- **Capabilities authorize.** `lign_has_capability(p_project_id, p_capability_key)` is the sole authorization vocabulary. Every RPC re-checks capabilities inline even when RLS also gates the read (defense in depth).
- **Events describe history.** Every state-changing RPC emits a past-tense event into `activity_events`. `activity_events` is append-only (UPDATE + DELETE blocked at the DB boundary, `SCHEMA_V1_LOCK.md` invariant 14).
- **ActivityEvent is the audit spine.** No per-entity history table pattern; every history-of-record query hits `activity_events` (`FREEZE_INDEX.md` APP 001).

---

## 5. Canonical architectural rules

The following write-once rules were established in APP 006–APP 009 and now govern every future RPC, migration, trigger, and index.

- **`CREATE OR REPLACE` discipline.** Frozen RPC extensions use single-function `CREATE OR REPLACE` with default-tail parameters; multiple overloads that risk named-argument dispatch ambiguity are eliminated (APP 009 F-2). In APP 009 the frozen 1-arg `finalize_release` and 2-arg `withdraw_release` overloads were dropped after single-function replacements were installed.
- **Default-tail parameters.** Additive extensions to a frozen RPC signature append parameters with `DEFAULT` clauses; positional callers of the frozen signature continue to bind unchanged (APP 006, APP 007, APP 008 Option A).
- **No overload ambiguity.** Where Option A coexistence is required (APP 006 `create_review`/`complete_review`, APP 007 `respond_to_approval`/`cancel_approval`, APP 008 `create_requirement`/`edit_requirement`), the frozen and extended overloads are distinct-arity so named-argument dispatch remains unambiguous (APP 007 §4.12, APP 008 §4.7).
- **Chain-init discipline (APP 006 T-CRIT-1).** Any RPC that initializes a chain row pre-computes the id via `gen_random_uuid()`, then INSERTs with all chain columns (`root_*`, `parent_*`) inline in one statement. No post-INSERT UPDATE of chain columns is ever permitted. The chain-immutability trigger is the enforcement mechanism (APP 006 §6 fix, APP 007 §4.6, APP 009 §4.2).
- **Exactly-once immutable chains (APP 009 F-1 asymmetric).** For supersession columns (`superseded_by_release_id`), `NULL → uuid` is permitted exactly once at the initial supersession write; `uuid → uuid` and `uuid → NULL` are rejected. For root columns (`root_release_id`, `root_review_id`, `root_approval_request_id`), any change after INSERT is rejected (APP 009 §2 F-1).
- **FK covering index in the same migration.** Every new foreign key gets a covering index in the same migration file that adds the FK (memory `project_lign_schema_v1_lock.md`; APP 006 §4; APP 007 §7; APP 008 §14).
- **`SECURITY DEFINER` hardening.** Every write RPC is `SECURITY DEFINER` with `SET search_path = ''`, `REVOKE ALL FROM public, anon, authenticated`, and `GRANT EXECUTE TO authenticated, service_role`. Purge-lifecycle RPCs (STORAGE 004) grant to `service_role` only (memory `project_lign_storage_layer_lock.md`).
- **Trigger discipline.** Row-local triggers that inspect only OLD/NEW columns are NOT `SECURITY DEFINER` (APP 009 F-6, matching frozen `enforce_release_status_via_rpc` precedent). Cross-table triggers that need to bypass caller RLS are `SECURITY DEFINER` with `search_path=''` and REVOKEd from `public/anon/authenticated` (APP 007 pattern; APP 008 `requirements_default_owner_on_insert`).
- **Composite tenancy on FKs.** Every cross-tenant FK is composite `(child_col, workspace_id) → parent(id, workspace_id)`; where a project ID is available it is included, e.g. release chain FKs `(col, project_id, workspace_id) → releases(id, project_id, workspace_id)` (APP 007 §3, APP 008 §2, APP 009 §3).
- **RESERVED vocabulary.** Names registered as reserved (capabilities and event types) are **name-locked**: they must never be emitted, must have zero role grants, and must not be wired into any RPC body (APP 006 `review.deadline_approached/passed`; APP 007 `approval.deadline_approached`; APP 008 `requirement.ai_suggest`, `requirement.ai_classify`, `requirement.import`, `requirement.auto_assess`, plus event names; APP 009 `release.schedule`, `.supersede`, `.ai_suggest`, `.ai_classify`, `.audit_export`, `.recall` and 7 reserved event names).
- **Server-opaque cursor pagination.** Dashboard reads paginate via opaque cursors keyed on `(sort_col, id)`; clients do not construct or introspect cursor payloads (APP 006, APP 007, APP 008, APP 009 dashboards).

---

## 6. Backend conventions

### RPC conventions
- Every RPC is `SECURITY DEFINER` with `search_path=''`, REVOKE from `public/anon/authenticated`, GRANT to `authenticated, service_role` (STORAGE purge RPCs: `service_role` only).
- Additive extensions to frozen RPCs follow Option A additive-tail; both frozen and extended overloads are preserved unless overload ambiguity requires the frozen one to be dropped (APP 009 F-2).
- Read RPCs return typed rows or `jsonb`; write RPCs emit a past-tense event into `activity_events` in the same transaction.
- Every RPC re-checks the relevant capability inline via `lign_has_capability`, even when RLS also gates the underlying read.

### Migration conventions
- Two-migration split pattern: `<slice>_schema` (columns, constraints, indexes, triggers) followed by `<slice>_authz_and_rpcs` (capability grants, RPCs, RLS extensions) — APP 006 (012+013), APP 007 (032–037), APP 008 (2 canonical + 2 folded fixes), APP 009 (2 canonical, B chunked remotely).
- Frozen migration files are SHA-verified byte-identical after freeze; APP 009 explicitly records SHA1 of frozen release baseline files (§11).
- All migrations apply to project `hsfporioghapwghrvvzd` only; never `vzgoobyltkgfrtycvtiz` (nuesync).

### Index conventions
- Every new FK gets a covering index in the same migration.
- Partial indexes are used for status-scoped predicates (e.g. `WHERE status <> 'purged' AND purge_reserved_at IS NULL` on `files_workspace_checksum_key`).
- Trigram GIN indexes install `pg_trgm` into the `extensions` schema; operator classes are qualified as `extensions.gin_trgm_ops` (APP 008 §14).

### Constraint conventions
- Additive enum columns use NULL-permissive CHECKs of shape `col IS NULL OR col IN (…)` to tolerate pre-migration rows (APP 008 §3, APP 009 §3).
- Comment target XOR predicate shape is `= 1` — arm count widens but the predicate shape never relaxes to `>= 0` (APP 008 F-6.1-L1 discipline).
- Composite unique keys anchor cross-slice FKs (e.g. `releases_id_workspace_key`).

### Trigger conventions
- Row-local triggers (chain-immutability, evidence-immutability, type-immutability) are NOT `SECURITY DEFINER` (APP 009 F-6).
- Cross-table triggers that need caller-RLS bypass are `SECURITY DEFINER` with `search_path=''` (APP 007 `no-self-approve`; APP 008 `requirements_default_owner_on_insert`).
- Every frozen trigger remains `tgenabled='O'` after any slice ships (empirically verified at each freeze).

### Capability conventions
- Capability keys follow `<module>.<verb>` (e.g. `review.coordinate`, `approval.veto`, `requirement.assess`, `release.finalize`).
- Frozen role-map arrays are byte-identical when `lign_has_capability` is reissued; additive keys are appended at the tail of the applicable role branch.
- Reserved capability names are registered in the function body with zero role grants.

### Event conventions
- Event names follow past-tense `<module>.<past-verb>` (e.g. `review.reopened`, `approval.superseded`, `requirement.assessed`, `release.finalized`).
- Frozen event names never gain a new alias; additive change is via payload keys only (APP 008 §12, APP 009 §7).
- RESERVED event names are past-tense and un-emitted; registered in `EVENT_MODEL.md` at slice freeze (APP 009 F-5 doc-diff discipline).

### RLS conventions
- Reads via a capability-check function (`lign_has_capability`).
- Writes RPC-only; write RLS policies are absent or explicitly deny direct DML.
- DELETE denied on governance tables (`activity_events`, `requirements`, `version_requirement_assessments`, `comment_edits`, `decisions`, `approval_responses`) — the pattern is archive/supersede, not hard-delete (`SCHEMA_V1_LOCK.md` invariants 6, 8, 11, 14; memory `project_lign_requirements_layer_lock.md`).

---

## 7. Frontend conventions

- **Routing namespace.** All authenticated routes live under `/workspace/:ws_id/…`; project-scoped routes live under `/workspace/:ws_id/project/:proj_id/…` (`FREEZE_INDEX.md` APP 002). All authenticated routes descend from `Gated → RootLayout`.
- **Deep-link routes.** `/deep/<kind>/:id` resolves via `DeepLinkResolver`; `kind` accepts new values additively. Current kinds: `comment`, `annotation`, `review`, `reviewer`, `approval`, `approver`, `requirement`, `release`.
- **Query keys.** All keys live in the `qk` registry under module-scoped prefixes and are append-only: `qk.review*`, `qk.approval*`, `qk.requirement*`, `qk.release*`, plus foundational `qk.session`, `qk.workspaces`, `qk.projects`, `qk.projectCapabilities`, etc.
- **Invalidator helpers.** Each module ships `invalidate<Module>Lists`, `invalidate<Module>`, `invalidate<Module>Inbox` under `src/features/shared/invalidate.ts`; mutations call the correct combination per RPC.
- **URL grammar per module.** Each slice owns a disjoint set of URL parameter names (see §14 Appendix).
- **Reusable primitives.** `user_bookmarks` and `user_saved_views` (APP 006 shared infrastructure), `RosterEditor` (APP 006, composed unmodified by APP 007's `ApprovalRosterEditor`), `CommentsPanel` (APP 005, embedded unmodified by APP 006/007/008 detail tabs; explicitly NOT consumed by APP 009), `DeepLinkResolver` (APP 002), `NavRail` (APP 002), `StateBadge` (APP 005, extended additively by APP 006/007/008), `useCopyLink` (APP 005, `LinkKind` extended additively per slice), `useWorkspaceHotkeys` (APP 005, additive handlers per slice).
- **Component vs feature ownership.** Cross-slice primitives live under `src/features/shared/` and `src/shell/`. Feature-specific components (e.g. `ApprovalActions`, `RequirementFilterBar`, `ReleaseEvidenceCard`) live under the owning slice's `src/features/<module>/` directory and are not reused across slices in this wave.
- **Optimistic mutation posture.** No optimistic cache mutation on governance-sensitive writes (release publish/withdraw, approval publish) — server-confirmed only (APP 009 §4.14).

---

## 8. Cross-slice communication

Slices communicate only via public RPCs and public events. The following are forbidden across slice boundaries:

- Direct SELECT of another slice's table bypassing that slice's read RPC where one exists.
- Direct UPDATE/INSERT/DELETE against another slice's tables (write access is RPC-only within the owning slice).
- Bypassing another slice's capability checks by calling internal helper functions.

Read consumption across slices is fine; write mutation is not. Illustrative frozen patterns:

- **APP 009 consumes APP 007 and APP 008 read-only.** `get_release_readiness_for_publish` calls `get_approval_readiness(p_version_id uuid)` and `get_release_readiness_for_version(p_asset_version_id uuid)` positionally, then merges the result into its own readiness contract (APP 009 §10).
- **APP 008 consumes APP 005 additively.** The 8th comment target XOR arm (`target_requirement_id`) was added by APP 008; the frozen 7-arm predicate shape `= 1` was preserved (APP 008 §2 F-6.1-L1).
- **APP 007 consumes APP 006 chain-init pattern.** `create_approval_draft` and `supersede_approval_request` follow the T-CRIT-1 pre-compute-UUID + inline-INSERT discipline (APP 007 §2 F-7.1).
- **APP 006 consumes APP 005 `CommentsPanel` unmodified.** Review Detail Comments tab embeds it as-is (APP 006 §5).

Any slice that needs a datum from another slice fetches it through the owning slice's public read RPC; if no such RPC exists, the owning slice must add one under its own re-freeze cycle.

---

## 9. Governance workflow

Every APP slice from APP 006 forward has followed a 7-stage cycle. Every stage produces a document; every document is preserved permanently under `docs/` or `docs/freeze/`.

1. **Freeze Index** — `docs/APP_00N_FREEZE_INDEX.md`. Enumerates the frozen surface at architectural level.
2. **Backend Proposal** — `docs/APP_00N_BACKEND_PROPOSAL.md`. Concrete SQL, RPC signatures, RLS, events, capabilities.
3. **Backend Re-freeze Review** — audit report identifying CRITICAL/HIGH/MEDIUM/LOW findings against the proposal.
4. **Backend Re-freeze Report** — the applied corrections; often merged into the head of the Backend Proposal.
5. **Implementation** — migrations applied to `hsfporioghapwghrvvzd`; frontend surface built and typechecked.
6. **Implementation Report** — records what shipped, verification results, deviations.
7. **Final Architecture Audit + Final Certification** — `docs/freeze/APP_00N_FINAL_CERTIFICATION.md`. Permanent freeze marker.

**Amendment process.** Any post-certification change requires an approved amendment document (`docs/freeze/APP_00N_AMENDMENT_00M.md`) that cites the section being amended, preserves backwards compatibility, and re-runs the full cycle (APP 006 §8). Any change to a frozen surface without an approved amendment is a **contract violation**.

---

## 10. Module dependency graph

Dependencies flow strictly one direction; later slices never modify earlier slices; earlier slices know nothing about later slices.

```
APP 001 (Domain Model & Platform Baseline)
   |
   v
APP 002 (Application Shell)
   |
   v
APP 003 (Projects, Disciplines & Design Workspace)     [re-freeze 2026-08-07: Migration 010 disciplines]
   |
   v
APP 004 (File Management & Viewer)                     [Migration 011: version_files write RLS]
   |
   v
APP 005 (Comments & Annotations)                       [no backend migrations]
   |
   v
APP 006 (Reviews)                                      [Migrations 012-013 + create_review init patch]
   |
   v
APP 007 (Approvals)                                    [Migrations 032-037]
   |
   v
APP 008 (Requirements product surface)                 [on frozen REQUIREMENTS 001-005; Migrations 038-041]
   |
   v
APP 009 (Releases product surface)                     [on frozen releases baseline + AUTH 008; Migrations 042-050]
   |
   v
APP 010 (Notifications)      reserved capability + event payload extensions accepted; no delivery yet
   |
   v
APP 011 (Realtime)           reserved channel names only; no publication additions
```

Prerequisite backend layers (frozen before or alongside APP slices): AUTH 001–009, STORAGE 001–004, REQUIREMENTS 001–005, releases baseline (`20260729230000_releases.sql`, AUTH 008 `20260801220000_auth_008_release_rls.sql`).

---

## 11. Permanent invariants

Every invariant below is frozen; violating any of them is a contract breach.

- **RLS on every user-facing table.** Enabled at Schema V1 lock; every subsequent slice preserves it (`SCHEMA_V1_LOCK.md` locked inventory).
- **`SECURITY DEFINER` on every write RPC**, with `SET search_path = ''`, REVOKE from `public/anon/authenticated`, GRANT to `authenticated, service_role` (STORAGE purge RPCs: `service_role` only).
- **Additive-only evolution.** No frozen column dropped, renamed, or narrowed; no frozen RPC signature altered semantically.
- **Composite tenancy on all cross-tenant FKs.** Every non-workspace, non-profile row carries `workspace_id`; cross-workspace relationships are structurally impossible (`SCHEMA_V1_LOCK.md` invariant 15).
- **Chain columns immutable.** `root_*` chain columns fully immutable after INSERT. Supersession columns permit exactly-once `NULL → uuid` per APP 009 F-1 asymmetric contract; all other transitions rejected.
- **Events are past-tense.** RESERVED names never emitted; frozen event names never renamed (APP 006 §2, APP 007 §4.11, APP 008 §4.10, APP 009 F-5).
- **Frozen migration files SHA-verified byte-identical** after each freeze (APP 009 §11 explicitly recorded SHA1 for the frozen releases baseline files).
- **Frozen pre-existing layers.** REQUIREMENTS 001–005 (2026-08-06), STORAGE 001–004 (2026-07-30), AUTH 001–009 backend, Schema V1 (Migrations 001–009, 2026-07-29 with re-freeze for Migration 010 on 2026-08-07 and policy-only Migration 011). All are pre-existing frozen layers that later APPs build on without modification.
- **`hsfporioghapwghrvvzd` is the LIGN Supabase project.** `vzgoobyltkgfrtycvtiz` (nuesync) is never touched.
- **Releases tables OUT of `supabase_realtime` publication.** `releases` and `release_items` are not enrolled; reserved channel names (`release:<id>`, `project:<id>:releases`) await a future re-freeze (APP 009 §4.13, §15).
- **Requirements tables OUT of `supabase_realtime` publication.** All 3 requirements tables absent from `pg_publication_tables` for `supabase_realtime` (APP 008 §2, memory `project_lign_requirements_layer_lock.md`).
- **Comments target XOR arm count** is exactly 8 after APP 008 widening, and the frozen `comments_target_xor_check` predicate shape remains `= 1` (APP 008 §2, §15).
- **Every capability re-check is inline in the RPC** even when RLS also gates it — defense in depth (APP 007 §12, APP 008 §12, APP 009 §12).
- **`EVENT_MODEL.md` vocabulary matches actual emitters.** F-5 doc-diff discipline established in APP 009: reserved event names are registered in `EVENT_MODEL.md` at slice freeze; no emitter appears in any `pg_proc` body for a reserved name.
- **Append-only history.** `activity_events`, `comment_edits`, `decisions`, and `approval_responses` are UPDATE/DELETE-blocked at the DB boundary; corrections happen via new rows, not mutations (`SCHEMA_V1_LOCK.md` invariants 6, 8, 11, 14).

---

## 12. Things intentionally NOT solved (yet)

The following surfaces are **deliberately deferred**. They are not defects, not open bugs, and not blockers.

- **Realtime (APP 011).** Reserved channel names only; no `supabase_realtime` publication additions in APP 001–009.
- **Notifications (APP 010).** Reserved event payload extensions accepted; no delivery infrastructure yet.
- **AI features.** Reserved capability keys (`requirement.ai_suggest`, `requirement.ai_classify`, `requirement.auto_assess`, `release.ai_suggest`, `release.ai_classify`) with zero role grants; reserved event names (`release.ai_suggested`, `release.ai_classified`) with no emitter; no AI RPCs.
- **Multi-asset bundle releases.** APP 009 supports single-version releases only in v1; multi-asset bundles are reserved for a future wave.
- **External integrations.** `requirement.import` reserved capability only; no Jira / DOORS / ReqIF import RPCs (APP 008 §4.8).
- **Scheduled deadline emitters.** `review.deadline_approached/passed` and `approval.deadline_approached` reserved names; cron/edge-function emitter belongs to a future cron slice (APP 006 §7, APP 007 §3).
- **Workspace-shared saved views.** `user_saved_views.visibility='workspace'` reserved for v2; APP 006 v1 enforces `visibility='private'` at the RLS layer (APP 006 §7).
- **Multi-asset reviews and Review Bundles.** v2 per APP 006 D-10.
- **Optimistic mutation on governance-sensitive writes.** Release publish/withdraw and approval publish are deliberately server-confirmed only (APP 009 §4.14).
- **Chain supersession for releases.** Reserved-only in v1; `create_release_superseding` deferred to Wave 4 (APP 009 §2 F-3).
- **Cross-workspace / cross-project releases.** Not supported; single-project bundles only.
- **Cross-slice invalidation of review metrics from APP 005 comment mutations.** Deferred as non-blocking; `open_comment_count` may show stale values until manual refetch (APP 006 §7).
- **Workspace-level analytics** and **multi-select dashboard filters.** v2 per APP 006 §7.
- **Recall / audit-export release features.** `release.recall`, `release.audit_export`, `release.recalled`, `release.audit_exported` reserved names only.
- **Any surface not explicitly frozen in APP 001–009 certifications.** If it is not in a certification, it does not exist.

---

## 13. Future evolution

New modules and amendments extend the platform without breaking anything by following these rules:

- **New APP slices follow the governance workflow (§9).** Freeze Index → Backend Proposal → Backend Re-freeze Review → Backend Re-freeze Report → Implementation → Implementation Report → Final Architecture Audit → Final Certification.
- **Consume prior slices via public RPCs only.** Reuse `get_approval_readiness`, `get_release_readiness_for_version`, `list_reviews_dashboard`, etc.
- **Reuse existing primitives (§7).** `RosterEditor`, `CommentsPanel`, `user_bookmarks`, `user_saved_views`, `DeepLinkResolver`, `NavRail`, `StateBadge`, `useCopyLink`, `useWorkspaceHotkeys`.
- **Register new capability keys under an unreserved `<module>.<verb>` name.** Append to the applicable role branches in `lign_has_capability`.
- **Register new event names under an unreserved past-tense `<module>.<past-verb>` name.** Update `EVENT_MODEL.md` in the Wave 1 doc-diff of the slice (F-5 discipline).
- **Add columns to a frozen table only via a new APP re-freeze cycle** with additive-only guarantees (NULL-permissive CHECKs, composite tenancy on any new FK, covering index in the same migration, `SECURITY DEFINER` + `search_path=''` on any new RPC).
- **Amend a frozen slice** by filing `docs/freeze/APP_00N_AMENDMENT_00M.md`, running the re-freeze review, applying, and re-certifying (APP 006 §8).

Extension is additive; modification requires an amendment; violation is a contract breach.

---

## 14. Appendix

### Canonical status vocabularies

| Slice | States |
|---|---|
| Reviews (APP 006) | `draft`, `ready_for_review`, `open`, `in_progress`, `waiting`, `completed`, `cancelled` |
| Approvals (APP 007) | `draft`, `pending`, `in_progress`, `approved`, `rejected`, `cancelled`, `expired`, `superseded` (`approved` terminal-immutable) |
| Requirements (REQUIREMENTS 001–005) | `draft`, `active`, `superseded`, `archived` |
| Releases (APP 009) | `draft`, `released`, `withdrawn` (reserved: `scheduled`, `superseded`) |
| Approval response decision (APP 007) | `approved`, `rejected`, `abstained` (`changes_requested` preserved at CHECK level for legacy reads only) |
| Approval policy (APP 007) | frozen `any`, `all` + additive `single`, `unanimous`, `majority`, `quorum`, `sequential` |
| Release type (APP 009) | 7-value enum (NULL-permissive CHECK) including `internal`, `preview`, `regulatory`, `final`, and reserved slots |

### Canonical event prefixes

`review.*`, `approval.*`, `requirement.*`, `release.*`, `comment.*`, `annotation.*`, `change.*`, `decision.*`, `file.*` (`file.attached`, `file.purged` only per STORAGE lock), `activity.*`. Reserved: `notification.*` (APP 010), `realtime.*` (APP 011) if either becomes name-locked; APP 009 registered 7 reserved `release.*` names, APP 008 registered 5 reserved `requirement.*` names, APP 007 registered `approval.deadline_approached`, APP 006 registered `review.deadline_approached/passed`.

### Canonical capability prefixes

Foundational: `project.*`, `workspace.*`, `asset.*`, `version.*`, `file.*`, `collection.*`, `activity.*`. Slice-owned: `review.*`, `approval.*`, `requirement.*`, `release.*`, `comment.*`, `annotation.*`, `change.*`, `decision.*`. Reserved (name-only, zero grants): `requirement.ai_suggest`, `requirement.ai_classify`, `requirement.import`, `requirement.auto_assess`, `release.schedule`, `release.supersede`, `release.ai_suggest`, `release.ai_classify`, `release.audit_export`, `release.recall`.

### Canonical query-key prefixes

`qk.review*`, `qk.approval*`, `qk.requirement*`, `qk.release*`, plus foundational `qk.session`, `qk.profile`, `qk.workspaces`, `qk.workspace`, `qk.workspaceMembers`, `qk.projects`, `qk.project`, `qk.projectCapabilities`, `qk.projectParticipants`, `qk.collections`, `qk.disciplines`, `qk.assets`, `qk.asset`, `qk.assetVersions`, `qk.assetVersion`, `qk.assetNeighbors`, `qk.versionFiles`, `qk.file`, `qk.signedUrl`, `qk.commentsForVersion`, `qk.commentsForAnnotation`, `qk.comment`, `qk.commentEdits`, `qk.annotationsForVersion`, `qk.annotation`, `qk.bookmarks`, `qk.savedViews`.

### Canonical URL parameter ownership

| Parameter | Owner | Notes |
|---|---|---|
| `?returnTo` | APP 002 | Sign-in bounce; regex `^\/[^/].*$` |
| `?from` | APP 003 | `collection:<id>|unfiled` |
| `?discipline` | APP 003 | Discipline filter |
| `?tab` | Shared across slices | Each screen scopes its own value set (`details|versions|files|comments|participants|activity|assessments|trace|history|notes|evidence|comparison|overview|decisions`) |
| `?comment`, `?annotation`, `?comments` | APP 005 | `?comments=unresolved|mine|mentions` |
| `?review`, `?participant`, `?owner`, `?reviewer`, `?due`, `?round` | APP 006 | Detail + dashboard filters |
| `?approval`, `?participant` (shared value set with reviews per slice), `?policy` | APP 007 | Detail context flag + dashboard filters |
| `?priority`, `?source`, `?category`, `?scope`, `?code`, `?compose`, `?requirement` | APP 008 | Dashboard filters + detail context flag |
| `?view`, `?status`, `?type`, `?q` | APP 009 dashboards | `?view=all|draft|released|withdrawn|discarded|published_by_me`; `?compose=1` for create dialog |

No two slices share a parameter name with a shared semantic.

---

> **This document is the constitutional architecture of LIGN.**
