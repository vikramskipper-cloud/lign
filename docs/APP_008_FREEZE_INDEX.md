# APP 008 — Freeze Index

**Canonical architecture reference for the Lign Requirements module.**

Implementation has not started. This document consolidates the APP 008 (Requirements product surface) architecture into one navigational reference on top of the frozen REQUIREMENTS 001–005 backend layer. It preserves every APP 001–007 contract; extension is additive only. Sections marked **[additive]** identify surface expansions that will be enumerated by the follow-on `APP_008_BACKEND_PROPOSAL.md` — no SQL, no migration, no RPC bodies are proposed here.

**Companion frozen inputs:**
- `supabase/migrations/20260804120000_requirements_002_schema.sql` — the 3 tables and additive columns.
- `supabase/migrations/20260805120000_requirements_003_authz_and_rpcs.sql` — 5 capabilities + 6 workflow RPCs.
- `supabase/migrations/20260806120000_requirements_004_events_and_traceability.sql` — 4 events + 3 read RPCs.
- `docs/APP_007_FREEZE_INDEX.md`, `docs/APP_006_FREEZE_INDEX.md` — pattern parity.
- `docs/DOMAIN_MODEL.md`, `docs/PERMISSIONS.md`, `docs/EVENT_MODEL.md`, `docs/STATE_MACHINES.md`, `docs/DATABASE_SCHEMA.md`, `docs/AUTHORIZATION_ARCHITECTURE.md`.
- Memory: `project_lign_requirements_layer_lock.md` (REQUIREMENTS 001–005 frozen).

---

## 1. Purpose

APP 008 owns the **product-surface architecture for Requirements** — dashboards, detail pages, filtering grammar, URL grammar, deep links, navigation, traceability views, metrics, and the additive extension seams the product UX genuinely requires. It builds on the frozen REQUIREMENTS 001–005 backend without weakening any invariant.

### 1.1 What Requirements ARE, ARE NOT, and DO

| Axis | Requirements ARE | Requirements are NOT |
|---|---|---|
| **Nature** | Long-lived project obligations | Comments, reviews, or approvals |
| **Origination** | Any stakeholder (client, consultant, regulator, QA, procurement, manufacturing, safety, internal team) | Only originating from within the design team |
| **Persistence** | Exist independently of any review or approval; survive the lifecycle of every asset they touch | Ephemeral opinions or ad-hoc feedback |
| **Effect** | Bind many assets, versions, collections, and downstream work; determine what "done" means | A checklist attached to one asset version |
| **Relationship to reviews** | Reviews *discuss* requirements | The vehicle for discussion |
| **Relationship to approvals** | Approvals *approve changes that satisfy* requirements | The record of authorization |
| **Verification** | Verified per-`asset_version` via `version_requirement_assessments` (satisfied / partial / not_satisfied / not_applicable) | Verified once at creation and forgotten |
| **First-class status** | A full module with its own dashboards, detail screens, URL grammar, deep links, metrics, notifications | A sidecar or a tab on another entity |

### 1.2 What APP 008 owns exclusively

- Requirement dashboards (workspace + project scope) and their view grammar.
- Requirement Detail page (Overview / Applicability / Assessments / History / Discussions / Traceability tabs).
- Requirement-scoped URL parameters (`?view`, `?status`, `?priority`, `?source`, `?category`, `?scope`, `?assignee`, `?code`, `?cursor`, `?tab`).
- Deep-link kinds: `requirement`, and code-form resolver `/deep/requirement/:code`.
- The NavRail "Requirements" entries at workspace and project scopes.
- The project-shell "Requirements" tab.
- Trace API surface (read RPC preview in §15, §27).
- Additive capabilities and event names reserved in §11, §21.
- Reusable primitives introduced in §11 (`RequirementDetailShell`, `AssessmentGrid`, `ScopeChip`, `TraceGraphCard`).

### 1.3 What APP 008 must not touch

- Frozen surface of REQUIREMENTS 001–005 (tables, workflow RPC signatures, capability keys, event vocabulary). Any conflict is recorded in §24 as a candidate for future re-freeze.
- APP 001–007 domain invariants, capability primer, `qk` conventions, router shape, URL grammar, deep-link kinds, hotkey bindings, or component APIs.
- Storage layer (STORAGE 001–004) — untouched.
- Realtime publication (REALTIME 001–002) — the 3 requirements tables remain OUT of `supabase_realtime`. See §22.

### 1.4 Collaboration with APP 006 (Reviews) and APP 007 (Approvals)

| Surface | APP 006 (Reviews) | APP 007 (Approvals) | APP 008 (Requirements) |
|---|---|---|---|
| Purpose | Iterate on a version | Grant authority for a version | Bind long-lived project obligations |
| Weight | Advisory | Binding, immutable | Structural — outlives the artifact |
| Cardinality | One review per version-round | Chain of approval requests per version | Many requirements per project; many-to-many with assets; per-version assessments |
| Relationship | Reviews may *discuss* requirements (loose join, §10) | Approvals may *cite* requirements via `decisions.requirement_id` (frozen; see §10) | Requirements are the referent |

APP 008 reads APP 006's `CommentsPanel` (unchanged) and APP 007's decision surfaces (unchanged); it never writes into their entities. APP 007 already reads `list_applicable_requirements` and displays a "Requirements status" panel per APP 007 §9 — APP 008 preserves that read contract.

---

## 2. Domain model

APP 008 works with three frozen entities from REQUIREMENTS 002 plus two conceptual product-layer entities that surface behavior already implicit in the frozen schema. No new schema is required for the base entities; extension columns are enumerated in §27 as **[additive]**.

### 2.1 `Requirement`

The primary object. Backed by frozen `public.requirements`.

**Frozen fields** (from REQUIREMENTS 002):
- `id uuid pk`
- `workspace_id uuid`, `project_id uuid` (immutable)
- `parent_requirement_id uuid` (immutable; nullable; two-level hierarchy — root or single-depth sub)
- `code text` (immutable; per-project stable; server-generated `R-NNN` for roots or `<parent_code>.<n>` for subs)
- `title text` (1..500 chars)
- `description text` (nullable free-form)
- `category text` (nullable; free-text in v1 — §7 recommends coalescing to a controlled vocabulary via **[additive]** enum)
- `source text` (nullable; free-text in v1 — §6 recommends coalescing to a controlled vocabulary via **[additive]** enum)
- `source_ref text` (nullable; regulation code, contract clause, ticket ID, etc.)
- `status text` — one of `draft | active | superseded | archived`
- `superseded_by_requirement_id uuid` (nullable; coherent with `status='superseded'`)
- `archived_at timestamptz` (nullable; coherent with `status='archived'`)
- `created_by_profile_id uuid`, `created_at timestamptz`, `updated_at timestamptz`

**[additive] Fields APP 008 will need** (labeled here; enumerated in §27):
- `priority text` — one of `critical | high | medium | low | informational` (see §8). *Why: sort order for dashboards; release-readiness computation cannot proceed without an ordinal signal.*
- `source_kind text` — controlled enum coalescing `source` (see §6). *Why: filter grammar and metrics rely on a bounded value space.*
- `category_kind text` — controlled enum coalescing `category` (see §7). *Why: same reason.*
- `owner_profile_id uuid` — separate from `created_by_profile_id` because ownership survives originator departure (see §5). *Why: notifications and inbox routing need a stable owner independent of creation actor.*
- `verification_method text` — one of `inspection | test | analysis | demonstration` (reserved v2 hook; see §23). *Why: aligns with common systems-engineering practice for future audit exports.*
- `due_at timestamptz` — optional deadline for first assessment on the latest version (see §8, §16). *Why: overdue metrics.*

None of the above **[additive]** fields are required to preserve the frozen surface — every existing RPC continues to function without them.

### 2.2 `RequirementApplicability`

Backed by frozen `public.requirement_design_assets`. Many-to-many join between `requirements` (root only — sub-requirements inherit) and `design_assets`. Empty set for a root ⇒ **project-wide**. Presence of rows ⇒ scoped to exactly those assets.

**Frozen fields:** `requirement_id`, `design_asset_id`, `workspace_id`, `project_id`, `created_at`.

**[additive] Fields APP 008 may need** (deferred; not v1 scope): none required for the surface described here. A future **[additive]** join `requirement_collections(requirement_id, collection_id)` is called out in §9 as an optional scope layer.

### 2.3 `VersionRequirementAssessment`

Backed by frozen `public.version_requirement_assessments`. Upsert per `(asset_version_id, requirement_id)`. Status: `satisfied | partial | not_satisfied | not_applicable`. Enforced by frozen `vra_enforce_applicability` trigger.

**Frozen fields:** `id`, `workspace_id`, `project_id`, `asset_version_id`, `requirement_id`, `status`, `note`, `assessed_by_profile_id`, `assessed_at`, `created_at`, `updated_at`.

**[additive] Fields APP 008 may need:** none in v1. Reserved for v2: `evidence_file_ids uuid[]` — links to attached evidence via APP 004 `FilesPanel` (§23).

### 2.4 `RequirementSource` (conceptual, product-layer)

Not a table. A controlled enum of source kinds surfaced through the **[additive]** `source_kind` column on `requirements`. See §6 for the enum values and the enum-vs-tags decision.

### 2.5 `RequirementCategory` (conceptual, product-layer)

Not a table. A controlled enum of category kinds surfaced through the **[additive]** `category_kind` column. See §7.

### 2.6 Ownership boundaries — reuse vs. new

| Layer | Reused frozen surface | **[additive]** required |
|---|---|---|
| Core table | `public.requirements` | 5 nullable columns (§2.1) |
| Applicability | `public.requirement_design_assets` | none in v1 |
| Assessment | `public.version_requirement_assessments` | none in v1 |
| Traceability | `changes.requirement_id`, `decisions.requirement_id` | 2 optional join tables (§10) |
| Bookmarks | `user_bookmarks` (APP 006) with `entity_kind='requirement'` | none |
| Saved views | `user_saved_views` (APP 006) with `scope='requirements'` | none |
| Roster | Not applicable (requirements have `owner_profile_id`, not a roster) | none |
| Comments | `CommentsPanel` (APP 005) with a new `target_requirement_id` **[additive]** on `comments` | 1 nullable column (§10) |

### 2.7 Cardinality summary

- One `requirement` has 0..N sub-requirements (max depth = 1 per frozen `enforce_requirement_hierarchy`).
- One `requirement` has 0..N `requirement_design_assets` (0 = project-wide).
- One `requirement` has 0..N `version_requirement_assessments` (one per version per requirement, upserted).
- One `requirement` may be cited by 0..N `changes.requirement_id` and 0..N `decisions.requirement_id`.
- One `requirement` may be superseded by exactly 0 or 1 other requirement (`superseded_by_requirement_id`).

---

## 3. Lifecycle

### 3.1 The 4-state lifecycle (frozen)

Per REQUIREMENTS 002 `requirements_status_check`:

- `draft` — requirement is being authored; not yet asserted as binding.
- `active` — requirement is live and binding; drives applicability and assessment flows.
- `superseded` — requirement has been replaced by a newer requirement (`superseded_by_requirement_id` set; coherent with status). Historical; not deletable.
- `archived` — requirement is retired without replacement (`archived_at` set; coherent with status). Historical; not deletable.

Terminal set: `superseded`, `archived`. Non-terminal set: `draft`, `active`.

### 3.2 Legal transitions

Enumerated by the frozen `edit_requirement`, `archive_requirement`, `supersede_requirement` RPCs.

```
                  create              publish
   ∅ ──────────▶ [ draft ] ─────────▶ [ active ]
                    │                    │
                    │  archive           │ archive
                    ▼                    ▼
                [ archived ]         [ archived ]
                    ▲                    │
                    │                    │  supersede
                    │                    ▼
                    │                [ superseded ]
                    │                    ▲
                    └────────────────────┘
                     (supersede blocked
                      on archived; frozen)
```

Guards enforced by frozen RPCs:
- `edit_requirement` — blocked on `superseded` and `archived`; only toggles between `draft` and `active` for status.
- `archive_requirement` — blocked on `superseded`; idempotent on `archived`.
- `supersede_requirement` — blocked on `superseded` and `archived` (old side); replacement must be `draft` or `active`; same project; not self.

### 3.3 Immutability at row level

Frozen `requirements_enforce_immutability` blocks post-creation changes to `workspace_id`, `project_id`, `code`, `parent_requirement_id`. Assessments are protected by frozen `vra_enforce_immutability` on `workspace_id`, `project_id`, `asset_version_id`, `requirement_id`.

### 3.4 Applicability lifecycle

`set_requirement_applicability` is root-only (frozen). Sub-requirements inherit parent applicability at assessment time via `vra_enforce_applicability`. Applicability is *replaceable* (delete + insert atomically) but assessments recorded before an applicability narrowing are preserved as historical facts (frozen behavior; assessments are never cascade-deleted from RDA changes).

### 3.5 Assessment lifecycle

`assess_version_requirement` upserts per `(asset_version_id, requirement_id)`. The **previous** status is captured into `subject_snapshot.previous_status` on `requirement.assessed`. Assessments are per-version — a positive assessment on `v3` does not roll forward to `v4`.

---

## 4. State machine

Full state × transition × trigger × event × capability × side-effects matrix. All rows describe the frozen backend; product surface simply exposes these transitions.

| From | To | Transition trigger | RPC | Event emitted | Capability required | Side effects |
|---|---|---|---|---|---|---|
| ∅ | `draft` | Author creates requirement | `create_requirement` | `requirement.created` | `requirement.create` | Server-generated `code` under per-project xact lock; row inserted; `subject_snapshot={code,title,parent_requirement_id,initial_status}` |
| ∅ | `active` | Author creates with `p_status='active'` | `create_requirement` | `requirement.created` | `requirement.create` | Same as above; `initial_status='active'` |
| `draft` | `active` | Status toggle via edit | `edit_requirement` | `requirement.updated` (kind=`edit`) | `requirement.edit` | Diff-based; only emitted if any field changed; `previous_status='draft'`, `new_status='active'` |
| `active` | `draft` | Status toggle via edit | `edit_requirement` | `requirement.updated` (kind=`edit`) | `requirement.edit` | Same; `previous_status='active'`, `new_status='draft'` |
| `draft` or `active` | `archived` | Retire without replacement | `archive_requirement` | `requirement.archived` | `requirement.archive` | Sets `archived_at=now()`; blocked on `superseded`; idempotent on `archived` (no event on no-op) |
| `draft` or `active` | `superseded` | Replaced by another requirement | `supersede_requirement` | `requirement.updated` (kind=`supersede`) | `requirement.edit` | Sets `superseded_by_requirement_id`; both sides must be same-project; replacement ∈ `draft/active` |
| `active` | `active` | Non-status field edit | `edit_requirement` | `requirement.updated` (kind=`edit`) | `requirement.edit` | Emits `changed_fields` in snapshot; no-op edit returns `out_updated=false` and emits nothing |
| `active` | `active` | Applicability narrowed/widened | `set_requirement_applicability` | `requirement.updated` (kind=`applicability`) | `requirement.edit` | Root-only; diff-counted `added/removed/kept`; `now_project_wide` flag; only emitted if net change |
| n/a (version-level) | n/a | Assessment recorded/updated | `assess_version_requirement` | `requirement.assessed` | `requirement.assess` | Upsert; `subject_kind='version_requirement_assessment'`; `previous_status` captured; action = `created \| updated` |

Terminal states cannot transition further; frozen guards enforce.

### 4.1 Supersession chain semantics

Supersession is directional: A → B (B supersedes A; A's `superseded_by_requirement_id = B.id`). Walking the chain:

- **Backward walk** (find what a requirement supersedes): starting from B, look at other rows in the same project where `superseded_by_requirement_id = B.id`.
- **Forward walk** (find what supersedes a requirement): follow `A.superseded_by_requirement_id`.

Chains may be longer than 2 (A → B → C is allowed, since B enters `superseded` on the second call and the guard on the new call operates on C, which is `draft/active`). The chain read RPC is a Requirement Detail primitive — see §15.

### 4.2 Assessment result vocabulary

`satisfied`, `partial`, `not_satisfied`, `not_applicable` are the only allowed values per `vra_status_check`. Product-layer badge tokens are proposed in §11.

---

## 5. Requirement ownership

### 5.1 Ownership vs. authorship

- **Authorship** — captured by frozen `created_by_profile_id` on `requirements`. Immutable historical fact.
- **Ownership** — the **[additive]** `owner_profile_id` on `requirements`. Mutable via `edit_requirement` (extended in APP 008 backend proposal). Survives originator departure from the workspace. Defaults to `created_by_profile_id` at creation time.

Rationale: requirements are long-lived; the person who first typed the title may leave the org years before the requirement is retired. Product surface must have a stable "owner" concept for inbox routing (§21), notification recipients (§21), and unassessed-critical follow-up (§16).

### 5.2 Assessment vs. authoring distinction

Assessment (`assess_version_requirement`) is a separate act from authoring or editing. The frozen capability model already reflects this: `contributor` may assess but not archive; `reviewer` and `approver` may assess but not create; `observer` may only view. The Requirement Detail's Assessments tab surfaces this — see §11.

### 5.3 Role × operation matrix (from frozen REQUIREMENTS 003)

| Capability | `lead` | `contributor` | `reviewer` | `approver` | `observer` | workspace admin |
|---|---|---|---|---|---|---|
| `requirement.view` | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ (via view-class admin override) |
| `requirement.create` | ✓ | ✓ | — | — | — | — |
| `requirement.edit` | ✓ | ✓ | — | — | — | — |
| `requirement.archive` | ✓ | — | — | — | — | — |
| `requirement.assess` | ✓ | ✓ | ✓ | ✓ | — | — |

Cites: `20260805120000_requirements_003_authz_and_rpcs.sql` §1 (`lign_has_capability` extension).

### 5.4 Orphaned originator policy

If a requirement's `created_by_profile_id` refers to a profile that has left the workspace (`FK ON DELETE SET NULL` per frozen schema), the row remains valid. Product surface renders "Unknown" or "Former member" in author slots. The **[additive]** `owner_profile_id` continues to route notifications; if the owner also leaves, notifications fall back to the project `lead` set (§21). Not a data-integrity concern — no fields ever become invalid.

### 5.5 Supersession chains and ownership

When B supersedes A, B's `owner_profile_id` defaults to the caller of `supersede_requirement` (which is often but not always A's owner). A's ownership is frozen at the moment of supersession — historical.

---

## 6. Requirement sources

### 6.1 Source dimension

A requirement's *source* answers: **who or what is the originating obligation**?

Enumerated source kinds:

| `source_kind` | Definition |
|---|---|
| `client` | The client organization contracting the project |
| `consultant` | Third-party consultant with jurisdiction over a discipline |
| `regulatory` | Statutory code, ordinance, or regulation |
| `internal_team` | An internal team of the design organization |
| `qa` | Quality assurance / quality control |
| `procurement` | Procurement, supply chain, or purchasing |
| `manufacturing` | Manufacturing, fabrication, or production |
| `safety` | Occupational, product, or public safety |
| `contractual` | A contract clause or SOW obligation not otherwise categorized |
| `other` | Escape hatch for organization-specific sources |

### 6.2 Enum vs. tags — decision

**Enum, backed by an [additive] `source_kind` text column with CHECK, plus retention of the frozen `source` free-text column for human labels.**

Rationale:
- Dashboards need to filter and aggregate on a bounded value space — the free-text `source` cannot support saved-view chips or metric buckets without a controlled dimension.
- Tags impose a many-to-many join (extra table) for a dimension that is almost always singular ("this requirement came from the client"). Enum captures the primary source cleanly.
- The frozen free-text `source` and `source_ref` columns remain for the exact human string ("Acme Corp Legal Team") and the reference ID ("NFPA 13 §14.2.3"), respectively.

Decision recorded as G-1 in §24.

### 6.3 `source_ref` semantics (frozen, preserved)

Free-text pointer to the originating artifact:
- Regulation code: `"NFPA 13 §14.2.3"`, `"OSHA 1910.147"`.
- Contract clause: `"SOW §4.1.2"`.
- Ticket ID: `"JIRA-4821"`, `"DOORS-REQ-90124"`.
- Meeting reference: `"Kickoff minutes 2026-03-14 §7"`.

No parsing in v1. Reserved for future AI extension (§20): regulation-code parser that turns `"NFPA 13 §14.2.3"` into a structured citation.

### 6.4 Multi-source requirements

A requirement with more than one origin (e.g. "client requested AND safety-mandated") is uncommon. If v1 UX proves otherwise, an **[additive]** `additional_source_kinds text[]` column can be added later without breaking the primary `source_kind`. Not proposed for v1.

---

## 7. Requirement categories

### 7.1 Category dimension

A requirement's *category* answers: **what kind of obligation is this**?

Enumerated category kinds:

| `category_kind` | Definition |
|---|---|
| `functional` | The system must do X |
| `non_functional` | Performance, reliability, scalability qualities |
| `regulatory` | Compliance with a statute or code |
| `contractual` | Explicit contract deliverable |
| `technical` | Technology-stack or interface constraint |
| `aesthetic` | Visual, spatial, or brand-driven obligations |
| `sustainability` | Energy, emissions, materials, lifecycle |
| `safety` | Occupational or product safety |
| `operational` | Ongoing operations, maintenance, or service |
| `other` | Escape hatch |

### 7.2 Enum vs. tags — decision

**Enum, backed by [additive] `category_kind` text column with CHECK, plus retention of the frozen `category` free-text column for human labels.**

Rationale identical to §6.2. Decision recorded as G-2 in §24.

### 7.3 Categories and disciplines

APP 003 introduced `disciplines` (per Migration 010, per memory `project_lign_schema_v1_lock.md`). Categories are **orthogonal** to disciplines:

- A discipline is a *practice area* (structural, MEP, architectural, civil).
- A category is a *kind of obligation* (functional, safety, aesthetic).
- A "safety" requirement can apply to any discipline; a "structural" discipline can carry any category of requirement.

The Requirement Detail page will offer both filters. No cross-table coupling required.

### 7.4 Category × source interaction

Not enforced. A `regulatory` category may have `regulatory` source (typical) but may also be `client` (client-imposed regulation reference). Free composition.

---

## 8. Requirement priority

### 8.1 Priority ladder

Five tiers, ordinal:

| `priority` | Meaning | Dashboard sort weight |
|---|---|---|
| `critical` | Must be satisfied; blocks release | 1 |
| `high` | Strongly required; escalate if unresolved | 2 |
| `medium` | Standard; default assignment | 3 |
| `low` | Preferred; deferrable | 4 |
| `informational` | Reference only; not gate-eligible | 5 |

Decision recorded as G-3 in §24.

### 8.2 Effect on dashboard sort

Default sort in every requirements dashboard view: `(priority asc, updated_at desc)`. User can override to `updated_at desc` alone. Priority is a first-class column in every card.

### 8.3 Effect on release readiness

Cross-slice with APP 009 (not yet frozen). APP 008 exposes the read; APP 009 defines the gate.

Recommended (deferred to APP 009 for authority):
- **Hard block:** any `critical` requirement applicable to the released version whose latest assessment is `not_satisfied`.
- **Soft warning:** any `critical` requirement applicable to the released version with no assessment on the released version.
- **Advisory:** any `high` requirement in either of the above states.

APP 008 does NOT implement the gate — it exposes the data via the trace API in §15. Decision recorded as G-4 in §24.

### 8.4 Priority is mutable

`priority` is on the mutable set of `edit_requirement`. Changing priority emits `requirement.updated` with `kind='edit'` and `changed_fields=['priority']`.

---

## 9. Requirement scope

Scope answers: **which artifacts does this requirement apply to?**

### 9.1 Scope layers

Five conceptual layers, resolved in this precedence order:

| Layer | Resolved by | Frozen? |
|---|---|---|
| Project-wide | `requirement_design_assets` empty for a root | Frozen |
| Asset-scoped | `requirement_design_assets` rows for a root | Frozen |
| Version-scoped (assessment time) | `version_requirement_assessments` rows per version | Frozen |
| Collection-scoped | Deferred — **[additive]** optional join `requirement_collections(requirement_id, collection_id)` | Not v1 |
| Discipline-scoped | Deferred — **[additive]** optional join `requirement_disciplines(requirement_id, discipline_id)` | Not v1 |

Decision recorded as G-5 in §24.

### 9.2 Scope-resolution algorithm

For a given `asset_version_id`:

```
resolve_applicable(asset_version_id):
  design_asset := asset_version.design_asset
  project     := asset_version.project

  for each requirement r in project where status in ('draft','active'):
    root := coalesce(r.parent_requirement_id, r.id)     # inherit
    if requirement_design_assets has no rows for root:
      applicable                                          # project-wide
    else if requirement_design_assets has (root, design_asset):
      applicable                                          # asset-scoped
    else:
      not applicable
```

This is exactly what frozen `list_applicable_requirements` computes (`root_wide` ∪ `scoped_root_ids`).

### 9.3 What "applies" means at each layer

- **Applies** ⇒ eligible for assessment against a version of an asset in the resolved set.
- **Not applicable** at assessment time ⇒ frozen trigger `vra_enforce_applicability` raises `23514`.
- Sub-requirements always inherit parent applicability — never independently scoped (frozen constraint on `set_requirement_applicability`).

### 9.4 Applicability narrowing preserves historical assessments

Narrowing applicability (removing an asset from the set) does not cascade-delete prior assessments on versions of that asset — frozen behavior. Product surface labels those as "historical" in the Assessments tab and excludes them from active metrics.

### 9.5 Applicability inheritance direction

Inheritance is **parent → child** only. Sub-requirements never carry their own `requirement_design_assets` rows (frozen guard in `set_requirement_applicability`). Decision recorded as G-6 in §24.

---

## 10. Relationships

### 10.1 Requirement ↔ Design Asset

- Table: frozen `public.requirement_design_assets` (many-to-many).
- Cardinality: many requirements per asset; many assets per requirement (empty = project-wide).
- New join: **none required**.
- Owner: APP 008 for the writer path (via existing `set_requirement_applicability`); APP 003 for asset-side reads.

### 10.2 Requirement ↔ Asset Version

- Table: frozen `public.version_requirement_assessments`.
- Cardinality: at most one assessment per (version, requirement); upsert.
- New join: **none required**.
- Owner: APP 008 for the writer path; APP 003/APP 004 for the version-side reads that surface the "N of M requirements assessed" chip on the version card.

### 10.3 Requirement ↔ Review (APP 006)

- Nature: **loose, informational**. Reviews may *discuss* requirements. Discussion is captured in comments.
- Proposal: **[additive]** nullable `comments.target_requirement_id uuid` — same shape as APP 005's 7-way XOR comment target, extending to an 8-way XOR (or, equivalently, adding a new sibling target). *Why: enables filtering comments to "discussions about R-042" in the Requirement Detail Discussions tab.*
- Alternative considered: freeform mention (`@R-042` in comment body). Rejected — hurts filterability and metrics.
- Decision recorded as G-7 in §24.
- **[additive]** capability: none new — reuses `comment.view` / `comment.create`.

### 10.4 Requirement ↔ Approval (APP 007)

- Two frozen anchors exist:
  1. `decisions.requirement_id` (frozen; workspace-coherent FK) — captures "this decision addresses R-042".
  2. Approvers' `decision_reason` free text — captures "waiver of R-042" as prose.
- APP 008 v1 does NOT introduce a new `approval_request_requirements` join. Rationale: approvals already reason about requirements through the frozen `decisions.requirement_id` and via the read of `list_applicable_requirements` on the Approval Detail (per APP 007 §9). Structured waivers are an APP 007 v2 concern.
- Decision recorded as G-8 in §24.

### 10.5 Requirement ↔ Change

- Table: frozen `changes.requirement_id` (nullable; same-project composite FK).
- Cardinality: many changes may cite one requirement; a change cites at most one requirement in v1.
- New join: **none required**.

### 10.6 Requirement ↔ Release (APP 009)

- Nature: read-only from APP 009's perspective. APP 009 consults the trace API (§15) to compute release readiness.
- APP 008 does NOT introduce a hard gate. APP 009 owns the gate policy.
- Reserved read RPC: `get_release_readiness_for_version(asset_version_id)` — **[additive]** (see §15, §27). *Why: convenience for APP 009; wraps `list_applicable_requirements` with priority + assessment aggregation.*
- Decision recorded as G-9 in §24.

### 10.7 Requirement ↔ Requirement (supersession + hierarchy)

- Two self-referential FKs (both frozen): `parent_requirement_id` (hierarchy) and `superseded_by_requirement_id` (chain).
- Hierarchy limited to one level (`enforce_requirement_hierarchy`).
- Supersession chains may be arbitrary length in the direction of "new supersedes old".
- Reserved read RPC: `get_requirement_chain(requirement_id)` — **[additive]** (see §15, §27). *Why: Traceability tab needs to render "was superseded by / supersedes".*

### 10.8 Summary table

| Relationship | Backend surface | Join needed | Cardinality | [additive]? |
|---|---|---|---|---|
| Requirement ↔ Asset | frozen `requirement_design_assets` | reused | N:M (root only) | no |
| Requirement ↔ Version | frozen `version_requirement_assessments` | reused | 1:1 per (v,r) upsert | no |
| Requirement ↔ Review | via comments | new `comments.target_requirement_id` | N:1 comment→req | yes (§27) |
| Requirement ↔ Approval | frozen `decisions.requirement_id` | reused | N:1 decision→req | no |
| Requirement ↔ Change | frozen `changes.requirement_id` | reused | N:1 change→req | no |
| Requirement ↔ Release | via trace API | none | N:1 release→req | no (read RPC additive) |
| Requirement ↔ Requirement | frozen self-FKs | reused | 1:0..1 supersede; 0..1:N parent-child | no |
| Requirement ↔ Collection | deferred | proposed additive join | N:M | future |
| Requirement ↔ Discipline | deferred | proposed additive join | N:M | future |

---

## 11. Requirement Detail page

Full-page route: `/workspace/:ws_id/project/:proj_id/requirement/:requirement_id`.

Also resolvable by code: `/deep/requirement/:code` (see §14).

### 11.1 Layout

```
Header:  ← Back · [Code chip] · Title · [Status badge] · [Priority badge] · [Source chip] · [Category chip] · ⋮ menu
Region A: Description card (rich text; edit-in-place when caller has requirement.edit)
Region B: Metadata rail (owner, created, updated, source_ref, verification_method)
Region C: Sub-requirements list (only shown for root requirements with children)
Tabs:    Overview | Applicability | Assessments | History | Discussions | Traceability
```

### 11.2 Header components

- **Code chip** — `R-012` or `R-012.3` in monospaced typography; click-to-copy via `useCopyLink('requirement:R-012')`.
- **Status badge** — `StateBadge` (APP 005 primitive) with new union members: `draft`, `active`, `superseded`, `archived`. Backward-compatible additive extension.
- **Priority badge** — new primitive `PriorityBadge` (APP 008 introduces).
- **Source chip / Category chip** — new primitive `ScopeChip` variants (APP 008 introduces).
- **⋮ menu** — Edit / Archive / Supersede / Set applicability / Copy link / Copy code / Bookmark.

### 11.3 Tabs

**Overview** — Description, metadata rail, sub-requirements list (if root), and a compact "Applies to" summary (project-wide vs. N assets).

**Applicability** — Root-only editor. Uses **[additive]** primitive `AssetPickerGrid` — a variant of APP 003's asset browser scoped to same project. For sub-requirements, this tab renders the inherited applicability read-only with a "Edit on parent R-012" affordance.

**Assessments** — Per-version grid. Columns: `Version · Assessed on · Assessor · Status · Note · Actions`. Row groups by asset for a multi-asset root. New primitive `AssessmentGrid` (APP 008 introduces). Inline assess action opens a small modal that calls `assess_version_requirement`.

**History** — Chronological `activity_events` feed filtered on `subject_kind='requirement' AND subject_id=<id>` UNION `subject_kind='version_requirement_assessment' AND subject_snapshot->>'requirement_id'=<id>`. Reuses APP 006 timeline shell if extracted; otherwise a bespoke component.

**Discussions** — Reuses APP 005 `CommentsPanel` unchanged. Server-side filter: `target_requirement_id = <id>` (via the **[additive]** column proposed in §10.3). Fallback if the column is not yet shipped: filter comments on the requirement's applicable versions and group under "General discussion".

**Traceability** — The trace graph rendering. See §15.

### 11.4 Right rail (metadata)

Fixed-width metadata card:
- Owner (avatar + name; falls back to author if unset).
- Created by / created at.
- Updated at.
- `source_kind` chip + `source_ref` monospaced.
- `category_kind` chip.
- Superseded-by link (if applicable).
- Supersedes link (backward chain, if applicable).
- Applicability summary (project-wide / N assets).
- Verification method (if `verification_method` set).

### 11.5 Empty states

- No description → "Add a description" affordance (opens edit-in-place if caller has `requirement.edit`).
- No applicability → "Project-wide" chip with tooltip explaining the empty-set convention.
- No assessments on any version → "No assessments yet — assess the current version" affordance (opens the assess modal).
- No sub-requirements on a root → hide the sub-requirements card (do not render an empty shell).

### 11.6 Loading states

- Full-page shell renders immediately with skeleton chips for badges and skeleton bars for tabs.
- Header data comes from `get_requirement(requirement_id)` — **[additive]** read RPC (§27).
- Tab bodies lazy-load on click; Overview loads eagerly.

### 11.7 Error states

- 404: "This requirement does not exist" — offer "Back to Requirements" and "Search by code".
- 403: "You do not have access to this requirement" — offer "Back to project" (never leak existence).
- 5xx: standard retry surface reused from APP 002.

### 11.8 Reusable primitives introduced by APP 008

- `RequirementDetailShell` — the full-page shell wrapping the header + tabs.
- `AssessmentGrid` — per-version assessment table with inline assess action.
- `AssetPickerGrid` — project-scoped asset multi-select for applicability editing.
- `ScopeChip` — small chip variant used for source/category/scope indicators.
- `PriorityBadge` — priority indicator with color tokens.
- `TraceGraphCard` — the traceability visualization (§15).
- `SupersessionChainCard` — inline chain viz for the metadata rail.

### 11.9 Extended primitives (backward-compatible)

- `StateBadge` — new `WorkflowState` union members: `draft` (already reserved), `active`, `superseded` (already reserved for approvals), `archived`.
- `useCopyLink` — new `LinkKind` values: `'requirement'` (uses ID), `'requirement-code'` (uses code).
- `DeepLinkResolver` — new kinds handled: `requirement`, `requirement-code`.

---

## 12. Requirement dashboard

Two levels, mirroring APP 006/APP 007 dashboard patterns:

- **Workspace requirements dashboard** — `/workspace/:ws_id/requirements` — cross-project inbox.
- **Project requirements dashboard** — `/workspace/:ws_id/project/:proj_id/requirements` — project-scoped.

### 12.1 Views

- `all_active` — all `draft`+`active` requirements the caller can view.
- `assigned_to_me` — I am the `owner_profile_id`.
- `recently_updated` — sorted by `updated_at desc`.
- `by_status` — grouped by status.
- `by_priority` — grouped by priority (critical first).
- `by_source` — grouped by `source_kind`.
- `needs_assessment` — applicable to at least one un-assessed version of the latest version per asset.
- `overdue_critical` — `priority=critical` + `due_at < now()` + no `satisfied` assessment on latest version.
- `bookmarks` — reuse `user_bookmarks` (APP 006) with `entity_kind='requirement'`.
- `saved:<id>` — reuse `user_saved_views` (APP 006) with `scope='requirements'`.
- `archived` — status = `archived`.
- `superseded` — status = `superseded`.

### 12.2 Card layout

Each requirement card:

```
[Code chip] Title                            [Status] [Priority]
Category · Source · Applicability summary
Owner avatar · Updated <relative>            Assessment coverage: 6 of 8 versions
```

Compact mode (dense list): 32px row height, chips only.

### 12.3 Columns (table view)

`Code · Title · Priority · Status · Source · Category · Applicability · Owner · Coverage · Last updated`.

Column set stable within slice; sorting server-side.

### 12.4 Filter bar

Multi-select chips for `status`, `priority`, `source_kind`, `category_kind`, `owner`, `scope` (project-wide vs. asset-scoped). Free-text search in `code`, `title`, `description` (§13). Cursor pagination via `(updated_at, id)` opaque cursor.

### 12.5 Keyboard shortcuts (additive to APP 005/006/007)

- `N` — new requirement (opens composer at `?compose=1`).
- `E` — edit selected (if selection in table view).
- `A` — assess selected (opens assess modal if a version is in context).
- `/` — focus search input.

No conflict with APP 005 (`C`/`P`/`Esc`), APP 006 (`R`/`E`/`Shift+Enter`), or APP 007 (`A`/`X`/`Shift+A`) — `E` is composed additively (context-scoped to Requirements dashboard).

Decision recorded as G-10 in §24.

### 12.6 Inbox counts

NavRail badge: **[additive]** `get_requirement_inbox_count(ws_id)` returning `{assigned_to_me, overdue_critical, needs_assessment}`. Displayed as compact tri-digit chip (99+ cap).

### 12.7 Bulk actions (v1 conservative)

- **Bookmark / unbookmark**
- **Archive** (permission-gated; confirm dialog)
- (No bulk assess — assessments must be per-version for audit clarity.)

### 12.8 Metrics strip

Above the table (collapsible, off by default):
- Total active count
- Unassessed critical (on latest version) count
- Overdue count (`due_at < now()` on non-terminal)
- Coverage % (assessed vs. applicable, on latest version)

Delivered by **[additive]** RPC `get_project_requirement_metrics(project_id)` / `get_workspace_requirement_metrics(ws_id)` (§16, §27).

---

## 13. Search & filtering

### 13.1 Text search

Server-side substring search on `requirements.code`, `requirements.title`, `requirements.description`. Case-insensitive. Trigram index recommended for `title` and `description` (**[additive]** GIN index; §27).

### 13.2 Structured filters

| Filter | URL param | Backend hook |
|---|---|---|
| Status | `?status=draft,active,superseded,archived` | direct column |
| Priority | `?priority=critical,high,medium,low,informational` | **[additive]** column |
| Source | `?source=client,regulatory,...` | **[additive]** `source_kind` |
| Category | `?category=functional,safety,...` | **[additive]** `category_kind` |
| Scope | `?scope=project_wide,asset_scoped` | derived from RDA count |
| Assignee | `?assignee=<profile_id>` | **[additive]** `owner_profile_id` |
| Has-assessment | `?has_assessment=true \| false` | derived from VRA |
| Code | `?code=R-042` | direct column |
| Project | (implicit for project dashboard; explicit for workspace) | direct column |

### 13.3 Saved views

Reuse APP 006 `user_saved_views` unchanged. Scope: `'requirements'`. Payload: JSONB of the filter/view/sort state. No new table.

### 13.4 Bookmarks

Reuse APP 006 `user_bookmarks` unchanged. `entity_kind='requirement'`. No new table.

### 13.5 Cursor pagination

Opaque `(updated_at, id)` tuple; direction `desc`; server never leaks the tuple. Mirrors APP 006 `list_reviews_dashboard` pattern. Delivered by **[additive]** `list_requirements_dashboard(scope, view, filters, cursor, limit)` (§27).

---

## 14. Linking

### 14.1 Deep links

Extends APP 002's `DeepLinkResolver` additively:

```
/deep/requirement/:id           → Requirement Detail (UUID form)
/deep/requirement/:code         → Requirement Detail (code form, e.g. R-042 or R-042.3)
```

The code-form resolver disambiguates within a project via a workspace-scoped lookup — since codes are per-project stable, the resolver must consult the current workspace context or accept a `?project=<id>` disambiguator.

### 14.2 Copy-link primitive

`useCopyLink` (APP 005, extended by APP 006 and APP 007) receives two more `LinkKind` values:
- `'requirement'` — emits `/deep/requirement/<id>`.
- `'requirement-code'` — emits `/deep/requirement/<code>?project=<id>`.

Purely additive.

### 14.3 Cross-slice linking

Any surface may cite a requirement by:
- Rendering the code as a `<RequirementRef code="R-042" />` inline component (new primitive).
- Emitting a `Copy code` action from any menu.
- Comment mentions in the Discussions tab (via `target_requirement_id` — §10.3).
- Approval decision reason free-text mention (unchanged from APP 007).
- Change composer citation via `changes.requirement_id` (frozen).
- Decision composer citation via `decisions.requirement_id` (frozen).

### 14.4 Backward links

The Traceability tab renders inbound references. See §15.

---

## 15. Traceability

### 15.1 The trace graph

For any requirement `R`:

```
                     ┌────────────────────────┐
                     │        R (this)        │
                     └─────────────┬──────────┘
                                   │
                ┌──────────────────┼──────────────────┬────────────────┐
                │                  │                  │                │
                ▼                  ▼                  ▼                ▼
    Applicable design_assets   Sub-requirements   Superseded-by     Supersedes
    (via requirement_design    (via parent_       (via              (backward
     _assets or project-wide)   requirement_id)    superseded_by_    walk on
                                                   requirement_id)   supersession)
                │
                ▼
    Asset versions
                │
                ▼
    Assessments (per-version compliance)
                │
                ├─── changes (via changes.requirement_id)
                ├─── decisions (via decisions.requirement_id)
                ├─── comments (via [additive] target_requirement_id)
                └─── approval decisions citing R via decisions.requirement_id
                         │
                         ▼
                 Approval requests
                         │
                         ▼
                 Releases (APP 009; via trace read)
                         │
                         ▼
                 Reviews (via comments; loose)
```

### 15.2 Traceability tab in Requirement Detail

Renders the graph in a `TraceGraphCard` primitive. Sections:

- **Applicable to** — asset chips (or "Project-wide" chip). Click chip → jump to asset.
- **Sub-requirements** — sub-chips with own status/priority.
- **Assessments** — compact matrix: rows = versions, cols = status; hover for note; click → open Assessments tab.
- **Related changes** — list of changes citing this requirement; click → change surface (APP 003).
- **Related decisions** — list of decisions citing this requirement; click → decision surface.
- **Related discussions** — count of comments with `target_requirement_id = <id>`; click → Discussions tab.
- **Approval history** — list of `approval_requests` whose `decisions` cite this requirement.
- **Supersession chain** — inline `SupersessionChainCard`: prior ← this → next.

### 15.3 Trace API surface

**[additive]** read RPC: `get_requirement_trace(requirement_id)` returning a bundled structure — assets, versions, assessments, changes, decisions, discussion count, approval requests, chain. Cite: enumerated in §27.

**[additive]** read RPC: `get_requirement_chain(requirement_id)` returning ordered array of the supersession chain (both directions).

**[additive]** read RPC: `get_release_readiness_for_version(asset_version_id)` returning `{applicable_count, satisfied_count, partial_count, not_satisfied_count, unassessed_count, critical_unsatisfied_count, critical_unassessed_count}`. Cite: enumerated in §27. Consumed by APP 009.

### 15.4 Direction of traversal

All trace edges are stored on the "downstream" side per frozen convention:
- `changes.requirement_id` — change knows its requirement.
- `decisions.requirement_id` — decision knows its requirement.
- `requirement_design_assets` — bidirectional; queried from either side.
- `version_requirement_assessments` — queried from either side.

No new columns needed on `requirements` to support the trace.

### 15.5 Trace performance

Trace RPC is a bundled read — one round-trip per Requirement Detail Traceability tab open. Backing indexes are already present (frozen `changes_requirement_idx`, `decisions_requirement_idx`, `rda_design_asset_idx`, `vra_requirement_idx`, `requirements_superseded_by_idx`). No **[additive]** indexes required for v1 loads.

---

## 16. Metrics

### 16.1 Per-requirement metrics

Delivered by **[additive]** `get_requirement(requirement_id)`:

- Latest assessment status per applicable version (matrix).
- Assessment coverage %: `assessed_versions / applicable_versions`.
- Latest assessment result (aggregate of latest version per asset).
- Days since last assessment on the latest current version.
- Days until `due_at` (if set) or "no due date".

### 16.2 Per-project metrics

Delivered by **[additive]** `get_project_requirement_metrics(project_id)`:

- Total requirement count.
- Counts by status (`draft`, `active`, `superseded`, `archived`).
- Counts by priority.
- Unassessed-on-latest-version count.
- Critical-unsatisfied count (would-block-release).
- Overdue count.
- Coverage rate (satisfied ÷ applicable, on latest version).
- Trailing 30d creation rate.
- Trailing 30d assessment activity rate.

### 16.3 Per-workspace metrics

Delivered by **[additive]** `get_workspace_requirement_metrics(ws_id)`:

- Rollup of per-project metrics, aggregated across projects the caller can view.
- Top-5 projects by critical-unsatisfied.
- Top-5 owners by open-requirement load.

### 16.4 Compliance dashboard concept

A **project-scoped compliance page** at `/workspace/:ws_id/project/:proj_id/requirements/compliance` — a specialized view of the requirements dashboard that focuses on:

- Coverage matrix (rows = requirements, cols = asset versions, cells = assessment status).
- Priority breakdown chart.
- Source breakdown chart.
- Release-readiness section (embeds `get_release_readiness_for_version` for the current version of each asset).

Compliance page is a **variant view** of the requirements dashboard, not a new route family — reachable via `?view=compliance` in v1. May graduate to its own route in v2. Decision recorded as G-11 in §24.

### 16.5 Derivation strategy

Metrics are computed by RPCs at query time from `activity_events` + `requirements` + `version_requirement_assessments`. No cached-metric columns in v1 — matches APP 006/APP 007 pattern.

---

## 17. Query architecture

### 17.1 Query key namespace tree

Append-only additions to `qk`:

```ts
qk.requirementsList(scope, view, filters)              // dashboard
qk.requirementsWorkspaceDashboard(wsId, view)
qk.requirementsProjectDashboard(projId, view)
qk.requirement(id)                                     // Detail read
qk.requirementByCode(projId, code)                     // Deep-link resolver
qk.requirementChain(id)                                // Supersession chain
qk.requirementTrace(id)                                // Bundled trace
qk.requirementAssessments(id)                          // Assessments tab
qk.requirementHistory(id)                              // History tab
qk.requirementDiscussions(id)                          // Comments filtered
qk.requirementApplicability(id)                        // Applicability editor
qk.requirementMetrics(scope)                           // Metrics strip
qk.requirementInboxCount(wsId)                         // NavRail badge
qk.applicableRequirementsForAsset(assetId, versionId?)
qk.assessmentsForVersion(versionId)                    // reuses frozen get_version_assessments
qk.releaseReadinessForVersion(versionId)               // APP 009 read hook
```

Reused (unchanged) from prior slices:
- `qk.savedViews(wsId, 'requirements')` — APP 006.
- `qk.bookmarks(wsId, 'requirement')` — APP 006.
- `qk.projectParticipants(id)` — APP 002.
- `qk.commentsForVersion(id)` — APP 005 (Discussions tab).
- `qk.assetVersion(id)`, `qk.designAsset(id)` — APP 003.

### 17.2 RPC → query key mapping

| RPC | Query key | Kind |
|---|---|---|
| `list_project_requirements` (frozen) | `qk.requirementsProjectDashboard` | Read |
| `list_applicable_requirements` (frozen) | `qk.applicableRequirementsForAsset` | Read |
| `get_version_assessments` (frozen) | `qk.assessmentsForVersion` | Read |
| `get_requirement` **[additive]** | `qk.requirement` | Read |
| `get_requirement_by_code` **[additive]** | `qk.requirementByCode` | Read |
| `get_requirement_chain` **[additive]** | `qk.requirementChain` | Read |
| `get_requirement_trace` **[additive]** | `qk.requirementTrace` | Read |
| `list_requirements_dashboard` **[additive]** | `qk.requirementsList` | Read |
| `get_requirement_inbox_count` **[additive]** | `qk.requirementInboxCount` | Read |
| `get_project_requirement_metrics` **[additive]** | `qk.requirementMetrics(project)` | Read |
| `get_workspace_requirement_metrics` **[additive]** | `qk.requirementMetrics(workspace)` | Read |
| `get_release_readiness_for_version` **[additive]** | `qk.releaseReadinessForVersion` | Read |
| `create_requirement` (frozen) | invalidates below | Write |
| `edit_requirement` (frozen) | invalidates below | Write |
| `archive_requirement` (frozen) | invalidates below | Write |
| `supersede_requirement` (frozen) | invalidates below | Write |
| `set_requirement_applicability` (frozen) | invalidates below | Write |
| `assess_version_requirement` (frozen) | invalidates below | Write |

### 17.3 Invalidation matrix

| Mutation | Invalidates |
|---|---|
| `create_requirement` | `requirementsList(*)`, `requirementInboxCount`, `requirementMetrics(project)`, `applicableRequirementsForAsset(*)` |
| `edit_requirement` | `requirement(id)`, `requirementsList(*)`, `requirementHistory(id)`, `requirementMetrics(project)` |
| `archive_requirement` | `requirement(id)`, `requirementsList(*)`, `requirementMetrics(project)`, `applicableRequirementsForAsset(*)` |
| `supersede_requirement` | `requirement(old_id)`, `requirement(new_id)`, `requirementChain(*)`, `requirementsList(*)`, `applicableRequirementsForAsset(*)`, `requirementMetrics(project)` |
| `set_requirement_applicability` | `requirement(id)`, `requirementApplicability(id)`, `applicableRequirementsForAsset(affected assets)`, `requirementMetrics(project)`, `requirementTrace(id)` |
| `assess_version_requirement` | `requirement(id)`, `requirementAssessments(id)`, `assessmentsForVersion(vid)`, `applicableRequirementsForAsset(a, vid)`, `releaseReadinessForVersion(vid)`, `requirementMetrics(project)`, `requirementTrace(id)`, `requirementHistory(id)` |

Cross-slice invalidations:
- APP 005 comment mutation with `target_requirement_id != null` → additionally invalidate `requirementDiscussions(requirement_id)` and `requirementTrace(requirement_id)`.
- APP 007 `respond_to_approval` that touches a decision with `requirement_id != null` → additionally invalidate `requirementTrace(requirement_id)`.
- APP 004 version publish → invalidate `applicableRequirementsForAsset(asset, new_version)` and `releaseReadinessForVersion(new_version)` for all requirements applicable to the asset.

### 17.4 Cursor pagination discipline

All dashboard reads use opaque `(updated_at desc, id desc)` cursors — same pattern as APP 006/APP 007. Server never accepts an offset. Client passes the last-seen cursor back on load-more. Empty cursor = start of list.

### 17.5 Optimistic updates

**None in v1.** Every mutation is round-trip. Assessment casting is deliberately non-optimistic because assessment status is authoritative for release readiness — an incorrect optimistic value would corrupt derived metrics for other clients.

---

## 18. URL grammar

### 18.1 Owned by APP 008

| Param | Values | Meaning |
|---|---|---|
| `?view=<all_active \| assigned_to_me \| recently_updated \| by_status \| by_priority \| by_source \| needs_assessment \| overdue_critical \| bookmarks \| saved:<id> \| archived \| superseded \| compliance>` | string | Dashboard view selector |
| `?status=<comma-list>` | subset of `draft,active,superseded,archived` | Status filter |
| `?priority=<comma-list>` | subset of `critical,high,medium,low,informational` | Priority filter |
| `?source=<comma-list>` | subset of `RequirementSource` enum | Source filter |
| `?category=<comma-list>` | subset of `RequirementCategory` enum | Category filter |
| `?scope=<project_wide \| asset_scoped>` | keyword | Scope filter |
| `?assignee=<profile_id>` | uuid | Owner filter |
| `?code=<R-nnn>` | string | Free-text search shortcut |
| `?cursor=<opaque>` | string | Pagination cursor |
| `?tab=<overview \| applicability \| assessments \| history \| discussions \| traceability>` | keyword | Detail tab selector |
| `?compose=1` | flag | Open composer modal |
| `?assess=<version_id>` | uuid | Open assess modal with pre-filled version |
| `?project=<project_id>` | uuid | Code-form deep-link disambiguator |
| `?requirement=<id>` | uuid | Workspace ↔ Requirement context flag (set when navigating from a requirement into the Design Workspace) |

### 18.2 Non-collision statement

Confirmed non-colliding with:
- APP 003 `?discipline`, `?from`.
- APP 005 `?comment`, `?annotation`, `?comments`, `?tab=comments`.
- APP 006 `?review`.
- APP 007 `?approval`, `?participant`.

Notes:
- `?tab` values are per-detail-page scoped — the Requirement Detail's tab set does not intersect APP 007's tab set (`comments|decisions|files|activity`) or APP 006's tab set.
- `?assignee` is APP 008-specific; APP 006/007 use `?approver`, `?requester`, `?participant` — no collision.
- `?scope` is APP 008-specific.
- `?status` and `?priority` values are enum-namespaced (frozen `WorkflowState` value pools disjoint across slices).

Decision recorded as G-12 in §24.

### 18.3 Deep-link routes

```
/deep/requirement/:id                        → Requirement Detail (UUID)
/deep/requirement/:code?project=<id>         → Requirement Detail (code form)
```

---

## 19. Navigation ownership

### 19.1 NavRail entries

New **workspace-level** NavItem: `Requirements` — routes to `/workspace/:ws_id/requirements`. Badge: `get_requirement_inbox_count(ws_id).assigned_to_me` (99+ cap).

New **project-level** NavItem: `Requirements` — routes to `/workspace/:ws_id/project/:proj_id/requirements`. Badge: count of `overdue_critical` from `get_project_requirement_metrics(project_id)` (99+ cap).

### 19.2 Position in nav order

Recommended nav order (additive):
- Workspace: Projects · Reviews · Approvals · **Requirements** · Bookmarks · Settings.
- Project: Overview · Design · Reviews · Approvals · **Requirements** · Releases · Activity.

Decision recorded as G-13 in §24.

### 19.3 Route table

```
/workspace/:ws_id/requirements                                                       workspace dashboard
/workspace/:ws_id/project/:proj_id/requirements                                      project dashboard
/workspace/:ws_id/project/:proj_id/requirements?view=compliance                      compliance view (variant)
/workspace/:ws_id/project/:proj_id/requirement/:requirement_id                       Requirement Detail
/deep/requirement/:id                                                                 deep-link resolver (UUID)
/deep/requirement/:code                                                               deep-link resolver (code)
```

### 19.4 Design Workspace tab

Add a **Requirements** tab to the Design Workspace RightPanel tab strip (APP 003's shell). Reads `list_applicable_requirements(design_asset_id, current_version_id)` and shows applicable requirements grouped by assessment status. Click → jump to Requirement Detail (opens as full page, preserves back-nav to workspace).

**[additive]** — extends APP 003's RightPanel tab strip. Does not modify APP 003 code beyond a new tab registration.

### 19.5 Design Workspace ↔ Requirement context banner

When the caller opens a version from a Requirement Detail via `?requirement=<id>`, the Design Workspace renders a subtle top banner: *"In requirement context — R-042 · Assess this version"*, with a "Back to requirement" link. Mirrors APP 006 review context banner and APP 007 approval context banner. Additive to APP 003.

---

## 20. AI extension seams

APP 008 does NOT implement AI. Reserved slots — deliberate API-surface seams for future AI features. All rendered as `<AISlot kind="..." />` components (pattern established by APP 006/APP 007). Default: renders nothing. AI slice fills.

| Seam kind | Where | Purpose |
|---|---|---|
| `requirement-classification` | Composer (paste from PDF/email) | Auto-classify pasted text into `source_kind`, `category_kind`, `priority` |
| `assessment-questions` | Assessments tab, per version | Auto-generate assessor prompts from requirement description + version diff |
| `applicability-suggestion` | Applicability editor | Suggest which assets this requirement most likely applies to based on similarity of description to asset descriptions |
| `regulation-parse` | Composer, `source_ref` field | Parse `"NFPA 13 §14.2.3"` into structured citation with hyperlink |
| `similar-requirements` | Composer + Detail header | Show similar requirements already in the project (dedup nudge) |
| `waiver-language` | Approver `decision_reason` — cross-slice (APP 007 already reserves this) | (No APP 008 change; APP 007 seam continues to serve) |
| `assessment-consistency` | Compliance page | Flag inconsistent assessments across versions (v3=satisfied, v4=not_satisfied, v5=satisfied — likely needs re-review) |
| `requirement-summary` | Detail header | One-line auto-summary of long descriptions |

### 20.1 Reserved capability keys (name-locked; no wiring in APP 008)

- `requirement.ai_suggest` — reserved for AI-assisted composer.
- `requirement.ai_classify` — reserved for AI-assisted classification.

### 20.2 Reserved event names (name-locked; no emitter in APP 008)

- `requirement.ai_suggested` — reserved for the AI slice.
- `requirement.ai_classified` — reserved for the AI slice.
- `requirement.imported` — reserved for future bulk import from external systems (§23).

Decision recorded as G-14 in §24.

---

## 21. Notification contracts

APP 008 emits nothing client-side. Backend RPCs already emit the frozen `requirement.*` events (per REQUIREMENTS 004). APP 010 (Notifications, not yet frozen) subscribes to these events and applies the following recipient rules.

### 21.1 Recipient rules (APP 010 will codify)

| Event | Recipients |
|---|---|
| `requirement.created` (root or sub) | Project members with `requirement.view`; muted for the actor. |
| `requirement.updated` (kind=`edit`, incl. status draft↔active) | Requirement `owner_profile_id` + subscribers of the requirement (see §21.3). |
| `requirement.updated` (kind=`supersede`) | Owner + assessors of the superseded requirement + project leads. |
| `requirement.updated` (kind=`applicability`) | Owner + subscribers + owners of newly-added or newly-removed asset roots (v2). |
| `requirement.archived` | Owner + assessors + project leads. |
| `requirement.assessed` (status=`not_satisfied` or `partial`) | Requirement owner + project leads. |
| `requirement.assessed` (status=`satisfied` or `not_applicable`) | Requirement owner only (no fan-out; low-signal). |
| **[additive]** `requirement.due_soon` (reserved) | Owner + project leads. |
| **[additive]** `requirement.overdue` (reserved) | Owner + project leads. |

### 21.2 Recipient computation

APP 010 owns the resolver. APP 008 provides the read hooks:
- Requirement owner: from `owner_profile_id` (falls back to `created_by_profile_id`).
- Project members: from `project_members` + role-capability map.
- Subscribers: from an **[additive]** `requirement_subscriptions(requirement_id, profile_id)` join if introduced (deferred; §23).

### 21.3 Subscription model (deferred)

An **[additive]** `requirement_subscriptions` table would let non-owners follow a requirement. Not v1. If demand surfaces, APP 010 owns the table; APP 008 provides the deep-link and UI toggle.

Decision recorded as G-15 in §24.

### 21.4 Muting

Actor-of-event muting is a standard APP 010 concern; APP 008 does not implement it.

---

## 22. Realtime contracts

### 22.1 Explicit statement

**The 3 requirements tables — `requirements`, `requirement_design_assets`, `version_requirement_assessments` — are OUT of the `supabase_realtime` publication.** This is the frozen boundary set by REALTIME 001 (per memory `project_lign_requirements_layer_lock.md`).

Real-time updates to Requirements dashboards, Detail pages, and NavRail badges happen via **query-invalidation only** — driven by APP 007's or APP 006's realtime channels when those emit events that cross-invalidate Requirements queries (§17.3 cross-slice invalidations).

### 22.2 Adding requirements tables to the publication is a REALTIME re-freeze event

Not an APP 008 decision. Any proposal to subscribe live to `requirement.*` events must go through the REALTIME layer's re-freeze process.

### 22.3 Reserved realtime channel names (name-locked; no subscription in APP 008)

Reserved for a future REALTIME re-freeze:

| Channel | Scope | Would invalidate |
|---|---|---|
| `requirement:{requirement_id}` | Single requirement updates | `requirement(id)`, `requirementAssessments(id)`, `requirementTrace(id)`, `requirementHistory(id)` |
| `project:{project_id}:requirements` | Project dashboard | `requirementsProjectDashboard(*)`, `requirementMetrics(project)` |
| `workspace:{ws_id}:requirements` | Workspace dashboard | `requirementsWorkspaceDashboard(*)`, `requirementInboxCount(ws)` |
| `version:{version_id}:assessments` | Per-version assessment stream | `assessmentsForVersion(vid)`, `releaseReadinessForVersion(vid)` |
| `user:{profile_id}:requirement-inbox` | Per-user inbox additions | `requirementsList(*, 'assigned_to_me')`, `requirementInboxCount` |

APP 008 exports these constants from `src/features/requirements/realtime.ts` as name-only placeholders. Subscription code is not shipped until REALTIME re-freeze.

### 22.4 Fallback in v1

Dashboards poll on tab-focus (5-minute stale time via TanStack Query) and refetch on cross-slice mutations. Acceptable for MVP; upgrade path is clean.

Decision recorded as G-16 in §24.

---

## 23. Extension points

Documented seams for future waves. All are name-locked or shape-locked here; nothing is implemented in APP 008.

### 23.1 Custom source kinds per workspace

**[additive]** table `requirement_custom_sources(workspace_id, key, label)`. Would let orgs extend the enum without a schema change. Deferred; enum + `other` sufficient for v1.

### 23.2 Custom categories per project

Symmetric to §23.1. Deferred.

### 23.3 Requirement templates

**[additive]** table `requirement_templates(id, workspace_id, name, payload_jsonb)`. Composer would offer "Create from template". Reserved event: `requirement.imported`.

### 23.4 Requirement libraries (shared across projects)

**[additive]** table `requirement_library_items(id, workspace_id, template_id, ...)`. Library items are copied into a project on adoption; the copy has its own `code` and lifecycle. Deferred to v2.

### 23.5 Regulatory-code libraries

Cross-cut with §23.4. A workspace-level library of common regulations (NFPA, IBC, ISO) shippable as a seed pack. Deferred.

### 23.6 Version-diff-driven auto-assessment

Reserved capability `requirement.auto_assess` for AI-assisted assessments based on version diff. Reserved event `requirement.auto_assessed`. Not in APP 008.

### 23.7 External-system sync (Jira, DOORS, ReqIF import)

Reserved event `requirement.imported`. Reserved capability `requirement.import`. Reserved column on requirements: `external_id text` and `external_system text`. Deferred to v2.

### 23.8 Evidence attachment on assessments

Reserved **[additive]** column on assessments: `evidence_file_ids uuid[]` — links to uploaded evidence via APP 004 storage. Reserved capability: reuse `file.attach`. Reserved event payload extension on `requirement.assessed`: `has_evidence bool`.

### 23.9 Structured waivers

Reserved **[additive]** table `requirement_waivers(approval_response_id, requirement_id, ...)` — links approval decisions to specific requirements they waive. Owned by APP 007 v2 or a dedicated waiver slice; APP 008 provides the read.

### 23.10 Requirement subscriptions

Reserved **[additive]** table `requirement_subscriptions(requirement_id, profile_id)`. See §21.3.

### 23.11 Verification method taxonomy

Reserved values on **[additive]** `verification_method` column: `inspection | test | analysis | demonstration`. Standard systems-engineering taxonomy. Not surfaced in v1 UX.

---

## 24. Open architectural decisions

Decisions taken during this freeze pass and questions deliberately deferred. Every decision may be overridden before implementation.

| # | Decision | Recommendation | Rationale |
|---|---|---|---|
| **G-1** | Source as enum vs. tags | **Enum via [additive] `source_kind`, retain free-text `source` for label** | Bounded value space needed for filters/metrics; single-source is the common case. |
| **G-2** | Category as enum vs. tags | **Enum via [additive] `category_kind`, retain free-text `category` for label** | Same rationale as G-1. |
| **G-3** | Priority tier count | **5 tiers: `critical`, `high`, `medium`, `low`, `informational`** | 5 tiers matches industry practice (Jira, DOORS); 3 too coarse for release-readiness gate; 7+ is decision paralysis. |
| **G-4** | Release readiness gate — loose vs. hard | **Loose in APP 008; APP 009 owns the gate policy** | APP 008 provides read; APP 009 defines "blocking" per release-type. |
| **G-5** | Collection-scoped and discipline-scoped applicability | **Deferred to v2 as [additive] joins** | Real UX demand not yet demonstrated; asset-scoped + project-wide covers v1. |
| **G-6** | Applicability inheritance direction | **Parent → child only** | Matches frozen `set_requirement_applicability` root-only guard. |
| **G-7** | Review-requirements linkage | **[additive] `comments.target_requirement_id`; no separate join** | Reuses APP 005's XOR-target grammar; enables filterable discussions. |
| **G-8** | Approval-requirements linkage | **Reuse frozen `decisions.requirement_id`; no new join in v1** | Structured waivers deferred to APP 007 v2. |
| **G-9** | Release-readiness gate policy | **Deferred to APP 009** | APP 008 exposes reads (`get_release_readiness_for_version`); APP 009 decides. |
| **G-10** | Keyboard shortcut for "new requirement" | **`N`** | Composes additively with APP 005/006/007 without collision. |
| **G-11** | Compliance page as its own route | **Variant `?view=compliance` in v1; potential route graduation in v2** | Route family stability; can promote later without breaking links. |
| **G-12** | URL grammar collision with APP 006/007 `?status` | **No collision — `?status` values are enum-namespaced per slice** | APP 006 `?status` values are review states; APP 007 approval states; APP 008 requirement states. Value pools disjoint. Filter parser routes by page context. |
| **G-13** | NavRail placement | **Between Approvals and Bookmarks at workspace; between Approvals and Releases at project** | Preserves the "gate-adjacent" grouping (reviews → approvals → requirements → releases). |
| **G-14** | AI capability + event names reserved now | **Yes: `requirement.ai_suggest`, `requirement.ai_classify`, `requirement.ai_suggested`, `requirement.ai_classified`, `requirement.imported`** | Locks the vocabulary before the AI slice starts; prevents rename churn. |
| **G-15** | Subscription model | **Deferred to APP 010** | Owner-based notifications sufficient for v1; subscriptions add DB surface. |
| **G-16** | Realtime for requirements tables | **Remains OUT of publication; query-invalidation only** | Preserves REALTIME 001 boundary; requirements are relatively low-churn. |
| **G-17** | Orphaned originator policy | **Preserve row; render as "Former member"; owner falls back to project leads** | Matches frozen `FK ON DELETE SET NULL` behavior. |
| **G-18** | Discipline coupling to categories | **Orthogonal; no coupling** | Discipline is practice-area; category is obligation-kind. Independent axes. |
| **G-19** | Assessment result on version rollover | **Per-version; positive on `v3` does NOT roll to `v4`** | Frozen behavior; reflects real-world verification discipline. |
| **G-20** | Multi-source requirements | **Deferred; single `source_kind` in v1** | Demand not established; `additional_source_kinds text[]` is a clean upgrade path. |
| **G-21** | Sub-requirement independent applicability | **No — inheritance only** | Frozen guard on `set_requirement_applicability`. |
| **G-22** | Requirement DELETE | **Never allowed — archive or supersede** | Frozen: no DELETE policy on `requirements`; also no DELETE on `version_requirement_assessments`. |
| **G-23** | Assessment DELETE | **Never allowed — new assessment is an UPDATE** | Frozen upsert-only pattern. |
| **G-24** | Ownership vs. authorship split | **Introduce [additive] `owner_profile_id` distinct from `created_by_profile_id`** | Long-lived requirements outlive originators. |
| **G-25** | Requirement code display format | **`R-NNN` for roots, `R-NNN.n` for subs (frozen)** | No product-layer override. |
| **G-26** | Bulk assess in dashboard | **Not offered** | Audit clarity; assessments are per-version acts. |
| **G-27** | Composer surface | **Full modal (not slide-over) with rich text description** | Requirements are long-form; enough real estate matters. |
| **G-28** | Deep-link `?project` disambiguator for code form | **Required when workspace context alone is ambiguous** | Codes are per-project stable, not workspace-unique. |
| **G-29** | Compliance page — matrix pivot direction | **Rows = requirements, cols = asset versions** | Reads left-to-right as "how each requirement fares across versions"; matches typical audit table. |
| **G-30** | AI slots default rendering | **Renders nothing when no AI slice loaded** | Matches APP 006/APP 007 pattern; keeps freeze usable without AI. |
| **G-31** | Requirement subscription self-service | **Deferred (§23.10)** | Not v1 scope. |
| **G-32** | External-system sync scope | **Deferred (§23.7); vocabulary reserved** | Import surface is large; separate slice. |
| **G-33** | Requirement `owner_profile_id` cross-workspace | **Not allowed — owner must be a workspace_member of the requirement's workspace** | Matches project role-membership scoping. |
| **G-34** | Priority as required on create | **Optional on create with default `medium`; may be set later via edit** | Reduces composer friction; still forces a default value. |
| **G-35** | Requirement editing while a review is open on an applicable version | **No block** | Requirements are structural; reviews are discussions. Editing a requirement does not affect an in-flight review. |
| **G-36** | Requirement editing while an approval is open on an applicable version | **No block; render a soft warning** | Approvers may want to know the referent shifted; RPC does not enforce. |
| **G-37** | Assessment update while an approval on the same version is terminal | **Allowed** | Assessments are historical facts; approval outcomes are immutable regardless. |
| **G-38** | Superseded requirement continues to receive assessments? | **No — frozen guard: `assess_version_requirement` blocks on `archived`, allows on `superseded`** | Wait — this is worth re-reading. The frozen RPC actually blocks only on `archived`. `superseded` allows new assessments (rare but legal). Product surface renders a warning banner. |
| **G-39** | Assessment note length limit | **1000 chars soft, 4000 chars hard** | Notes are for compliance evidence prose; not for essays. |
| **G-40** | Compliance matrix cell click behavior | **Opens Assessments tab focused on that version** | Matches trace navigation intuition. |

---

## 25. Freeze checklist / non-goals

**In scope for APP 008 v1:**
- Requirement dashboards (workspace + project).
- Requirement Detail page (6 tabs).
- Requirement composer + edit modal.
- Applicability editor.
- Assessment modal.
- Traceability tab + trace API surface.
- Metrics strip + compliance page (as `?view` variant).
- Deep links + copy link.
- NavRail entries + badges.
- Cross-slice invalidation hooks.
- Reusable primitives (§11.8).

**Explicitly out of scope for APP 008 v1:**
- AI features of any kind (seams only — §20).
- Realtime subscriptions on requirements tables (name-locked channels only — §22).
- Notification delivery (APP 010's concern — §21).
- Requirement libraries / templates / imports (§23).
- Requirement subscriptions (§21.3).
- Custom source/category enums per workspace (§23.1–2).
- Evidence attachment on assessments (§23.8).
- Structured waivers (§23.9).
- Verification method surfacing in UX (column reserved, not surfaced — §23.11).
- Bulk assessment (G-26).
- Hard release-readiness gate (§8.3, G-4 — APP 009's concern).
- Approval-requirements structured join (G-8).
- Discipline / collection scope layers (G-5).
- Cross-project supersession (G-33 — always same-project per frozen guard).
- Weighted priorities or numeric priority scores (5 ordinal tiers only, G-3).
- Compliance page as its own route family (G-11 — variant view in v1).

---

## 26. Cross-slice compatibility matrix

| Slice | Interaction with APP 008 | Direction |
|---|---|---|
| APP 001 (Domain) | Consumes: `Requirement`, `RequirementApplicability`, `VersionRequirementAssessment` entities added to domain model per REQUIREMENTS 005 doc updates. APP 008 introduces no domain-model changes beyond field-level additive extensions. | Consume-only |
| APP 002 (Application shell) | Extends: `qk` namespace, `DeepLinkResolver` kinds (`requirement`, `requirement-code`), `CAPABILITY_KEYS` (with reserved AI keys per G-14), `NavRail` items. All additive. | Extend additively |
| APP 003 (Projects & Design Workspace) | Extends: RightPanel tab strip gets a `Requirements` tab; project shell gets a `Requirements` nav item. Reads `list_applicable_requirements`. Does not modify APP 003 tables or routes. | Extend additively |
| APP 004 (Files & Viewer) | Consumes: version context for assess modal. Reserved future consumer via evidence attachment (§23.8). | Consume-only |
| APP 005 (Comments & Annotations) | Extends: `comments.target_requirement_id` nullable column proposed **[additive]** (§10.3). Reuses `CommentsPanel` unchanged. `StateBadge` and `useCopyLink` extended additively (§11.9). | Extend additively |
| APP 006 (Reviews) | Reuses: `user_bookmarks` (with `entity_kind='requirement'`), `user_saved_views` (with `scope='requirements'`). Reviews and requirements are orthogonal — loose coupling via shared version context and via `target_requirement_id` on comments. Reviews still discuss whatever they discuss; APP 008 adds the requirement-focused filter. | Reuse; loose coupling |
| APP 007 (Approvals) | Reuses: existing frozen `decisions.requirement_id` linkage. Approval Detail already shows "Requirements status" per APP 007 §9 — APP 008 preserves the read. No APP 007 modifications. Reserved future join for structured waivers (§23.9). | Reuse; loose coupling |
| APP 008 (this) | Owner | Owner |
| APP 009 (Releases, not yet frozen) | Consumes: `get_release_readiness_for_version(asset_version_id)` — **[additive]** read RPC. APP 009 defines the gate policy; APP 008 exposes the data. | Provide read contract |
| APP 010 (Notifications, not yet frozen) | Consumes: frozen `requirement.*` events + **[additive]** reserved event names (§20.2, §21.1). Recipient rules per §21. | Provide event contract |
| APP 011 (Realtime, not yet frozen) | Reserved channels (§22.3) name-locked. No subscriptions in APP 008. Adding requirements tables to publication requires REALTIME re-freeze. | Provide reserved channel names |

---

## 27. Backend surface delta (preview)

This is a scope statement for the follow-on `APP_008_BACKEND_PROPOSAL.md`. No SQL, no bodies, no migration ordering here — just the enumerated set of proposed additions the Backend Proposal will elaborate.

### 27.1 [additive] columns

| Table | Column | Type | Nullable | Purpose |
|---|---|---|---|---|
| `public.requirements` | `priority` | `text` | yes (default `'medium'`) | Priority tier (G-3) |
| `public.requirements` | `source_kind` | `text` | yes | Enum-backed source dimension (G-1) |
| `public.requirements` | `category_kind` | `text` | yes | Enum-backed category dimension (G-2) |
| `public.requirements` | `owner_profile_id` | `uuid` | yes | Stable owner separate from creator (G-24) |
| `public.requirements` | `verification_method` | `text` | yes | Systems-engineering taxonomy (reserved, §23.11) |
| `public.requirements` | `due_at` | `timestamptz` | yes | First-assessment deadline for overdue metrics (§8, §16) |
| `public.comments` | `target_requirement_id` | `uuid` | yes | 8th target in XOR (G-7); nullable; composite FK to `requirements(id, workspace_id)` |

Each column includes a matching CHECK constraint for enum values where applicable, an index if it drives dashboard filters (`priority`, `source_kind`, `owner_profile_id`, `due_at`), and appropriate composite FK for tenant coherence.

### 27.2 [additive] tables

**None required for v1.** Deferred (§23):
- `requirement_subscriptions` — for §21.3 (deferred).
- `requirement_templates` — for §23.3 (deferred).
- `requirement_library_items` — for §23.4 (deferred).
- `requirement_collections` — for §9.1 (deferred).
- `requirement_disciplines` — for §9.1 (deferred).
- `requirement_waivers` — for §23.9 (deferred; APP 007 v2 or later).
- `requirement_custom_sources` / `requirement_custom_categories` — for §23.1–2 (deferred).

### 27.3 [additive] read RPCs

| RPC | Purpose |
|---|---|
| `get_requirement(requirement_id)` | Requirement Detail read (metadata + latest assessments + counts) |
| `get_requirement_by_code(project_id, code)` | Deep-link `/deep/requirement/:code` resolver |
| `get_requirement_chain(requirement_id)` | Supersession chain (backward + forward) |
| `get_requirement_trace(requirement_id)` | Bundled trace graph (§15) |
| `list_requirements_dashboard(scope, view, filters, cursor, limit)` | Paginated dashboard read |
| `get_requirement_inbox_count(ws_id)` | NavRail badge (`{assigned_to_me, overdue_critical, needs_assessment}`) |
| `get_project_requirement_metrics(project_id)` | Metrics strip |
| `get_workspace_requirement_metrics(ws_id)` | Metrics strip |
| `get_release_readiness_for_version(asset_version_id)` | APP 009 read hook (§10.6, §15.3) |

All: `SECURITY DEFINER`, `SET search_path = ''`, `REVOKE` from public/anon, `GRANT EXECUTE` to `authenticated, service_role`. All gate on `requirement.view` capability (or its APP-009-side equivalent for readiness).

### 27.4 [additive] write RPCs

**None new for the core workflow** — the frozen 6 workflow RPCs (`create_requirement`, `edit_requirement`, `archive_requirement`, `supersede_requirement`, `set_requirement_applicability`, `assess_version_requirement`) already cover every state transition.

Additive params proposed on frozen RPCs (backward-compatible; use Option-A additive-arg pattern per APP 006/APP 007 precedent):
- `edit_requirement` — new nullable params: `p_priority`, `p_source_kind`, `p_category_kind`, `p_owner_profile_id`, `p_verification_method`, `p_due_at`.
- `create_requirement` — same 6 nullable params for initial values.

Both should keep every prior signature and behavior byte-for-byte; the additive params default to `NULL` and leave the corresponding column unchanged.

### 27.5 [additive] capabilities

| Capability | Purpose | Default role grants |
|---|---|---|
| `requirement.ai_suggest` (reserved) | Gate AI-assisted composer (§20.1) | Not wired in APP 008 |
| `requirement.ai_classify` (reserved) | Gate AI-assisted classification (§20.1) | Not wired in APP 008 |

No new capability keys are wired in APP 008 v1. The 5 frozen keys cover every product action. Reserved keys are name-locked for future AI wave.

### 27.6 [additive] events

**None new emitted in APP 008 v1.** The 4 frozen events (`requirement.created`, `requirement.updated`, `requirement.archived`, `requirement.assessed`) cover every state transition.

Reserved event names (name-locked, no emitter in APP 008):
- `requirement.due_soon` — reserved for scheduled emitter (belongs to cron slice).
- `requirement.overdue` — same.
- `requirement.imported` — reserved for external-system sync (§23.7).
- `requirement.ai_suggested`, `requirement.ai_classified`, `requirement.auto_assessed` — reserved for AI slice.

Additive payload extensions on frozen events (backward-compatible; consumers ignore unknown keys):
- `requirement.created` — add `priority`, `source_kind`, `category_kind`, `owner_profile_id` when set.
- `requirement.updated` (kind=`edit`) — include `priority`, `owner_profile_id`, and other **[additive]** fields in `changed_fields` when they changed.
- `requirement.assessed` — add `priority` and `is_critical_unsatisfied` computed flag for APP 010 fan-out logic.

### 27.7 [additive] indexes

| Table | Index | Purpose |
|---|---|---|
| `requirements` | `(project_id, priority)` | Priority-sorted dashboard scans |
| `requirements` | `(project_id, owner_profile_id)` | Assigned-to-me view |
| `requirements` | `(project_id, source_kind)` | Source filter |
| `requirements` | `(project_id, category_kind)` | Category filter |
| `requirements` | `(project_id, due_at)` partial `WHERE due_at IS NOT NULL AND status IN ('draft','active')` | Overdue view |
| `requirements` | GIN trigram on `title` and `description` | Text search (§13.1) |
| `comments` | `(target_requirement_id)` partial `WHERE target_requirement_id IS NOT NULL` | Discussions tab filter |

### 27.8 [additive] triggers

**None required for v1.** All frozen invariant triggers continue to enforce their contracts. If the **[additive]** `owner_profile_id` is added, a trigger to default it to `created_by_profile_id` on INSERT is proposed (soft convenience; not an invariant).

### 27.9 RLS deltas

Existing RLS policies on `requirements`, `requirement_design_assets`, `version_requirement_assessments` continue to work unchanged — the **[additive]** columns are covered by the existing SELECT policy. Any **[additive]** table would need its own policies; none proposed for v1.

For `comments.target_requirement_id` **[additive]** column: APP 005 comment RLS policies remain unchanged; the new column does not weaken any policy. A capability check (`requirement.view`) may be added in the composer client-side to prevent authoring comments targeted at requirements the caller cannot view — enforcement is best-effort; the truly-private case is already blocked by `requirements` SELECT.

### 27.10 Reserved but not proposed

- Any REALTIME publication change (`supabase_realtime`) — belongs to REALTIME re-freeze (§22.2).
- Any additional cron emitter — belongs to cron slice.
- Any AI wiring — belongs to AI slice.

---

## Canonical routes

```
/workspace/:ws_id/requirements                                                       workspace dashboard
/workspace/:ws_id/project/:proj_id/requirements                                      project dashboard
/workspace/:ws_id/project/:proj_id/requirements?view=compliance                      compliance variant
/workspace/:ws_id/project/:proj_id/requirement/:requirement_id                       Requirement Detail
/deep/requirement/:id                                                                deep-link resolver (UUID)
/deep/requirement/:code                                                              deep-link resolver (code)
```

---

## Canonical query keys

```ts
qk.requirementsList(scope, view, filters)
qk.requirementsWorkspaceDashboard(wsId, view)
qk.requirementsProjectDashboard(projId, view)
qk.requirement(id)
qk.requirementByCode(projId, code)
qk.requirementChain(id)
qk.requirementTrace(id)
qk.requirementAssessments(id)
qk.requirementHistory(id)
qk.requirementDiscussions(id)
qk.requirementApplicability(id)
qk.requirementMetrics(scope)
qk.requirementInboxCount(wsId)
qk.applicableRequirementsForAsset(assetId, versionId?)
qk.assessmentsForVersion(versionId)
qk.releaseReadinessForVersion(versionId)
```

Reused (unchanged): `qk.savedViews`, `qk.bookmarks`, `qk.projectParticipants`, `qk.commentsForVersion`, `qk.assetVersion`, `qk.designAsset`.

---

## Canonical URL parameters

Owned by APP 008:

```
?view=<all_active | assigned_to_me | recently_updated | by_status | by_priority | by_source | needs_assessment | overdue_critical | bookmarks | saved:<id> | archived | superseded | compliance>
?status=<draft,active,superseded,archived>
?priority=<critical,high,medium,low,informational>
?source=<client,consultant,regulatory,internal_team,qa,procurement,manufacturing,safety,contractual,other>
?category=<functional,non_functional,regulatory,contractual,technical,aesthetic,sustainability,safety,operational,other>
?scope=<project_wide | asset_scoped>
?assignee=<profile_id>
?code=<R-nnn>
?cursor=<opaque>
?tab=<overview | applicability | assessments | history | discussions | traceability>
?compose=1
?assess=<version_id>
?project=<project_id>                (code-form deep-link disambiguator)
?requirement=<id>                    (workspace ↔ requirement context flag)
```

Reused (unchanged from prior slices): `?discipline`, `?from`, `?comment`, `?annotation`, `?comments`, `?review`, `?approval`, `?participant`.

---

## Canonical events

Owned by APP 008 (all frozen in REQUIREMENTS 004 — this doc changes nothing on the emitter side):

- `requirement.created`
- `requirement.updated` (kinds: `edit`, `supersede`, `applicability`)
- `requirement.archived`
- `requirement.assessed`

RESERVED (name-only, no emitter in APP 008):
- `requirement.due_soon`
- `requirement.overdue`
- `requirement.imported`
- `requirement.ai_suggested`
- `requirement.ai_classified`
- `requirement.auto_assessed`

---

## Canonical capabilities

Owned by APP 008 (all frozen in REQUIREMENTS 003):

- `requirement.view`
- `requirement.create`
- `requirement.edit`
- `requirement.archive`
- `requirement.assess`

RESERVED (name-only, no wiring in APP 008):
- `requirement.ai_suggest`
- `requirement.ai_classify`
- `requirement.import`
- `requirement.auto_assess`

---

## Canonical reusable primitives

Introduced by APP 008 for downstream slices:

- `RequirementDetailShell` — the full-page shell wrapping the header + tabs.
- `AssessmentGrid` — per-version assessment table with inline assess action.
- `AssetPickerGrid` — project-scoped asset multi-select for applicability editing.
- `ScopeChip` — small chip variant used for source/category/scope indicators.
- `PriorityBadge` — priority indicator with color tokens.
- `TraceGraphCard` — the traceability visualization.
- `SupersessionChainCard` — inline chain viz for the metadata rail.
- `RequirementRef` — inline `R-042` reference component for cross-slice citation.
- `useRequirementInboxCount` — hook exported for NavRail consumers.
- `useReleaseReadinessForVersion` — hook exported for APP 009 consumption.
- Realtime channel-name constants (`src/features/requirements/realtime.ts`) — placeholder-only per §22.3.

Extended additively (backward-compatible):

- `StateBadge` — new `WorkflowState` union members: `draft`, `active`, `superseded`, `archived`. Prior members preserved.
- `useCopyLink` — `LinkKind` gains `'requirement'`, `'requirement-code'`.
- `useWorkspaceHotkeys` — new handler slot: `onNewRequirement` (bound to `N` in requirements dashboards).
- `DeepLinkResolver` — 2 additive kinds handled (`requirement`, `requirement-code`).

---

## Canonical design tokens

APP 008 introduces the following token bindings, all reusing tokens already present in `globals.css` (per APP 005/APP 007 palette):

- Status `draft` → neutral surface tokens.
- Status `active` → `--color-state-open` (blue).
- Status `superseded` → `--color-state-superseded` (neutral — filled by APP 007).
- Status `archived` → muted neutral.
- Priority `critical` → `--color-state-blocked` (red — filled by APP 007).
- Priority `high` → `--color-warning` (existing).
- Priority `medium` → `--color-state-open` (blue).
- Priority `low` → `--color-state-in-progress` (existing).
- Priority `informational` → neutral surface tokens.
- Assessment `satisfied` → `--color-state-resolved` (green).
- Assessment `partial` → `--color-warning`.
- Assessment `not_satisfied` → `--color-state-blocked` (red).
- Assessment `not_applicable` → muted neutral.

No new tokens declared. All reservations from APP 005/APP 007 are re-used, not redefined.

---

## Canonical extension seams

For APP 009–011 and AI:

| Seam | Location | Consumer |
|---|---|---|
| `get_release_readiness_for_version` RPC | Read RPC | APP 009 |
| `get_requirement_trace` RPC | Read RPC | APP 009, APP 010, AI slice |
| Event `requirement.assessed` with `is_critical_unsatisfied` payload | Backend event emitter | APP 010 |
| Event `requirement.updated` (kind=`supersede`) with `superseded_by_code` | Backend event emitter | APP 010 |
| Reserved event `requirement.due_soon` / `requirement.overdue` | Cron slice | APP 010 |
| Reserved channel names on `requirements` / `assessments` | `src/features/requirements/realtime.ts` | APP 011 (post REALTIME re-freeze) |
| Reserved capability `requirement.ai_suggest`, `requirement.ai_classify` | Capability primer | AI slice |
| Reserved `AISlot kind="requirement-classification"` | Composer | AI slice |
| Reserved `AISlot kind="assessment-questions"` | Assessments tab | AI slice |
| Reserved `AISlot kind="applicability-suggestion"` | Applicability editor | AI slice |
| Reserved `AISlot kind="regulation-parse"` | Composer `source_ref` | AI slice |
| Reserved `AISlot kind="similar-requirements"` | Composer + Detail header | AI slice |
| Reserved `AISlot kind="assessment-consistency"` | Compliance page | AI slice |
| Reserved column `evidence_file_ids uuid[]` on `version_requirement_assessments` | Schema (reserved) | v2 evidence slice |
| Reserved column `external_id text`, `external_system text` on `requirements` | Schema (reserved) | v2 sync slice |
| Reserved table `requirement_subscriptions` | Not implemented in APP 008 | APP 010 or v2 |
| Reserved table `requirement_waivers` | Not implemented in APP 008 | APP 007 v2 or waiver slice |
| Reserved table `requirement_templates`, `requirement_library_items` | Not implemented in APP 008 | v2 authoring slice |
| Reserved table `requirement_collections`, `requirement_disciplines` | Not implemented in APP 008 | v2 scope slice |

---

## Canonical backend additions required (preview only)

**Not proposed here** — this is an architecture document. A future `APP_008_BACKEND_PROPOSAL.md` will enumerate migrations, prioritize into waves, and detail exact SQL shapes. Preliminary count (from §27):

- 7 **[additive]** columns (6 on `requirements`, 1 on `comments`) with CHECKs and composite FKs.
- 0 new tables in v1 (deferred set enumerated in §27.2).
- 9 **[additive]** read RPCs.
- 0 new write RPCs; frozen 6 workflow RPCs remain the sole write surface (with backward-compatible additive params).
- 0 new capability keys wired in v1 (5 frozen keys cover every action; 2 reserved for AI).
- 0 new emitted events in v1 (4 frozen events cover every transition; 6 reserved event names for future waves).
- 7 **[additive]** indexes (5 btree + 1 GIN trigram + 1 partial on comments).
- 0 defense-in-depth triggers required (frozen triggers cover invariants; 1 optional default-owner trigger).
- Additive payload extensions on 3 of the 4 frozen events (backward-compatible — consumers ignore unknown keys).
- Realtime publication change: **none** — requirements tables remain OUT per §22.

---

**APP 008 Freeze Index ready for backend proposal.**
