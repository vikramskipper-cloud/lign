# APP 009 — Freeze Index

**Canonical architecture reference for the Lign Releases module.**

Implementation has not started. This document consolidates the APP 009 (Releases product surface) architecture into one navigational reference on top of the **frozen releases baseline** shipped in Migration 008 (`20260729230000_releases.sql`) and AUTH 008 (`20260801220000_auth_008_release_rls.sql`). It preserves every APP 001–008 contract; extension is additive only. Sections marked **[additive]** identify surface expansions the follow-on `APP_009_BACKEND_PROPOSAL.md` will elaborate — no SQL, no migration, no RPC bodies, no trigger definitions are proposed here.

**Foundational premise (non-negotiable):**

> **Requirements → Reviews → Approvals → Release.**
>
> A Release is the **final governed publication** of a design version. It **consumes** the evidence produced by the upstream governance surfaces (Requirements, Reviews, Approvals) and **never duplicates** their workflows. Releases do not collect discussion (that is Reviews). Releases do not collect votes (that is Approvals). Releases do not evaluate requirements (that is Requirement Assessments). Releases publish an already-governed version.

**Companion frozen inputs:**
- `supabase/migrations/20260729230000_releases.sql` — the frozen `releases` + `release_items` tables, the finalization-prerequisites trigger, the parent-draft-mutation trigger, and the deferred `decisions.resulting_release_id` composite FK.
- `supabase/migrations/20260801220000_auth_008_release_rls.sql` — RLS policies for `releases` / `release_items`, the `enforce_release_status_via_rpc` gate trigger, and the `finalize_release` / `withdraw_release` RPCs.
- `docs/APP_008_FREEZE_INDEX.md`, `docs/APP_007_FREEZE_INDEX.md`, `docs/APP_006_FREEZE_INDEX.md` — pattern parity + upstream governance contracts consumed by APP 009.
- `docs/freeze/APP_006_FINAL_CERTIFICATION.md`, `docs/freeze/APP_007_FINAL_CERTIFICATION.md`, `docs/freeze/APP_008_FINAL_CERTIFICATION.md` — governance records for the upstream slices.
- `docs/DOMAIN_MODEL.md`, `docs/DATABASE_SCHEMA.md`, `docs/EVENT_MODEL.md`, `docs/PERMISSIONS.md`, `docs/STATE_MACHINES.md`, `docs/SCHEMA_V1_LOCK.md`, `docs/AUTHORIZATION_ARCHITECTURE.md`.
- Memory: `project_lign_schema_v1_lock.md`, `project_lign_storage_layer_lock.md`, `project_lign_requirements_layer_lock.md`.

---

## 1. Purpose

APP 009 owns the **product-surface architecture for Releases** — the Release Detail page, the workspace and project Release dashboards, the release evidence bundle, the release-supersession chain visualization, the Design Workspace integration, the filtering grammar, the URL grammar, the deep links, the navigation entries, and the small set of additive backend extensions the surface genuinely requires. It builds on the frozen releases baseline from Migration 008 + AUTH 008 without weakening any invariant and without duplicating the upstream Reviews / Approvals / Requirements workflows.

### 1.1 What Releases ARE, ARE NOT, and DO

| Axis | Releases ARE | Releases are NOT | Releases DO |
|---|---|---|---|
| **Nature** | The final governed publication of a design version — an immutable historical fact | A synonym for `version.published`; a rating; a review; an approval; a requirement | Consume upstream governance evidence and freeze it into a bundle |
| **Weight** | Contractual + auditable | Advisory | Bind the version to a channel and a moment in time |
| **Cardinality (v1)** | One release publishes one bundle of asset-versions in a project (multi-item allowed; single-asset typical) | A per-asset property; a workspace-wide artifact | Snapshot every included `(design_asset, version)` pair immutably |
| **Discussion** | No — every discussion lives upstream in Reviews | The place to talk about a design | Reference the review evidence |
| **Voting** | No — every vote lives upstream in Approvals | The place to vote on a design | Reference the approval evidence |
| **Requirement evaluation** | No — every assessment lives in APP 008 `version_requirement_assessments` | The place to evaluate requirements | Reference the assessment evidence |
| **Mutation posture** | Terminal-immutable once `released` (per frozen `enforce_release_status_via_rpc`) | Editable in place after publication | Supersede by publishing a **new** release (v2) or withdraw |
| **Effect on the version** | None (`design_assets.current_version_id` is not touched — frozen invariant) | Sets Current; supersedes prior versions; changes Latest | Simply record "this version was released, under this channel, at this time, by this actor" |
| **First-class status** | A full module with dashboards, detail screens, URL grammar, deep links, notifications, and reserved AI seams | A sidecar tab on the Design Workspace | Own the historical publication record |

### 1.2 The `Requirements → Reviews → Approvals → Release` pipeline

```
                    APP 008                APP 006             APP 007              APP 009
                 REQUIREMENTS   ─────▶    REVIEWS   ─────▶   APPROVALS  ─────▶   RELEASES
                 obligations              discussion          authorization       publication
                     │                       │                    │                   │
                     │                       │                    │                   │
                     ▼                       ▼                    ▼                   ▼
                assessments             comments +           approved / rejected   evidence
                per version             annotations          per version           snapshot at
                                        per version                                publish time
                     │                       │                    │                   │
                     └───────────────────────┴────────────────────┴───────────────────┘
                                              consumed as evidence
                                             (READ; never mutated)
```

Every APP 009 subsystem enforces this pipeline. The Release Detail page renders evidence bundled from all three upstream slices without ever writing back into them. The publish action re-verifies approval evidence at the DB boundary (frozen `enforce_release_finalization_prerequisites`) and re-verifies requirement readiness at the RPC boundary (**[additive]** thin wrapper around APP 008's frozen `get_release_readiness_for_version` — see §6, §9, §19). Nothing in APP 009 mutates a review, an approval response, or a requirement assessment.

### 1.3 What APP 009 owns exclusively

- Release Detail page (Overview / Evidence / Comparison / History / Notes tabs — §10).
- Workspace + project Release dashboards and their view grammar (§11).
- Release-scoped URL parameters (§16).
- Deep-link kinds: `release`, `release-code` (§15).
- The NavRail "Releases" entries at workspace and project scopes (§14).
- The Design Workspace RightPanel "Releases" tab body (§12).
- The `release_type` channel semantics per §9.
- Additive capabilities and event names reserved in §19–20.
- Reusable primitives introduced in §26 (`ReleaseEvidenceCard`, `ReleaseComparisonView`, `ReleaseCard`, `ReleaseFilterBar`, `ReleaseChainCard`).

### 1.4 What APP 009 must not touch

- Frozen surface of Migration 008 + AUTH 008 (tables, columns, triggers, RLS, capability keys, event vocabulary). Any conflict is recorded in §28 as a candidate for future re-freeze.
- APP 001–008 domain invariants, capability primer, `qk` conventions, router shape, URL grammar, deep-link kinds, hotkey bindings, or component APIs.
- APP 006 Reviews entities (`reviews`, `review_participants`, `review_rounds`) — consumed as READ evidence only.
- APP 007 Approvals entities (`approval_requests`, `approval_responses`, `approvals`) — consumed as READ evidence only via `get_approval_readiness`.
- APP 008 Requirements entities (`requirements`, `requirement_design_assets`, `version_requirement_assessments`) — consumed as READ evidence only via `get_release_readiness_for_version`.
- Storage layer (STORAGE 001–004) — untouched.
- Realtime publication (REALTIME 001–002) — the 2 release tables remain OUT of `supabase_realtime`; see §23.

### 1.5 Collaboration with APP 006 (Reviews), APP 007 (Approvals), APP 008 (Requirements)

| Surface | APP 006 (Reviews) | APP 007 (Approvals) | APP 008 (Requirements) | APP 009 (Releases) |
|---|---|---|---|---|
| Purpose | Iterate on a version | Grant authority for a version | Bind long-lived project obligations | Publish an already-governed version |
| Weight | Advisory | Binding, immutable | Structural — outlives artifact | Contractual, terminal-immutable |
| Cardinality | One review per version-round | Chain of approval requests per version | Many requirements per project | One release publishes a bundle of `(asset, version)` pairs, once |
| Emits | `review.*` events | `approval.*` events | `requirement.*` events | `release.*` events (frozen 5, reserved 2) |
| Consumed by APP 009 | Evidence bundle (linked reviews per version) | Evidence bundle (approval-request outcome per version) — REQUIRED for `finalize_release` per frozen trigger | Evidence bundle (readiness metric per version) — CONSULTED per `release_type` policy | — |
| Writes back to APP 009 | Never | Never | Never | — |

APP 009 is exclusively a **downstream consumer**. Every write path in APP 009 (`create_release`, `add_release_item`, `remove_release_item`, `finalize_release`, `withdraw_release`) only mutates rows in `releases` and `release_items` — never in the upstream slices' tables.

---

## 2. Domain boundaries

APP 009 works with two frozen entities (Migration 008) plus a set of conceptual product-layer entities that surface behavior already implicit in the frozen schema. No new schema is required for the core entities; every extension is enumerated in §27 as **[additive]** and defaults to nullable / backwards-compatible.

### 2.1 Inside APP 009's boundary

| Entity / concept | Backing surface | Owner |
|---|---|---|
| `Release` (the publication record) | frozen `public.releases` | APP 009 |
| `ReleaseItem` (the join to `asset_versions`) | frozen `public.release_items` | APP 009 |
| Release notes | frozen `releases.notes` (free-form text) | APP 009 |
| Release channel / type | frozen `releases.channel` (free-form text — see §9 for enum-vs-tags decision) | APP 009 |
| Release evidence bundle | **[additive]** `releases.evidence_snapshot jsonb` OR bundled read RPC (§6) | APP 009 |
| Release supersession chain | **[additive]** `releases.superseded_by_release_id` + `releases.root_release_id` (§8) | APP 009 |
| Release Detail page | New UI surface | APP 009 |
| Release dashboards | New UI surfaces | APP 009 |
| Release notifications (recipient rules) | APP 010 consumes; APP 009 defines contract | APP 009 (contract) / APP 010 (delivery) |
| Release realtime channels | Reserved names; no subscriptions in APP 009 | APP 009 (names) / APP 011 (subscriptions) |

### 2.2 Outside APP 009's boundary — consumed but not owned

| External concept | Backing surface | Owner | APP 009's contact point |
|---|---|---|---|
| Review comments and rounds | `reviews`, `review_participants`, `review_rounds`, `comments` | APP 006 | READ only; via the Evidence tab (§6) |
| Approval requests / responses / outcomes | `approval_requests`, `approval_responses`, `approvals` | APP 007 | READ only; via `get_approval_readiness(version_id)` |
| Requirement assessments | `version_requirement_assessments` | APP 008 | READ only; via `get_release_readiness_for_version(version_id)` |
| Requirements themselves | `requirements`, `requirement_design_assets` | APP 008 | READ only; count of applicable requirements for the released version |
| Asset version content | `asset_versions`, `version_files`, storage buckets | APP 003 + APP 004 + STORAGE | READ only; version metadata rendered in cards |
| Comment authoring | `comments` (7-way XOR) | APP 005 | Not extended for releases per §26 recommendation |
| Notifications delivery | APP 010 | APP 010 | Event contract only (§22) |
| Realtime broadcast | APP 011 | APP 011 | Reserved channel names only (§23) |
| Historical activity feed | `activity_events` | APP 002 | READ only; History tab renders `subject_kind='release'` rows |

### 2.3 "Consumes but does not own" contract

APP 009 promises:
- It will never `INSERT` / `UPDATE` / `DELETE` any row outside of `releases` and `release_items` (aside from the standard `activity_events` audit trail write that every governance RPC performs).
- It will never propose a modification to any RPC owned by APP 006 / APP 007 / APP 008.
- It will never require an upstream slice to fire an event on APP 009's behalf.
- It will never cache an upstream slice's write path.

APP 009 accepts:
- If APP 007's `get_approval_readiness` returns "no approved request," `finalize_release` **must** raise. The frozen `enforce_release_finalization_prerequisites` trigger already enforces this at the DB boundary and cannot be relaxed.
- If APP 008's `get_release_readiness_for_version` indicates critical unassessed / unsatisfied requirements, the UX renders a warning and — per `release_type` policy (§9) — may soft-block the publish action. The soft-block is **product-side** and does not reach the DB (the DB does not know about requirement readiness).
- If APP 006 has no completed review for the version, the publish action is not blocked. Reviews are advisory (per APP 006 D-1); the release channel policy may recommend a review but never require one at the DB layer.

### 2.4 Cardinality summary

- One `release` has 1..N `release_items` (min 1 enforced by frozen `enforce_release_finalization_prerequisites` at finalize time; drafts may have 0 items during composition).
- One `release_item` references exactly one `asset_version` (via `(version_id, project_id)` composite FK) and one `design_asset` (denormalized, verified by `(version_id, design_asset_id)` composite FK).
- One `asset_version` may appear in 0..N different releases historically (frozen `release_items_release_version_key unique(release_id, version_id)` — same version cannot appear twice in the same release).
- One `release` is superseded by exactly 0 or 1 other release (via **[additive]** `superseded_by_release_id`).
- One `release` belongs to exactly one project + workspace (frozen composite FK).

### 2.5 What the Backend Proposal will elaborate

Every **[additive]** field / RPC / capability / event / index referenced in this document will be enumerated with signatures, defaults, and rationale in the forthcoming `APP_009_BACKEND_PROPOSAL.md`. Preliminary counts appear in §27.

---

## 3. Release lifecycle

### 3.1 The frozen 3-state MVP lifecycle

Per `STATE_MACHINES.md v1 §15` and Migration 008 `releases_status_check`:

- `draft` — release is being composed. Items may be added/removed. Metadata (name / notes / channel / effective_at) may be edited. Not yet published.
- `released` — release is published. All frozen invariants have been verified. Items are immutable (frozen `enforce_release_items_parent_draft_mutation`). Status / metadata are RPC-locked (frozen `enforce_release_status_via_rpc`).
- `withdrawn` — release was previously `released` and has been withdrawn. Historical record preserved with `withdrawn_at` and `withdrawn_reason`.

**Terminal set:** `withdrawn`. **Effectively terminal (transitions only to withdrawn):** `released`. **Non-terminal:** `draft`.

### 3.2 Reserved schema values (not exercised in MVP)

Frozen `releases_status_check` also permits:

- `scheduled` — reserved for a future scheduled-publication workflow (cron-driven or admin-driven). No transitions in v1.
- `superseded` — reserved for a future auto-supersession workflow. No transitions in v1.

**APP 009 v1 does NOT exercise these values.** The reserved values remain in the CHECK constraint so a future re-freeze can extend the lifecycle without an ALTER. APP 009's product surface renders these states with "Reserved" copy if they ever appear (defensive rendering; the RPCs cannot produce them in v1). Decision recorded as G-1 in §28.

### 3.3 Legal transitions (frozen)

Enumerated exactly by the frozen `finalize_release` and `withdraw_release` RPCs plus the metadata-only RLS UPDATE policy:

```
                       create              finalize_release
   ∅ ──────────────▶ [ draft ] ────────────────────────▶ [ released ]
                        │                                     │
                        │  (metadata edits: name /            │  withdraw_release
                        │   notes / channel /                 │
                        │   effective_at via                  │
                        │   RLS UPDATE, RPC-gate              ▼
                        │   trigger blocks status)        [ withdrawn ]
                        │
                        │  (item mutations via
                        │   INSERT/UPDATE/DELETE on
                        │   release_items — allowed
                        │   only while draft)
                        │
                        │  ✗ no DELETE policy on releases
                        │  ✗ no supersede path in MVP
                        │  ✗ no withdraw-from-draft path
                        ▼
                     (cannot leave draft except
                      via finalize_release)
```

### 3.4 Terminal-immutability of `released`

Once a release reaches `released`:

- `releases.status`, `releases.released_at`, `releases.withdrawn_at`, `releases.withdrawn_reason` are locked by frozen `enforce_release_status_via_rpc` — only the `finalize_release` / `withdraw_release` RPCs may mutate them via the `lign.allow_release_status_write` transaction GUC.
- `releases.id`, `releases.workspace_id`, `releases.project_id`, `releases.created_by_profile_id` are unconditionally immutable (also enforced by `enforce_release_status_via_rpc`).
- `release_items` rows for this release cannot be inserted / updated / deleted (frozen `enforce_release_items_parent_draft_mutation` — raises `23514` on any mutation when parent is not `draft`).
- Free-form metadata (`name`, `notes`, `channel`, `effective_at`) remains technically UPDATEable via the RLS UPDATE policy with `release.create` capability — **but APP 009 product surface hides these edit affordances after publication**. Rationale: the frozen RLS permits post-release metadata edits so admins can correct typos, but the product policy is that a published release is a historical record and should not be edited after the fact. Decision recorded as G-2 in §28.

### 3.5 Rollback semantics

There is no rollback path. Once `released`, the only forward motion is `withdrawn`. Once `withdrawn`, there is no path back to `released` (frozen `withdraw_release` requires `status='released'`; no `unwithdraw_release` RPC exists and none is proposed). Remediation for a mistaken release is:

1. Withdraw the mistaken release with a `reason` explaining the mistake.
2. Optionally publish a **new** release with the correct scope (APP 009 v2 will link the new release to the withdrawn one via **[additive]** `superseded_by_release_id`; in v1 the linkage is a free-text mention in `notes` — see §8, G-3).

Decision recorded as G-3 in §28.

### 3.6 Draft-time item composition

While in `draft`, the release composer allows:

- Adding items via `add_release_item(release_id, design_asset_id, version_id, notes, sort_order)` — **[additive]** RPC per §27 (frozen schema supports this shape; only the RPC wrapper is new). The frozen `enforce_release_items_parent_draft_mutation` trigger permits INSERT while parent is draft.
- Removing items via `remove_release_item(release_id, version_id)` — **[additive]** RPC per §27.
- Reordering items by updating `release_items.sort_order` — **[additive]** RPC `reorder_release_items(release_id, ordered_version_ids uuid[])` per §27. Frozen `release_items_release_sort_order_key unique(release_id, sort_order)` enforces deterministic ordering.
- Editing metadata (`name`, `notes`, `channel`, `effective_at`) via direct UPDATE (frozen RLS UPDATE policy permits this).

At `finalize_release` time:
- Frozen trigger requires ≥ 1 item.
- Frozen trigger requires every item's `(design_asset_id, version_id)` to have an `approval_requests` row with `status='approved'`.
- **[additive]** RPC-side wrapper (§27) may consult `get_release_readiness_for_version` per item and, per `release_type` policy (§9), raise a warning or soft-block. Never overrides the frozen trigger.

### 3.7 Discard-draft semantics

A `draft` release with 0 items may be discarded with no ceremony. **[additive]** RPC `discard_release_draft(release_id)` per §27 removes the row (RLS DELETE would need to be added — see §28 G-4 for the alternative of soft-discard via a `discarded_at` column). Discard is forbidden once the release has ≥ 1 `release_items` row unless the caller first removes all items (defense against accidental data loss). Frozen schema has **no DELETE policy on releases** — this is an intentional gap in the frozen layer that **[additive]** work must decide: either introduce a narrowly-scoped DELETE policy for zero-item drafts by the creator only, or introduce a soft-discard column. Decision recorded as G-4 in §28.

---

## 4. State machine

Full state × transition × trigger × emitted event × capability × side-effects matrix. Every row describes a frozen or **[additive]** path. Frozen rows cite the migration; **[additive]** rows will be enumerated in the Backend Proposal.

| From | To | Transition trigger | RPC | Event emitted | Capability required | Side effects | Source |
|---|---|---|---|---|---|---|---|
| ∅ | `draft` | Author creates release | `create_release` **[additive]** | `release.created` | `release.create` | Row inserted; `created_by_profile_id = auth.uid()` (frozen RLS INSERT check); `status='draft'` (frozen RLS INSERT check) | frozen RLS INSERT policy + **[additive]** RPC |
| `draft` | `draft` (item added) | Add item | `add_release_item` **[additive]** | `release.item_added` (frozen name) | `release.create` | `release_items` INSERT; frozen `enforce_release_items_parent_draft_mutation` permits (parent is draft) | frozen `release_items` RLS + **[additive]** RPC |
| `draft` | `draft` (item removed) | Remove item | `remove_release_item` **[additive]** | `release.item_removed` (frozen name) | `release.create` | `release_items` DELETE; frozen `enforce_release_items_parent_draft_mutation` permits | frozen `release_items` RLS + **[additive]** RPC |
| `draft` | `draft` (items reordered) | Reorder items | `reorder_release_items` **[additive]** | — (no event; sort order is presentational) | `release.create` | `release_items.sort_order` UPDATE; frozen unique-per-release constraint enforced | **[additive]** RPC |
| `draft` | `draft` (metadata edit) | Edit name/notes/channel/effective_at | direct UPDATE via RLS | — (no event in v1; **[additive]** reserved `release.notes_updated` for v2) | `release.create` | Row UPDATE; frozen `enforce_release_status_via_rpc` blocks non-metadata columns | frozen RLS UPDATE policy |
| `draft` | `released` | Finalize | `finalize_release` (frozen) | `release.finalized` (frozen) | `release.finalize` (frozen) | Sets `status='released'`, `released_at=now()`; frozen `enforce_release_finalization_prerequisites` re-verifies (≥1 item + every item approved); `activity_events` row written by RPC; **[additive]** RPC-side wrapper snapshots evidence bundle (§6) into `releases.evidence_snapshot` before the status write | frozen AUTH 008 RPC + **[additive]** snapshot pre-step |
| `released` | `withdrawn` | Withdraw | `withdraw_release` (frozen) | `release.withdrawn` (frozen) | `release.withdraw` (frozen) | Sets `status='withdrawn'`, `withdrawn_at=now()`, `withdrawn_reason=p_reason`; frozen RPC requires `status='released'` | frozen AUTH 008 RPC |
| `draft` | ∅ (discard) | Discard empty draft | `discard_release_draft` **[additive]** (see §3.7 + G-4) | — (or reserved `release.draft_discarded`) | `release.create` | Row DELETE — requires zero items; RLS DELETE policy addition is an **[additive]** gap flagged in §28 | **[additive]** RPC + policy |

### 4.1 Reserved-state transitions (name-locked; no emitter in MVP)

For a future re-freeze, if the reserved `scheduled` and `superseded` states are activated:

| From | To | Transition trigger | Reserved event name |
|---|---|---|---|
| `draft` | `scheduled` | Schedule for future publish | `release.scheduled` (frozen name; no emitter) |
| `scheduled` | `released` | Cron / admin trigger at `effective_at` | `release.finalized` (reuse existing) |
| `scheduled` | `draft` | Unschedule | Reserved — no name yet |
| `released` | `superseded` | New release publishes and marks old superseded | `release.superseded` (frozen name; no emitter) |

None of these are wired in APP 009 v1. Decision recorded as G-5 in §28.

### 4.2 Terminal-outcome rules

- `withdrawn` is truly terminal — no transition path exists in v1 or in the reserved-state extension.
- `released` transitions only to `withdrawn`.
- `superseded` (reserved) would be truly terminal once activated.
- Terminal-state rows remain SELECTable indefinitely (frozen RLS SELECT policy on `release.view`).

### 4.3 Event ordering guarantees

- `release.created` fires within the `create_release` RPC's transaction.
- `release.item_added` / `release.item_removed` fire within the corresponding **[additive]** RPC's transaction.
- `release.finalized` fires **after** the frozen `enforce_release_finalization_prerequisites` trigger has verified all prerequisites, and within the same transaction as the status UPDATE (see frozen `finalize_release` RPC body).
- `release.withdrawn` fires within the frozen `withdraw_release` RPC's transaction, after the status UPDATE.
- No event is retracted. If a transaction rolls back, no event is emitted (activity_events INSERT is within the same transaction).

---

## 5. Release model

The core entity. Every column enumerated below is either **frozen** (cited to Migration 008 or AUTH 008) or **[additive]** (deferred to the Backend Proposal). No frozen column is proposed for change.

### 5.1 Frozen columns on `public.releases` (Migration 008)

| Column | Type | Nullable | Default | Purpose | Immutability |
|---|---|---|---|---|---|
| `id` | `uuid` | no | `gen_random_uuid()` | Primary key | Immutable (frozen `enforce_release_status_via_rpc`) |
| `workspace_id` | `uuid` | no | — | Tenant scope | Immutable (frozen) |
| `project_id` | `uuid` | no | — | Project scope; composite FK with `workspace_id` to `projects(id, workspace_id)` | Immutable (frozen) |
| `name` | `text` | no | — | Human-readable release name | Mutable via RLS UPDATE (product surface hides post-release, G-2) |
| `notes` | `text` | yes | — | Release notes / description | Mutable via RLS UPDATE (product surface hides post-release, G-2) |
| `channel` | `text` | yes | — | Free-text channel; APP 009 layers the `release_type` enum over this (§9) | Mutable via RLS UPDATE (product surface hides post-release, G-2) |
| `status` | `text` | no | `'draft'` | Lifecycle state; CHECK in `('draft','scheduled','released','superseded','withdrawn')` | RPC-only (frozen `enforce_release_status_via_rpc` gate + `lign.allow_release_status_write` GUC) |
| `effective_at` | `timestamptz` | yes | — | Reserved for scheduled-publish semantics (§3.2) | Mutable via RLS UPDATE (v1 unused) |
| `released_at` | `timestamptz` | yes | — | Set by `finalize_release` RPC | RPC-only |
| `withdrawn_at` | `timestamptz` | yes | — | Set by `withdraw_release` RPC | RPC-only |
| `withdrawn_reason` | `text` | yes | — | Set by `withdraw_release` RPC | RPC-only |
| `created_by_profile_id` | `uuid` | yes | — | FK → `profiles(id)` ON DELETE SET NULL | Immutable (frozen) |
| `created_at` | `timestamptz` | no | `now()` | — | Immutable |
| `updated_at` | `timestamptz` | no | `now()` | Maintained by frozen `set_updated_at` trigger | Trigger-maintained |

Frozen constraints preserved:
- `releases_status_check` — 5-value enum (`draft`, `scheduled`, `released`, `superseded`, `withdrawn`).
- `releases_released_metadata_check` — non-draft/scheduled requires `released_at`.
- `releases_withdrawn_metadata_check` — `withdrawn` requires `withdrawn_at`.
- `releases_project_fk` — composite `(project_id, workspace_id)` → `projects(id, workspace_id)`.
- `releases_id_project_workspace_key unique(id, project_id, workspace_id)` — for `release_items`' 3-col composite FK.
- `releases_id_workspace_key unique(id, workspace_id)` — for `decisions.resulting_release_fk`.

### 5.2 Frozen columns on `public.release_items` (Migration 008)

| Column | Type | Nullable | Purpose | Immutability |
|---|---|---|---|---|
| `id` | `uuid` | no | Primary key | Immutable |
| `workspace_id` | `uuid` | no | Tenant scope; part of composite FK | Immutable |
| `project_id` | `uuid` | no | Part of composite FK to parent release | Immutable |
| `release_id` | `uuid` | no | Composite FK `(release_id, project_id, workspace_id)` → `releases(id, project_id, workspace_id)` | Immutable |
| `version_id` | `uuid` | no | Composite FK `(version_id, project_id)` → `asset_versions(id, project_id)` | Mutation blocked once parent leaves draft (frozen trigger) |
| `design_asset_id` | `uuid` | no | Denormalized; composite FK `(version_id, design_asset_id)` → `asset_versions(id, design_asset_id)` for sanity | Same |
| `notes` | `text` | yes | Per-item notes | Same |
| `sort_order` | `integer` | no | `0` default; CHECK `>= 0`; unique per `(release_id, sort_order)` | Same |
| `created_at`, `updated_at` | `timestamptz` | no | Standard | — |

Frozen constraints preserved:
- `release_items_release_version_key unique(release_id, version_id)` — a version appears at most once per release.
- `release_items_release_sort_order_key unique(release_id, sort_order)` — deterministic ordering.

### 5.3 [additive] columns proposed for `public.releases`

Enumerated with rationale; enumerated for signature in §27.

| Column | Type | Nullable | Purpose | Why |
|---|---|---|---|---|
| `superseded_by_release_id` | `uuid` | yes | Chain pointer to the release that supersedes this one | Needed for supersession chain (§8). Composite FK `(superseded_by_release_id, project_id, workspace_id)` → `releases(id, project_id, workspace_id)` — same-project constraint. |
| `root_release_id` | `uuid` | yes | Chain head pointer for O(1) chain lookup | Mirrors APP 006 T-CRIT-1 lesson — pre-compute UUID + INSERT chain columns inline. |
| `release_type` | `text` | yes | Enum-backed channel dimension (§9) | Frozen `channel` column is free-text and cannot support dashboard filters / metrics; enum column layered on top preserves the frozen column for human labels. |
| `evidence_snapshot` | `jsonb` | yes | Frozen bundle of approval + review + requirement evidence captured at `finalize_release` time (§6) | Immutability guarantee: evidence never mutates after publish, even if upstream changes. |
| `published_by_profile_id` | `uuid` | yes | FK → `profiles(id)` — the actor who published (may differ from `created_by_profile_id`) | Frozen schema captures only creator, not publisher. |
| `discarded_at` | `timestamptz` | yes | Soft-discard timestamp for draft cleanup | Alternative to introducing a DELETE policy; see G-4 in §28. |

None of the above are required to preserve the frozen surface — every existing RPC continues to function without them. All are labeled **[additive]** and defaulted to `NULL`.

### 5.4 Distinguishing frozen vs. additive rendering

APP 009 UI will render frozen fields with high confidence and **[additive]** fields with feature-flag gating during rollout. Once the Backend Proposal ships, the flags collapse. Fallback rendering for a Release created before the **[additive]** columns exist:

- `release_type` unset → render `channel` free-text or "Untyped" if both are null.
- `evidence_snapshot` unset → render a live re-compute banner ("Evidence snapshot not captured for this release — showing current upstream state") and consult upstream reads on the fly. Live re-compute is **NOT immutable evidence**; the banner warns.
- `superseded_by_release_id` / `root_release_id` unset → render as head-of-chain.
- `published_by_profile_id` unset → fall back to `created_by_profile_id`.

### 5.5 Relationships summary

| Relationship | Backing surface | Cardinality | Direction |
|---|---|---|---|
| Release → Project | frozen composite FK | N:1 | Downstream |
| Release → Workspace | frozen composite FK (transitive) | N:1 | Downstream |
| Release → ReleaseItem | frozen composite FK | 1:N | Owned |
| ReleaseItem → AssetVersion | frozen composite FK | N:1 | Consumer |
| ReleaseItem → DesignAsset | frozen composite FK (denormalized) | N:1 | Consumer |
| Release → Release (supersession) | **[additive]** `superseded_by_release_id` | 1:0..1 | Chain |
| Release → Profile (created_by) | frozen FK ON DELETE SET NULL | N:1 | Attribution |
| Release → Profile (published_by) | **[additive]** FK ON DELETE SET NULL | N:1 | Attribution |
| Decision → Release | frozen `decisions.resulting_release_id` composite FK (Migration 008 completes the deferred FK) | N:0..1 | Cross-reference from decisions |
| Requirement → Release | via trace API (APP 008 `get_release_readiness_for_version`) | N:M read-only | READ-only consumption |
| Approval → Release | via `get_approval_readiness` (APP 007) | N:M read-only | READ-only consumption |
| Review → Release | via evidence snapshot; loose | N:M read-only | READ-only consumption |

### 5.6 Interaction with `design_assets.released_version_ref` — clarification

There is **no** `released_version_ref` column on `design_assets` in the frozen schema. The frozen invariant is that a release does not modify `design_assets.current_version_id` (per Migration 008 header comment §"Architectural notes" and STATE_MACHINES.md line 411). Product surface computes "the released version of this asset" by querying `release_items` joined against `releases` filtered on `status='released'` and sorted by `released_at desc`. Decision recorded as G-6 in §28.

### 5.7 Immutability rules once published

Enforced by frozen `enforce_release_status_via_rpc` on UPDATE:

1. `id`, `workspace_id`, `project_id`, `created_by_profile_id` — unconditionally immutable.
2. `status`, `released_at`, `withdrawn_at`, `withdrawn_reason` — mutable only when the transaction GUC `lign.allow_release_status_write = 'true'` (set only by `finalize_release` / `withdraw_release` RPCs).
3. `name`, `notes`, `channel`, `effective_at` — mutable via RLS UPDATE at any time (but product surface hides edit UI post-`released` per G-2).

Enforced by frozen `enforce_release_items_parent_draft_mutation` on `release_items`:

- Any INSERT / UPDATE / DELETE on `release_items` is rejected (`23514`) if parent `releases.status <> 'draft'`.

Enforced by frozen `enforce_release_finalization_prerequisites` on releases (BEFORE INSERT + BEFORE UPDATE OF status):

- Transition to `released` requires ≥ 1 `release_items` row.
- Transition to `released` requires every item to have an approved `approval_requests` row for its `(design_asset_id, version_id)`.

---

## 6. Release evidence

### 6.1 What the evidence bundle contains

The evidence bundle is the frozen record of governance signals present at publish time. It answers "what did we have when we shipped?" A release's evidence bundle contains:

- **Approval evidence** — for each `release_items` row, the `approval_requests.id` that was `approved` at `finalize_release` time (already required by frozen trigger). Snapshot fields: `approval_request_id`, `policy`, `outcome`, `outcome_computed_at`, `approver_count`, `approved_count`, `has_veto_cast`.
- **Requirement evidence** — for each `release_items` row's version, the result of `get_release_readiness_for_version(version_id)` at finalize time: `{applicable_count, satisfied_count, partial_count, not_satisfied_count, unassessed_count, critical_unsatisfied_count, critical_unassessed_count}`.
- **Review evidence** — for each `release_items` row's version, the count and IDs of `reviews` in `completed` status at finalize time. No comment bodies — only aggregate counts + IDs so the Evidence tab can link back to the reviews.
- **Item-level snapshot** — per item: `release_item_id`, `design_asset_id`, `design_asset_name`, `version_id`, `version_sequence`, `version_published_at`.
- **Publish context** — `published_by_profile_id`, `published_at`, `release_type`, `channel`.

### 6.2 Storage: `jsonb` snapshot on the release row

Recommended: store the entire bundle as **[additive]** `releases.evidence_snapshot jsonb` (nullable). Rationale:

- Immutability by construction — a `jsonb` column on the release row moves with the row and is snapshotted atomically in the `finalize_release` RPC's transaction.
- No join tables. The alternative (a `release_evidence` table with per-approval, per-requirement, per-review rows) would introduce N additional joins per release read for zero product-observable benefit.
- Pointers, not embeds. The snapshot stores IDs and small aggregates, not comment bodies or approval decision reasons. Deep-link to the source-of-truth records for full detail.
- Compact. A typical release with 3 items and ~5 approvals + ~40 requirements + ~2 reviews per item snapshots to well under 8 KB.

Decision recorded as G-7 in §28.

### 6.3 Immutability guarantees

Once written by `finalize_release`, the `evidence_snapshot` never mutates. Even if:

- An approval is later cancelled or its approvers change roles.
- A requirement is later archived or superseded.
- A review is later reopened (frozen APP 006 `reopen_review` creates a new linked row; the old row's ID in the snapshot remains valid but its `status` may have changed).

The snapshot preserves the state at publish time. The Evidence tab renders both:

1. The snapshotted values ("At publish time: 8 approvals, 40 requirements satisfied, 2 completed reviews").
2. A "Now" delta if any snapshotted record has since changed status ("2 requirements have since been superseded — click to see current state").

Live values are always fetched via read RPCs; snapshotted values live in the `jsonb`. The two are never conflated.

### 6.4 What the evidence bundle does NOT contain

- Comment bodies (looked up live from `comments` via IDs).
- Approval decision reasons (looked up live from `approval_responses` via IDs).
- Requirement descriptions (looked up live from `requirements` via IDs).
- Version file bytes (never in the DB anyway; STORAGE 001).
- Reviewer / approver identities beyond the ID (profiles are looked up live).

This keeps the snapshot small, cheap to write, and free of PII duplication concerns.

### 6.5 Rendering the evidence bundle

The Release Detail **Evidence tab** renders:

- **Approvals section** — one row per approved request per item; click → APP 007 Approval Detail.
- **Requirements section** — for each item's version: applicable requirements grouped by assessment status; click → APP 008 Requirement Detail; per-requirement chip shows "As of publish time: satisfied" vs "Now: not_satisfied" delta.
- **Reviews section** — one row per completed review per item's version; click → APP 006 Review Detail.
- **Item detail** — expandable card per `release_items` row.

Empty-state copy: "No evidence snapshot was captured for this release. Showing live upstream state as of now." (renders when `evidence_snapshot IS NULL`).

### 6.6 Backend surface

- **[additive]** `releases.evidence_snapshot jsonb` column (§27).
- **[additive]** read RPC `get_release_evidence(release_id)` returning the snapshot plus a "current-state" side-by-side delta for each snapshotted record (§27).
- **[additive]** internal helper (called inside `finalize_release`) to build the snapshot before the status write. See §19 for capability discussion.

### 6.7 Cross-slice invariants preserved

- APP 006 owns review status — evidence snapshot never writes to `reviews`.
- APP 007 owns approval outcome — evidence snapshot never writes to `approvals`.
- APP 008 owns assessment status — evidence snapshot never writes to `version_requirement_assessments`.
- Evidence is a **read** into a **jsonb** on the release; nothing about the upstream slice tables changes.

---

## 7. Version relationship

### 7.1 Cardinality: one release publishes one version of an asset (per item; multiple items allowed)

Per frozen schema, a `release_items` row is `1:1` with an `(asset_version_id, design_asset_id)` pair, and `release_items_release_version_key` guarantees the same version cannot appear twice in the same release. A release therefore publishes a **bundle** of `(asset, version)` pairs — typically one item in v1, but any positive count is legal.

Multi-item multi-asset bundle releases are permitted by the frozen schema. Product surface presents them as "N items" cards on the dashboard and as expandable per-item sections on the Detail page. Advanced multi-asset UX (co-review, cross-asset diff, package export) is deferred to a future wave — see §28 G-8.

### 7.2 How the release captures "the version at publish time"

The `release_items` row is the immutable capture:

- `version_id` — foreign key to the specific `asset_versions` row that was included. `asset_versions` rows are themselves immutable once published (per APP 004 STATE_MACHINES.md §12).
- `design_asset_id` — denormalized asset FK; also immutable (per APP 003 STATE_MACHINES.md §11).
- Frozen `enforce_release_items_parent_draft_mutation` prevents any subsequent mutation of these FKs after the parent transitions out of `draft`.

Thus the release's item set is a photograph. It captures **which version** was published, not "the latest version at the time." If the asset later gains a `v4` after a release published `v3`, the release still points at `v3` forever.

### 7.3 Absence of `design_assets.released_version_ref`

The frozen schema does NOT introduce a "released version pointer" on `design_assets`. Rationale (also captured in G-6):

- A release is not exclusive — multiple releases may include different versions of the same asset historically. There is no single "the released version."
- The frozen release-lifecycle invariant "Release does not change `design_assets.current_version_id`" (STATE_MACHINES.md line 411) applies symmetrically to any hypothetical `released_version_ref` — coupling release status to a version-side pointer would violate the independence invariant.
- Product surface computes "most recently released version of this asset" by querying `release_items JOIN releases ON release.status='released' WHERE design_asset_id=... ORDER BY released_at DESC LIMIT 1`. This is bounded and cheap given the frozen `release_items_version_asset_idx` (Migration 008) plus **[additive]** `releases_project_status_released_idx` (already present as `releases_project_status_released_idx (project_id, status, released_at desc)` in Migration 008).

### 7.4 Interaction with subsequent versions

A newer version does not retroactively affect a prior release:

- Publishing `v4` after `v3` was released does not modify the release row.
- Publishing `v4` does not automatically release `v4` (independence invariant, STATE_MACHINES.md §5).
- Publishing `v4` does not automatically supersede the prior release (STATE_MACHINES.md §15 explicit non-goal).

The product surface shows both facts on the asset's version list:

- The version card for `v3` displays a `StateBadge` variant "Released" (see §12, §13) with a click-through to the release.
- The version card for `v4` displays no release badge until it is itself included in a released release.

### 7.5 Interaction with the version selector in the Design Workspace

APP 003's Design Workspace version selector (per APP 003 architecture) surfaces the version list for an asset. APP 009 additively decorates:

- A "Released" chip next to any version that appears in a `released`-status release for the asset.
- A per-release affordance ("View release R-042") for a chip that has multiple releases (rare) — resolves to a small popover listing all releases containing the version.

Decoration is one-way (APP 009 reads; APP 003 renders). APP 003 is not modified beyond an additive slot in its version card.

### 7.6 Cross-asset release integrity

Frozen composite FKs make cross-project releases structurally impossible (per Migration 008 header comment §"Composite tenant/project integrity"):

- `release_items.release_fk` — item's `(release_id, project_id, workspace_id)` must match the release's project+workspace.
- `release_items.version_project_fk` — item's version must belong to an asset in the same project.
- `release_items.version_asset_fk` — item's denormalized asset must match the version's asset.

APP 009 relies on these invariants without duplicating them at the RPC layer. If a future workspace-scoped or workspace-federated release is required, that is a re-freeze (§28 G-8).

---

## 8. Previous release chain

### 8.1 The `superseded_by_release_id` / `root_release_id` model

The chain lets a release point at the release that superseded it. In MVP the chain is **not automatically populated** (STATE_MACHINES.md §15 D7: "Releases do not automatically supersede prior releases"). It is populated only when a subsequent release explicitly supersedes a prior one via a future **[additive]** `supersede_release(prior_release_id, new_release_id)` RPC (see §27; not shipped in v1).

Chain shape:

```
    root                                             head
    ─────                                            ─────
    R-001 ◀── R-002 ◀── R-003 ◀── R-004  (older on the left)
      ↑         ↑         ↑         ↑
      │         │         │         │
      superseded_by ─────────────────┘
                                    (each row points at the next)

    Every row also carries root_release_id = R-001
    for O(1) head-of-chain lookup without walking.
```

### 8.2 Chain-init discipline (APP 006 T-CRIT-1 lesson applied)

Chain-init must be atomic. Per APP 006 T-CRIT-1 (the rounds chain-init lesson) and APP 007 §21 G-14, the discipline is:

1. Pre-compute the new UUID (`new_release_id := gen_random_uuid()`).
2. Compute `root_release_id`:
   - If the prior release has `root_release_id IS NOT NULL`, use it (extending an existing chain).
   - Else (prior release is the root), use `prior_release_id` (starting a chain).
3. INSERT the new release with `superseded_by_release_id = NULL` (it is now the head) and `root_release_id` set inline.
4. UPDATE the prior release setting `superseded_by_release_id = new_release_id`.
5. Both UPDATE + INSERT happen in one transaction inside `create_release_superseding` (**[additive]** RPC, deferred to v2).

Do **not** rely on triggers to backfill `root_release_id` on INSERT — the trigger cannot resolve a two-row chain-init that spans a single statement.

### 8.3 Immutability of the chain

Once written, `superseded_by_release_id` and `root_release_id` are immutable. This is a defense-in-depth trigger in the Backend Proposal (analogous to APP 007 §21 G-30 `reviews_chain_immutable`). Attempting to UPDATE these columns raises. Rationale: the chain is a historical audit record; retroactively re-writing it corrupts every downstream consumer's view of history.

### 8.4 Terminal-immutability of `released` (recap)

- A `released` release cannot become anything except `withdrawn` (frozen).
- Editing a `released` release's evidence, items, or status-adjacent columns is impossible (frozen triggers).
- Supersession does not mutate the prior release's status in v1 — the prior release remains `released` even after being superseded (STATE_MACHINES.md §15 D7). Only the `superseded_by_release_id` pointer changes.

Contrast: APP 007 Approvals **do** set the prior request's `status='superseded'` when a new request supersedes it (APP 007 §3.5). APP 009 deliberately diverges — the frozen release lifecycle does not activate the `superseded` state in MVP, and forcibly setting it would require a re-freeze of `enforce_release_status_via_rpc`. Decision recorded as G-9 in §28.

### 8.5 Walking the chain

- **Backward walk** (find what a release supersedes): find the row where `superseded_by_release_id = this.id` (unique guarantee — see §8.7).
- **Forward walk** (find what supersedes this): follow `this.superseded_by_release_id`.
- **Chain head**: `this.root_release_id` (O(1); no walk).
- **Chain length**: bounded by the number of superseding actions; typically 1–3, occasionally more.

### 8.6 Chain read RPC

**[additive]** `get_release_chain(release_id)` returns an ordered array of the full chain (root → head) with per-node metadata: `release_id`, `name`, `release_type`, `status`, `released_at`, `withdrawn_at`. Enumerated in §27.

Chain rendered in the Release Detail metadata rail via `ReleaseChainCard` (§26).

### 8.7 Chain uniqueness invariant

Only one release may supersede a given release. Enforced by a **[additive]** partial unique index: `UNIQUE (superseded_by_release_id) WHERE superseded_by_release_id IS NOT NULL` — actually, this is inverted; the correct invariant is `UNIQUE (prior_release_id)` on the *prior side*, which is naturally expressed as: for any release A, there is at most one release B with `B.superseded_by_release_id IS NULL AND B.root_release_id = A.root_release_id AND B.id <> A.id AND ...` — too complex to enforce as a single index. Instead: enforce that any release row has at most one row pointing at it via `superseded_by_release_id`, which is a `UNIQUE (superseded_by_release_id) WHERE superseded_by_release_id IS NOT NULL` partial index on the parent side. §27 enumerates this **[additive]** index. Decision recorded as G-10 in §28.

### 8.8 Chain vs. multi-asset bundle

A chain is a temporal supersession relationship between two whole releases. A bundle is a spatial grouping of items within a single release. They are orthogonal:

- Chain: R-001 (Q1 client package) ← R-002 (Q1 client package rev A) ← R-003 (Q1 client package final).
- Bundle: R-042 contains items for `[Site plan v3, HVAC schematic v7, Structural framing v2]`.

Both may co-exist (R-042 above may itself be superseded by R-043 which also has 3 items).

---

## 9. Release types

### 9.1 Enumerated `release_type` values

Recommended set:

| `release_type` | Definition | Typical evidence policy |
|---|---|---|
| `internal` | Internal team consumption; not a contractual milestone | Optional approval; optional review; requirements advisory |
| `preview` | Early preview to client / stakeholders; not final | Recommended approval; recommended review; requirements advisory |
| `client` | Formal client-facing package | Required approval; recommended review; critical requirements should be satisfied |
| `regulatory` | Submission to a regulatory body | Required approval (typically unanimous or with veto approvers per APP 007 §5.6); required review; **all** critical + regulatory-category requirements must be satisfied |
| `final` | Final project publication | Required approval; required review; requirements strongly enforced |
| `patch` | Small correction to a previously released version | Required approval; review optional; requirements re-checked on delta |
| `hotfix` | Emergency correction; expedited path | Required approval (may be single-approver policy); review may be skipped; requirements re-checked on delta only |

### 9.2 Enum vs. tags decision

**Enum, backed by an [additive] `release_type text` column with CHECK constraint, retaining the frozen `channel` free-text column for human-readable labels.**

Rationale:
- Dashboards need to filter and aggregate on a bounded value space — the free-text `channel` cannot support saved-view chips or metric buckets without a controlled dimension.
- Tags impose a many-to-many join for a dimension that is almost always singular ("this is a client package"). Enum captures the primary type cleanly.
- The frozen `channel` column remains for the human string ("Q1 Client Package · v2 rev A"). Mirrors APP 008 §6.2 pattern for `source_kind`.

Decision recorded as G-11 in §28.

### 9.3 Semantics per type: which types require which evidence

APP 009 defines evidence policy per release type. Enforcement layers:

| Policy layer | Enforcement | Which release types |
|---|---|---|
| **DB boundary** (frozen `enforce_release_finalization_prerequisites`) | Every `release_items` row's version must have an `approved` `approval_requests` row | ALL types (frozen; not overridable) |
| **RPC boundary** (**[additive]** wrapper on `finalize_release`) | Per-type additional checks: e.g., regulatory requires all critical + regulatory-category requirements satisfied | `regulatory`, `final` (hard blocks); `client` (soft warning); `internal`, `preview`, `patch`, `hotfix` (advisory) |
| **UI boundary** (Release composer + publish button) | Renders warnings, disables publish when hard block would fire | ALL types (advisory rendering; server is authoritative) |

The DB-boundary invariant is universal — even `hotfix` cannot bypass the approved-approval-request requirement. The RPC-boundary policy layers *additional* per-type checks; it cannot loosen the DB invariant. Decision recorded as G-12 in §28.

### 9.4 Cross-slice with APP 007 approval-readiness

APP 007's `get_approval_readiness(version_id)` returns `{has_approved, blocking_requests[], latest_outcome}`. APP 009's `finalize_release` wrapper consults this per item at publish time. If any item fails, the RPC raises before the frozen trigger even fires. This is defense-in-depth — the frozen trigger is authoritative, but the wrapper produces a clearer error message and enables the UI to preflight before the user clicks Publish.

### 9.5 Cross-slice with APP 008 requirement-readiness

APP 008's `get_release_readiness_for_version(version_id)` returns `{applicable_count, satisfied_count, partial_count, not_satisfied_count, unassessed_count, critical_unsatisfied_count, critical_unassessed_count}`. APP 009's `finalize_release` wrapper consults this per item at publish time and, per the release_type policy above, may hard-block, soft-block, or advise.

### 9.6 Reserved release types

Reserved for future waves (name-locked; not in v1 enum):

- `staged` — reserved for a scheduled-publish workflow (§3.2).
- `snapshot` — reserved for AI-assisted per-milestone auto-releases (§21).
- `demo` — reserved for demo-environment publishing.

These are not in the v1 CHECK constraint. Adding them is an **[additive]** re-freeze. Decision recorded as G-13 in §28.

### 9.7 Release type is mutable while `draft`, frozen once `released`

While `draft`, the composer permits changing `release_type` (subject to `release.create` capability). Once `released`, the type is immutable (frozen `enforce_release_status_via_rpc` blocks all column changes except those specifically permitted; **[additive]** `release_type` is proposed to be added to the immutable set at the same time it is introduced).

---

## 10. Release Detail architecture

Full-page route: `/workspace/:ws_id/project/:proj_id/release/:release_id`.

Also resolvable by URL-safe code (see §15): `/deep/release/:code`.

### 10.1 Layout

```
Header:   ← Back · [Type chip] · Release name · [Status badge] · Published <relative> by <name> · ⋮ menu
Region A: Item bundle summary card (compact list of items with per-item version chip)
Region B: Right rail (metadata: type, status, effective_at, published_at, published_by, chain position, actions)
Tabs:     Overview | Evidence | Comparison | History | Notes
```

### 10.2 Header components

- **Type chip** — new primitive `ReleaseTypeChip` (see §26); reuses `ScopeChip` variant from APP 008.
- **Release name** — human name from frozen `releases.name`.
- **Status badge** — `StateBadge` (APP 005 primitive) with additive union members: `draft`, `released`, `withdrawn` (reserved: `scheduled`, `superseded`).
- **Published relative** — "Published 3 days ago by Alice" (falls back to "created by Alice" if draft; falls back to "Unknown" if `published_by_profile_id IS NULL AND created_by_profile_id IS NULL`).
- **⋮ menu** — Publish (if draft + capable) / Withdraw (if released + capable) / Copy link / Copy code / Bookmark / Export evidence PDF (v2).

### 10.3 Body tabs

**Overview**

- One-liner: "Release R-042 · client type · 3 items · published 2026-08-01 by Alice Smith · currently released."
- Bundle card: list of `release_items` with per-item cards showing `[Asset thumbnail] Asset name · Version v3 · Published 2026-07-28`. Click asset → APP 003 Design Workspace. Click version → APP 004 Viewer with `?release=<id>` context banner.
- Compact evidence summary chip strip: "8 approvals · 40 requirements · 2 reviews · No warnings" (from `evidence_snapshot` or live).
- Notes preview (first 500 chars of `releases.notes`; expands on click).

**Evidence** (see §6 for full breakdown)

- Approvals section — per-item approval evidence with click-through to APP 007 Approval Detail.
- Requirements section — per-item requirement readiness with click-through to APP 008 Requirement Detail; delta indicator for any requirement whose status has changed since publish.
- Reviews section — per-item completed reviews with click-through to APP 006 Review Detail.
- "Refresh live state" affordance — re-fetches upstream and re-renders the delta indicators without mutating the snapshot.

**Comparison**

- Delta vs. prior release in the chain (if any):
  - Items added / removed / version-bumped.
  - Evidence delta (any approvals gained/lost, any requirements status flipped, any reviews added).
- If no prior release: empty state "This is the first release in the chain."
- New primitive: `ReleaseComparisonView` (see §26).

**History**

- Chronological `activity_events` feed filtered on `subject_kind='release' AND subject_id=<id>`.
- Renders: `release.created`, `release.item_added`, `release.item_removed`, `release.finalized`, `release.withdrawn` (frozen event types).
- Reuses APP 006 timeline shell if extracted; otherwise a bespoke component.

**Notes**

- Free-form `releases.notes` (may become rich text in v2 per G-14).
- Read-only while `released` per §5.7 / G-2 (edit affordance hidden even though RLS allows).
- v2: **[additive]** reserved event `release.notes_updated` for tracking post-release note edits if that policy loosens.

### 10.4 Right rail (metadata)

- Type chip.
- Status badge.
- `effective_at` (if set; else "Not scheduled").
- `released_at` + `published_by_profile_id` (falls back to `created_by_profile_id`).
- `channel` (frozen free-text field, if set).
- Supersession chain via `ReleaseChainCard`: prior ← this → next; click any node → jump.
- Actions: Publish (if `draft` + `release.finalize` capable); Withdraw (if `released` + `release.withdraw` capable); Copy link.
- Reserved AI slot: `<AISlot kind="release-summary" />` (empty in v1; see §21).

### 10.5 Empty states

- No items in draft → "Add an item to publish this release" affordance (opens item-picker modal).
- No notes → "Add release notes" affordance (draft only).
- No supersession chain → hide the ReleaseChainCard (do not render an empty shell).
- No evidence snapshot on a `released` release (legacy row) → banner "Evidence snapshot not captured; showing live upstream state."

### 10.6 Loading states

- Full-page shell renders immediately with skeleton chips for badges and skeleton bars for tabs.
- Header + Overview load eagerly from `get_release(release_id)` **[additive]** read RPC.
- Evidence / Comparison tabs lazy-load on click via `get_release_evidence(release_id)` and `get_release_comparison(release_id)` respectively.
- History tab lazy-loads on click via `list_release_activity(release_id, cursor)`.

### 10.7 Error states

- 404: "This release does not exist." — offer "Back to Releases".
- 403: "You do not have access to this release." — offer "Back to project" (never leak existence).
- Publish-time failure (frozen trigger raised): render the raw trigger message ("release cannot transition to released: N items reference versions without an approved approval_request") in a toast + inline banner in the composer with per-item chips highlighting the offenders. Do not swallow the DB error.
- Withdraw-time failure: standard retry surface reused from APP 002.

### 10.8 Publish confirmation

Publishing is a high-consequence action. Confirmation:

- Modal titled "Publish this release?"
- Body: "This publishes N items as `client` type. Once published, items and status become immutable. You may still withdraw the release later, but you cannot un-publish."
- Warnings surface here: any per-item requirement gaps per the release-type policy (§9).
- Buttons: Cancel · Publish.
- Confirmation is required for `release.finalize` per D-9 style (matches APP 007 confirm-on-decide pattern).

### 10.9 Withdraw confirmation

- Modal titled "Withdraw this release?"
- Body: "This marks the release as withdrawn. Historical evidence is preserved. Downstream consumers may be notified."
- Mandatory `withdrawn_reason` text area (min 3 chars).
- Buttons: Cancel · Withdraw.

### 10.10 Reusable primitives

- `ReleaseDetailShell` — full-page shell wrapping the header + tabs (§26).
- `ReleaseEvidenceCard` — Evidence tab per-item card (§26).
- `ReleaseComparisonView` — Comparison tab body (§26).
- `ReleaseChainCard` — inline chain viz for the metadata rail (§26).
- `ReleaseTypeChip` — type indicator with color tokens (§26).

---

## 11. Dashboard architecture

Two levels, mirroring APP 006 / APP 007 / APP 008 dashboard patterns:

- **Workspace releases dashboard** — `/workspace/:ws_id/releases` — cross-project inbox.
- **Project releases dashboard** — `/workspace/:ws_id/project/:proj_id/releases` — project-scoped.

### 11.1 Views

- `all` — all releases the caller can view (any status).
- `recent` — sorted by `updated_at desc`, all statuses.
- `scheduled` — `status='scheduled'` (reserved; empty in MVP).
- `drafts` — `status='draft'` (only drafts).
- `released` — `status='released'` (published, not withdrawn).
- `superseded` — head-of-chain not this release, i.e., this release has a `superseded_by_release_id` set (reserved-state variant: `status='superseded'`).
- `withdrawn` — `status='withdrawn'`.
- `by_type` — grouped by `release_type`.
- `bookmarks` — reuse `user_bookmarks` (APP 006) with `entity_kind='release'`.
- `saved:<id>` — reuse `user_saved_views` (APP 006) with `scope='releases'`.
- `overdue_scheduled` — `status='scheduled' AND effective_at < now()` (reserved; empty in MVP).

Decision recorded as G-15 in §28.

### 11.2 Card layout

Each release card:

```
[Type chip] Release name                          [Status badge]
Channel · N items · Published <relative> by <name>
                                                  Evidence: 8 apps · 40 reqs · 2 rvws
```

Compact mode (dense list): 32px row height, chips only.

### 11.3 Columns (table view)

`Name · Type · Status · Items · Channel · Published at · Published by · Evidence summary · Last updated`.

Column set stable within slice; sorting server-side.

### 11.4 Filter bar

Multi-select chips for `status`, `release_type`, `published_by`, `project` (workspace scope only), `has_evidence_gaps` (derived). Free-text search in `name` and `channel` (§13.1). Date range for `released_at`. Cursor pagination via `(updated_at, id)` opaque cursor.

New primitive: `ReleaseFilterBar` (§26).

### 11.5 Inbox counts

NavRail badge: **[additive]** `get_release_inbox_count(ws_id)` returning `{drafts_assigned_to_me, scheduled_today, overdue_scheduled}`. Displayed as compact tri-digit chip (99+ cap).

- `drafts_assigned_to_me` — drafts created by the caller (frozen `created_by_profile_id = caller`).
- `scheduled_today` — reserved (`status='scheduled' AND effective_at::date = current_date`); zero in MVP.
- `overdue_scheduled` — reserved; zero in MVP.

### 11.6 Keyboard shortcuts (additive to APP 005/006/007/008)

- `N` — new release (opens composer at `?compose=1`); context-scoped to release dashboards (composes additively with APP 008 `N` — filter parser routes by page context).
- `P` — publish selected draft (if selection in table view + capable); opens publish confirmation.
- `W` — withdraw selected released release (if selection + capable); opens withdraw confirmation.
- `/` — focus search input (composes with APP 008 `/`).

No conflict with APP 005 (`C`/`P`/`Esc` — `P` here is publish in release dashboard context, not pin in comment context; scoped by page), APP 006 (`R`/`E`/`Shift+Enter`), APP 007 (`A`/`X`/`Shift+A`), or APP 008 (`N`/`E`/`A`). The `P` collision with APP 005 is resolved by page context: `P` in release dashboard = publish; `P` in comment panel = pin. Decision recorded as G-16 in §28.

### 11.7 Bulk actions (v1 conservative)

- **Bookmark / unbookmark**
- **Discard draft** (permission-gated; only for zero-item drafts; confirm dialog) — subject to G-4 policy.
- (No bulk publish — publishing is a high-consequence per-release act. No bulk withdraw — same.)

### 11.8 Metrics strip

Above the table (collapsible, off by default):
- Total released count (all-time).
- Trailing 30d released count.
- Withdrawn rate (trailing 30d withdrawn / trailing 30d released).
- Avg items per release (trailing 30d).
- Median time-to-publish (draft-creation to `released_at`).

Delivered by **[additive]** RPC `get_project_release_metrics(project_id)` / `get_workspace_release_metrics(ws_id)` (§27).

### 11.9 Empty states

- No releases yet → "No releases yet. Publish your first release from a version." with a link to the project's Design Workspace.
- No drafts → "No drafts. Start a new release from a version card."
- No withdrawn → "No withdrawn releases." (positive-framed empty state).

---

## 12. Design Workspace integration

APP 003's Design Workspace already has a RightPanel tab strip (per APP 003 architecture). APP 009 additively registers a **Releases** tab.

### 12.1 The Releases tab

- Route: `?tab=releases` on `/workspace/:ws_id/project/:proj_id/asset/:asset_id` (or the equivalent version-scoped route).
- Body: two sections:
  - **Releases of this asset** — all releases that include any version of the current asset. One card per release; grouped by `release_type`; sorted by `released_at desc`.
  - **Releases of this version** — if a version is in context, filter to releases where `release_items.version_id = current_version_id`.
- Empty state: "This asset has never been released. Publish a release from a version." with a Publish quick-action.

### 12.2 Publish quick action

Gated by:
1. Caller has `release.create` capability.
2. Caller has `release.finalize` capability (for the publish confirmation).
3. Current version has an `approved` `approval_requests` row (frozen invariant — otherwise `finalize_release` will raise).

If any gate fails, the button is disabled with a tooltip explaining what is missing. Clicking (when enabled) opens a slim composer modal pre-filled with the current version as the single item, prompting for `release_type`, `name`, and optional `notes`.

The quick-action does not skip governance; it just simplifies the composition. All frozen triggers still fire.

### 12.3 Version card badge

Every version card in the Design Workspace's version list gets an additive `Released` badge if the version appears in any `released`-status release. Click badge → popover listing releases; single-release case click-through to Release Detail; multi-release case click-through to a filtered dashboard view.

### 12.4 Timeline of releases per version

Optional embed on the version card expansion: a compact `ReleaseChainCard`-style stripe showing all releases (across the chain) that included this version, sorted chronologically. Deferred to v1.1 if scope is tight.

### 12.5 Read-only historical view

The Releases tab in the Design Workspace is read-only for `released` and `withdrawn` releases (matching §5.7 policy). Drafts may be edited from either the workspace tab or the full Release Detail page; edits sync via query invalidation.

### 12.6 Design Workspace ↔ Release context banner

When the caller opens a version from the Release Detail via `?release=<id>`, the Design Workspace renders a subtle top banner: *"In release context — R-042 · client · Published 3 days ago"*, with a "Back to release" link. Mirrors APP 006/APP 007/APP 008 context banner pattern. Additive to APP 003. Decision recorded as G-17 in §28.

---

## 13. Version interaction

### 13.1 Version selector integration

APP 003's version selector surfaces the version list for an asset. APP 009 additively:

- Decorates each version row with a "Released" chip if it appears in any `released` release.
- Adds a hover-tooltip listing the release names (up to 3, "and N more").

APP 003 is not modified beyond an additive slot; APP 009 supplies the render.

### 13.2 State badge on version cards

- Existing frozen version states: `draft`, `published`, `superseded`, `deprecated` (per APP 004 STATE_MACHINES.md §12).
- APP 009 does NOT add a "released" state to `asset_versions.status` (that would violate the independence invariant — STATE_MACHINES.md line 411).
- APP 009 layers an additional `Released` chip *alongside* the version's `StateBadge` (not replacing it). A version can be `published` AND `Released` (via inclusion in a released release). A version can be `published` AND NOT `Released` (never released). A version can be `deprecated` AND `Released` (if it was released before being deprecated — historical).

### 13.3 Viewing the release from the version

Version card → hover Released chip → popover with release name + click-through to Release Detail.

### 13.4 Viewing the version from the release

Release Detail Overview → per-item version chip → click → APP 004 Viewer with `?release=<id>` context banner.

### 13.5 Symmetry with approvals

APP 007 already ships the version-side integration for approvals (per APP 007 §7 / §10). APP 009's version-side integration for releases follows the same pattern, using the same `StateBadge`-adjacent chip convention.

### 13.6 Version deletion is impossible (frozen invariant)

Since `asset_versions` rows are immutable and never deleted (APP 004 invariant), a `release_items.version_id` FK is always resolvable. No dead-link handling needed.

---

## 14. Navigation

### 14.1 NavRail entries

New **workspace-level** NavItem: `Releases` — routes to `/workspace/:ws_id/releases`. Badge: `get_release_inbox_count(ws_id).drafts_assigned_to_me` (99+ cap).

New **project-level** NavItem: `Releases` — routes to `/workspace/:ws_id/project/:proj_id/releases`. Badge: count of `released`-status releases in trailing 30d (light informational; may be dropped in favor of an empty badge if the count is noisy). Decision recorded as G-18 in §28.

### 14.2 Position in nav order

Recommended nav order (additive):

- **Workspace:** Projects · Reviews · Approvals · Requirements · **Releases** · Bookmarks · Settings.
- **Project:** Overview · Design · Reviews · Approvals · Requirements · **Releases** · Activity.

Preserves the pipeline grouping: Reviews → Approvals → Requirements → Releases. Matches APP 008 §19.2 recommendation. Decision recorded as G-19 in §28.

### 14.3 Route table

```
/workspace/:ws_id/releases                                                   workspace dashboard
/workspace/:ws_id/project/:proj_id/releases                                  project dashboard
/workspace/:ws_id/project/:proj_id/release/:release_id                       Release Detail
/workspace/:ws_id/project/:proj_id/release/:release_id?tab=evidence          Release Detail (Evidence tab)
/workspace/:ws_id/project/:proj_id/release/:release_id?tab=comparison        Release Detail (Comparison tab)
/deep/release/:id                                                            deep-link resolver (UUID)
/deep/release/:code                                                          deep-link resolver (code form)
```

### 14.4 Design Workspace RightPanel tab registration

Add a **Releases** tab to the Design Workspace RightPanel tab strip (APP 003's shell). Reads via **[additive]** `list_releases_for_asset(asset_id)` and **[additive]** `list_releases_for_version(version_id)` RPCs. Click through → Release Detail.

**[additive]** — extends APP 003's RightPanel tab strip. Does not modify APP 003 code beyond a new tab registration.

---

## 15. Deep links

### 15.1 Deep-link routes

Extends APP 002's `DeepLinkResolver` additively:

```
/deep/release/:id           → Release Detail (UUID form)
/deep/release/:code         → Release Detail (code form; e.g., a URL-safe display code)
```

The code form uses a display code (see §15.4) generated per release. Because release names are free-text (frozen `releases.name`), the code is derived from the release-per-project sequence number or a slugified name+suffix. Decision recorded as G-20 in §28.

### 15.2 Copy-link primitive

`useCopyLink` (APP 005, extended by APP 006/APP 007/APP 008) receives two more `LinkKind` values:

- `'release'` — emits `/deep/release/<id>`.
- `'release-code'` — emits `/deep/release/<code>?project=<id>`.

Purely additive.

### 15.3 Cross-slice linking

Any surface may cite a release by:
- Rendering the name/code as a `<ReleaseRef code="R-042" />` inline component (new primitive).
- Emitting a Copy link / Copy code action from any menu.
- Comment mentions may reference a release in body text (no dedicated `target_release_id` on comments — recommend against per foundational premise; releases do not collect discussion).
- Approval decision reason free-text mention (unchanged from APP 007).
- Requirement description free-text mention (unchanged from APP 008).
- Decision composer citation via frozen `decisions.resulting_release_id` (Migration 008 completes this deferred FK).

### 15.4 Release display code

A per-project sequence-based code, generated at `create_release` time (**[additive]** convention): `R-NNN` where `NNN` is the next per-project sequence. Storage:

- Option A: derive on the fly from the ordinal of `releases.created_at asc` per project (no storage; cheap read).
- Option B: **[additive]** `releases.code text` column with per-project unique constraint and generation under an xact lock (mirrors APP 008 `requirements.code` pattern).

Recommended: Option B for stability (Option A's ordinal shifts if a draft is deleted, breaking deep links). Decision recorded as G-21 in §28.

### 15.5 Backward links

The Release Detail already surfaces:
- Related approvals (Evidence tab).
- Related reviews (Evidence tab).
- Related requirements (Evidence tab).
- Related decisions (via `decisions.resulting_release_id`; not shown by default; deferred to v1.1).
- Prior release in chain (metadata rail).
- Superseding release in chain (metadata rail).

---

## 16. URL grammar

### 16.1 Owned by APP 009

| Param | Values | Meaning |
|---|---|---|
| `?view=<all \| recent \| scheduled \| drafts \| released \| superseded \| withdrawn \| by_type \| bookmarks \| saved:<id> \| overdue_scheduled>` | string | Dashboard view selector |
| `?status=<comma-list>` | subset of `draft,scheduled,released,superseded,withdrawn` | Status filter |
| `?type=<comma-list>` | subset of `internal,preview,client,regulatory,final,patch,hotfix` | Type filter |
| `?assignee=<profile_id>` | uuid | `published_by` filter (workspace scope) |
| `?asset=<design_asset_id>` | uuid | Filter to releases including this asset |
| `?date_from=<iso-date>` | date | Released-at lower bound |
| `?date_to=<iso-date>` | date | Released-at upper bound |
| `?cursor=<opaque>` | string | Pagination cursor |
| `?tab=<overview \| evidence \| comparison \| history \| notes>` | keyword | Detail tab selector |
| `?compose=1` | flag | Open composer modal |
| `?project=<project_id>` | uuid | Code-form deep-link disambiguator |
| `?release=<id>` | uuid | Workspace ↔ Release context flag (set when navigating from a release into the Design Workspace) |
| `?item=<version_id>` | uuid | Focus a specific item within Release Detail |

### 16.2 Non-collision statement

Confirmed non-colliding with:

- APP 003 `?discipline`, `?from`.
- APP 005 `?comment`, `?annotation`, `?comments`, `?tab=comments`.
- APP 006 `?review`.
- APP 007 `?approval`, `?participant`.
- APP 008 `?priority`, `?source`, `?category`, `?scope`, `?code`, `?requirement`.

Notes:
- `?tab` values are per-detail-page scoped — the Release Detail's tab set (`overview | evidence | comparison | history | notes`) does not intersect any prior slice's tab set.
- `?assignee` is APP 008-and-APP-009-shared but disambiguated by page context (dashboard). In release context, `?assignee` means `published_by`; in requirement context, it means `owner`. Parser routes by dashboard slice. Decision recorded as G-22 in §28.
- `?asset` is release-specific; APP 003 uses `?discipline` for asset filtering — no collision.
- `?date_from` / `?date_to` are new; no prior slice used date-range params.
- `?type` is release-specific; APP 008 uses `?source` / `?category`; APP 006/APP 007 use `?policy`. No collision.
- `?status` values are enum-namespaced per slice (frozen `WorkflowState` value pools disjoint across slices; see APP 008 G-12 for the parallel discussion).
- `?item` is release-specific; not used by any other slice.

Decision recorded as G-22 in §28.

### 16.3 Deep-link routes

```
/deep/release/:id                        → Release Detail (UUID)
/deep/release/:code?project=<id>         → Release Detail (code form)
```

---

## 17. Query architecture

### 17.1 Query key namespace tree

Append-only additions to `qk`:

```ts
qk.releasesList(scope, view, filters)              // dashboard
qk.releasesWorkspaceDashboard(wsId, view)
qk.releasesProjectDashboard(projId, view)
qk.release(id)                                     // Detail read
qk.releaseByCode(projId, code)                     // Deep-link resolver
qk.releaseChain(id)                                // Supersession chain
qk.releaseEvidence(id)                             // Evidence tab
qk.releaseComparison(id)                           // Comparison tab
qk.releaseHistory(id)                              // History tab
qk.releaseItems(id)                                // Overview + Detail body
qk.releaseMetrics(scope)                           // Metrics strip
qk.releaseInboxCount(wsId)                         // NavRail badge
qk.releasesForAsset(assetId)                       // Design Workspace tab (asset scope)
qk.releasesForVersion(versionId)                   // Design Workspace tab (version scope)
```

Reused (unchanged) from prior slices:
- `qk.savedViews(wsId, 'releases')` — APP 006.
- `qk.bookmarks(wsId, 'release')` — APP 006.
- `qk.projectParticipants(id)` — APP 002.
- `qk.assetVersion(id)`, `qk.designAsset(id)` — APP 003.
- `qk.approvalReadiness(versionId)` — APP 007 (consumed by publish gate).
- `qk.releaseReadinessForVersion(versionId)` — APP 008 (consumed by publish gate).

### 17.2 RPC → query key mapping

| RPC | Query key | Kind | Source |
|---|---|---|---|
| `finalize_release` (frozen AUTH 008) | invalidates below | Write | frozen |
| `withdraw_release` (frozen AUTH 008) | invalidates below | Write | frozen |
| `create_release` **[additive]** | invalidates below | Write | additive |
| `add_release_item` **[additive]** | invalidates below | Write | additive |
| `remove_release_item` **[additive]** | invalidates below | Write | additive |
| `reorder_release_items` **[additive]** | invalidates below | Write | additive |
| `discard_release_draft` **[additive]** | invalidates below | Write | additive (subject to G-4) |
| `get_release` **[additive]** | `qk.release` | Read | additive |
| `get_release_by_code` **[additive]** | `qk.releaseByCode` | Read | additive |
| `get_release_chain` **[additive]** | `qk.releaseChain` | Read | additive |
| `get_release_evidence` **[additive]** | `qk.releaseEvidence` | Read | additive |
| `get_release_comparison` **[additive]** | `qk.releaseComparison` | Read | additive |
| `list_release_activity` **[additive]** | `qk.releaseHistory` | Read | additive |
| `list_release_items` **[additive]** | `qk.releaseItems` | Read | additive |
| `list_releases_dashboard` **[additive]** | `qk.releasesList` | Read | additive |
| `get_release_inbox_count` **[additive]** | `qk.releaseInboxCount` | Read | additive |
| `get_project_release_metrics` **[additive]** | `qk.releaseMetrics(project)` | Read | additive |
| `get_workspace_release_metrics` **[additive]** | `qk.releaseMetrics(workspace)` | Read | additive |
| `list_releases_for_asset` **[additive]** | `qk.releasesForAsset` | Read | additive |
| `list_releases_for_version` **[additive]** | `qk.releasesForVersion` | Read | additive |

### 17.3 Invalidation matrix

| Mutation | Invalidates |
|---|---|
| `create_release` | `releasesList(*)`, `releaseInboxCount`, `releaseMetrics(project)` |
| `add_release_item` | `release(id)`, `releaseItems(id)`, `releaseEvidence(id)` (evidence unfrozen while draft — recomputes on read), `releasesForAsset(asset)`, `releasesForVersion(version)` |
| `remove_release_item` | Same as add_release_item |
| `reorder_release_items` | `release(id)`, `releaseItems(id)` |
| `finalize_release` | `release(id)`, `releaseEvidence(id)`, `releaseComparison(id)`, `releaseHistory(id)`, `releasesList(*)`, `releaseInboxCount`, `releaseMetrics(project)`, `releasesForAsset(each asset in bundle)`, `releasesForVersion(each version in bundle)` — plus cross-slice invalidations per §18 |
| `withdraw_release` | Same as finalize (except no evidence recompute — snapshot preserved) |
| `discard_release_draft` | `release(id)` (removed), `releasesList(*)`, `releaseInboxCount` |

### 17.4 Cursor pagination discipline

All dashboard reads use opaque `(updated_at desc, id desc)` cursors — same pattern as APP 006 / APP 007 / APP 008. Server never accepts an offset. Client passes the last-seen cursor back on load-more. Empty cursor = start of list.

### 17.5 Optimistic updates

**None in v1.** Every mutation is round-trip. `finalize_release` and `withdraw_release` are deliberately non-optimistic because the DB may raise on trigger failure and an incorrect optimistic value would corrupt every viewer's local state. Also, `finalize_release` writes the evidence snapshot as a side effect — the snapshot content is server-computed and cannot be pre-guessed. Decision recorded as G-23 in §28.

### 17.6 Stale time policy

- Dashboards: 60 seconds (matches APP 006/APP 007 pattern).
- Release Detail: 30 seconds.
- Evidence tab: 5 minutes (evidence snapshot is immutable; live-delta re-fetch is manual via "Refresh live state").
- Metrics: 5 minutes.

---

## 18. Cache ownership

Which slice owns which query key, and what to invalidate on cross-slice events.

### 18.1 Ownership matrix

| Query key | Owning slice | Consumers |
|---|---|---|
| `qk.release(id)` | APP 009 | Release Detail, Design Workspace Releases tab |
| `qk.releaseChain(id)` | APP 009 | Release Detail metadata rail |
| `qk.releaseEvidence(id)` | APP 009 | Release Detail Evidence tab; also read live upstream on tab open |
| `qk.releasesList(...)` | APP 009 | Dashboards |
| `qk.releasesForAsset(id)` | APP 009 | Design Workspace RightPanel |
| `qk.releasesForVersion(id)` | APP 009 | Design Workspace RightPanel |
| `qk.approvalReadiness(vid)` | APP 007 | APP 009 publish gate |
| `qk.releaseReadinessForVersion(vid)` | APP 008 | APP 009 publish gate |
| `qk.review(id)` | APP 006 | APP 009 Evidence tab (informational click-through) |
| `qk.approvalRequest(id)` | APP 007 | APP 009 Evidence tab |
| `qk.requirement(id)` | APP 008 | APP 009 Evidence tab |

### 18.2 Cross-slice invalidations on `release.finalized`

When APP 009 emits `release.finalized`, downstream and lateral caches invalidate:

| Cache | Reason |
|---|---|
| `qk.approvalRequest(each approval_request_id in evidence)` | APP 007 detail now shows "released" side-effect flag |
| `qk.approvalsForVersion(version)` | APP 007 version tab shows release status |
| `qk.requirement(each requirement_id applicable to released version)` | APP 008 detail shows "released versions covered" chip |
| `qk.releaseReadinessForVersion(version)` | APP 008 read reflects new release |
| `qk.designAsset(asset)` | APP 003 asset card shows Released chip |
| `qk.assetVersion(version)` | APP 003 version card shows Released chip |

### 18.3 Cross-slice invalidations on `release.withdrawn`

Same set as `release.finalized` — every downstream consumer that indicated "released" now needs to reflect "withdrawn" (which may or may not un-set the Released chip depending on whether other releases still cover the version).

### 18.4 Cross-slice invalidations on `release.created` / `release.item_added` / `release.item_removed`

Narrow scope — the draft is not yet public evidence:

- Only APP 009's own caches (`releasesList`, `release(id)`, `releaseItems(id)`, `releaseInboxCount`).
- No APP 003/APP 006/APP 007/APP 008 invalidation. Drafts are not counted as "released" anywhere upstream.

### 18.5 Reverse invalidations (upstream → APP 009)

- **APP 007 `approval.approved` on a version referenced by a draft release**: invalidate `qk.release(id)` for any draft containing that version (publish gate may unblock). Also invalidate `qk.approvalReadiness(vid)`.
- **APP 007 `approval.rejected` / `expired` / `cancelled`**: symmetric — publish gate may re-block.
- **APP 008 `requirement.assessed` on a version referenced by a draft release**: invalidate `qk.releaseReadinessForVersion(vid)` and `qk.release(id)` for any draft containing that version.
- **APP 006 `review.completed` on a version referenced by a draft release**: no APP 009 invalidation required (reviews are advisory, not gating).
- **APP 004 version publish**: `releasesForAsset(asset)` may change if the newly-published version becomes an eligible release candidate; invalidate.

### 18.6 Ownership summary rule

APP 009 owns everything under `qk.release*`. APP 007 owns `approvalReadiness`. APP 008 owns `releaseReadinessForVersion`. No slice writes into another's cache directly — invalidations flow through the TanStack Query invalidation matrix at mutation-time or on realtime events (once realtime is unfrozen for releases; see §23).

---

## 19. Capability model

### 19.1 Frozen capability keys (AUTH 008 + PERMISSIONS.md §2.12)

- `release.view` — read releases and release items (frozen SELECT policies on both tables).
- `release.create` — INSERT / UPDATE / DELETE on `release_items` while parent is `draft`; INSERT on `releases`; UPDATE metadata on `releases` (frozen policies).
- `release.finalize` — invoke `finalize_release` RPC (frozen check inside RPC body).
- `release.withdraw` — invoke `withdraw_release` RPC (frozen check inside RPC body).

### 19.2 Default role mapping (PERMISSIONS.md §5)

| Capability | `lead` | `contributor` | `reviewer` | `approver` | `observer` |
|---|---|---|---|---|---|
| `release.view` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `release.create` | ✓ | ✓ | — | — | — |
| `release.finalize` | ✓ | — | — | — | — |
| `release.withdraw` | ✓ | — | — | — | — |

Workspace admin: `release.view` only (per admin-override rule in PERMISSIONS.md); admin may override to finalize/withdraw only via a re-freeze — not proposed. Rationale for the concentrated `finalize` / `withdraw` grants: release is a high-consequence transition that should have concentrated accountability (PERMISSIONS.md line 208).

### 19.3 [additive] capability proposals

**None new for the v1 write surface.** The 4 frozen keys cover every product action:
- `release.view` for read.
- `release.create` for draft composition + item management + metadata edits.
- `release.finalize` for publish.
- `release.withdraw` for withdraw.

Reserved for future waves (name-locked; not wired in APP 009):

| Capability | Purpose |
|---|---|
| `release.schedule` | Reserved — gate for the future `schedule_release` RPC transitioning `draft → scheduled` |
| `release.supersede` | Reserved — gate for the future `create_release_superseding` RPC that chains a new release from a prior one |
| `release.ai_suggest` | Reserved — gate AI-assisted release-notes generation (§21) |
| `release.ai_classify` | Reserved — gate AI-assisted `release_type` classification (§21) |
| `release.audit_export` | Reserved — gate for future PDF/CSV export of evidence bundle |

Decision recorded as G-24 in §28.

### 19.4 Cross-slice capability check: publishing requires evidence

The frozen `enforce_release_finalization_prerequisites` trigger enforces approved-approvals at the DB boundary — this is the primary check. In addition, per §9.3, the **[additive]** `finalize_release` wrapper (or a thin outer RPC) may perform per-release-type checks reading `get_approval_readiness` and `get_release_readiness_for_version`. These reads are gated by their own slices' capabilities (`approval.view` and `requirement.view`), which any project participant already holds by default.

The publish action does NOT introduce a new capability check beyond `release.finalize` — the evidence checks are data checks (does the data exist?), not permission checks (may the caller see the data?).

### 19.5 Enforcement points

| Check | Where | What raises |
|---|---|---|
| `release.view` for SELECT | frozen RLS `releases_select` + `release_items_select` | RLS-hidden (empty result) |
| `release.create` for INSERT/UPDATE on `releases` and `release_items` | frozen RLS policies | RLS 42501 |
| `release.finalize` for status → `released` | frozen inside `finalize_release` RPC body | 42501 |
| `release.withdraw` for status → `withdrawn` | frozen inside `withdraw_release` RPC body | 42501 |
| Every-item-approved invariant | frozen `enforce_release_finalization_prerequisites` trigger | 23514 |
| ≥ 1 item invariant | frozen `enforce_release_finalization_prerequisites` trigger | 23514 |
| Draft-only item mutation | frozen `enforce_release_items_parent_draft_mutation` trigger | 23514 |
| Immutability of `id/workspace/project/created_by` | frozen `enforce_release_status_via_rpc` trigger | 23514 |
| RPC-only status transitions | frozen `enforce_release_status_via_rpc` + GUC | 42501 |
| Per-release-type policy (soft) | **[additive]** RPC wrapper (§9.3) | Custom RAISE at RPC layer |

---

## 20. Event ownership

### 20.1 Frozen event vocabulary (EVENT_MODEL.md §4.12 + AUTH 008 RPCs)

- `release.created` — emitted on draft creation. Payload: `{name}`. Subject: `release / project`. **Not** currently emitted by any frozen RPC (the frozen `finalize_release` and `withdraw_release` are the only shipped RPCs; `create_release` is not yet in the frozen surface — the emit happens in the **[additive]** `create_release` RPC per §27). Name is frozen in EVENT_MODEL.md line 185.
- `release.item_added` — emitted when an item is attached. Payload: `{release_id, asset_id, asset_name, version_id, version_sequence}`. Subject: `release_item / project`. Frozen name (EVENT_MODEL.md line 186); emitter is the **[additive]** `add_release_item` RPC per §27.
- `release.item_removed` — emitted when an item is detached. Payload: `{release_id, asset_id, version_id}`. Subject: `release_item / project`. Frozen name (EVENT_MODEL.md line 187); emitter is the **[additive]** `remove_release_item` RPC per §27.
- `release.finalized` — emitted on transition to `released`. Payload: `{name, item_count, channel}` (from frozen AUTH 008 `finalize_release` body). Subject: `release / project`. Frozen name + emitter.
- `release.withdrawn` — emitted on transition to `withdrawn`. Payload: `{reason}` (from frozen AUTH 008 `withdraw_release` body). Subject: `release / project`. Frozen name + emitter.

APP 009 preserves all frozen names byte-for-byte. Payload extensions are backward-compatible (§20.4).

### 20.2 Past-tense discipline

All event names use past-tense verbs (per EVENT_MODEL.md §2 verb convention): `created`, `added`, `removed`, `finalized`, `withdrawn`. **[additive]** future names must follow the same discipline: `superseded`, `scheduled`, `notes_updated`, `audit_exported`, `recalled`.

### 20.3 Subject kind convention

- Release-scoped events: `subject_kind='release'`, `subject_id=release.id`.
- Item-scoped events: `subject_kind='release_item'`, `subject_id=release_item.id`.
- Scope: `project` (all release events are project-scoped, per Migration 008 composite scoping).

### 20.4 [additive] payload extensions (backward-compatible)

Per APP 007 §17.1 precedent, payload extensions are additive and consumers ignore unknown keys.

| Event | [additive] payload keys |
|---|---|
| `release.created` | `release_type`, `code` (once §15.4/G-21 is decided), `created_by_profile_id` |
| `release.item_added` | `release_type`, `item_id`, `sort_order`, `notes_snippet` (first 200 chars) |
| `release.item_removed` | `release_type`, `item_id` |
| `release.finalized` | `release_type`, `published_by_profile_id`, `approved_request_ids[]`, `requirement_readiness` (aggregate from evidence snapshot), `review_count`, `superseded_prior_release_id` (if chaining) |
| `release.withdrawn` | `release_type`, `withdrawn_by_profile_id` |

### 20.5 Reserved event names (name-locked; no emitter in APP 009)

Per EVENT_MODEL.md §D3 (line 422) and §D7 (line 426), these are already frozen in the vocabulary as reserved:

- `release.scheduled` — reserved for the future scheduled-publication workflow (§3.2). No emitter in APP 009 v1.
- `release.superseded` — reserved for automatic release supersession (§3.2, §8.4). No emitter in APP 009 v1; if a manual supersession is introduced via **[additive]** `create_release_superseding` RPC, this event fires (deferred).

Additional reserved names (name-locked in this document; not yet in EVENT_MODEL.md; will be added via **[additive]** doc update in the Backend Proposal):

- `release.notes_updated` — reserved for post-release note edits (§10.3 Notes tab v2).
- `release.audit_exported` — reserved for PDF/CSV export of evidence.
- `release.recalled` — reserved for a stronger form of withdrawal (e.g., recall due to safety issue); distinct from `withdrawn` for audit tone.
- `release.ai_suggested` — reserved for AI-assisted release-notes generation.
- `release.ai_classified` — reserved for AI-assisted `release_type` classification.

Decision recorded as G-25 in §28.

### 20.6 No event on metadata edits in v1

Per §4 state machine table, no event is emitted on `draft`-time metadata edits (name/notes/channel/effective_at UPDATE). Rationale: drafts are ephemeral; per-field diff events would overwhelm the activity feed. Post-release note edits (if that policy ever loosens) would fire `release.notes_updated`. Decision recorded as G-26 in §28.

### 20.7 Event fan-out per EVENT_MODEL.md §12

- Project-level release events (`release.finalized`, `release.withdrawn`) — visible to workspace `owner`/`admin` or active `project_participants` of that project (EVENT_MODEL.md §12).
- Draft-time events (`release.created`, `release.item_added`, `release.item_removed`) — audit-only per EVENT_MODEL.md §11 (lines 361-ish; drafts do not fan out as notifications).

---

## 21. AI extension seams

APP 009 does NOT implement AI. Reserved slots — deliberate API-surface seams for future AI features. All rendered as `<AISlot kind="..." />` components (pattern established by APP 006/APP 007/APP 008). Default: renders nothing. AI slice fills.

| Seam kind | Where | Purpose |
|---|---|---|
| `release-notes-generation` | Composer (release notes textarea) | Auto-generate release notes from version diff + related review comments + approval decision reasons |
| `release-type-classification` | Composer (release_type selector) | Auto-classify release type from change scope + evidence signals |
| `release-anomaly-detection` | Release Detail Overview | Flag anomalies: "This release has fewer approvals than typical for `client` type" or "This release publishes 3 versions all changed on the same day — unusual" |
| `release-summary` | Release Detail header (right rail) | One-paragraph auto-summary of what changed and why |
| `evidence-gap-explanation` | Composer publish gate warning | Plain-language explanation of which evidence is missing and why the release type policy flags it |
| `comparison-narrative` | Release Detail Comparison tab | Auto-generate narrative diff between this release and prior release in chain |
| `withdrawal-drafting` | Withdraw modal | Suggest phrasing for `withdrawn_reason` based on the mistake context |

### 21.1 Reserved capability keys (name-locked; no wiring in APP 009)

- `release.ai_suggest` — reserved for AI-assisted release-notes and comparison-narrative.
- `release.ai_classify` — reserved for AI-assisted release_type classification.

### 21.2 Reserved event names (name-locked; no emitter in APP 009)

- `release.ai_suggested` — reserved for the AI slice.
- `release.ai_classified` — reserved for the AI slice.
- `release.audit_exported` — reserved for future PDF/CSV export (may involve AI-generated executive summary).

Decision recorded as G-27 in §28.

---

## 22. Notification contracts

APP 009 emits nothing client-side. Backend RPCs emit the frozen `release.*` events. APP 010 (Notifications, not yet frozen) subscribes to these events and applies the following recipient rules.

### 22.1 Recipient rules (APP 010 will codify)

| Event | Recipients |
|---|---|
| `release.created` (draft) | Audit-only per EVENT_MODEL.md; no fan-out. Author only (self-echo suppressed). |
| `release.item_added` | Audit-only; no fan-out. |
| `release.item_removed` | Audit-only; no fan-out. |
| `release.finalized` | All project members with `release.view` (per EVENT_MODEL.md §4.12 line 188 "project participants" recipient rule); externally: subscribers on distribution list per release_type (v2). |
| `release.withdrawn` | Same set that received the `release.finalized` for this release. Muted for the actor. |
| **[additive]** `release.scheduled` (reserved) | Assignee + project lead. |
| **[additive]** `release.superseded` (reserved) | Same set as prior `release.finalized`. |
| **[additive]** `release.recalled` (reserved) | Same set as `release.withdrawn` plus a wider ring per policy. |
| **[additive]** `release.notes_updated` (reserved) | Owner + subscribers. |

### 22.2 Distribution lists (v2)

Per release type, a project may configure a distribution list of external stakeholders (email / webhook / integration). Recipient list is stored per-project (deferred; not in v1). Owned by APP 010.

### 22.3 Fan-out cascade on withdraw

Per the recipient parity rule above: anyone who received the `release.finalized` event receives the `release.withdrawn` event. APP 010 implements the parity by joining on `activity_events.subject_id` — no APP 009 code required.

### 22.4 Muting

Actor-of-event muting is a standard APP 010 concern; APP 009 does not implement it. Decision recorded as G-28 in §28.

### 22.5 Cross-slice notification interaction

- APP 007's `approval.approved` on a version referenced by a draft release: APP 010 may notify the draft's creator "your release is now ready to publish." Deferred to APP 010; APP 009 provides the linkage via the draft's `release_items.version_id`.
- APP 008's `requirement.assessed` with `is_critical_unsatisfied=true` on a version referenced by a released release: APP 010 may notify the release publisher "a critical requirement on a released version has been marked not-satisfied." Deferred; APP 009's evidence snapshot captures the state at publish time so the notification can render a proper delta.

---

## 23. Realtime boundaries

### 23.1 Explicit statement

**The 2 releases tables — `releases` and `release_items` — are OUT of the `supabase_realtime` publication.** This is the frozen boundary set by REALTIME 001 (per memory `project_lign_schema_v1_lock.md` and mirroring APP 008 §22.1 pattern).

Real-time updates to Release dashboards, Detail pages, and NavRail badges happen via **query-invalidation only** — driven by cross-slice mutation events at the TanStack Query layer (§18) plus tab-focus poll.

### 23.2 Adding releases tables to the publication is a REALTIME re-freeze event

Not an APP 009 decision. Any proposal to subscribe live to `release.*` events must go through the REALTIME layer's re-freeze process.

### 23.3 Reserved realtime channel names (name-locked; no subscription in APP 009)

Reserved for a future REALTIME re-freeze:

| Channel | Scope | Would invalidate |
|---|---|---|
| `release:{release_id}` | Single release updates | `release(id)`, `releaseItems(id)`, `releaseEvidence(id)`, `releaseHistory(id)`, `releaseChain(id)` |
| `project:{project_id}:releases` | Project dashboard | `releasesProjectDashboard(*)`, `releaseMetrics(project)` |
| `workspace:{ws_id}:releases` | Workspace dashboard | `releasesWorkspaceDashboard(*)`, `releaseInboxCount(ws)` |
| `version:{version_id}:releases` | Per-version release stream | `releasesForVersion(vid)` (used by Design Workspace + APP 003 version card) |
| `asset:{asset_id}:releases` | Per-asset release stream | `releasesForAsset(aid)` |
| `user:{profile_id}:release-inbox` | Per-user inbox additions | `releasesList(*, 'drafts_assigned_to_me')`, `releaseInboxCount` |

APP 009 exports these constants from `src/features/releases/realtime.ts` as name-only placeholders. Subscription code is not shipped until REALTIME re-freeze.

### 23.4 Fallback in v1

Dashboards poll on tab-focus (60-second stale time via TanStack Query). Detail pages refetch on cross-slice mutations per §18. Acceptable for MVP given the low churn rate of releases (typically 1–10 per project per month); upgrade path is clean.

Decision recorded as G-29 in §28.

---

## 24. Loading/error states

### 24.1 Skeleton shapes

- **Dashboard card skeleton** — 64px height; two chip placeholders (type + status), one line for name, one line for metadata, small chip for evidence summary. Renders during initial load and while switching views.
- **Detail header skeleton** — chip placeholders for type + status; text-shimmer for name and "published by"; hidden menu.
- **Detail tab skeleton** — Overview shows item-card skeletons (one per expected item); Evidence shows section skeletons for approvals/requirements/reviews; Comparison shows a two-column diff-frame skeleton; History shows five row skeletons; Notes shows a paragraph skeleton.
- **Metrics strip skeleton** — five chip placeholders with numeric-shimmer.

### 24.2 Empty-state copy

| Surface | Copy |
|---|---|
| Workspace dashboard | "No releases yet in this workspace. Start a release from a project's Design Workspace." |
| Project dashboard | "No releases yet in this project. Start a release from a version card in the Design Workspace." |
| Filtered view returns nothing | "No releases match these filters. Clear filters or try a different view." |
| Draft with no items | "This release has no items yet. Add an asset version to publish." |
| Evidence tab (draft) | "This release is a draft — evidence will be captured at publish time." |
| Evidence tab (released, no snapshot) | "Evidence snapshot not captured for this release. Showing live upstream state." |
| Comparison tab (no prior) | "This is the first release in the chain — no comparison available." |
| History tab | "No activity yet." (rendered only if a draft has literally never been touched — unusual). |
| Notes tab (empty draft) | "Add release notes to explain what this release includes." |
| Notes tab (empty released) | "No notes were provided for this release." |

### 24.3 Error-state copy

| Error | Copy | Recovery |
|---|---|---|
| Failed to load Release Detail | "Couldn't load release." | Retry button + Back to Releases |
| Failed to load Evidence | "Couldn't load evidence." | Retry button (does not fall back to live state — the user should know we didn't load the snapshot) |
| Failed to load Comparison | "Couldn't load comparison." | Retry button |
| Failed to load History | "Couldn't load activity." | Retry button |
| 404 | "This release does not exist." | Back to Releases |
| 403 | "You do not have access to this release." | Back to project (never leak existence) |
| Publish trigger failure (frozen) | Render the raw trigger message + per-item chips highlighting the offenders | Fix upstream evidence; retry publish |
| Withdraw failure | "Couldn't withdraw release." | Retry button + Cancel |
| Discard failure | "Couldn't discard draft." | Retry button + Cancel |

### 24.4 Retry patterns

- Standard TanStack Query retry: 3x with exponential backoff on network errors.
- No retry on 4xx (RLS-hidden results, capability failures, trigger failures — these are user-actionable).
- Manual retry buttons on all failure surfaces.

### 24.5 Optimistic-update posture

**Recommended: no optimistic mutations for release publish/withdraw due to governance sensitivity — apply after server confirmation only.**

- `create_release` (draft): could be optimistic (draft creation is low-consequence), but the ordinal code (§15.4/G-21) requires a server round-trip anyway to reserve the sequence. Not optimistic.
- `add_release_item` / `remove_release_item` / `reorder_release_items`: draft-only, low-consequence — could be optimistic. Recommended: not optimistic in v1 for simplicity; upgrade in v1.1 if UX demand exists.
- `finalize_release`: NEVER optimistic. The trigger may raise; the evidence snapshot is server-computed; a wrong local state would confuse the user.
- `withdraw_release`: NEVER optimistic. Same reasoning.

Decision recorded as G-30 in §28.

---

## 25. Desktop/mobile behavior

### 25.1 Desktop (≥1024px)

- Two-column Release Detail (body + right rail).
- Dashboard table full-width with all columns.
- Design Workspace RightPanel Releases tab renders inline.
- Metrics strip visible above dashboard table.

### 25.2 Tablet (768–1024px)

- Release Detail collapses to single column; right rail becomes an expandable drawer.
- Dashboard hides low-priority columns (evidence summary, last updated); keeps name/type/status/items/published-at.
- Design Workspace RightPanel tab strip becomes horizontally scrollable.

### 25.3 Mobile (<768px)

Mobile is a **secondary** use case for releases (publishing is a deliberate desk-based action; viewing is a common mobile action).

- Dashboard is a stacked card list.
- Release Detail single-column, tabs at top as a horizontal scroller.
- Right rail collapses into a bottom-sheet triggered by "Metadata" button.
- Publish button is full-width sticky bottom bar (draft state only).
- Withdraw button is full-width sticky bottom bar (released state only).
- Long-press card → context menu (bookmark, copy link).
- Reason field auto-focuses with mobile keyboard on Withdraw tap.

### 25.4 Touch interaction for tabs

- Horizontal swipe between tabs on mobile (respecting reduced-motion preferences).
- Tap target ≥ 44px for chips and buttons.

### 25.5 Print / export

- Release Detail has a print-friendly view (v1.1) that lays out header + evidence + items + notes for archival print.
- PDF export of evidence bundle is a v2 feature (reserved capability `release.audit_export`; reserved event `release.audit_exported`).

Decision recorded as G-31 in §28.

---

## 26. Reusable primitives

### 26.1 Consumed unchanged from prior slices

- `user_bookmarks` (APP 006) with `entity_kind='release'`.
- `user_saved_views` (APP 006) with `scope='releases'`.
- `DeepLinkResolver` (APP 002) — extend additively per §15.
- `NavRail` (APP 002 + APP 006 badge prop).
- `StateBadge` (APP 005) — extend additively with `WorkflowState` union members `draft`, `released`, `withdrawn` (already-reserved `superseded`, `scheduled` from APP 007's palette continue).
- `useCopyLink` (APP 005; extended by APP 006, APP 007, APP 008) — additive `LinkKind` values `'release'`, `'release-code'`.
- `useWorkspaceHotkeys` (APP 006) — additive handler slots `onNewRelease`, `onPublishRelease`, `onWithdrawRelease`.
- `qk` registry patterns (APP 002, APP 005, APP 006).
- Timeline component (APP 006) — reused in Release Detail History tab.
- Metrics-strip component (APP 006/APP 007 pattern) — reused in Release dashboards.
- `ScopeChip` (APP 008) — reused for `release_type` chip variant.
- `RequirementRef` (APP 008) — reused in Evidence tab requirements section.

### 26.2 NOT consumed: `CommentsPanel` (APP 005)

Per the foundational premise (§1), Releases do NOT collect discussion. Discussion happens upstream in Reviews. APP 009 does NOT reuse APP 005's `CommentsPanel` and does NOT add a `target_release_id` column to `comments`. If a user wants to discuss a release, the appropriate surface is a comment on the released *version* (via APP 005's existing `target_version_id`) or on the *review* that led to the release (via APP 006). Decision recorded as G-32 in §28.

### 26.3 NOT consumed: `RosterEditor` (APP 006)

Per the foundational premise, Releases do NOT collect votes or assignments. Approvers live in APP 007. APP 009 does NOT reuse `RosterEditor` and does NOT add participant/assignee tables to the release surface. Decision recorded as G-33 in §28.

### 26.4 NEW primitives introduced by APP 009

Release-specific; not cross-slice reusable in this wave (may be extracted in a future wave once patterns stabilize across dashboards):

| Primitive | Purpose |
|---|---|
| `ReleaseDetailShell` | Full-page shell wrapping the header + tabs |
| `ReleaseEvidenceCard` | Per-item card on the Evidence tab, groups approval + requirement + review sections |
| `ReleaseComparisonView` | Comparison tab body (delta vs prior release in chain) |
| `ReleaseChainCard` | Inline chain viz for the metadata rail (analogous to APP 007 `ApprovalChainCard` and APP 008 `SupersessionChainCard`) |
| `ReleaseTypeChip` | `release_type` indicator with color tokens |
| `ReleaseCard` | Dashboard card for a release |
| `ReleaseFilterBar` | Filter bar for release dashboards |
| `ReleaseItemPicker` | Composer modal for selecting `(asset, version)` pairs to add |
| `ReleasePublishConfirm` | Publish confirmation modal with warnings (§10.8) |
| `ReleaseWithdrawConfirm` | Withdraw confirmation modal with mandatory reason (§10.9) |
| `ReleaseRef` | Inline release reference component for cross-slice citation |
| `useReleaseInboxCount` | Hook exported for NavRail consumers |
| `useReleasesForVersion` | Hook exported for APP 003 version card consumers |
| `useReleasesForAsset` | Hook exported for APP 003 asset card consumers |

### 26.5 Extended primitives (backward-compatible)

- `StateBadge` — new `WorkflowState` union members: `released`, `withdrawn` (reserved-in-palette-already: `superseded`, `scheduled`). Prior members preserved.
- `useCopyLink` — `LinkKind` gains `'release'`, `'release-code'`.
- `useWorkspaceHotkeys` — new handler slots: `onNewRelease` (bound to `N` in release dashboards), `onPublishRelease` (bound to `P` in release dashboards; context-scoped per G-16), `onWithdrawRelease` (bound to `W` in release dashboards).
- `DeepLinkResolver` — 2 additive kinds handled (`release`, `release-code`).
- Design tokens — `released` → `--color-state-resolved` (green — reused from APP 007 approved); `withdrawn` → `--color-state-blocked` (red — reused from APP 007 rejected); `draft` → neutral surface tokens; `superseded` (reserved) → `--color-state-superseded` (neutral). No new tokens declared.

### 26.6 AISlot primitives

Reserved (no wiring in APP 009 v1) — see §21:

- `<AISlot kind="release-notes-generation" />`
- `<AISlot kind="release-type-classification" />`
- `<AISlot kind="release-anomaly-detection" />`
- `<AISlot kind="release-summary" />`
- `<AISlot kind="evidence-gap-explanation" />`
- `<AISlot kind="comparison-narrative" />`
- `<AISlot kind="withdrawal-drafting" />`

---

## 27. Backend delta preview

This is a scope statement for the follow-on `APP_009_BACKEND_PROPOSAL.md`. No SQL, no bodies, no migration ordering here — just the enumerated set of proposed additions the Backend Proposal will elaborate.

### 27.1 [additive] columns

| Table | Column | Type | Nullable | Purpose |
|---|---|---|---|---|
| `public.releases` | `release_type` | `text` | yes | Enum-backed channel dimension (G-11); CHECK in v1 enum |
| `public.releases` | `evidence_snapshot` | `jsonb` | yes | Frozen evidence bundle at publish (G-7) |
| `public.releases` | `superseded_by_release_id` | `uuid` | yes | Chain pointer (G-9, G-10); composite FK `(id, project_id, workspace_id)` |
| `public.releases` | `root_release_id` | `uuid` | yes | Chain head (G-9); composite FK `(id, project_id, workspace_id)` |
| `public.releases` | `published_by_profile_id` | `uuid` | yes | FK → `profiles(id)` ON DELETE SET NULL |
| `public.releases` | `discarded_at` | `timestamptz` | yes | Soft-discard timestamp (G-4 alternative) |
| `public.releases` | `code` | `text` | yes | Per-project stable display code (G-21) |

Each column includes a matching CHECK constraint for enum values where applicable, an index if it drives dashboard filters (`release_type`, `published_by_profile_id`, `superseded_by_release_id`, `code`), and appropriate composite FK for tenant coherence.

### 27.2 [additive] tables

**None required for v1.** Deferred:

- Distribution lists (`release_distributions`) — for §22.2 (deferred to APP 010).
- Release templates (`release_templates`) — for future authoring; not v1.
- Release bundle exports (`release_audit_exports`) — for future audit export capability; not v1.

### 27.3 [additive] read RPCs

| RPC | Purpose |
|---|---|
| `get_release(release_id)` | Release Detail read (metadata + item summary + chain position + evidence summary) |
| `get_release_by_code(project_id, code)` | Deep-link `/deep/release/:code` resolver |
| `get_release_chain(release_id)` | Supersession chain (root → head) |
| `get_release_evidence(release_id)` | Evidence tab bundle + live-delta re-fetch |
| `get_release_comparison(release_id)` | Comparison vs prior release in chain |
| `list_release_activity(release_id, cursor, limit)` | History tab cursor-paginated |
| `list_release_items(release_id)` | Overview + composer body |
| `list_releases_dashboard(scope, view, filters, cursor, limit)` | Paginated dashboard read |
| `get_release_inbox_count(ws_id)` | NavRail badge |
| `get_project_release_metrics(project_id)` | Metrics strip |
| `get_workspace_release_metrics(ws_id)` | Metrics strip |
| `list_releases_for_asset(design_asset_id)` | Design Workspace Releases tab (asset scope) |
| `list_releases_for_version(version_id)` | Design Workspace Releases tab (version scope) |

All: `SECURITY DEFINER`, `SET search_path = ''`, `REVOKE` from public/anon, `GRANT EXECUTE` to `authenticated, service_role`. All gate on `release.view` capability.

### 27.4 [additive] write RPCs

| RPC | Purpose | Capability |
|---|---|---|
| `create_release(project_id, name, notes, channel, release_type)` | Create a draft; server-generates `code`; emits `release.created` | `release.create` |
| `add_release_item(release_id, design_asset_id, version_id, notes, sort_order)` | Attach an item while draft; emits `release.item_added` | `release.create` |
| `remove_release_item(release_id, version_id)` | Detach an item while draft; emits `release.item_removed` | `release.create` |
| `reorder_release_items(release_id, ordered_version_ids uuid[])` | Update `sort_order` deterministically | `release.create` |
| `discard_release_draft(release_id)` | Remove or soft-discard an empty draft (subject to G-4 policy) | `release.create` |
| `edit_release_metadata(release_id, name, notes, channel, release_type, effective_at)` | Draft-only metadata edits (thin wrapper over direct UPDATE; enables event emission if future policy requires) | `release.create` |

**Additive params on frozen RPCs (backward-compatible):**

- `finalize_release(release_id, p_release_type text default null, p_capture_evidence boolean default true)` — new nullable trailing params: `p_release_type` (lets the RPC coerce a draft into a type if the caller sets it at publish time; NULL keeps prior column value) and `p_capture_evidence` (default `true`; setting `false` explicitly skips the snapshot for edge-case backfill scenarios). Every prior signature and behavior preserved byte-for-byte; the additive params default to NULL/true.
- `withdraw_release(release_id, p_reason, p_recall boolean default false)` — new nullable trailing param `p_recall` reserved for the future `release.recalled` event (§20.5); NULL/false keeps the existing `release.withdrawn` behavior.

**Reserved for future:**

- `schedule_release(release_id, effective_at)` — reserved for scheduled-publish workflow (§3.2); no emitter.
- `create_release_superseding(prior_release_id, ...)` — reserved for chain-init (§8.2); no emitter until wired.
- `export_release_audit(release_id, format)` — reserved for audit export (§25.5); no emitter until wired.

### 27.5 [additive] capabilities

**None new wired in v1.** The 4 frozen keys (`release.view`, `release.create`, `release.finalize`, `release.withdraw`) cover every product action.

**Reserved (name-locked; not wired):**

| Capability | Purpose |
|---|---|
| `release.schedule` | Reserved — scheduled-publish gate |
| `release.supersede` | Reserved — chain-init gate |
| `release.ai_suggest` | Reserved — AI-assisted composer |
| `release.ai_classify` | Reserved — AI-assisted classification |
| `release.audit_export` | Reserved — PDF/CSV export |
| `release.recall` | Reserved — recall variant of withdrawal |

### 27.6 [additive] events

**None new emitted in APP 009 v1.** The 5 frozen events (`release.created`, `release.item_added`, `release.item_removed`, `release.finalized`, `release.withdrawn`) cover every state transition.

**[additive] payload extensions on frozen events** (backward-compatible; consumers ignore unknown keys) — see §20.4:
- `release.created`, `release.item_added`, `release.item_removed`, `release.finalized`, `release.withdrawn` each gain fields per §20.4.

**Reserved event names** (name-locked, no emitter in APP 009):
- `release.scheduled` (already reserved in EVENT_MODEL.md §D3)
- `release.superseded` (already reserved in EVENT_MODEL.md §D7)
- `release.notes_updated` (reserved by APP 009 v1)
- `release.audit_exported` (reserved by APP 009 v1)
- `release.recalled` (reserved by APP 009 v1)
- `release.ai_suggested`, `release.ai_classified` (reserved by APP 009 v1)

### 27.7 [additive] indexes

| Table | Index | Purpose |
|---|---|---|
| `releases` | `(project_id, release_type, released_at desc)` | Type-filtered released list |
| `releases` | `(project_id, published_by_profile_id, released_at desc)` | Published-by-me view |
| `releases` | `(project_id, code)` unique partial `WHERE code IS NOT NULL` | Deep-link code resolver + uniqueness |
| `releases` | `(root_release_id)` partial `WHERE root_release_id IS NOT NULL` | Chain head lookup |
| `releases` | `(superseded_by_release_id)` unique partial `WHERE superseded_by_release_id IS NOT NULL` | Chain-uniqueness invariant per G-10 |
| `releases` | GIN on `evidence_snapshot` jsonb path `approval_request_ids` | Reverse lookup "does any release cite this approval?" (v1.1 optimization; deferred if not needed) |
| `releases` | `(workspace_id, status, released_at desc)` | Workspace dashboard scan (frozen `releases_workspace_status_idx` covers first two cols; extend if needed) |

Reused (frozen):
- `releases_project_workspace_idx (project_id, workspace_id)`.
- `releases_created_by_profile_id_idx (created_by_profile_id) partial`.
- `releases_project_status_released_idx (project_id, status, released_at desc)`.
- `releases_workspace_status_idx (workspace_id, status)`.
- `release_items_release_project_workspace_idx`, `release_items_version_project_idx`, `release_items_version_asset_idx`.

### 27.8 [additive] triggers

| Trigger | Purpose |
|---|---|
| `enforce_release_chain_immutable` (BEFORE UPDATE on `releases`) | Blocks post-INSERT mutation of `superseded_by_release_id` and `root_release_id` (analog of APP 007 §21 G-30) |
| `enforce_release_evidence_immutable` (BEFORE UPDATE on `releases`) | Blocks mutation of `evidence_snapshot` after it is written (analog of frozen `enforce_release_status_via_rpc` pattern) |
| `enforce_release_type_immutable_when_released` (BEFORE UPDATE on `releases`) | Blocks mutation of `release_type` when `status='released'` (§9.7) |

Frozen triggers preserved unchanged:
- `enforce_release_finalization_prerequisites_insert` / `_update` — ≥1 item + every-item-approved at finalize (Migration 008).
- `enforce_release_items_parent_draft_mutation` — item mutations only while draft (Migration 008).
- `enforce_release_status_via_rpc` — status/id/workspace/project/created_by immutability + RPC-only status write (AUTH 008).
- `releases_set_updated_at`, `release_items_set_updated_at` — standard timestamp maintenance.

### 27.9 RLS deltas

Existing RLS policies on `releases` and `release_items` continue unchanged:

- `releases_select` — `release.view` capability.
- `releases_insert` — `release.create` + caller-is-creator + status='draft'.
- `releases_update` — `release.create` (immutability enforced by triggers).
- `release_items_select` — parent's `release.view`.
- `release_items_insert` / `_update` / `_delete` — parent's `release.create` + parent-draft trigger.

**[additive]** proposals per G-4:
- Option A: narrow DELETE policy on `releases` for creator-only + status='draft' + zero items.
- Option B: soft-discard via `discarded_at` column; no DELETE policy needed.

The **[additive]** `evidence_snapshot`, `release_type`, `superseded_by_release_id`, `root_release_id`, `published_by_profile_id`, `discarded_at`, `code` columns are covered by the existing SELECT policy (no policy change). Immutability enforced by triggers per §27.8.

### 27.10 Reserved but not proposed

- Any REALTIME publication change (`supabase_realtime`) — belongs to REALTIME re-freeze (§23.2).
- Any additional cron emitter (for scheduled releases) — belongs to cron slice.
- Any AI wiring — belongs to AI slice.
- Any DELETE policy on `release_items` beyond the existing frozen policy — draft-only mutation is already permitted; harder deletes (e.g., for GDPR) are a separate governance concern.
- Any modification to the frozen `enforce_release_finalization_prerequisites` invariant (both ≥1 item and every-item-approved remain unconditional).

### 27.11 Preliminary count

- 7 **[additive]** columns on `releases`.
- 0 new tables in v1 (deferred set enumerated in §27.2).
- 13 **[additive]** read RPCs.
- 6 **[additive]** write RPCs (all new; frozen 2 write RPCs remain unchanged in signature — additive trailing params only).
- 0 new capability keys wired in v1 (4 frozen keys cover every action; 6 reserved names for future waves).
- 0 new emitted events in v1 (5 frozen events cover every transition; 7 reserved event names for future waves — 2 already in EVENT_MODEL.md, 5 reserved by APP 009).
- ~5 **[additive]** indexes (btree + partial unique + optional GIN).
- 3 **[additive]** defense-in-depth triggers.
- Additive payload extensions on all 5 frozen events (backward-compatible).
- Realtime publication change: **none** — releases tables remain OUT per §23.

---

## 28. Open architectural decisions

Decisions taken during this freeze pass and questions deliberately deferred. Every decision may be overridden before implementation.

| # | Decision | Recommendation | Rationale |
|---|---|---|---|
| **G-1** | Reserved lifecycle states (`scheduled`, `superseded`) | **Keep reserved in frozen CHECK; do NOT exercise in APP 009 v1** | Preserves upgrade path; product-side defensive rendering handles unexpected values. |
| **G-2** | Post-release metadata edits allowed by RLS but hidden by UI | **UI hides edit affordances after `released`** | RLS permits typo-fixes by admins; product policy is that a released release is a historical record. |
| **G-3** | Rollback path (un-withdraw) | **None — withdrawal is terminal** | Historical record integrity. Publish a new release with `superseded_by_release_id` for remediation. |
| **G-4** | Draft discard policy | **Soft-discard via `discarded_at` column** (Option B) | Preserves audit trail of "someone started this and abandoned it"; simpler than adding a DELETE policy; matches APP 008 archive-not-delete posture. |
| **G-5** | Reserved-state transition names | **Reserved (`release.scheduled`, `release.superseded`) name-locked; no emitter in v1** | Vocabulary stability; future re-freeze can activate without renaming. |
| **G-6** | `design_assets.released_version_ref` pointer | **Do NOT add** | Violates independence invariant (STATE_MACHINES.md line 411); "most recently released version" is a query, not a pointer. |
| **G-7** | Evidence storage: jsonb snapshot vs join rows | **jsonb `releases.evidence_snapshot`** | Immutability by construction; single row read; pointers-not-embeds keeps size small; matches simplicity budget. |
| **G-8** | Multi-asset bundle release UX | **Supported by frozen schema; advanced UX (cross-asset diff, package export) deferred** | Frozen `release_items` already permits N items; v1 renders as expandable per-item cards without dedicated multi-asset workflows. |
| **G-9** | Prior release status on supersession | **Prior remains `released`; only `superseded_by_release_id` pointer updates** | STATE_MACHINES.md §15 D7 explicit non-goal; activating the `superseded` state requires a re-freeze of `enforce_release_status_via_rpc`. |
| **G-10** | Chain uniqueness invariant | **Partial unique index on `superseded_by_release_id`** | One release may supersede at most one prior release; enforced at index level. |
| **G-11** | Release type as enum vs. tags | **Enum via [additive] `release_type text`, retain frozen `channel` for label** | Bounded space for filters/metrics; single-type is common case; mirrors APP 008 G-1/G-2. |
| **G-12** | Release-type evidence policy | **DB-boundary is universal; RPC-boundary per-type policy is [additive] wrapper** | Frozen trigger cannot be loosened; per-type checks add defense-in-depth and better error messages. |
| **G-13** | Reserved release types | **`staged`, `snapshot`, `demo` name-locked; not in v1 CHECK** | Preserves upgrade path without over-committing v1 vocabulary. |
| **G-14** | Rich text for release notes | **Deferred to v2** | Frozen `notes text` handles plain text; rich-text editor + storage is a larger surface. |
| **G-15** | Dashboard views | **11 views enumerated in §11.1** | Covers dashboard needs; `scheduled` / `overdue_scheduled` reserved for MVP-plus. |
| **G-16** | `P` keybinding collision (APP 005 pin vs APP 009 publish) | **Resolve by page context: `P` in release dashboard = publish; `P` in comment panel = pin** | Page-scoped hotkey parser is the established convention. |
| **G-17** | Design Workspace context banner | **Yes** | Mirrors APP 006/APP 007/APP 008 banner pattern. |
| **G-18** | Project-scope NavRail badge source | **Trailing-30d released count (informational)** | Empty badge is acceptable if noisy; may be dropped in v1.1. |
| **G-19** | NavRail placement | **Between Requirements and Bookmarks at workspace; between Requirements and Activity at project** | Preserves pipeline grouping (reviews → approvals → requirements → releases). |
| **G-20** | Deep-link code disambiguator | **`?project=<id>` required when workspace context alone is ambiguous** | Codes are per-project stable; workspace-level disambiguation matches APP 008 G-28. |
| **G-21** | Release display code storage | **[additive] `releases.code text` with per-project unique + xact-lock generation** | Ordinal-derived codes shift on draft deletion; stored codes are stable deep-link targets. |
| **G-22** | URL grammar `?assignee` collision | **Disambiguated by dashboard page context** (release: `published_by`; requirement: `owner`) | Filter parser routes by slice; same posture as APP 008 G-12. |
| **G-23** | Optimistic updates | **None in v1** for `finalize` / `withdraw`; drafts non-optimistic for simplicity | Governance surface — server is authoritative; incorrect local state could corrupt viewers. |
| **G-24** | Additional capability keys wired in v1 | **None** | 4 frozen keys cover all v1 actions; 6 reserved names for future waves. |
| **G-25** | Reserved event names in APP 009 v1 | **`release.notes_updated`, `release.audit_exported`, `release.recalled`, `release.ai_suggested`, `release.ai_classified`** (plus `release.scheduled`, `release.superseded` from EVENT_MODEL.md) | Locks vocabulary before future waves; prevents rename churn. |
| **G-26** | Metadata-edit events | **None emitted in v1** | Draft metadata churn would overwhelm activity feed; post-release edits fire `release.notes_updated` when v2 loosens policy. |
| **G-27** | AI capability + event names reserved now | **Yes: `release.ai_suggest`, `release.ai_classify`, `release.ai_suggested`, `release.ai_classified`** | Locks vocabulary before AI slice starts. |
| **G-28** | Actor-of-event muting | **APP 010's concern; APP 009 does not implement** | Standard notification framework responsibility. |
| **G-29** | Realtime for release tables | **Remains OUT of publication; query-invalidation only** | Preserves REALTIME 001 boundary; releases are low-churn. |
| **G-30** | Publish/withdraw non-optimistic | **Yes — server-only** | Trigger may raise; evidence snapshot is server-computed; wrong optimistic state confuses users. |
| **G-31** | Print/export view | **Print-friendly v1.1; PDF export v2 (reserved capability `release.audit_export`)** | Not v1 scope; reserved surface. |
| **G-32** | `target_release_id` on `comments` | **Do NOT add** | Releases do not collect discussion per foundational premise; discussion lives upstream in Reviews. |
| **G-33** | RosterEditor / participant table on releases | **Do NOT add** | Releases do not collect votes or assignments; approvers live in APP 007. |
| **G-34** | Multi-item multi-asset bundle UX | **Supported by schema; v1 UX renders expandable cards; advanced UX deferred to future wave** | See G-8. |
| **G-35** | Withdraw-to-recall variant | **`release.recalled` event name reserved; `withdraw_release(p_recall bool default false)` additive param** | Recall is a stronger form of withdrawal with wider notification fan-out; distinct for audit tone. |
| **G-36** | Interaction with APP 008 requirement assessments | **APP 009 READs `get_release_readiness_for_version`; enforces per release-type policy at RPC layer; never mutates assessments** | Pipeline integrity: assessments live in APP 008 forever. |
| **G-37** | Orphaned publisher policy | **`created_by_profile_id` and `published_by_profile_id` both FK SET NULL; product renders "Former member"** | Matches APP 008 §5.4 orphaned-originator posture. |
| **G-38** | Release code display format | **`R-NNN` per-project** | Simple, familiar; matches APP 008 requirement-code shape. |
| **G-39** | Release notes length limit | **10 000 chars soft; 40 000 chars hard** | Notes are for release-level narrative; not for essays. |
| **G-40** | Whether a withdrawn release can be re-published | **No — supersession only** | Publish a new release instead; historical record preserved. |
| **G-41** | Release DELETE (hard) | **Never for released/withdrawn; conditional for zero-item drafts per G-4** | Historical record integrity. |
| **G-42** | `ReleaseItem` DELETE after publish | **Never** | Frozen `enforce_release_items_parent_draft_mutation` enforces. |
| **G-43** | Cross-project release bundling | **Structurally impossible per frozen composite FKs** | Migration 008 header comment §"Composite tenant/project integrity". |
| **G-44** | Compliance-audit export | **v2 via reserved `release.audit_export` capability + `release.audit_exported` event** | Not v1 scope. |
| **G-45** | Reviewer role and releases | **`reviewer` role has `release.view` only; cannot create/finalize/withdraw** | Per PERMISSIONS.md §5 default role map. |
| **G-46** | Whether APP 009 requires a completed Review | **No — reviews are advisory per APP 006 D-1** | Only Approvals are DB-required; Reviews may be recommended per release_type policy but never blocking. |
| **G-47** | Whether `release.finalize` should also emit `release.item_added` for pre-existing items | **No** | Items were emitted when added during draft composition; re-emitting at publish would double-count. |
| **G-48** | Idempotency of `finalize_release` on already-`released` state | **RPC raises "release is <status> (must be draft)"; product surface preflight-checks and hides Publish button** | Frozen behavior; RPC is not idempotent — publisher must be draft. |
| **G-49** | Interaction with `decisions.resulting_release_id` | **READ-only from release side; APP 003 change surfaces write this FK at decision-recording time** | Migration 008 completes the deferred FK; APP 009 renders "N decisions reference this release" on the Detail page but never writes the FK. |
| **G-50** | Release notes format sanitization | **Plain text v1; sanitize on read for XSS defense; rich text v2** | Standard XSS discipline; no rich-text HTML in v1. |

---

## 29. Freeze checklist / non-goals

### 29.1 In scope for APP 009 v1

- Release Detail page (5 tabs: Overview / Evidence / Comparison / History / Notes).
- Workspace + project Release dashboards (11 views).
- Release composer (draft creation + item picker + metadata editor).
- Publish confirmation + withdraw confirmation flows.
- Evidence bundle snapshot at publish time (jsonb).
- Release supersession chain (columns + immutability triggers; UI viz).
- Release display code (`R-NNN` per project).
- Deep links + copy link.
- NavRail entries + badges.
- Cross-slice invalidation hooks (APP 007 approval readiness, APP 008 requirement readiness).
- Design Workspace RightPanel Releases tab.
- Version card "Released" chip additive to APP 003.
- Reusable primitives (§26.4).
- 4 frozen capabilities + 5 frozen events unchanged.

### 29.2 Explicitly out of scope for APP 009 v1

- AI features of any kind (seams only — §21).
- Realtime subscriptions on release tables (name-locked channels only — §23).
- Notification delivery (APP 010's concern — §22).
- Scheduled-publish workflow (frozen `scheduled` state reserved; not exercised — §3.2).
- Automatic release supersession (frozen `superseded` state reserved; manual supersession deferred to v1.1 — §8.4).
- Release channels / distribution lists (§22.2 — deferred to APP 010).
- Release templates (deferred).
- Release libraries / cross-workspace release sharing.
- Multi-asset bundle advanced UX (§27 G-8, G-34).
- Rich text for release notes (§28 G-14).
- PDF/CSV audit export (§25.5, §28 G-31).
- Post-release notes edits emitting `release.notes_updated` (reserved; v2).
- Recall variant (`release.recalled` event reserved; §28 G-35).
- Structured discussion on releases (§28 G-32).
- Roster / participant table on releases (§28 G-33).
- Un-withdrawal (§28 G-3, G-40).
- Hard DELETE on released/withdrawn releases (§28 G-41).
- Cross-project bundled releases (structurally impossible; §28 G-43).
- Adding release tables to the realtime publication (REALTIME re-freeze; §23.2).
- Modifying any frozen surface from Migration 008 or AUTH 008.
- Modifying APP 001–008 domain, tables, RPCs, events, capabilities, routes, or components (all extensions are additive).

---

## 30. Cross-slice compatibility matrix

| Slice | Interaction with APP 009 | Direction |
|---|---|---|
| APP 001 (Domain) | Consumes: `Release`, `ReleaseItem` entities already in frozen DOMAIN_MODEL.md. APP 009 introduces no domain-model changes beyond field-level additive extensions. | Consume-only |
| APP 002 (Application shell) | Extends: `qk` namespace, `DeepLinkResolver` kinds (`release`, `release-code`), `CAPABILITY_KEYS` (with reserved AI keys per G-27), `NavRail` items, hotkey slots. All additive. | Extend additively |
| APP 003 (Projects & Design Workspace) | Extends: RightPanel tab strip gets a `Releases` tab; version cards get a `Released` chip; project shell gets a `Releases` nav item. Reads `list_releases_for_asset` / `list_releases_for_version`. Does not modify APP 003 tables or routes. | Extend additively |
| APP 004 (Files & Viewer) | Consumes: version context in Release Detail item cards; `useSignedUrl` for previews. Reserved future consumer via audit export attaching PDFs. | Consume-only |
| APP 005 (Comments & Annotations) | Reuses: `StateBadge`, `useCopyLink`, `useWorkspaceHotkeys`, design tokens — all additive. Does NOT add `target_release_id` per G-32. `CommentsPanel` is NOT reused. | Extend additively (small surface) |
| APP 006 (Reviews) | Reuses: `user_bookmarks` (with `entity_kind='release'`), `user_saved_views` (with `scope='releases'`), timeline component, dashboard shell pattern. READs review status for the Evidence tab. Does not mutate reviews. | Reuse; loose coupling |
| APP 007 (Approvals) | Consumes: `get_approval_readiness(version_id)` at publish gate. READs `approval_requests` and `approvals` for Evidence tab. Frozen `enforce_release_finalization_prerequisites` trigger already reads `approval_requests.status`. Does not mutate approvals. | Reuse; hard consume (DB-boundary) |
| APP 008 (Requirements) | Consumes: `get_release_readiness_for_version(version_id)` at publish gate per release-type policy. READs `requirements` for Evidence tab. Does not mutate requirements or assessments. | Reuse; soft consume (RPC-boundary) |
| APP 009 (this) | Owner | Owner |
| APP 010 (Notifications, not yet frozen) | Consumes: frozen `release.*` events + **[additive]** reserved event names (§20.5, §22.1). Recipient rules per §22. | Provide event contract |
| APP 011 (Realtime, not yet frozen) | Reserved channels (§23.3) name-locked. No subscriptions in APP 009. Adding release tables to publication requires REALTIME re-freeze. | Provide reserved channel names |

---

**APP 009 Freeze Index ready for backend proposal.**
