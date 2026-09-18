# APP 008 Backend Proposal (Re-freeze Applied)

## APP 008 Backend Re-freeze Report

### 1. Verdict

**APP 008 Backend is frozen.** All accepted findings from the Backend Re-freeze Review have been applied. No new backend surface introduced. No priority changes. No wave-plan changes. Zero CRITICAL findings; one HIGH, one MEDIUM, five LOW documentation-consistency corrections applied.

### 2. Corrections applied

| Finding ID | Severity | Applied? | Sections touched | One-line summary |
|---|---|---|---|---|
| F-3.1-H1 | HIGH | Yes | §1, §3.4, §5.1 | Composite FK target renamed `workspace_members(profile_id, workspace_id)` → `workspace_members(user_id, workspace_id)` with frozen-schema justification (unique key `workspace_members_workspace_user_key` on `(workspace_id, user_id)`) inlined. |
| F-3.4-M1 | MEDIUM | Yes | §12.2 | Removed stale "future re-freeze" claim; documented that `superseded_by_code` is already emitted by frozen `supersede_requirement` (REQUIREMENTS 004 L314). No additive `kind='supersede'` keys added. |
| F-6.1-L1 | LOW | Yes | §6.1 | XOR wording tightened: frozen `comments_target_xor_check` (`= 1`) is exactly-one-of-seven; APP 008 widens to exactly-one-of-eight. All "or 0 / all-null" language removed. |
| F-3.3-L1 | LOW | Yes | §8.5 | `assessment_coverage jsonb` and `applicability_summary jsonb` locked to canonical object shapes with per-key documentation. |
| F-3.3-L2 | LOW | Yes | §8.5, §15 | `p_saved_view_id uuid default null` added as distinct additive tail param; inline `saved:<uuid>` encoding replaced. Existing `p_view` string set unchanged. |
| F-3.7-L1 | LOW | Yes | §11.1 | Default-owner trigger dependency on `created_by_profile_id` (populated by frozen `create_requirement` per REQUIREMENTS 003 L235–L236) documented; service-role bypass no-op path stated. |
| F-3.1-L1 | LOW | Yes | §3.4, §5.1 | "Workspace member" clarified to mean an active member (`workspace_members` row where `status` is not `removed`). |

### 3. Final backend surface

| Kind | Count | Detail |
|---|---|---|
| Additive columns (frozen tables) | 7 | `requirements.priority text NULL default 'medium'`; `requirements.source_kind text NULL`; `requirements.category_kind text NULL`; `requirements.owner_profile_id uuid NULL`; `requirements.verification_method text NULL`; `requirements.due_at timestamptz NULL`; `comments.target_requirement_id uuid NULL`. |
| New tables (v1) | 0 | 8 reserved by name only: `requirement_subscriptions`, `requirement_templates`, `requirement_library_items`, `requirement_collections`, `requirement_disciplines`, `requirement_waivers`, `requirement_custom_sources`, `requirement_custom_categories`. |
| Additive indexes | 7 | I-1 `requirements_project_priority_idx`; I-2 `requirements_project_owner_idx`; I-3 `requirements_project_source_idx`; I-4 `requirements_project_category_idx`; I-5 `requirements_due_at_partial_idx`; I-6 `requirements_title_desc_trgm_idx`; I-7 `comments_target_requirement_partial_idx`. |
| Additive read RPCs | 9 | `get_requirement` (detail); `get_requirement_by_code` (deep-link resolver); `get_requirement_chain` (supersession chain); `get_requirement_trace` (traceability bundle); `list_requirements_dashboard` (dashboard row set); `get_requirement_inbox_count` (NavRail badge); `get_project_requirement_metrics` (project metrics); `get_workspace_requirement_metrics` (workspace rollup); `get_release_readiness_for_version` (APP 009 hook). |
| Frozen write RPCs extended via Option A tail params | 2 | `create_requirement` (+6 tail params); `edit_requirement` (+6 tail params). |
| New capabilities wired in Wave 1 | 0 | 4 reserved by name only: `requirement.ai_suggest`, `requirement.ai_classify`, `requirement.import`, `requirement.auto_assess`. |
| New emitted event types in Wave 1 | 0 | 6 reserved: `requirement.due_soon`, `requirement.overdue`, `requirement.imported`, `requirement.ai_suggested`, `requirement.ai_classified`, `requirement.auto_assessed`. |
| Optional triggers | 1 | `requirements_default_owner_on_insert` (BEFORE INSERT convenience). |
| Payload key additions on frozen `requirement.*` events | 3 of 4 events touched | `requirement.created` (adds `priority`, `source_kind`, `category_kind`, `owner_profile_id`, `verification_method`, `due_at`); `requirement.updated` kind=`edit` (adds `previous_*`/`new_*` for priority, owner, due_at; extended `changed_fields`); `requirement.assessed` (adds `priority`, `is_critical_unsatisfied`, `owner_profile_id`). `requirement.archived` unchanged in Wave 1. |
| Composite FK targets corrected | 1 | `requirements.owner_profile_id → workspace_members(user_id, workspace_id)` (was misstated as `(profile_id, workspace_id)`; corrected across §1, §3.4, §5.1). |

### 4. Final implementation waves

Four-wave plan preserved byte-for-byte from the pre-review proposal.

| Wave | Priority tier | Item count | Contents |
|---|---|---|---|
| Wave 1 | Critical | **12** | 4 columns on `requirements` + composite FK + 2 indexes (I-1, I-2); 3 read RPCs (`get_requirement`, `get_requirement_by_code`, `list_requirements_dashboard`); 2 extended write RPCs (`create_requirement`, `edit_requirement`); `requirement.created` payload extension. |
| Wave 2 | High | **10** | `requirements.due_at`; `comments.target_requirement_id` + FK + XOR widening; 4 indexes (I-3, I-4, I-5, I-7); 2 read RPCs (`get_requirement_chain`, `get_requirement_inbox_count`); `requirement.updated` and `requirement.assessed` payload extensions. |
| Wave 3 | Medium | **7** | Optional default-owner trigger; I-6 GIN trigram index; 4 read RPCs (`get_requirement_trace`, `get_project_requirement_metrics`, `get_workspace_requirement_metrics`, `get_release_readiness_for_version`); optional `requirement.archived` payload extension. |
| Wave 4 | Future | **20** | `requirements.verification_method`; 4 reserved capabilities; 6 reserved events; 4 reserved columns; 8 reserved tables; reserved realtime channels — intentionally unimplemented. |

**Tally: 12 Critical / 10 High / 7 Medium / 20 Future.** Identical to pre-review tallies.

### 5. Cross-slice guarantee

- **APP 001 (Auth), APP 002 (Workspaces/Projects), APP 003 (Assets), APP 004 (Versions), APP 005 (Comments/Reviews scaffolding), APP 006 (Reviews), APP 007 (Approvals):** frozen contracts intact. No file modified in any APP 001–007 document or migration. The APP 005 `comments` table receives one additive nullable column (`target_requirement_id`) and one CHECK widening (XOR arm count 7 → 8) via APP 008 migrations only; no APP 005 file byte changes.
- **REQUIREMENTS 001–005 migrations:** byte-identical. No CREATE/ALTER touching `requirements`, `requirement_design_assets`, `version_requirement_assessments`, `lign_has_capability`, the 6 frozen workflow RPCs, the 3 frozen read RPCs, or the frozen event emissions.
- **APP 009 (Releases):** consumes `get_release_readiness_for_version` (§8.9) read-only. Gate policy remains APP 009-owned.
- **APP 010 (Notifications):** consumes additive event payload keys per §12; no APP 010 file touched.
- **APP 011 (Realtime) — REMAINS OUT.** Requirements tables stay excluded from `supabase_realtime`. Any change to the realtime publication is a REALTIME re-freeze, not an APP 008 concern.

### 6. Freeze checklist

| # | Item | Status |
|---|---|---|
| 1 | Zero CRITICAL findings outstanding | Yes |
| 2 | F-3.1-H1 composite FK target column-name corrected | Yes |
| 3 | F-3.4-M1 stale `superseded_by_code` claim removed | Yes |
| 4 | F-6.1-L1 XOR predicate wording tightened | Yes |
| 5 | F-3.3-L1 `assessment_coverage` / `applicability_summary` shapes locked | Yes |
| 6 | F-3.3-L2 `p_saved_view_id` split out as distinct tail param | Yes |
| 7 | F-3.7-L1 default-owner trigger dependency note added | Yes |
| 8 | F-3.1-L1 active-member clarification added | Yes |
| 9 | No new backend surface introduced by re-freeze | Yes |
| 10 | Priority counts unchanged (12/10/7/20) | Yes |
| 11 | Wave plan tallies unchanged | Yes |
| 12 | No APP 001–007 file modified | Yes |
| 13 | REQUIREMENTS 001–005 migrations byte-identical | Yes |
| 14 | Frozen RPC signatures preserved byte-for-byte | Yes |
| 15 | Frozen event names and payload keys preserved (only additive keys) | Yes |
| 16 | Realtime remains OUT for requirements tables | Yes |

### 7. Freeze contract

This document is the authoritative backend contract for APP 008. Every additive column, index, RPC, tail parameter, event payload key, capability reservation, event reservation, table reservation, and realtime channel reservation enumerated below is the complete v1 backend delta. Any future change to this surface requires an amendment, a fresh re-freeze review, and explicit approval per LIGN governance discipline.

**APP 008 Backend is frozen.**

---

# APP 008 — Backend Proposal (Requirements Product Surface)

**Design proposal only. No SQL, no implementation, no migrations.** Every backend addition required to support the frozen APP 008 architecture, mapped to the Freeze Index sections and prioritized for a phased re-freeze. Backend Re-freeze Review has been applied; §25 captures every finding disposition.

**Companion documents:**
- [`APP_008_FREEZE_INDEX.md`](APP_008_FREEZE_INDEX.md) — the frozen architecture this proposal supports. §27 (backend-surface delta preview) is the authoritative scope anchor.
- [`APP_007_BACKEND_PROPOSAL.md`](APP_007_BACKEND_PROPOSAL.md) — pattern parity: chapter grammar, Option-A additive-tail RPC style, chain-init discipline citation, coverage-matrix shape.
- [`APP_006_BACKEND_PROPOSAL.md`](APP_006_BACKEND_PROPOSAL.md) — secondary pattern reference (T-CRIT-1 chain-initialization precedent).
- [`freeze/APP_007_FINAL_CERTIFICATION.md`](freeze/APP_007_FINAL_CERTIFICATION.md) — governance shape.
- [`SCHEMA_V1_LOCK.md`](SCHEMA_V1_LOCK.md) — the current schema lock; APP 008 extends it additively only.
- [`PERMISSIONS.md`](PERMISSIONS.md) — capability catalog; two reserved-only keys documented here (no wiring in v1).
- [`EVENT_MODEL.md`](EVENT_MODEL.md) — event vocabulary; six RESERVED names + payload extensions on four frozen events proposed here.

**Frozen invariants cited by this proposal (REQUIREMENTS 001–005; MUST NOT modify):**
- `supabase/migrations/20260804120000_requirements_002_schema.sql` L28–L91 — `public.requirements` table definition (structural columns, status CHECK, coherence CHECKs, `no_self_supersede` CHECK).
- `supabase/migrations/20260804120000_requirements_002_schema.sql` L52–L53 — the two anchor UNIQUE keys `(id, workspace_id)` and `(id, project_id)` on `requirements` that every downstream composite FK depends on.
- `supabase/migrations/20260804120000_requirements_002_schema.sql` L130–L158 — `enforce_requirement_hierarchy` trigger (one-level parent/child).
- `supabase/migrations/20260804120000_requirements_002_schema.sql` L164–L191 — `enforce_requirement_immutability` trigger (workspace_id, project_id, code, parent_requirement_id are structural).
- `supabase/migrations/20260804120000_requirements_002_schema.sql` L199–L230 — `public.requirement_design_assets` join table (empty = project-wide).
- `supabase/migrations/20260804120000_requirements_002_schema.sql` L236–L285 — `public.version_requirement_assessments` per-version compliance table + `vra_version_requirement_key` UNIQUE.
- `supabase/migrations/20260804120000_requirements_002_schema.sql` L293–L346 — `enforce_assessment_applicability` trigger (sub-req inherits parent applicability).
- `supabase/migrations/20260804120000_requirements_002_schema.sql` L348–L376 — `enforce_assessment_immutability` trigger.
- `supabase/migrations/20260804120000_requirements_002_schema.sql` L383–L415 — additive `changes.requirement_id` and `decisions.requirement_id` columns + covering indexes.
- `supabase/migrations/20260804120000_requirements_002_schema.sql` L434–L487 — RLS SELECT/INSERT/UPDATE policies on all three tables (no DELETE policy anywhere; DELETE is denied at RLS level).
- `supabase/migrations/20260805120000_requirements_003_authz_and_rpcs.sql` L30–L154 — `lign_has_capability` extension: five keys `requirement.view`, `requirement.create`, `requirement.edit`, `requirement.archive`, `requirement.assess` with the role map (lead all 5; contributor 4 sans archive; reviewer/approver view+assess; observer view; workspace admin gets view via override).
- `supabase/migrations/20260805120000_requirements_003_authz_and_rpcs.sql` L165–L247 — `create_requirement` signature (9 params) + advisory-xact-lock code generation (`R-NNN` root, `<parent>.<n>` sub).
- `supabase/migrations/20260805120000_requirements_003_authz_and_rpcs.sql` L260–L330 — `edit_requirement` signature (7 params); blocked on `superseded`/`archived`; toggles `draft ↔ active` only.
- `supabase/migrations/20260805120000_requirements_003_authz_and_rpcs.sql` L338–L386 — `archive_requirement` signature (1 param) + idempotency semantics.
- `supabase/migrations/20260805120000_requirements_003_authz_and_rpcs.sql` L396–L500+ — `supersede_requirement`, `set_requirement_applicability`, `assess_version_requirement` signatures and state-machine guards.
- `supabase/migrations/20260806120000_requirements_004_events_and_traceability.sql` L34–L110 — `create_requirement` emits `requirement.created` with `subject_snapshot={code,title,parent_requirement_id,initial_status}`.
- `supabase/migrations/20260806120000_requirements_004_events_and_traceability.sql` L112+ — `edit_requirement` emits `requirement.updated` (kind=`edit`) only when `changed_fields` is non-empty.
- `supabase/migrations/20260806120000_requirements_004_events_and_traceability.sql` — `archive_requirement` emits `requirement.archived`; `supersede_requirement` emits `requirement.updated` (kind=`supersede`); `set_requirement_applicability` emits `requirement.updated` (kind=`applicability`); `assess_version_requirement` emits `requirement.assessed` with `subject_kind='version_requirement_assessment'` and `previous_status` captured.
- `supabase/migrations/20260806120000_requirements_004_events_and_traceability.sql` — three read RPCs: `list_project_requirements`, `list_applicable_requirements` (optional `p_version_id` → assessment status), `get_version_assessments`.
- Realtime publication boundary — per REALTIME 001 and `project_lign_requirements_layer_lock.md`: the three requirements tables are **OUT** of `supabase_realtime` and any change to that boundary is a REALTIME re-freeze, not an APP 008 concern.

---

## Executive summary

- **Scope anchor.** This proposal implements the backend surface delta enumerated in `APP_008_FREEZE_INDEX.md` §27. That preview is authoritative: 7 additive columns, 0 new tables in v1, 9 additive read RPCs, 0 new write RPCs (backward-compatible tail params only), 0 new capability wirings (2 reserved names), 0 new emitted event types (6 reserved names + additive payload keys on the 4 frozen events), 7 additive indexes, 1 optional trigger.
- **Additive-only guarantee.** No frozen RPC signature is renamed or removed. No frozen event name changes. No frozen capability role map changes. No frozen table RLS policy is weakened. Every extension either (a) adds a nullable column with a CHECK and a covering index, (b) adds a tail param to an existing SECURITY DEFINER RPC with a `NULL` default that leaves the corresponding column unchanged, (c) adds a new SECURITY DEFINER read RPC, or (d) adds new keys to an existing frozen event payload.
- **Chain-initialization discipline preserved.** No new chain columns are introduced on `requirements` in APP 008. The frozen `superseded_by_requirement_id` FK (L61–L63 of REQUIREMENTS 002) plus `enforce_requirement_immutability` (L164–L191) already govern the supersession chain. The APP 006 T-CRIT-1 pre-computed-UUID + inline-INSERT precedent therefore does not need to be re-applied here.
- **Frozen state machine unchanged.** `draft → active`, `draft|active → archived`, `draft|active → superseded` remain the only legal transitions. Terminal set `{archived, superseded}`. Only frozen guards enforce; APP 008 adds no new guards to `requirements` or `version_requirement_assessments`.
- **Priority and ownership dimensions surfaced additively.** `priority`, `source_kind`, `category_kind`, `owner_profile_id`, `verification_method`, `due_at` are added as nullable columns on `requirements`. Each has a matching CHECK (for enum-backed columns), a matching covering index (for dashboard-critical filters), and a matching event-payload key (backwards-compat additive).
- **Discussion linkage via the existing comment XOR grammar.** `comments.target_requirement_id` is added as a nullable column (the 8th arm of the frozen XOR family). APP 005's comment RLS policies are unchanged; the enforcement discipline is preserved (§10 of the Freeze Index).
- **No new tables in Wave 1.** Every join proposed by the Freeze Index (§9 collection/discipline scopes, §21 subscriptions, §23 libraries/templates/waivers) is explicitly deferred with a reserved name only. The freeze index counts zero new tables in v1 (Freeze Index §27.2).
- **No new write RPCs.** The frozen 6-RPC workflow surface (`create_requirement`, `edit_requirement`, `archive_requirement`, `supersede_requirement`, `set_requirement_applicability`, `assess_version_requirement`) is the sole write path. Additive tail params on `create_requirement` and `edit_requirement` carry the new column values.
- **No new emitted event types in Wave 1.** The four frozen events cover every state transition. Six event names are reserved by string only (`requirement.due_soon`, `requirement.overdue`, `requirement.imported`, `requirement.ai_suggested`, `requirement.ai_classified`, `requirement.auto_assessed`) so the cron/AI/import slices can bind against fixed strings later without renaming.
- **Two capability names reserved.** `requirement.ai_suggest` and `requirement.ai_classify` are name-locked in PERMISSIONS.md but wired nowhere (no role grants). The AI slice fills them.
- **Trace API is a bundled read.** `get_requirement_trace(requirement_id)` returns a single jsonb structure covering assets, versions, assessments, changes, decisions, discussion count, approval requests, supersession chain. No new indexes required for v1 loads (frozen `changes_requirement_idx`, `decisions_requirement_idx`, `rda_design_asset_idx`, `vra_requirement_idx`, `requirements_superseded_by_idx` cover it).
- **Release-readiness read is APP 008-owned, APP 009-consumed.** `get_release_readiness_for_version(asset_version_id)` returns the shape `{applicable_count, satisfied_count, partial_count, not_satisfied_count, unassessed_count, critical_unsatisfied_count, critical_unassessed_count}`. APP 009 owns the gate policy (Freeze Index G-4, G-9).
- **Realtime stays OUT.** The three requirements tables remain excluded from `supabase_realtime`. Cross-slice invalidation is driven by APP 006/APP 007 channels only (Freeze Index §22). Six realtime channel names are reserved for a future REALTIME re-freeze.
- **Backwards-compat statement.** After this backend re-freeze lands: every APP 001–007 contract byte is preserved. Every REQUIREMENTS 001–005 contract byte is preserved. Callers of frozen RPCs continue to compile and execute unchanged; new callers additionally pass the tail params.
- **Wave plan.** Wave 1 Critical (schema + core RPCs); Wave 2 High (dashboards, metrics, inbox, comment-target column); Wave 3 Medium (traceability, saved-view/bookmark reuse wiring, reserved-name registration); Wave 4 Future (intentionally unimplemented; catalogues the reserved surface).

---

## 0. Conventions

Every proposed change carries four attributes.

- **Why:** the concrete user-facing behavior or invariant it enables.
- **Freeze Index section:** the APP 008 Freeze Index section (`§n`) or governance-decision ID (`G-n`) that requires it.
- **Priority:** `Critical` | `High` | `Medium` | `Future`.
- **Blocks implementation?** `yes` (v1 cannot ship without it) or `no` (v1 works without; polish or deferred).

Priority tiers:

| Tier | Meaning |
|---|---|
| **Critical** | v1 cannot ship at all without this. Must land in the first re-freeze wave. |
| **High** | v1 can start but a major feature is degraded or stubbed. First or second wave. |
| **Medium** | Polish / enterprise-adjacent; v1 works without it. Third wave. |
| **Future** | v2 territory; explicitly out of APP 008 v1 shipping scope. |

House rules (repeated verbatim from APP 006/APP 007 backend proposals so this document stands alone):

- **Additive-only.** No column is renamed. No column is dropped. No CHECK is narrowed. No enum value is removed. Every new column is nullable, every new CHECK is a widening or applies only to new columns.
- **Option A tail params.** Extensions to frozen RPCs always append parameters with `DEFAULT NULL`. A caller who passes only the original argument set observes byte-identical behavior. The frozen 9-arg `create_requirement` signature and the 7-arg `edit_requirement` signature remain callable verbatim.
- **SECURITY DEFINER + `SET search_path = ''`.** Every new RPC and every new trigger function is `SECURITY DEFINER` with `SET search_path = ''`. Every RPC is `REVOKE`d from `public`/`anon` and `GRANT`ed to `authenticated, service_role`. Every trigger function is `REVOKE`d from `public`/`anon`/`authenticated` with no `GRANT` (trigger functions fire under the row-writer's transaction context and never need `EXECUTE`).
- **Composite tenancy.** Every new FK is composite: at minimum `(target_id, workspace_id)`; where the referenced table also has `project_id` (e.g. `requirements`), the FK includes `project_id` too. This matches SCHEMA_V1_LOCK's house rule and mirrors the frozen `requirements` anchor UNIQUE keys at L52–L53 of REQUIREMENTS 002.
- **Covering index on every new FK.** No new FK ships without a matching btree index on the FK columns. Partial-index predicates (`WHERE col IS NOT NULL`) are used when the FK is nullable to keep the index small.
- **Capability naming per PERMISSIONS.md.** Dot-separated `subject.verb` (e.g. `requirement.ai_suggest`). Every capability key is registered in PERMISSIONS.md §5 (role map) and mirrored in `CAPABILITY_KEYS` typescript constants.
- **Event naming per EVENT_MODEL.md.** Past-tense (`requirement.created`, `requirement.imported`, `requirement.overdue`). Never future-tense. Never bare verbs. Every new event name is either emitted-in-this-slice or explicitly reserved with the RESERVED annotation and no emitter.
- **RESERVED event names.** A RESERVED name is a name-only lock in EVENT_MODEL.md. No emitter exists in APP 008; APP 010 / cron / AI slice fills them later against the fixed strings.
- **`COMMENT ON COLUMN` house pattern.** Every new column ships with a `COMMENT ON COLUMN` in the same migration (APP 006 house pattern; APP 007 F-1.4). Not enumerated per column below.

---

## 1. Executive summary of surface additions

Consolidated view of what this proposal adds, mirrored from `APP_008_FREEZE_INDEX.md` §27 and expanded per section below.

| Kind | Count (v1) | Reserved-only | Notes |
|---|---|---|---|
| New tables | 0 | 7 | Every join deferred (§2 below). |
| New columns on frozen tables | 7 | 3 | 6 on `requirements`, 1 on `comments`. Reserved: `evidence_file_ids uuid[]` on VRA, `external_id text` + `external_system text` on `requirements`. |
| New indexes | 7 | 0 | 5 btree + 1 GIN trigram + 1 partial (see §4). |
| New CHECK constraints | 3 | 0 | On `requirements.priority`, `requirements.source_kind`, `requirements.category_kind`. |
| New composite FK constraints | 2 | 0 | `requirements.owner_profile_id → workspace_members(user_id, workspace_id)` (§5); `comments.target_requirement_id` composite to `requirements(id, workspace_id)` (§5). |
| Enum widenings | 0 (new enums) | 0 | All new enum-shaped columns are net-new CHECKs, not widenings of frozen enums. |
| New capabilities (wired) | 0 | 2 | `requirement.ai_suggest`, `requirement.ai_classify` (name-only). |
| New read RPCs | 9 | 0 | See §8. |
| New write RPCs | 0 | 0 | See §9. |
| Tail params on frozen RPCs | 12 | 0 | 6 on `create_requirement`, 6 on `edit_requirement` (see §9). |
| New emitted event types | 0 | 6 | See §13. |
| Payload-key additions to frozen events | 3 events touched | 0 | `requirement.created`, `requirement.updated`, `requirement.assessed` (see §12). |
| New triggers | 1 (optional convenience) | 0 | Default-owner-on-insert (see §11). |
| RLS policies added | 0 | 0 | No new tables, no policy changes on frozen tables (see §10). |
| Realtime publication changes | 0 | 6 channels | Requirements tables stay OUT per Freeze Index §22 (see §19). |

---

## 2. New tables

**None in v1.** The Freeze Index §27.2 statement is honored: zero new tables. Every proposal that would introduce a table is deferred to a future re-freeze:

| Reserved table | Purpose | Freeze Index section | Reserved-only rationale |
|---|---|---|---|
| `requirement_subscriptions(requirement_id, profile_id)` | Non-owner follow model for notifications (§21.3) | §21.3, G-15, G-31 | Owner-based notifications sufficient for v1; APP 010 owns the subscription resolver. |
| `requirement_templates(id, workspace_id, name, payload_jsonb)` | Composer "create from template" (§23.3) | §23.3 | Adds a distinct authoring surface; deferred. |
| `requirement_library_items(id, workspace_id, template_id, ...)` | Cross-project shared library (§23.4) | §23.4 | Copy-on-adopt semantics deferred to v2. |
| `requirement_collections(requirement_id, collection_id)` | Collection-scoped applicability (§9.1) | §9.1, G-5 | Asset-scoped + project-wide covers v1 UX. |
| `requirement_disciplines(requirement_id, discipline_id)` | Discipline-scoped applicability (§9.1) | §9.1, G-5, G-18 | Discipline is orthogonal to category; not needed for v1 filters. |
| `requirement_waivers(approval_response_id, requirement_id)` | Structured waiver linkage (§23.9) | §23.9, G-8 | Approval-side owns this; APP 007 v2 concern. |
| `requirement_custom_sources(workspace_id, key, label)` / `requirement_custom_categories` | Org-specific enum extension (§23.1–2) | §23.1, §23.2 | Enum + `other` escape hatch covers v1. |

- **Why (deferral):** Every table above adds new RLS surface, at least one new capability key, and at least one new event or invalidation edge. The Freeze Index scoped v1 to what the frozen 3-table backbone plus additive columns can express.
- **Freeze Index section:** §27.2 (explicit "None required for v1").
- **Priority:** N/A (deferred).
- **Blocks implementation?** No.

---

## 3. New columns on frozen tables

All columns below ship with (a) a `COMMENT ON COLUMN` in the same migration, (b) a CHECK where enum-shaped, (c) a covering index if dashboard-critical (see §4), (d) a matching event-payload key on the relevant frozen event when set (see §12).

### 3.1 `public.requirements.priority text null default 'medium'`

- **Why:** Ordinal priority tier drives dashboard sort order (Freeze Index §8.2) and gates release-readiness computation in APP 009 (Freeze Index §8.3, G-4). Without an ordinal signal the "critical unsatisfied" bucket has no formal source.
- **Shape note:** `CHECK (priority IS NULL OR priority IN ('critical','high','medium','low','informational'))`. Default `'medium'` matches Freeze Index G-34 ("optional on create; default `medium`; may be set later via edit"). Existing rows are left with `NULL` — treated as "unset" in dashboards; new rows default to `'medium'`.
- **Freeze Index section:** §8, §27.1, G-3, G-34.
- **Priority:** Critical.
- **Blocks implementation?** Yes — priority-sorted dashboard views (§12.1 of the Freeze Index: `by_priority`, `overdue_critical`, `all_active` default sort) cannot render without this column.

### 3.2 `public.requirements.source_kind text null`

- **Why:** Bounded value space for the requirement-source dimension (Freeze Index §6). The frozen `source text` column (free-text; L37 of REQUIREMENTS 002) is preserved for the human-readable label ("Acme Corp Legal Team"); the enum-backed `source_kind` gives dashboards and metrics a filterable, aggregable axis.
- **Shape note:** `CHECK (source_kind IS NULL OR source_kind IN ('client','consultant','regulatory','internal_team','qa','procurement','manufacturing','safety','contractual','other'))`. NULLable — pre-enum rows carry NULL and render as "Source not classified" in the UI.
- **Freeze Index section:** §6, §27.1, G-1.
- **Priority:** Critical (dashboard `by_source` view and `?source=` filter cannot function without it).
- **Blocks implementation?** Yes.

### 3.3 `public.requirements.category_kind text null`

- **Why:** Symmetric to §3.2 for the requirement-category dimension (Freeze Index §7). The frozen `category text` column (L36 of REQUIREMENTS 002) is preserved for the human label.
- **Shape note:** `CHECK (category_kind IS NULL OR category_kind IN ('functional','non_functional','regulatory','contractual','technical','aesthetic','sustainability','safety','operational','other'))`. NULLable.
- **Freeze Index section:** §7, §27.1, G-2.
- **Priority:** Critical (dashboard `by_category` filter and compliance-page category breakdown).
- **Blocks implementation?** Yes.

### 3.4 `public.requirements.owner_profile_id uuid null`

- **Why:** Ownership survives originator departure. The frozen `created_by_profile_id` (L42 of REQUIREMENTS 002) is an immutable historical fact; `owner_profile_id` is the routable identity used for the `assigned_to_me` dashboard view (Freeze Index §12.1), NavRail badges (Freeze Index §12.6), and APP 010 notification routing (Freeze Index §21.2).
- **Shape note:** Composite FK `(owner_profile_id, workspace_id) → workspace_members(user_id, workspace_id) ON DELETE SET NULL` to satisfy G-33 (owner must be an active workspace member of the requirement's workspace — i.e. a `workspace_members` row where `status` is not `removed`). In the frozen schema, `workspace_members.user_id` is the FK to `public.profiles(id)` (per `20260728220000_workspaces_identity.sql` L90). The composite unique constraint that satisfies this FK is `workspace_members_workspace_user_key` on `(workspace_id, user_id)` (L104); Postgres accepts the reordered composite as satisfying an FK reference to `(user_id, workspace_id)` provided the exact column pair is unique-covered. Cross-workspace owners are structurally impossible via this FK. Falls back to `created_by_profile_id` in the read layer when NULL. A `default_owner_on_insert` optional convenience trigger is proposed in §11.
- **Freeze Index section:** §5.1, §21.2, §27.1, G-17, G-24, G-33.
- **Priority:** Critical (assigned-to-me and inbox reads require it).
- **Blocks implementation?** Yes.

### 3.5 `public.requirements.verification_method text null`

- **Why:** Systems-engineering verification taxonomy (Freeze Index §2.1, §23.11). Reserved for future audit exports (ReqIF/DOORS) and for the future assessment-consistency AI slot (Freeze Index §20). Not surfaced in v1 UX.
- **Shape note:** `CHECK (verification_method IS NULL OR verification_method IN ('inspection','test','analysis','demonstration'))`. NULLable.
- **Freeze Index section:** §2.1, §23.11, §27.1.
- **Priority:** Future.
- **Blocks implementation?** No (column shipped in Wave 1 so future exports have a place to land, but no UI in v1).

### 3.6 `public.requirements.due_at timestamptz null`

- **Why:** First-assessment deadline for the `overdue_critical` dashboard view (Freeze Index §12.1) and for the reserved `requirement.due_soon` / `requirement.overdue` cron emitters (Freeze Index §20.2, §21.1). Also feeds the "Days until due" metric per §16.1.
- **Shape note:** No CHECK (any timestamp valid). Partial covering index in §4 filters on `WHERE due_at IS NOT NULL AND status IN ('draft','active')`.
- **Freeze Index section:** §8, §12.1 (`overdue_critical`), §16.1, §27.1.
- **Priority:** High (dashboard view + metric).
- **Blocks implementation?** No for the composer and detail page; yes for the `overdue_critical` view and the cron slice.

### 3.7 `public.comments.target_requirement_id uuid null`

- **Why:** Requirement-scoped discussions filter in the Requirement Detail Discussions tab (Freeze Index §11.3, §10.3, G-7). Extends the frozen XOR target family on `comments` (whose current arms are the 7-way `version|change|decision|approval_request|review|annotation|null` set) with an 8th arm.
- **Shape note:** Composite FK `(target_requirement_id, workspace_id) → requirements(id, workspace_id) ON DELETE SET NULL`. NULLable to preserve every existing row and every existing XOR pattern. Partial covering index in §4 filters on `WHERE target_requirement_id IS NOT NULL`. The XOR CHECK on `comments` MUST be re-authored additively to include the new arm — this is the one CHECK widening in APP 008 and is enumerated in §6.
- **Freeze Index section:** §10.3, §27.1, G-7.
- **Priority:** High (Discussions tab has a documented server-side fallback per Freeze Index §11.3, so the tab renders without this column; Discussions filter and `requirement.discussion.count` metric depend on it).
- **Blocks implementation?** No (fallback exists); yes if the Discussions tab ships with server-side filtering.

### 3.8 Reserved-only columns (name-locked; not shipped in Wave 1)

The Freeze Index reserves the following columns by name (§23.7, §23.8). They are documented here so the vocabulary is stable:

| Table | Column | Purpose | Freeze Index section |
|---|---|---|---|
| `version_requirement_assessments` | `evidence_file_ids uuid[]` | Attach evidence files to an assessment (§23.8) | §23.8 |
| `requirements` | `external_id text` | External system's ID for import/sync (§23.7) | §23.7 |
| `requirements` | `external_system text` | External system identifier ("jira", "doors", "reqif") (§23.7) | §23.7 |
| `requirements` | `additional_source_kinds text[]` | Multi-source support (§6.4, G-20) | §6.4 |

- **Why (deferral):** Each column introduces its own migration surface (a CHECK, potentially a covering index, potentially a new capability); the Freeze Index scoped v1 to the six non-reserved columns in §3.1–§3.7 above.
- **Priority:** Future.
- **Blocks implementation?** No.

---

## 4. New indexes

Every new FK gets a covering index; every dashboard filter that appears in the Freeze Index §12 filter bar gets a supporting index; text search gets a GIN trigram index.

| # | Index name | Table | Definition | Purpose | Priority | Blocks impl? |
|---|---|---|---|---|---|---|
| I-1 | `requirements_project_priority_idx` | `requirements` | `(project_id, priority) WHERE status IN ('draft','active')` | Priority-sorted dashboard scans; default sort `(priority asc, updated_at desc)` per Freeze Index §8.2; `by_priority` view. | Critical | Yes |
| I-2 | `requirements_project_owner_idx` | `requirements` | `(project_id, owner_profile_id) WHERE owner_profile_id IS NOT NULL` | `assigned_to_me` dashboard view (Freeze Index §12.1); `?assignee=` filter (§13.2). | Critical | Yes |
| I-3 | `requirements_project_source_idx` | `requirements` | `(project_id, source_kind) WHERE source_kind IS NOT NULL` | `by_source` view + `?source=` filter. | High | No (linear scan tolerable for small projects; degrades at scale). |
| I-4 | `requirements_project_category_idx` | `requirements` | `(project_id, category_kind) WHERE category_kind IS NOT NULL` | `?category=` filter and compliance-page category breakdown. | High | No. |
| I-5 | `requirements_due_at_partial_idx` | `requirements` | `(due_at) WHERE due_at IS NOT NULL AND status IN ('draft','active')` | `overdue_critical` view; cron scan for reserved `requirement.due_soon`/`requirement.overdue` emitters. | High | No (dashboard view + reserved cron). |
| I-6 | `requirements_title_desc_trgm_idx` | `requirements` | `GIN (title gin_trgm_ops, description gin_trgm_ops)` (requires `pg_trgm` extension already-installed check; freeze-index §13.1 recommends trigram) | Text search on `code`/`title`/`description` per Freeze Index §13.1. `code` uses the frozen `requirements_project_code_key` UNIQUE index (L94 of REQUIREMENTS 002) for exact-match `?code=` lookups. | Medium | No (fallback ILIKE scan acceptable at MVP scale). |
| I-7 | `comments_target_requirement_partial_idx` | `comments` | `(target_requirement_id) WHERE target_requirement_id IS NOT NULL` | Discussions tab filter; `requirementDiscussions(id)` query key backing. | High | No (only needed with §3.7). |

Existing frozen indexes on `requirements` remain unchanged (`requirements_project_code_key` L94, `requirements_project_status_idx` L98, `requirements_parent_idx` L102, `requirements_superseded_by_idx` L107, `requirements_workspace_idx` L112, `requirements_project_created_at_idx` L114 of REQUIREMENTS 002). Existing frozen indexes on `requirement_design_assets` (`rda_design_asset_idx`, `rda_project_idx`, L224–L227) and on `version_requirement_assessments` (`vra_requirement_idx`, `vra_project_status_idx`, `vra_workspace_idx`, L277–L281) are sufficient for every trace-graph read described in §16.

**Trigram extension prerequisite (I-6).** `pg_trgm` is expected to already be present in the frozen extension set (same as APP 006 GIN trigram usage on `reviews.title`). If it is not, an idempotent `CREATE EXTENSION IF NOT EXISTS pg_trgm` ships alongside the index. This is documentation-only in this proposal.

---

## 5. New constraints

### 5.1 Composite FK: `requirements.owner_profile_id`

- **Definition:** `(owner_profile_id, workspace_id) → public.workspace_members(user_id, workspace_id) ON DELETE SET NULL`.
- **Frozen-schema justification:** In `20260728220000_workspaces_identity.sql` L90, `workspace_members.user_id` is the FK to `public.profiles(id)`; there is no `profile_id` column on `workspace_members`. The composite UNIQUE that satisfies the FK reference is `workspace_members_workspace_user_key` on `(workspace_id, user_id)` (L104); Postgres accepts the reordered composite `(user_id, workspace_id)` as satisfying the FK provided the exact column pair is unique-covered. This note is inlined so an implementation-time reader does not re-discover the column-name ambiguity.
- **Purpose:** Enforces the G-33 invariant "owner must be an active workspace_member of the requirement's workspace" — where "active" means a `workspace_members` row whose `status` is not `removed`. Cross-workspace owner assignment is structurally impossible. Owner departure (workspace_member row deleted) sets the column back to NULL; the read layer then falls back to `created_by_profile_id` for display and to project leads for notification routing (G-17).
- **Priority:** Critical.

### 5.2 Composite FK: `comments.target_requirement_id`

- **Definition:** `(target_requirement_id, workspace_id) → public.requirements(id, workspace_id) ON DELETE SET NULL`.
- **Purpose:** Same-workspace coherence for the new comment target. Deleting a requirement (never allowed at RLS per L454 of REQUIREMENTS 002 — DELETE denied) is a no-op here; the FK protects only against cross-workspace comment→requirement wiring at INSERT time. The frozen `requirements` anchor UNIQUE key `(id, workspace_id)` at L52 of REQUIREMENTS 002 satisfies the composite reference.
- **Priority:** High.

### 5.3 CHECK: comments XOR-target widening (see §6)

Enumerated in §6.1.

### 5.4 Every new CHECK from §3

For clarity all CHECKs added by APP 008 are re-listed here in one place:

| CHECK | Table | Definition | Section |
|---|---|---|---|
| `requirements_priority_check` | `requirements` | `priority IS NULL OR priority IN ('critical','high','medium','low','informational')` | §3.1 |
| `requirements_source_kind_check` | `requirements` | `source_kind IS NULL OR source_kind IN (…10 values…)` | §3.2 |
| `requirements_category_kind_check` | `requirements` | `category_kind IS NULL OR category_kind IN (…10 values…)` | §3.3 |
| `requirements_verification_method_check` | `requirements` | `verification_method IS NULL OR verification_method IN ('inspection','test','analysis','demonstration')` | §3.5 |

All four CHECKs are `NULL`-permissive: pre-existing rows carry NULL until a targeted edit sets the value. **No frozen CHECK is narrowed.** The frozen `requirements_status_check` (L69–L70), `requirements_code_check` (L72–L73), `requirements_title_check` (L75–L76), `requirements_no_self_supersede` (L79–L80), `requirements_superseded_coherence` (L83–L85), `requirements_archived_coherence` (L88–L90), and the frozen `vra_status_check` (L249–L250 of REQUIREMENTS 002) are all preserved byte-for-byte.

---

## 6. Enum / CHECK additions

### 6.1 `comments` XOR-target widening (paired with §3.7)

- **Change:** the frozen `comments_target_xor_check` at `20260729190000_reviews_comments_annotations.sql` L365–L374 requires **exactly one** of the seven target columns (`target_version_id`, `target_review_id`, `target_annotation_id`, `target_change_id`, `target_decision_id`, `target_design_asset_id`, `target_approval_request_id`) to be non-null (predicate `= 1`). APP 008 widens the CHECK to require **exactly one** of the eight target columns to be non-null (adds `target_requirement_id` as the eighth arm). The frozen predicate shape (`= 1`) is preserved; only the arm count changes.
- **Why:** The additive `target_requirement_id` column would otherwise permit a comment to be simultaneously anchored to a version and a requirement, breaking the "exactly one target" invariant. The re-authored CHECK preserves every legal shape and adds one new legal shape.
- **Freeze Index section:** §10.3, G-7.
- **Priority:** High (only required if §3.7 ships; deferred otherwise).
- **Blocks implementation?** No (Discussions tab has a documented fallback per Freeze Index §11.3).

**No frozen enum values are removed.** The frozen `requirements.status` set `{draft, active, superseded, archived}` (L69–L70 of REQUIREMENTS 002) is untouched. The frozen `version_requirement_assessments.status` set `{satisfied, partial, not_satisfied, not_applicable}` (L249–L250) is untouched.

---

## 7. Capability additions

Two capability keys are reserved by name. **Neither is wired in APP 008 v1.** No role grants are added; no RPC gates on either key; no RLS policy references either key. They exist in this proposal only so PERMISSIONS.md and the `CAPABILITY_KEYS` constant have the name locked before the AI slice starts writing against them.

| Capability | Purpose | Default role grants (v1) | Freeze Index section | Priority | Blocks impl? |
|---|---|---|---|---|---|
| `requirement.ai_suggest` | Gate AI-assisted composer suggestions (Freeze Index §20.1). | None (name-only). | §20.1, §27.5, G-14 | Future | No |
| `requirement.ai_classify` | Gate AI-assisted classification (Freeze Index §20.1). | None (name-only). | §20.1, §27.5, G-14 | Future | No |

Additional reserved capability names per Freeze Index §23.6, §23.7 (name-locked, not wired):

- `requirement.import` — bulk import from Jira/DOORS/ReqIF (§23.7).
- `requirement.auto_assess` — AI-assisted version-diff-driven auto-assessment (§23.6).

**Extend before duplicating rule.** Every product-layer action APP 008 exposes maps to one of the five frozen capabilities:

- Viewing dashboards, detail page, filter bar → `requirement.view`.
- Composing a new requirement (composer modal, `?compose=1`) → `requirement.create`.
- Editing metadata, changing priority, changing owner, setting applicability → `requirement.edit`. (The frozen `set_requirement_applicability` RPC already gates on `requirement.edit` per REQUIREMENTS 003.)
- Archive action from ⋮ menu → `requirement.archive`.
- Assess action from Assessments tab or from the Design Workspace RightPanel Requirements tab → `requirement.assess`.

The `edit` capability covers priority mutation (Freeze Index §8.4), owner mutation, source/category classification, and applicability edits — all as additive parameter values on the frozen `edit_requirement` and `set_requirement_applicability` RPCs. No new capability is required because no genuinely new authorization axis is introduced.

**PERMISSIONS.md registration checklist (mirrors APP 007 F-5.2 discipline):**

- `requirement.ai_suggest` → `CAPABILITY_KEYS.REQUIREMENT_AI_SUGGEST` → PERMISSIONS.md §5 role table row: reserved, no grants.
- `requirement.ai_classify` → `CAPABILITY_KEYS.REQUIREMENT_AI_CLASSIFY` → PERMISSIONS.md §5 role table row: reserved, no grants.
- `requirement.import` → reserved, no grants.
- `requirement.auto_assess` → reserved, no grants.

---

## 8. Read RPCs

All read RPCs below are `SECURITY DEFINER`, `SET search_path = ''`, `REVOKE` from `public`/`anon`, `GRANT EXECUTE` to `authenticated, service_role`. Every RPC re-checks `requirement.view` on the project (or on the requested workspace scope) at function entry, using `public.lign_has_capability`. Cursor pagination is opaque `(updated_at desc, id desc)` — the server never accepts an offset.

**Standing discipline (mirrors APP 007 §7 preamble).** RLS on `requirements`, `requirement_design_assets`, `version_requirement_assessments` doesn't compose cleanly with per-row aggregations across projects. Every read below runs under DEFINER and re-checks capability internally.

### 8.1 `get_requirement(p_requirement_id uuid)`

- **Purpose:** Powers Requirement Detail header + Overview tab (Freeze Index §11.1, §11.6).
- **Return shape:** jsonb with keys `requirement` (the row, joined with owner + creator + parent code), `sub_requirements` (array of child rows), `applicability_summary` (`{is_project_wide bool, asset_count int, asset_ids uuid[]}`), `assessment_summary` (`{versions_applicable int, versions_assessed int, latest_status_per_asset jsonb}`), `metrics` (`{coverage_pct numeric, days_since_last_assessment int, days_until_due int|null}`), `chain_position` (`{supersedes uuid|null, superseded_by uuid|null, chain_depth int}`).
- **Capability check:** `requirement.view` on the requirement's project.
- **Pagination:** None (single row).
- **Freeze Index section:** §11.6, §15.3, §16.1, §17.1 (`qk.requirement`), §17.2.
- **Priority:** Critical.
- **Blocks implementation?** Yes (Requirement Detail cannot render).

### 8.2 `get_requirement_by_code(p_project_id uuid, p_workspace_id uuid, p_code text)`

- **Purpose:** Backs the deep-link resolver `/deep/requirement/:code` (Freeze Index §14.1, §14.2, §18.3). Codes are per-project stable (frozen `requirements_project_code_key` UNIQUE at L94 of REQUIREMENTS 002); `?project=` disambiguates at the URL layer (Freeze Index G-28).
- **Return shape:** jsonb with keys `requirement_id`, `code`, `title`, `status`, `project_id`, `workspace_id`. Returns NULL if not found.
- **Capability check:** `requirement.view` on the resolved project (fail-closed: if the project isn't in the caller's view set, return NULL — never leak existence).
- **Freeze Index section:** §14.1, §17.1 (`qk.requirementByCode`), G-28.
- **Priority:** Critical (deep links unusable without it).
- **Blocks implementation?** Yes for `/deep/requirement/:code`.

### 8.3 `get_requirement_chain(p_requirement_id uuid)`

- **Purpose:** Renders the SupersessionChainCard in the Requirement Detail metadata rail and the Traceability tab's supersession section (Freeze Index §11.4, §15.2, §17.1 `qk.requirementChain`).
- **Return shape:** jsonb array ordered oldest → newest of `{requirement_id, code, title, status, superseded_by_requirement_id, is_current bool}`. The array walks both directions: backward via other rows in the same project whose `superseded_by_requirement_id` equals a row in the chain (per Freeze Index §4.1 backward-walk semantics); forward via `superseded_by_requirement_id`.
- **Capability check:** `requirement.view`.
- **Pagination:** None (chain is bounded — Freeze Index §4.1 notes chains may exceed length 2 but are still small).
- **Freeze Index section:** §4.1, §10.7, §11.4, §15.2, §17.1.
- **Priority:** High.
- **Blocks implementation?** No (metadata rail can render without the chain viz initially).

### 8.4 `get_requirement_trace(p_requirement_id uuid)`

- **Purpose:** Backs the Traceability tab (Freeze Index §11.3, §15) and is consumed by APP 009 (release-readiness), APP 010 (notifications), and the AI slice (Freeze Index §20 seams).
- **Return shape:** jsonb bundle:
  ```
  {
    requirement: {...},
    applicable_assets: [ { design_asset_id, name, project_id } ] | [] (project-wide),
    is_project_wide: bool,
    sub_requirements: [ { id, code, title, status, priority } ],
    assessments: [ { asset_version_id, asset_id, version_number, status, note, assessed_at, assessed_by_profile_id } ],
    related_changes: [ { change_id, kind, created_at, subject_label } ],
    related_decisions: [ { decision_id, subject_kind, subject_id, created_at, decision_reason_snippet } ],
    discussion_count: int,
    approval_requests: [ { approval_request_id, status, outcome_at, root_approval_request_id } ],
    supersession_chain: [ { id, code, status } ],
    metrics: { coverage_pct, critical_unsatisfied_count, unassessed_on_latest_count }
  }
  ```
- **Capability check:** `requirement.view` on the requirement's project.
- **Depth / limit discipline:** No graph traversal — every edge is a direct index lookup against `changes.requirement_id` (frozen `changes_requirement_idx`), `decisions.requirement_id` (frozen `decisions_requirement_idx`), `requirement_design_assets` (frozen `rda_design_asset_idx`, `rda_project_idx`), `version_requirement_assessments` (frozen `vra_requirement_idx`). Approval-request enumeration is bounded by "distinct approval_requests reachable via decisions citing this requirement" — a two-hop lookup (`decisions.requirement_id → decisions.subject_id → approval_requests.id`) using existing indexes. **No new indexes required for v1 loads** (Freeze Index §15.5).
- **Freeze Index section:** §15.3, §15.4, §15.5, §17.1 (`qk.requirementTrace`), §17.3 (invalidations).
- **Priority:** Medium (Traceability tab is opt-in; Overview loads eagerly without it).
- **Blocks implementation?** No.

### 8.5 `list_requirements_dashboard(p_ws_id uuid, p_proj_id uuid, p_view text, p_status_filter text[], p_priority_filter text[], p_source_filter text[], p_category_filter text[], p_scope_filter text, p_owner_ids uuid[], p_search text, p_cursor_updated_at timestamptz, p_cursor_id uuid, p_limit integer, p_saved_view_id uuid default null)`

- **Purpose:** Powers every requirements dashboard view (Freeze Index §12, §12.1, §12.4). Workspace scope when `p_proj_id IS NULL`; project scope otherwise.
- **Return shape:** jsonb with keys `rows` (array of dashboard-card rows: `{requirement_id, code, title, status, priority, source_kind, category_kind, owner_profile_id, updated_at, applicability_summary, assessment_coverage, project_id, project_name}`) + `next_cursor` (`{updated_at, id} | null`).
  - **`applicability_summary jsonb`** — canonical object shape `{ scope text CHECK IN ('project_wide','asset_scoped'), asset_count integer }`. `scope='project_wide'` when no rows exist in `requirement_design_assets` for the effective root; `scope='asset_scoped'` otherwise. `asset_count` is the count of `requirement_design_assets` rows for the effective root (0 when `project_wide`).
  - **`assessment_coverage jsonb`** — canonical object shape `{ coverage_pct numeric, applicable_versions_count integer, satisfied_count integer, latest_version_assessed boolean }`. `coverage_pct` = `satisfied_count / applicable_versions_count` (0 when denominator is 0); `applicable_versions_count` is the count of latest-per-asset versions the requirement applies to; `satisfied_count` is the subset of those with a `version_requirement_assessments` row whose `status='satisfied'`; `latest_version_assessed` is true iff every applicable latest-version has any VRA row (regardless of status).
- **View parameter:** one of `all`, `active`, `my`, `overdue`, `compliance`, `bookmarks` per Freeze Index §12.1 and §18.1 (the existing `p_view` string set is unchanged). Additional named views documented for future binding: `all_active`, `assigned_to_me`, `recently_updated`, `by_status`, `by_priority`, `by_source`, `needs_assessment`, `overdue_critical`, `archived`, `superseded`. Server-side interpretation:
  - `assigned_to_me` → `owner_profile_id = auth.uid()`.
  - `needs_assessment` → requirement is applicable to at least one version on the latest per-asset version with no `version_requirement_assessments` row.
  - `overdue_critical` → `priority='critical' AND due_at < now() AND no satisfied assessment on latest version`.
  - `compliance` → identical row set as `all_active` but with a richer `assessment_coverage` field per row (Freeze Index §16.4).
- **Saved-view parameter (`p_saved_view_id uuid default null`):** additive tail parameter. When non-NULL, the RPC resolves the saved view's filter payload from the frozen `user_saved_views` (APP 006) and applies it, ignoring the raw `p_view` value. When NULL, `p_view` retains its existing semantics. This replaces the earlier inline `saved:<uuid>` view-encoding hack with a distinct, type-safe tail param. Pure additive tail param; the existing `p_view` string set remains unchanged.
- **Pagination:** Opaque `(updated_at desc, id desc)` cursor per Freeze Index §13.5 and §17.4.
- **Capability check:** `requirement.view` at the project scope (or a union across the caller's projects at workspace scope).
- **Freeze Index section:** §12, §13, §17.1, §17.4.
- **Priority:** Critical (every dashboard route calls this).
- **Blocks implementation?** Yes.

### 8.6 `get_requirement_inbox_count(p_ws_id uuid)`

- **Purpose:** NavRail badge (Freeze Index §12.6, §19.1, §17.1 `qk.requirementInboxCount`).
- **Return shape:** jsonb `{assigned_to_me int, overdue_critical int, needs_assessment int}` — the tri-digit chip payload.
- **Capability check:** `requirement.view` on the workspace-scope projection.
- **Freeze Index section:** §12.6, §19.1.
- **Priority:** High.
- **Blocks implementation?** No (badge can be hidden pending; NavRail item still routes).

### 8.7 `get_project_requirement_metrics(p_project_id uuid)`

- **Purpose:** Metrics strip above the project dashboard and the compliance-page charts (Freeze Index §12.8, §16.2, §16.4).
- **Return shape:** jsonb with keys `total_count`, `by_status` (`{draft, active, superseded, archived}`), `by_priority` (`{critical, high, medium, low, informational}`), `by_source` (map), `unassessed_on_latest_count`, `critical_unsatisfied_count`, `overdue_count`, `coverage_rate numeric`, `trailing_30d_creation_rate`, `trailing_30d_assessment_activity_rate`.
- **Capability check:** `requirement.view` on the project.
- **Derivation:** Computed at query time from `requirements`, `version_requirement_assessments`, and `activity_events` — no cached-metric columns in v1 per Freeze Index §16.5 (matches APP 006/APP 007 pattern).
- **Freeze Index section:** §16.2, §16.4, §16.5, §17.1.
- **Priority:** Medium.
- **Blocks implementation?** No (metrics strip is collapsible-off-by-default per Freeze Index §12.8).

### 8.8 `get_workspace_requirement_metrics(p_ws_id uuid)`

- **Purpose:** Rollup across projects for the workspace dashboard (Freeze Index §16.3).
- **Return shape:** jsonb with keys `total_active`, `by_status`, `by_priority`, `top5_projects_by_critical_unsatisfied` (array of `{project_id, project_name, count}`), `top5_owners_by_open_load` (array of `{profile_id, display_name, count}`), `overdue_count_across_workspace`.
- **Capability check:** `requirement.view` on each project the caller can see; rollup restricted to that set.
- **Freeze Index section:** §16.3.
- **Priority:** Medium.
- **Blocks implementation?** No.

### 8.9 `get_release_readiness_for_version(p_asset_version_id uuid)`

- **Purpose:** APP 009 (Releases) read hook. Backs `useReleaseReadinessForVersion` per Freeze Index §17.1 (`qk.releaseReadinessForVersion`) and the reserved release-readiness gate (Freeze Index §8.3, §10.6, §15.3, G-4, G-9).
- **Return shape:** jsonb `{applicable_count int, satisfied_count int, partial_count int, not_satisfied_count int, unassessed_count int, critical_unsatisfied_count int, critical_unassessed_count int}`. Every field is computed against the requirements applicable to the version's asset (project-wide ∪ asset-scoped root ids from `requirement_design_assets`, per the frozen `list_applicable_requirements` algorithm at REQUIREMENTS 004).
- **Capability check:** `requirement.view` on the version's project. APP 009 will additionally require its own `release.view` on the call site.
- **Freeze Index section:** §8.3, §10.6, §15.3, §17.1.
- **Priority:** Medium (APP 008 v1 works without it; APP 009 requires it).
- **Blocks implementation?** No for APP 008; yes for APP 009's release-readiness UI.

### 8.10 Frozen read RPCs (unchanged)

The three frozen read RPCs from REQUIREMENTS 004 remain the sole read path for their concerns and are called directly by APP 008 clients (via `qk.applicableRequirementsForAsset`, `qk.assessmentsForVersion`, project-list variants). No wrapper is added.

- `list_project_requirements(p_project_id uuid)` — unchanged.
- `list_applicable_requirements(p_design_asset_id uuid, p_version_id uuid default null)` — unchanged; version arg is optional and, when supplied, joins assessment status.
- `get_version_assessments(p_asset_version_id uuid)` — unchanged.

---

## 9. Write RPCs

**No new write RPCs.** The frozen six-RPC workflow surface (`create_requirement`, `edit_requirement`, `archive_requirement`, `supersede_requirement`, `set_requirement_applicability`, `assess_version_requirement`) covers every state transition APP 008 UX invokes (Freeze Index §4, §27.4). Every additional field APP 008 needs to write is carried in via **Option A additive-tail parameters**.

### 9.1 `create_requirement` — extended (Option A additive tail params)

**Frozen signature (preserved byte-for-byte)** per REQUIREMENTS 003 L165–L179 / REQUIREMENTS 004 L34–L44:

```
create_requirement(
  p_project_id            uuid,
  p_workspace_id          uuid,
  p_title                 text,
  p_description           text default null,
  p_category              text default null,
  p_source                text default null,
  p_source_ref            text default null,
  p_parent_requirement_id uuid default null,
  p_status                text default 'draft'
)
```

**New tail params (all `DEFAULT NULL`; a caller passing only the frozen 9-arg set observes byte-identical behavior):**

- `p_priority text default null` — validated against `('critical','high','medium','low','informational')`. If NULL, the row's `priority` column takes the column default (`'medium'` per §3.1).
- `p_source_kind text default null` — validated against the 10-value enum in §3.2.
- `p_category_kind text default null` — validated against the 10-value enum in §3.3.
- `p_owner_profile_id uuid default null` — validated (if non-null) against workspace membership via the composite FK (§5.1). NULL defaults to `auth.uid()` at the RPC layer OR is left NULL and the optional default-owner trigger (§11) fills it.
- `p_verification_method text default null` — validated against the 4-value enum in §3.5.
- `p_due_at timestamptz default null`.

**Capability required:** `requirement.create` (unchanged — the tail params do not require an additional capability).

**Side effects:**
- Server-generated `code` via advisory-xact-lock (frozen L208–L230 of REQUIREMENTS 003).
- Emits `requirement.created` (frozen L88–L103 of REQUIREMENTS 004) with **additive payload keys** per §12.1 below: `priority`, `source_kind`, `category_kind`, `owner_profile_id`, `verification_method`, `due_at` are added into `subject_snapshot` when non-null.

**Error codes preserved:** `42501` (unauthenticated / forbidden), `22004` (required arg missing), `22023` (invalid status or enum value), `23503` (parent not found in project).

**Freeze Index section:** §2.1, §27.4, G-34 (default priority behavior).
**Priority:** Critical.
**Blocks implementation?** Yes (composer cannot set priority/source/owner otherwise).

### 9.2 `edit_requirement` — extended (Option A additive tail params)

**Frozen signature (preserved byte-for-byte)** per REQUIREMENTS 003 L260–L268:

```
edit_requirement(
  p_requirement_id uuid,
  p_title          text default null,
  p_description    text default null,
  p_category       text default null,
  p_source         text default null,
  p_source_ref     text default null,
  p_status         text default null
)
```

**New tail params (all `DEFAULT NULL`; sentinel semantics: NULL leaves the column unchanged):**

- `p_priority text default null` — CHECK-validated at input; column update via `coalesce(p_priority, priority)`.
- `p_source_kind text default null` — CHECK-validated; `coalesce`-updated.
- `p_category_kind text default null` — CHECK-validated; `coalesce`-updated.
- `p_owner_profile_id uuid default null` — validated against workspace-member composite FK; `coalesce`-updated. To clear owner (fall back to creator), APP 008 does not offer that UX; if ever needed, a v2 tail param `p_clear_owner boolean default false` would provide the escape hatch.
- `p_verification_method text default null` — CHECK-validated; `coalesce`-updated.
- `p_due_at timestamptz default null` — `coalesce`-updated. To clear `due_at`, same rationale as owner.

**Capability required:** `requirement.edit` (unchanged).

**Frozen state guards preserved:** blocked on `superseded`/`archived` (L302–L304 of REQUIREMENTS 003); status transitions restricted to `draft ↔ active` (L306–L308).

**Diff / event discipline preserved:** the frozen `edit_requirement` at REQUIREMENTS 004 L120+ computes `changed_fields` against the pre-UPDATE row and emits `requirement.updated` (kind=`edit`) only when at least one field changed. The additive tail fields participate in that diff — see §12.2 below for the `changed_fields` payload extension.

**Error codes preserved.** New codes for enum-invalid tail params: `22023`.

**Freeze Index section:** §2.1, §5.1, §8.4, §27.4.
**Priority:** Critical.
**Blocks implementation?** Yes.

### 9.3 `archive_requirement` — unchanged

Frozen signature (1 param) and behavior (L338–L386 of REQUIREMENTS 003) preserved verbatim. No additive tail params required — the archive action carries no new UI-driven metadata in APP 008.

### 9.4 `supersede_requirement` — unchanged

Frozen signature (2 params) and behavior preserved verbatim. No additive tail params: the new requirement's tail fields are set via `create_requirement` (called separately before or independently of `supersede_requirement`, which merely wires the pointer). If a future re-freeze adds `p_note text default null` for the supersession event's audit trail, that is a Wave 4 concern.

### 9.5 `set_requirement_applicability` — unchanged

Frozen signature and behavior preserved verbatim (root-only guard; applicability replaced atomically via delete+insert; `requirement.updated` kind=`applicability` event emitted). No additive tail params in APP 008.

### 9.6 `assess_version_requirement` — unchanged

Frozen signature and behavior preserved verbatim (upsert per `(asset_version_id, requirement_id)`; frozen `vra_enforce_applicability` and `vra_enforce_immutability` triggers unchanged; `requirement.assessed` event emitted with `previous_status` captured). The Freeze Index §23.8 reserves `evidence_file_ids uuid[]` as an additive tail param for a future evidence slice — deferred to Wave 4.

### 9.7 No new write RPCs

The Freeze Index §27.4 statement is explicit: "None new for the core workflow — the frozen 6 workflow RPCs already cover every state transition." APP 008 preserves that boundary.

### 9.8 Reserved write RPCs (not shipped)

Name-locked for future waves (Freeze Index §23):

- `import_requirements(p_project_id, p_workspace_id, p_source_system, p_payload_jsonb)` — reserved for §23.7 (external-system sync). Emits reserved `requirement.imported`.
- `apply_requirement_template(p_project_id, p_template_id, p_overrides jsonb)` — reserved for §23.3 (templates).
- `auto_assess_version(p_asset_version_id, p_ai_run_id)` — reserved for §23.6 (AI auto-assessment). Emits reserved `requirement.auto_assessed`.
- `set_requirement_owner(p_requirement_id, p_new_owner_profile_id)` — subsumed by `edit_requirement`'s `p_owner_profile_id` tail param in APP 008; would only be introduced if a dedicated capability (e.g. `requirement.reassign`) were later split off.

---

## 10. RLS additions

### 10.1 Frozen policies preserved

Every RLS policy on `requirements` (L434–L452 of REQUIREMENTS 002), `requirement_design_assets` (L457–L467), and `version_requirement_assessments` (L472–L486) is preserved byte-for-byte. No SELECT policy is narrowed. No INSERT/UPDATE `WITH CHECK` is loosened. The DELETE-denied posture (no DELETE policy on `requirements` or `version_requirement_assessments`) is preserved — hard delete remains impossible at RLS.

### 10.2 New capability keys in existing policies

**None.** The two reserved capability keys (§7) are name-only; no RLS policy references them.

### 10.3 New tables

**None** (per §2). No new RLS policy sets are required.

### 10.4 Additive columns and RLS

The seven additive columns (§3.1–§3.7) are covered by the existing SELECT policies:

- `requirements.priority`, `.source_kind`, `.category_kind`, `.owner_profile_id`, `.verification_method`, `.due_at` — all covered by `requirements_select` (L434–L436) which gates on `requirement.view`. No column-level GRANT changes required; PostgREST exposes them under the same policy.
- `comments.target_requirement_id` — covered by the existing frozen APP 005 comments RLS. The new column does not weaken any policy; write-side, the frozen comment INSERT policy already gates on `comment.create` in the target scope. A capability check (`requirement.view`) MAY be added client-side in the composer as a defense-in-depth nudge to prevent authoring comments targeted at requirements the caller cannot view — enforcement is best-effort; the truly-private case is already blocked by the `requirements_select` policy hiding the row.

### 10.5 RPC-only writes for reserved join tables

Every reserved join table (§2) would ship with RPC-only writes and zero-policy RLS on the roster/join surface — matching APP 007 §9 / APP 006 §9 discipline. This is documented here so future implementers see the shape without needing to re-derive it. No table ships in v1.

**Priority:** N/A (no RLS delta).

---

## 11. Trigger additions

Standing discipline (mirrors APP 007 §10 preamble): every trigger function below is `SECURITY DEFINER` with `SET search_path = ''`. `REVOKE ALL … FROM public, anon, authenticated` mirrors the frozen `enforce_requirement_hierarchy`, `enforce_requirement_immutability`, `enforce_assessment_applicability`, `enforce_assessment_immutability` REVOKE block at L494–L497 of REQUIREMENTS 002. Trigger functions are **never** `GRANT`ed to `authenticated`; only RPCs are.

### 11.1 `requirements_default_owner_on_insert` (optional convenience)

- **Purpose:** When `owner_profile_id` is NULL at INSERT, default it to `created_by_profile_id` (which itself defaults to `auth.uid()` at the RPC layer). This is a soft convenience, not an invariant — the read layer already falls back gracefully. Shipping the trigger keeps the `owner_profile_id` column populated for the `assigned_to_me` view (§8.5) even when a caller invokes `create_requirement` without passing the tail param.
- **Timing:** `BEFORE INSERT ON public.requirements FOR EACH ROW`.
- **Behavior:**
  ```
  if NEW.owner_profile_id is null then
    NEW.owner_profile_id := NEW.created_by_profile_id;
  end if;
  return NEW;
  ```
- **REVOKE:** `REVOKE ALL ON FUNCTION public.requirements_default_owner_on_insert() FROM public, anon, authenticated`. No `GRANT`.
- **Dependency note:** This BEFORE INSERT trigger reads `NEW.created_by_profile_id`. The frozen `create_requirement` RPC (per `20260805120000_requirements_003_authz_and_rpcs.sql` L235–L236) populates `created_by_profile_id` before insertion via `auth.uid()`. If a raw service-role INSERT bypasses the RPC and leaves `created_by_profile_id` NULL, the trigger silently no-ops and `owner_profile_id` remains NULL (fall-through path exercised in the read layer per §3.4).
- **Priority:** Medium (Wave 1 nice-to-have; can also be handled entirely inside `create_requirement`).
- **Blocks implementation?** No.

### 11.2 Chain-init discipline (NOT applicable)

**No new chain columns are introduced by APP 008.** The frozen `superseded_by_requirement_id` FK (L61–L63 of REQUIREMENTS 002) plus `enforce_requirement_immutability` (L164–L191, which does NOT guard `superseded_by_requirement_id` — only `workspace_id`, `project_id`, `code`, `parent_requirement_id`) plus the `requirements_superseded_coherence` CHECK (L83–L85) together govern chain integrity. Supersession is applied by the frozen `supersede_requirement` RPC (REQUIREMENTS 003) as a single UPDATE. **Therefore the APP 006 T-CRIT-1 pre-computed-UUID + inline-INSERT precedent does not apply to APP 008** — no new column requires chain-initialization discipline. If a future re-freeze adds a `root_requirement_id` grouping pointer, that migration will need to apply the precedent then.

### 11.3 Denorm-maintenance triggers (none)

**No denorm columns are introduced by APP 008.** Metrics are computed at query time (Freeze Index §16.5) — no cached counters, no cached coverage percentages, no cached "last assessed at" columns. This matches APP 006 and APP 007 v1 discipline. If future metrics load exceeds tolerable query cost, a Wave 4 concern can introduce cached-metric columns with matching denorm-maintenance triggers.

### 11.4 Cascade behavior (none new)

The frozen cascade posture is preserved:

- `requirement_design_assets` cascade-deletes on requirement deletion — moot in practice because requirement DELETE is denied at RLS (L454 of REQUIREMENTS 002); the cascade is a defense-in-depth statement for postgres/service_role.
- `version_requirement_assessments` cascade-deletes on requirement deletion — same.
- `changes.requirement_id` `ON DELETE SET NULL` (L389–L390) preserves change history if a requirement is deleted via service_role.
- `decisions.requirement_id` `ON DELETE SET NULL` (L406–L408) — same.

APP 008 introduces no new cascade edges beyond the composite FKs in §5 (`owner_profile_id` → SET NULL; `target_requirement_id` → SET NULL). Both are conservative and match the frozen posture.

---

## 12. Event payload extensions

**Backwards-compatibility rule (repeated from APP 007 §11 preamble):** all payload extensions add new keys to existing frozen event types. Consumers MUST ignore unknown keys. No key is ever removed, renamed, or repurposed.

### 12.1 `requirement.created` — payload additions

**Frozen `subject_snapshot` shape** (per REQUIREMENTS 004 L97–L102): `{code, title, parent_requirement_id, initial_status}`.

**Additive keys (only present when non-null on the row):**
- `priority text` — added when `p_priority` was supplied to `create_requirement` (§9.1) or when the column default is captured in the emit block.
- `source_kind text` — added when supplied.
- `category_kind text` — added when supplied.
- `owner_profile_id uuid` — added when supplied.
- `verification_method text` — added when supplied.
- `due_at timestamptz` — added when supplied.

**Backwards-compat statement:** existing consumers reading only `code`, `title`, `parent_requirement_id`, `initial_status` are unaffected. New consumers (APP 010 recipient resolver per Freeze Index §21.1; AI slice) may key on the added fields when present.

**Freeze Index section:** §21.1 (recipient rules reference `priority` and `owner_profile_id`), §27.6.
**Priority:** Critical (composer emits richer payload from Wave 1).

### 12.2 `requirement.updated` — payload additions

Three kinds are already emitted by the frozen RPCs (per REQUIREMENTS 004): `kind='edit'`, `kind='supersede'`, `kind='applicability'`.

**Additive keys for `kind='edit'`:**
- `changed_fields text[]` — already carried by the frozen `edit_requirement` diff block; APP 008 extends the diff set to include `priority`, `source_kind`, `category_kind`, `owner_profile_id`, `verification_method`, `due_at`. When one of the six additive fields changes and no other field changes, the event's `changed_fields` will be a single-element array — a legal shape today.
- `previous_priority text | null`, `new_priority text | null` — added when `priority` is in `changed_fields`.
- `previous_owner_profile_id uuid | null`, `new_owner_profile_id uuid | null` — added when `owner_profile_id` is in `changed_fields`. Enables APP 010 to notify the outgoing and incoming owner.
- `previous_due_at timestamptz | null`, `new_due_at timestamptz | null` — added when `due_at` is in `changed_fields`. Enables cron slice to reschedule reserved `requirement.due_soon`/`requirement.overdue` timers.

**Additive keys for `kind='supersede'`:** none. `superseded_by_code text` is **already emitted** by the frozen `supersede_requirement` RPC per `20260806120000_requirements_004_events_and_traceability.sql` L314 and is documented in `EVENT_MODEL.md` §4.13 (~L198). APP 008 adds **no further keys** for `kind='supersede'`; the frozen payload is preserved unchanged and consumed by APP 010 renderers as-is ("R-012 was superseded by R-042").

**Additive keys for `kind='applicability'`:** none required for v1. The frozen payload already carries `added_asset_ids`, `removed_asset_ids`, `kept_asset_ids`, `now_project_wide bool` (per REQUIREMENTS 004).

**Backwards-compat statement:** existing consumers unaffected. Every added key is optional.

**Freeze Index section:** §5, §8.4, §21.1, §27.6.
**Priority:** High.

### 12.3 `requirement.archived` — payload additions

**Frozen payload** carries `code`, `title`, `previous_status`, `archived_at`.

**Additive keys:** none required for v1. If APP 010 needs `owner_profile_id` for recipient fan-out (Freeze Index §21.1), it can be added here in Wave 2 as an additive key. Left uncommitted in Wave 1 to keep the change surface tight.

**Priority:** Medium (only if APP 010 recipient resolver reads it from the event vs. re-reading the row).

### 12.4 `requirement.assessed` — payload additions

**Frozen `subject_snapshot` shape** carries `asset_version_id`, `requirement_id`, `status`, `previous_status`, `note_snippet`, `action` (`created|updated`).

**Additive keys:**
- `priority text` — denormalized from the requirement at emit time. Enables APP 010 to fan out critical-unsatisfied assessments to project leads without a follow-up read (Freeze Index §21.1 recipient rule: "`assessed (status=not_satisfied or partial)` → Requirement owner + project leads").
- `is_critical_unsatisfied bool` — computed flag: `priority='critical' AND status IN ('not_satisfied','partial')`. Convenience for the notification recipient resolver.
- `owner_profile_id uuid | null` — denormalized owner at emit time; enables owner-first notification routing.

**Backwards-compat statement:** existing consumers unaffected.

**Freeze Index section:** §21.1, §27.6.
**Priority:** High (APP 010 needs the flag for fan-out logic).

---

## 13. New event types

**None emitted in APP 008 v1.** The four frozen events (`requirement.created`, `requirement.updated`, `requirement.archived`, `requirement.assessed`) cover every state transition.

### 13.1 RESERVED event names (name-only lock, no emitter in APP 008)

Every name below is registered in EVENT_MODEL.md with `RESERVED` annotation. No RPC in APP 008 emits them. Downstream slices bind against the fixed string.

| Event name | Reserved for | Emitter (future) | Freeze Index section |
|---|---|---|---|
| `requirement.due_soon` | Cron slice; reserved for APP 010 "approaching deadline" notification | Cron RPC scanning `requirements_due_at_partial_idx` (§4 I-5) | §20.2, §21.1 |
| `requirement.overdue` | Cron slice; reserved for APP 010 "overdue" notification | Same cron RPC | §20.2, §21.1 |
| `requirement.imported` | External-system sync (§23.7) | `import_requirements` RPC (reserved §9.8) | §20.2, §23.7 |
| `requirement.ai_suggested` | AI slice; reserved for AI-assisted composer suggestions | AI slice RPC | §20.2, G-14 |
| `requirement.ai_classified` | AI slice; reserved for AI-assisted classification | AI slice RPC | §20.2, G-14 |
| `requirement.auto_assessed` | AI slice; reserved for version-diff-driven auto-assessment | `auto_assess_version` RPC (reserved §9.8) | §23.6 |

**Payload shape (documentation for future emitters):**

- `requirement.due_soon` — `subject_kind='requirement'`, `subject_id=<requirement_id>`, `subject_snapshot={code, title, due_at, days_until_due, owner_profile_id}`.
- `requirement.overdue` — same shape as `due_soon`; `days_until_due` becomes negative.
- `requirement.imported` — `subject_snapshot={code, title, source_system, external_id, batch_id}`.
- `requirement.ai_suggested` — `subject_snapshot={code|null, suggestion_kind, ai_run_id, confidence}`.
- `requirement.ai_classified` — `subject_snapshot={suggested_source_kind|null, suggested_category_kind|null, suggested_priority|null, ai_run_id}`.
- `requirement.auto_assessed` — `subject_kind='version_requirement_assessment'`, `subject_snapshot={asset_version_id, requirement_id, ai_run_id, model_suggested_status, human_review_required bool}`.

**No emitter for these names is implemented in APP 008.** Type names are locked in the vocabulary only.

### 13.2 Discussion-related event reuse

APP 005 already owns `comment.created` and `comment.resolved`. The Freeze Index §17.3 cross-slice invalidations state: "APP 005 comment mutation with `target_requirement_id != null` → additionally invalidate `requirementDiscussions(requirement_id)` and `requirementTrace(requirement_id)`." **No new event type is added for requirement-scoped comments** — the invalidation edge is a subscribe-time filter on the existing `comment.*` events, keyed on the additive `target_requirement_id` column in the event payload (APP 005 payload already carries the target set; adding `target_requirement_id` to the payload when the frozen XOR arm is populated is a minor APP 005 payload extension enumerated by the APP 005 side, not by APP 008).

---

## 14. Query support RPCs

Every dashboard, filter, autocomplete, and detail-page query in APP 008 is backed by one of the read RPCs in §8. This section maps the Freeze Index §17.2 mapping table to the concrete signatures.

| Query key (Freeze Index §17.1) | Backing RPC | Section |
|---|---|---|
| `qk.requirement(id)` | `get_requirement(p_requirement_id)` | §8.1 |
| `qk.requirementByCode(projId, code)` | `get_requirement_by_code(p_project_id, p_workspace_id, p_code)` | §8.2 |
| `qk.requirementChain(id)` | `get_requirement_chain(p_requirement_id)` | §8.3 |
| `qk.requirementTrace(id)` | `get_requirement_trace(p_requirement_id)` | §8.4 |
| `qk.requirementsList(scope, view, filters)` | `list_requirements_dashboard(...)` | §8.5 |
| `qk.requirementsWorkspaceDashboard(wsId, view)` | `list_requirements_dashboard(p_ws_id, NULL, ...)` | §8.5 |
| `qk.requirementsProjectDashboard(projId, view)` | `list_requirements_dashboard(p_ws_id, p_proj_id, ...)` | §8.5 |
| `qk.requirementInboxCount(wsId)` | `get_requirement_inbox_count(p_ws_id)` | §8.6 |
| `qk.requirementMetrics('project', projId)` | `get_project_requirement_metrics(p_project_id)` | §8.7 |
| `qk.requirementMetrics('workspace', wsId)` | `get_workspace_requirement_metrics(p_ws_id)` | §8.8 |
| `qk.requirementAssessments(id)` | Frozen `get_version_assessments` variant scoped by requirement; alternatively a client-side filter of `get_requirement_trace(id).assessments`. | §8.4 fallback |
| `qk.requirementHistory(id)` | Reads `activity_events` filtered on `subject_kind='requirement' AND subject_id=<id>` UNION `subject_kind='version_requirement_assessment' AND subject_snapshot->>'requirement_id'=<id>`. Backed by the frozen activity_events read pattern from APP 006; no new RPC required. | Frozen |
| `qk.requirementDiscussions(id)` | Frozen APP 005 `list_comments` variant filtered on `target_requirement_id`. | Frozen (once §3.7 ships) |
| `qk.requirementApplicability(id)` | Client-side filter of `get_requirement(id).applicability_summary` + frozen `list_project_requirements` for the asset picker's requirement-side. | §8.1 |
| `qk.applicableRequirementsForAsset(assetId, versionId?)` | Frozen `list_applicable_requirements(p_design_asset_id, p_version_id)` | Frozen |
| `qk.assessmentsForVersion(versionId)` | Frozen `get_version_assessments(p_asset_version_id)` | Frozen |
| `qk.releaseReadinessForVersion(versionId)` | `get_release_readiness_for_version(p_asset_version_id)` | §8.9 |

**Cursor discipline.** The one paginated RPC (`list_requirements_dashboard`, §8.5) uses opaque `(updated_at desc, id desc)` cursors, encoded server-side, opaque to the client. No offset is ever accepted. Empty cursor = start of list. Matches APP 006 `list_reviews_dashboard` and APP 007 `list_approvals_dashboard` shape.

**No autocomplete RPC** in v1. Search in the filter bar uses the same `list_requirements_dashboard` with `p_search` filled in — trigram-backed (§4 I-6) when the extension is present.

---

## 15. Dashboard support

The dashboard product surface (Freeze Index §12) is backed by:

- **Row set:** `list_requirements_dashboard` (§8.5) — one RPC covers workspace and project scope, every named view (`all`, `active`, `my`, `overdue`, `compliance`, `bookmarks` + documented aliases `all_active`, `assigned_to_me`, `recently_updated`, `by_status`, `by_priority`, `by_source`, `needs_assessment`, `overdue_critical`, `archived`, `superseded`), saved views via the `p_saved_view_id` tail param, every filter (`?status`, `?priority`, `?source`, `?category`, `?scope`, `?assignee`, `?code`), text search (`?search=` maps to `p_search`), and cursor pagination.
- **Inbox badges:** `get_requirement_inbox_count` (§8.6) — the tri-digit chip `{assigned_to_me, overdue_critical, needs_assessment}` for the NavRail workspace-level Requirements entry.
- **Metrics strip:** `get_project_requirement_metrics` (§8.7) at project scope; `get_workspace_requirement_metrics` (§8.8) at workspace scope. Both are opt-in reads (Freeze Index §12.8 — collapsible off by default).
- **Bookmarks:** frozen APP 006 `user_bookmarks` with `entity_kind='requirement'`; frozen `toggle_bookmark` RPC unchanged (Freeze Index §13.4).
- **Saved views:** frozen APP 006 `user_saved_views` with `scope='requirements'`; frozen `save_dashboard_view`/`delete_dashboard_view` RPCs unchanged (Freeze Index §13.3).
- **Compliance page:** a variant `?view=compliance` server-interpreted by `list_requirements_dashboard` to enrich each row with the per-asset coverage payload (Freeze Index §16.4, G-11). Not a distinct RPC; same row set with a richer projection.

**Denorm counts.** None. Every count is computed at query time. This matches Freeze Index §16.5 and mirrors APP 006/APP 007 v1 discipline. If the `list_requirements_dashboard` payload's per-row `assessment_coverage` becomes too expensive at scale, a Wave 4 cached column can be introduced without breaking the RPC signature (the field remains in the return shape; only its source changes).

**My-scope filters.** `p_owner_ids uuid[]` at the RPC layer; `assigned_to_me` view resolves to `p_owner_ids := ARRAY[auth.uid()]` server-side. No client-side leak of the owner set. Matches APP 007 `p_approver_profile_ids uuid[]` shape.

---

## 16. Requirement traceability support

The trace-graph RPC (§8.4, `get_requirement_trace`) is the sole backing for the Traceability tab (Freeze Index §11.3, §15). This section restates its shape and index-backing for clarity.

**Signature:** `get_requirement_trace(p_requirement_id uuid)` returning `jsonb`.

**Return-shape restatement (see §8.4 for the full block):**

- `requirement` — the row (includes the additive columns from §3).
- `applicable_assets []` — resolved from `requirement_design_assets` joined to `design_assets`; empty ⇒ project-wide.
- `is_project_wide bool` — derived from row count on `requirement_design_assets` for the effective root.
- `sub_requirements []` — from `requirements` where `parent_requirement_id = p_requirement_id` (frozen `requirements_parent_idx`).
- `assessments []` — from `version_requirement_assessments` where `requirement_id = p_requirement_id` (frozen `vra_requirement_idx`).
- `related_changes []` — from `changes` where `requirement_id = p_requirement_id` (frozen `changes_requirement_idx` per REQUIREMENTS 002 L392–L394).
- `related_decisions []` — from `decisions` where `requirement_id = p_requirement_id` (frozen `decisions_requirement_idx` per REQUIREMENTS 002 L410–L412).
- `discussion_count int` — from `comments` where `target_requirement_id = p_requirement_id` (backed by new partial index §4 I-7, once §3.7 ships).
- `approval_requests []` — two-hop: `decisions.requirement_id = p_requirement_id → decisions.subject_id → approval_requests.id` when `decisions.subject_kind = 'approval_request'` (the frozen decision→approval linkage).
- `supersession_chain []` — walks `requirements.superseded_by_requirement_id` forward and backward via frozen `requirements_superseded_by_idx`.
- `metrics` — inline `{coverage_pct, critical_unsatisfied_count, unassessed_on_latest_count}`.

**Depth / limit discipline.** No graph traversal beyond the direct edges above. The chain walk (bounded) is the only iterative subquery. Every other edge is a single index lookup. No cursor is exposed on this RPC — the full bundle is returned in one round-trip (Freeze Index §15.5).

**Trace performance restatement (Freeze Index §15.5).** All indexes required for v1 loads already exist frozen. The Traceability tab is bounded by "how many changes and decisions cite this requirement" — a typical requirement in a project has O(1–10) such citations, well within a bundled read.

**Cross-slice trace-hook additions.** APP 009 (Releases) consumes the trace via `get_release_readiness_for_version` (§8.9) which is a projection of the trace filtered by version applicability. APP 010 (Notifications) consumes the trace's `discussion_count` and `approval_requests` fields for context in the notification body.

---

## 17. Requirement relationship model

The Freeze Index §10 enumerates every requirement ↔ X relationship. This section restates which relationships require new join tables or columns.

| Relationship | Backend surface | Additive in APP 008? | Freeze Index reference |
|---|---|---|---|
| Requirement ↔ Design Asset | Frozen `requirement_design_assets` join (L199–L230 of REQUIREMENTS 002). | No new surface. | §10.1 |
| Requirement ↔ Asset Version | Frozen `version_requirement_assessments` upsert per `(version, requirement)` (L236–L285 of REQUIREMENTS 002). | No new surface. | §10.2 |
| Requirement ↔ Review (APP 006) | Loose linkage via comments; new nullable `comments.target_requirement_id` column (§3.7) + XOR CHECK widening (§6.1). | Yes — one additive column, one CHECK widening. | §10.3, G-7 |
| Requirement ↔ Approval (APP 007) | Frozen `decisions.requirement_id` (L402–L408 of REQUIREMENTS 002) — reused. Approval Detail already shows "Requirements status" per APP 007 §9. **No new join table.** | No new surface. | §10.4, G-8 |
| Requirement ↔ Change | Frozen `changes.requirement_id` (L383–L397 of REQUIREMENTS 002). | No new surface. | §10.5 |
| Requirement ↔ Release (APP 009) | Read-only from APP 009 via `get_release_readiness_for_version` (§8.9). **No hard gate here.** APP 009 owns the gate policy. | Read RPC additive only. | §10.6, G-4, G-9 |
| Requirement ↔ Requirement | Frozen self-FKs `parent_requirement_id` and `superseded_by_requirement_id`. Backed by `get_requirement_chain` (§8.3). | No new surface. | §10.7, G-6, G-21 |
| Requirement ↔ Collection | Deferred (reserved `requirement_collections` join per §2 / Freeze Index §9.1). | No — reserved-only. | §9.1, G-5 |
| Requirement ↔ Discipline | Deferred (reserved `requirement_disciplines` join per §2 / Freeze Index §9.1). | No — reserved-only. | §9.1, G-5, G-18 |

**Justification for not adding `review_requirements`, `approval_request_requirements`, `release_requirements` join tables in v1:**

The Freeze Index §10.3 chose freeform linkage via comments for reviews (decision G-7). The Freeze Index §10.4 chose reuse of the frozen `decisions.requirement_id` linkage for approvals (decision G-8: "APP 008 v1 does NOT introduce a new `approval_request_requirements` join. Rationale: approvals already reason about requirements through the frozen `decisions.requirement_id` and via the read of `list_applicable_requirements` on the Approval Detail (per APP 007 §9). Structured waivers are an APP 007 v2 concern"). The Freeze Index §10.6 chose read-only integration for releases (decision G-9: "APP 008 does NOT introduce a hard gate. APP 009 owns the gate policy"). All three decisions are cited in this proposal's coverage matrix (§23) and preserved without proposing new tables.

If a future re-freeze introduces structured waivers (Freeze Index §23.9), the `requirement_waivers(approval_response_id, requirement_id, ...)` table would land then — owned by APP 007 v2 or a dedicated waiver slice.

---

## 18. Metrics support

Metrics RPCs are enumerated in §8.7 (`get_project_requirement_metrics`) and §8.8 (`get_workspace_requirement_metrics`). This section restates their shape against the Freeze Index §16 requirement list.

### 18.1 Per-project totals (Freeze Index §16.2)

Delivered by `get_project_requirement_metrics(p_project_id)`:

| Metric | Source |
|---|---|
| Total requirement count | `COUNT(*)` on `requirements` where `project_id = p_project_id`. |
| Counts by status | `COUNT(*) GROUP BY status`. |
| Counts by priority | `COUNT(*) GROUP BY priority` (falls back to "unset" bucket for NULL). |
| Unassessed-on-latest-version count | Requirements applicable to at least one asset's latest version with no VRA row on that version. |
| Critical-unsatisfied count | `priority='critical' AND latest VRA on any applicable asset's latest version is 'not_satisfied' or 'partial'`. |
| Overdue count | `due_at < now() AND status IN ('draft','active') AND (no VRA or latest is not 'satisfied')`. |
| Coverage rate | `satisfied ÷ applicable` on latest version per asset. |
| Trailing 30d creation rate | `COUNT(activity_events) WHERE event_type='requirement.created' AND occurred_at > now() - interval '30 days'`. |
| Trailing 30d assessment activity rate | Same shape for `requirement.assessed`. |

### 18.2 Per-workspace rollups (Freeze Index §16.3)

Delivered by `get_workspace_requirement_metrics(p_ws_id)`:

- Rollup of per-project metrics, filtered to projects the caller can view.
- Top-5 projects by critical-unsatisfied count.
- Top-5 owners by open-requirement load (`priority IN ('critical','high') AND status='active'`).

### 18.3 Days-since-last-assessment

Exposed per-row via `get_requirement(p_requirement_id).metrics.days_since_last_assessment` (§8.1). Computed as `EXTRACT(DAY FROM now() - max(vra.assessed_at))` for the requirement. NULL when no assessment exists.

### 18.4 Derivation strategy restatement

Every metric is computed at query time from `requirements` + `version_requirement_assessments` + `activity_events`. No cached-metric columns in v1 (Freeze Index §16.5). Matches APP 006 / APP 007 posture.

---

## 19. Cross-slice hooks

### 19.1 APP 006 (Reviews) — read integration

- Reviews may **discuss** requirements. Discussion capture flows via the additive `comments.target_requirement_id` column (§3.7). No changes to APP 006 RPCs or tables.
- The Requirement Detail Discussions tab reuses APP 005's `CommentsPanel` filtered on `target_requirement_id`. APP 006's `ReviewDetail` remains unchanged.

### 19.2 APP 007 (Approvals) — read integration

- Approvals may **cite** requirements via the frozen `decisions.requirement_id` (L402–L408 of REQUIREMENTS 002). Approval Detail already renders "Requirements status" per APP 007 §9 by reading `list_applicable_requirements` — APP 008 preserves that contract.
- APP 008 adds `get_requirement_trace` (§8.4) which enumerates approval requests whose decisions cite the requirement — the two-hop lookup described in §16. No changes to APP 007 RPCs, tables, or events.

### 19.3 APP 009 (Releases) — read-only integration

- APP 009 consumes `get_release_readiness_for_version(p_asset_version_id)` (§8.9). The return shape supports both loose (advisory) and hard (blocking) gate policies — APP 009 decides which per release-type.
- **Recommendation (deferred to APP 009 for authority; Freeze Index §8.3, G-4):** APP 009's release-readiness computation should include an "all critical assessed" check: `critical_unassessed_count == 0 AND critical_unsatisfied_count == 0`. APP 008 exposes both counts; APP 009 owns the enforcement.

### 19.4 APP 010 (Notifications) — event contract

- APP 010 subscribes to the four frozen `requirement.*` events plus the six reserved names (§13.1). Recipient rules per Freeze Index §21.1 are honored via the additive payload keys in §12 (`priority`, `owner_profile_id`, `is_critical_unsatisfied`).
- APP 008 does not implement the resolver, the delivery, or the muting — those are APP 010 concerns.

### 19.5 APP 011 (Realtime) — REMAINS OUT

**The three requirements tables remain OUT of `supabase_realtime`.** This is the frozen boundary set by REALTIME 001 (per `project_lign_requirements_layer_lock.md`). Adding requirements tables to the publication is a REALTIME re-freeze event, not an APP 008 decision (Freeze Index §22.2).

Fallback in v1: dashboards poll on tab-focus (5-minute stale time via TanStack Query) and refetch on cross-slice mutations. APP 007's and APP 006's realtime channels drive cross-slice invalidation of requirements queries via the mapping in Freeze Index §17.3.

Reserved realtime channel names (Freeze Index §22.3), name-locked with no subscription in APP 008:

- `requirement:{requirement_id}`
- `project:{project_id}:requirements`
- `workspace:{ws_id}:requirements`
- `version:{version_id}:assessments`
- `user:{profile_id}:requirement-inbox`

APP 008 exports these constants from `src/features/requirements/realtime.ts` as name-only placeholders. Subscription code is not shipped until REALTIME re-freeze.

---

## 20. Future extension points

Every future extension seam is name-locked in this proposal so downstream slices can bind against fixed strings without renaming pressure.

### 20.1 Reserved capability keys (Freeze Index §20.1, §23.6, §23.7)

- `requirement.ai_suggest`
- `requirement.ai_classify`
- `requirement.import`
- `requirement.auto_assess`

### 20.2 Reserved event names (Freeze Index §20.2, §21.1)

- `requirement.due_soon`
- `requirement.overdue`
- `requirement.imported`
- `requirement.ai_suggested`
- `requirement.ai_classified`
- `requirement.auto_assessed`

### 20.3 Reserved RPC name patterns (Freeze Index §23)

- `import_requirements(...)` — bulk import.
- `apply_requirement_template(...)` — template instantiation.
- `auto_assess_version(...)` — AI auto-assessment.

### 20.4 Reserved columns (Freeze Index §23.7, §23.8, §6.4)

- `version_requirement_assessments.evidence_file_ids uuid[]` — evidence attachment.
- `requirements.external_id text`, `.external_system text` — external-system sync.
- `requirements.additional_source_kinds text[]` — multi-source support.

### 20.5 Reserved tables (Freeze Index §23, §9.1, §21.3)

Enumerated in §2 above.

### 20.6 Reserved AI slot kinds (Freeze Index §20)

- `requirement-classification`
- `assessment-questions`
- `applicability-suggestion`
- `regulation-parse`
- `similar-requirements`
- `assessment-consistency`
- `requirement-summary`

These are frontend-slot names, not backend contracts, but they're captured here so the ecosystem has one place to consult.

### 20.7 Reserved realtime channel names

Enumerated in §19.5 above.

---

## 21. Consolidated priority summary

| Priority | Item | Section | Blocks impl? |
|---|---|---|---|
| **Critical** | `requirements.priority` column + CHECK + default `'medium'` | §3.1 | Yes |
| **Critical** | `requirements.source_kind` column + CHECK | §3.2 | Yes |
| **Critical** | `requirements.category_kind` column + CHECK | §3.3 | Yes |
| **Critical** | `requirements.owner_profile_id` column + composite FK | §3.4, §5.1 | Yes |
| **Critical** | Index I-1 `requirements_project_priority_idx` | §4 | Yes |
| **Critical** | Index I-2 `requirements_project_owner_idx` | §4 | Yes |
| **Critical** | `create_requirement` extended (Option A tail params ×6) | §9.1 | Yes |
| **Critical** | `edit_requirement` extended (Option A tail params ×6) | §9.2 | Yes |
| **Critical** | `get_requirement` read RPC | §8.1 | Yes |
| **Critical** | `get_requirement_by_code` read RPC | §8.2 | Yes |
| **Critical** | `list_requirements_dashboard` read RPC | §8.5 | Yes |
| **Critical** | `requirement.created` payload extension (priority, source_kind, category_kind, owner_profile_id, verification_method, due_at) | §12.1 | Yes |
| **High** | `requirements.due_at` column | §3.6 | No |
| **High** | `comments.target_requirement_id` column + composite FK | §3.7, §5.2 | No |
| **High** | XOR CHECK widening on `comments` | §6.1 | No |
| **High** | Index I-3 `requirements_project_source_idx` | §4 | No |
| **High** | Index I-4 `requirements_project_category_idx` | §4 | No |
| **High** | Index I-5 `requirements_due_at_partial_idx` | §4 | No |
| **High** | Index I-7 `comments_target_requirement_partial_idx` | §4 | No |
| **High** | `get_requirement_chain` read RPC | §8.3 | No |
| **High** | `get_requirement_inbox_count` read RPC | §8.6 | No |
| **High** | `requirement.updated` payload extension (previous/new priority, owner, due_at; extended `changed_fields`) | §12.2 | No |
| **High** | `requirement.assessed` payload extension (priority, is_critical_unsatisfied, owner_profile_id) | §12.4 | No |
| **Medium** | `requirements_default_owner_on_insert` trigger | §11.1 | No |
| **Medium** | Index I-6 GIN trigram on `requirements(title, description)` | §4 | No |
| **Medium** | `get_requirement_trace` read RPC | §8.4 | No |
| **Medium** | `get_project_requirement_metrics` read RPC | §8.7 | No |
| **Medium** | `get_workspace_requirement_metrics` read RPC | §8.8 | No |
| **Medium** | `get_release_readiness_for_version` read RPC | §8.9 | No |
| **Medium** | `requirement.archived` payload extension (owner_profile_id, if APP 010 needs) | §12.3 | No |
| **Future** | `requirements.verification_method` column + CHECK | §3.5 | No |
| **Future** | Reserved capability: `requirement.ai_suggest` | §7 | No |
| **Future** | Reserved capability: `requirement.ai_classify` | §7 | No |
| **Future** | Reserved capability: `requirement.import` | §7 | No |
| **Future** | Reserved capability: `requirement.auto_assess` | §7 | No |
| **Future** | Reserved event: `requirement.due_soon` | §13.1 | No |
| **Future** | Reserved event: `requirement.overdue` | §13.1 | No |
| **Future** | Reserved event: `requirement.imported` | §13.1 | No |
| **Future** | Reserved event: `requirement.ai_suggested` | §13.1 | No |
| **Future** | Reserved event: `requirement.ai_classified` | §13.1 | No |
| **Future** | Reserved event: `requirement.auto_assessed` | §13.1 | No |
| **Future** | Reserved columns: `evidence_file_ids uuid[]`, `external_id`, `external_system`, `additional_source_kinds text[]` | §3.8, §20.4 | No |
| **Future** | Reserved tables: `requirement_subscriptions`, `_templates`, `_library_items`, `_collections`, `_disciplines`, `_waivers`, `_custom_sources`, `_custom_categories` | §2, §20.5 | No |
| **Future** | Reserved realtime channels (5 names) | §19.5, §20.7 | No |

**Tally:** 12 Critical, 10 High, 7 Medium, 20 Future.

---

## 22. Implementation waves

Four waves. Wave 1 is the Backend Re-freeze target; Wave 4 is documentation-only.

### Wave 1 — Critical (Backend Re-freeze target)

**Schema:**
- 4 columns on `requirements` (`priority`, `source_kind`, `category_kind`, `owner_profile_id`).
- 4 CHECKs (`priority`, `source_kind`, `category_kind` — one each; the `owner_profile_id` FK is a composite FK, not a CHECK).
- 1 composite FK (`owner_profile_id` → `workspace_members`).
- 2 indexes (I-1, I-2).

**RPCs:**
- 3 read RPCs (`get_requirement`, `get_requirement_by_code`, `list_requirements_dashboard`).
- 0 new write RPCs.
- 2 frozen write RPCs extended with Option A tail params (`create_requirement`, `edit_requirement`).

**Capabilities:** 0 wired. 4 reserved names registered in PERMISSIONS.md (`requirement.ai_suggest`, `requirement.ai_classify`, `requirement.import`, `requirement.auto_assess`).

**Events:** 0 new emitted. 6 reserved names registered in EVENT_MODEL.md. Payload extensions on `requirement.created` shipped in Wave 1 (part of the extended `create_requirement`).

**Triggers:** 0 required. 1 optional (`requirements_default_owner_on_insert`) may ship in Wave 1 as convenience.

**Wave 1 summary:** 4 columns, 3 CHECKs, 1 FK, 2 indexes, 3 read RPCs, 2 extended write RPCs, 0 wired capabilities, 0 emitted event types, 1 event payload extended, 0–1 triggers.

**After Wave 1, APP 008 v1 implementation of composer + dashboards can start.**

### Wave 2 — High

**Schema:**
- 2 columns (`requirements.due_at`, `comments.target_requirement_id`).
- 1 composite FK (`comments.target_requirement_id`).
- 1 CHECK widening (`comments` XOR).
- 4 indexes (I-3, I-4, I-5, I-7).

**RPCs:**
- 2 read RPCs (`get_requirement_chain`, `get_requirement_inbox_count`).

**Events:** payload extensions on `requirement.updated` (with `previous_priority`, `new_priority`, `previous_owner_profile_id`, `new_owner_profile_id`, `previous_due_at`, `new_due_at`) and on `requirement.assessed` (with `priority`, `is_critical_unsatisfied`, `owner_profile_id`).

**Wave 2 summary:** 2 columns, 1 FK, 1 CHECK widening, 4 indexes, 2 read RPCs, 2 event payloads extended.

### Wave 3 — Medium

**Schema:**
- 1 index (I-6 GIN trigram — requires `pg_trgm` extension check).

**RPCs:**
- 4 read RPCs (`get_requirement_trace`, `get_project_requirement_metrics`, `get_workspace_requirement_metrics`, `get_release_readiness_for_version`).

**Events:** optional payload extension on `requirement.archived` if APP 010 recipient resolver requires denormalized `owner_profile_id`.

**Reserved-name registration:** all reserved capability keys, event names, realtime channel names, RPC names, and column names committed to PERMISSIONS.md, EVENT_MODEL.md, and the code registries.

**Wave 3 summary:** 1 index, 4 read RPCs, up to 1 event payload extension, full reserved-name registration.

### Wave 4 — Future (intentionally unimplemented)

**Catalogues:**
- 1 column (`requirements.verification_method` and its CHECK — may ship in Wave 1 for storage-only, no UI).
- 4 reserved columns (§3.8).
- 8 reserved tables (§2).
- 3 reserved write RPCs (§9.8).
- 6 reserved event emitters (§13.1).
- 4 reserved capability wirings (§7).
- Weighted priorities / numeric scoring, hierarchical escalation, delegation, bulk assessment, hard release-readiness gate — all APP 009 / APP 010 / AI-slice / future-re-freeze concerns.

**Wave 4 summary:** 0 changes shipped; documentation-only registry of the deferred surface.

---

## 23. Coverage matrix

Every Freeze Index section (§1 through §24) mapped to the backend items in this proposal that back it.

| Freeze Index § | Description | Backend items | Coverage |
|---|---|---|---|
| §1 | Purpose | N/A (product-scope statement) | N/A |
| §2 | Domain model — `Requirement`, `RequirementApplicability`, `VersionRequirementAssessment`, source/category concepts | §3.1–§3.7 (additive columns); §5 (composite FKs); §6 (CHECK widenings); §9.1, §9.2 (frozen RPCs extended) | **Fully covered** |
| §3 | Lifecycle — 4-state, transitions, immutability, applicability, assessment | Frozen surface unchanged; §11.2 restates that no new chain columns are needed | **Fully covered (via frozen)** |
| §4 | State machine table + supersession chain semantics + assessment vocabulary | Frozen surface unchanged; §8.3 (`get_requirement_chain`) surfaces the walk | **Fully covered** |
| §5 | Requirement ownership | §3.4 (`owner_profile_id`); §5.1 (FK); §9.1, §9.2 (RPC tail params); §11.1 (optional default trigger); §12.1, §12.2 (payload) | **Fully covered** |
| §6 | Requirement sources — enum + free-text | §3.2 (`source_kind` column + CHECK); §12.1, §12.2 (payload); §4 I-3 (index) | **Fully covered** |
| §7 | Requirement categories — enum + free-text | §3.3 (`category_kind` column + CHECK); §12.1, §12.2 (payload); §4 I-4 (index) | **Fully covered** |
| §8 | Requirement priority — 5 tiers, mutable, release-readiness input | §3.1 (`priority` column + CHECK + default); §4 I-1 (index); §9.1, §9.2 (RPC tail params); §12.1, §12.2 (payload); §8.9 (release-readiness read) | **Fully covered** |
| §9 | Requirement scope — 5 layers | Frozen `requirement_design_assets` unchanged; collection/discipline layers deferred (§2, Freeze Index G-5) | **Partially covered (v1)**, deferred for collection/discipline layers |
| §10 | Relationships — asset, version, review, approval, change, release, requirement, collection, discipline | §3.7 (`comments.target_requirement_id`); §5.2 (FK); §6.1 (XOR widening); §8.9 (release-readiness); §17 restates | **Fully covered** for v1 surface; join tables reserved for v2 |
| §11 | Requirement Detail page primitives | §8.1 (`get_requirement`); §8.3 (chain); §8.4 (trace); §12 payload extensions | **Fully covered** |
| §12 | Requirement dashboard — views, filters, inbox, metrics | §8.5 (`list_requirements_dashboard`); §8.6 (inbox); §8.7 (metrics); §4 indexes I-1 through I-5 | **Fully covered** |
| §13 | Search & filtering — text, structured, saved views, bookmarks, cursor | §8.5 with `p_search`, `p_status_filter`, `p_priority_filter`, `p_source_filter`, `p_category_filter`, `p_scope_filter`, `p_owner_ids`, opaque cursor; §4 I-6 (GIN trigram, Wave 3); frozen APP 006 bookmarks/saved-views reused | **Fully covered** |
| §14 | Linking — deep links, copy-link, cross-slice | §8.2 (`get_requirement_by_code`); no backend changes for `useCopyLink` beyond frozen surface | **Fully covered** |
| §15 | Traceability | §8.4 (`get_requirement_trace`); §8.3 (chain); §8.9 (release-readiness) | **Fully covered** |
| §16 | Metrics — per-requirement, per-project, per-workspace, compliance | §8.1 (per-req in `get_requirement`); §8.7 (project); §8.8 (workspace); compliance view via §8.5 variant | **Fully covered** |
| §17 | Query architecture — qk namespace, RPC mapping, invalidations, cursor | §8 read RPCs; §14 mapping table; cross-slice invalidations documented at Freeze Index §17.3 | **Fully covered** |
| §18 | URL grammar | Backend does not own URL grammar; §8.5 accepts every filter param cleanly | **Fully covered (backend contract)** |
| §19 | Navigation ownership | Backend does not own NavRail; §8.6 backs the workspace-level badge; §8.7 backs the project-level badge | **Fully covered (backend contract)** |
| §20 | AI extension seams | §7 reserved capabilities (`requirement.ai_suggest`, `requirement.ai_classify`); §13.1 reserved events (`requirement.ai_suggested`, `requirement.ai_classified`, `requirement.auto_assessed`) | **Fully covered (reserved-only)** |
| §21 | Notification contracts | §12.1, §12.2, §12.4 payload extensions carry `priority`, `owner_profile_id`, `is_critical_unsatisfied` for APP 010 recipient resolver | **Fully covered (contract only; APP 010 owns delivery)** |
| §22 | Realtime contracts | §19.5 confirms requirements tables remain OUT of `supabase_realtime`; §20.7 reserved channel names | **Fully covered (name-locked, no subscription)** |
| §23 | Extension points | §2 (reserved tables); §3.8 (reserved columns); §7 (reserved capabilities); §9.8 (reserved RPCs); §13.1 (reserved events); §20 (all seams) | **Fully covered (reserved-only)** |
| §24 | Open architectural decisions | Every G-* decision cited in the relevant section above; see §24 below for backwards-compat statement | **Fully covered** |

**Deferred to Future** (per Freeze Index scope decisions, not gaps in this proposal): collection scope, discipline scope, structured waivers, requirement subscriptions, templates, libraries, imports, evidence attachment, weighted priorities, hard release gate.

---

## 24. Backwards-compat guarantees

Explicit statement that this proposal, on landing, preserves every prior contract.

### 24.1 No frozen RPC signature is broken

- `create_requirement(uuid, uuid, text, text, text, text, text, uuid, text)` — 9-arg signature preserved verbatim. New tail params default to NULL. A caller invoking the frozen 9-arg form observes byte-identical behavior. The extended form is a Postgres function overload via default parameters — the SAME function, with additional trailing parameters.
- `edit_requirement(uuid, text, text, text, text, text, text)` — 7-arg signature preserved verbatim. Same default-NULL discipline.
- `archive_requirement(uuid)` — unchanged.
- `supersede_requirement(uuid, uuid)` — unchanged.
- `set_requirement_applicability(uuid, uuid[])` (frozen name and shape) — unchanged.
- `assess_version_requirement(...)` (frozen signature) — unchanged.
- `list_project_requirements(uuid)` — unchanged.
- `list_applicable_requirements(uuid, uuid default null)` — unchanged.
- `get_version_assessments(uuid)` — unchanged.

### 24.2 No frozen event name changes

The four frozen event types remain: `requirement.created`, `requirement.updated`, `requirement.archived`, `requirement.assessed`. Every payload extension is additive (§12). Consumers reading only the frozen `subject_snapshot` keys are unaffected.

### 24.3 No frozen capability role map changes

The five frozen capability keys (`requirement.view`, `requirement.create`, `requirement.edit`, `requirement.archive`, `requirement.assess`) retain their frozen role grants (per REQUIREMENTS 003 L77–L154). Lead: all 5. Contributor: 4 (view, create, edit, assess) — never archive. Reviewer / approver: view + assess. Observer: view. Workspace admin: view via override.

The two reserved capability keys (`requirement.ai_suggest`, `requirement.ai_classify`) plus the further reserved `requirement.import`, `requirement.auto_assess` are added to PERMISSIONS.md with **zero role grants** — they change nothing about existing authorization for any existing role.

### 24.4 No frozen table RLS policy changes

Every SELECT, INSERT, UPDATE policy on `requirements`, `requirement_design_assets`, `version_requirement_assessments` per REQUIREMENTS 002 L434–L486 is preserved byte-for-byte. The DELETE-denied posture is preserved. RLS on `comments` is preserved; the additive `target_requirement_id` column does not weaken any policy (§10.4).

### 24.5 No frozen trigger changes

Every trigger from REQUIREMENTS 002 (`requirements_set_updated_at`, `requirements_enforce_hierarchy`, `requirements_enforce_immutability`, `vra_enforce_applicability`, `vra_enforce_immutability`, `vra_set_updated_at`) is preserved verbatim. The one new trigger (`requirements_default_owner_on_insert`, §11.1) is optional and additive — it fires only when `owner_profile_id` is NULL at INSERT and only defaults the value; it never blocks any INSERT.

### 24.6 No conflict with Freeze Index scope

Every proposal in this document appears in Freeze Index §27 preview or in a section explicitly cited by §27. Where the Freeze Index defers something (collection scope, discipline scope, subscriptions, templates, libraries, waivers, custom enums, evidence attachment, weighted priorities, hard release gate), this proposal defers it too. **No frozen surface is proposed for modification.** If a future need arises to modify the frozen REQUIREMENTS surface, it will be recorded as a candidate for a future re-freeze — not proposed here.

### 24.7 No conflict with SCHEMA_V1_LOCK

Every new column is additive; every new FK is composite (tenancy-coherent); every new index is either partial (for nullable columns) or a covering index on a new FK; every new CHECK is a widening or applies only to new columns. Total table count remains 26 (per `project_lign_schema_v1_lock.md`) — zero new tables in v1. Schema V1 lock is preserved.

### 24.8 No conflict with STORAGE 001–004, REALTIME 001–002, AUTH 001–009

- STORAGE surface: untouched.
- REALTIME publication: unchanged (requirements tables remain OUT — §19.5).
- AUTH: `lign_has_capability` extension in REQUIREMENTS 003 L30–L154 is the frozen extension; APP 008 adds no further branches to it. Reserved capability keys are registered in PERMISSIONS.md without touching `lign_has_capability`.

---

## 25. Applied review-finding pattern

Every accepted finding from the Backend Re-freeze Review has been applied to this document. Table shape mirrors `APP_007_BACKEND_PROPOSAL.md` §0.

| ID | Severity | Applied? | Section(s) touched | One-line summary |
|---|---|---|---|---|
| F-3.1-H1 | HIGH | Yes | §1, §3.4, §5.1 | Composite FK target renamed `workspace_members(profile_id, workspace_id)` → `workspace_members(user_id, workspace_id)` with frozen-schema justification inlined. |
| F-3.1-L1 | LOW | Yes | §3.4, §5.1 | "Workspace member" clarified to mean an active member (`workspace_members.status != 'removed'`). |
| F-3.4-M1 | MEDIUM | Yes | §12.2 | Stale claim removed: `superseded_by_code` is already emitted by frozen `supersede_requirement` (REQUIREMENTS 004 L314); no additive keys for `kind='supersede'`. |
| F-6.1-L1 | LOW | Yes | §6.1 | XOR wording tightened: frozen `comments_target_xor_check` is exactly-one-of-seven (predicate `= 1`); APP 008 widens to exactly-one-of-eight. |
| F-3.3-L1 | LOW | Yes | §8.5 | `assessment_coverage` and `applicability_summary` return-shape locked to canonical object shapes. |
| F-3.3-L2 | LOW | Yes | §8.5, §15 | `p_saved_view_id uuid default null` split out as a distinct additive tail parameter; inline `saved:<uuid>` view-encoding replaced. |
| F-3.7-L1 | LOW | Yes | §11.1 | Default-owner trigger dependency on `created_by_profile_id` populated by frozen `create_requirement` (REQUIREMENTS 003 L235–L236) documented; service-role bypass no-op path stated. |

---

**APP 008 Backend is frozen.**
