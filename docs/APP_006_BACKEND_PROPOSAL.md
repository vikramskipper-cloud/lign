# APP 006 — Backend Re-freeze Proposal

**Design proposal only. No SQL, no implementation, no migrations.** Every backend addition required to support the frozen APP 006 architecture, mapped to the freeze index sections and prioritized for a phased re-freeze.

Companion documents:
- [`APP_006_FREEZE_INDEX.md`](APP_006_FREEZE_INDEX.md) — the frozen architecture this proposal supports.
- [`SCHEMA_V1_LOCK.md`](SCHEMA_V1_LOCK.md) — the current schema lock; APP 006 re-freeze extends it.
- [`PERMISSIONS.md`](PERMISSIONS.md) — capability catalog; two new keys proposed here.
- [`EVENT_MODEL.md`](EVENT_MODEL.md) — event vocabulary; seven new types (two RESERVED) + payload extensions proposed here.

---

## Convention

Every proposed change carries four attributes:

- **Why:** the concrete user-facing behavior or invariant it enables.
- **Section:** the APP 006 Freeze Index section (`§n`) that requires it.
- **Priority:** `Critical` | `High` | `Medium` | `Future`.
- **Blocks implementation:** what specifically cannot ship without it. `None (nice-to-have)`, `v1 subset` (blocks part of v1), `v1 entirely` (blocks all of v1), `v2 only`.

Priority tiers:

| Tier | Meaning |
|---|---|
| **Critical** | v1 cannot ship at all without this. Must land in the first re-freeze wave. |
| **High** | v1 can start but a major feature is degraded / stubbed. Must land in the first or second wave. |
| **Medium** | Polish / enterprise-adjacent; v1 works without it. Third-wave re-freeze. |
| **Future** | v2 territory; explicitly outside the APP 006 v1 shipping scope. |

---

## 1. New tables

### 1.1 `user_bookmarks`

- **Why:** Bookmarks view on the review dashboard; generalized so downstream slices (Assets, Approvals, Releases) can reuse the same table without their own bookmarking model.
- **Shape (design intent):** `(id pk, user_id, workspace_id, subject_kind text, subject_id uuid, created_at)`. Unique per `(user_id, subject_kind, subject_id)`. Composite FK on `workspace_id` for tenant scoping. `subject_kind` open-vocabulary text ('review', later 'asset', 'version', etc.) — no CHECK constraint, application-side vocabulary.
- **Section:** §9 Dashboard (Bookmarks view), §28 (reusable for future slices).
- **Priority:** Medium.
- **Blocks implementation:** v1 subset — the Bookmarks view is one of eight dashboard views; the other seven ship regardless. Bookmark UI can be stubbed until this lands.

### 1.2 `user_saved_views`

- **Why:** Persist per-user dashboard views (filter + column set + sort) across sessions and devices.
- **Shape (design intent):** `(id pk, user_id, workspace_id, scope text, name text, definition jsonb, visibility text default 'private', created_at, updated_at)`. Unique per `(user_id, workspace_id, scope, name)`. `scope` = `'reviews'` for APP 006; extensible to other dashboards. `visibility` reserved for v2 sharing (`private` | `workspace`).
- **Section:** §9 Dashboard (Saved views), §28 (reusable).
- **Priority:** Medium.
- **Blocks implementation:** v1 subset — dashboard ships with a built-in view set; user-defined saved views are additive. UI can hide the "Save as new view" affordance until this lands.

### 1.3 Optional: `project_review_settings`

- **Why:** Per-project `max_open_rounds` guard so accidental proliferation of parallel rounds is prevented. Optional per D-20 (which recommends "no hard constraint; UI warns").
- **Shape (design intent):** `(project_id pk, max_open_rounds int null, updated_at)`. Nullable → no enforcement; positive int → enforce.
- **Section:** §6 Rounds (G-6).
- **Priority:** Future.
- **Blocks implementation:** None. UI enforces the warning today; DB enforcement is a v2 hardening.

---

## 2. New columns

All on existing frozen tables. All additive; no drops, no renames.

### 2.1 `reviews.round_number int not null default 1`

- **Why:** Distinguish Round 1 from Round 2/3/… in a chain. Displayed on dashboard rows and Review Detail header.
- **Section:** §6 Rounds (G-3).
- **Priority:** Critical.
- **Blocks implementation:** v1 entirely. Every dashboard row, every Review Detail header, and every reopen operation reads this column.

### 2.2 `reviews.parent_review_id uuid null`

- **Why:** Link a round to its immediate predecessor. Enables the "prior round" jump in the timeline region and the chain integrity check on reopen.
- **Shape note:** composite FK `(parent_review_id, workspace_id) → reviews(id, workspace_id)` on delete restrict; self-reference allowed only within the same workspace.
- **Section:** §6 Rounds (G-4).
- **Priority:** Critical.
- **Blocks implementation:** v1 entirely (rounds cannot exist without a linkage column).

### 2.3 `reviews.root_review_id uuid null`

- **Why:** Convenience pointer for chain-wide queries (dashboard groups on `root_review_id`; `get_review_chain(root)` scans one predicate). Set to `self` on Round 1; propagated on reopen.
- **Shape note:** composite FK same as `parent_review_id`.
- **Section:** §6 Rounds (G-4).
- **Priority:** Critical.
- **Blocks implementation:** v1 entirely — dashboard grouping is unworkable without it.

### 2.4 `reviews.coordinator_profile_id uuid null`

- **Why:** Enterprise separation-of-duty: owner (creator) vs coordinator (day-to-day driver). Falls back to owner if null.
- **Shape note:** FK to `profiles(id) on delete set null` (matches other author-style columns).
- **Section:** §5 State machine (transitions gated on coordinator), §8 Reviewer model (coordinator role) (G-5).
- **Priority:** Critical.
- **Blocks implementation:** v1 entirely — every roster mutation and state transition in the frozen architecture assumes coordinator can exist independent of owner.

### 2.5 `reviews.policy text not null default 'parallel'`

- **Why:** Enterprise reviewer policies (parallel default, sequential unlock, quorum threshold). Every reviewer-response UX branch reads this.
- **Shape note:** CHECK `policy in ('parallel','sequential','quorum')`.
- **Section:** §8 Reviewer model (G-8).
- **Priority:** High.
- **Blocks implementation:** v1 subset — parallel is the frozen default; sequential/quorum features can be dark-launched. Column must exist even for parallel-only ship so the client can safely read it.

### 2.6 `reviews.quorum_min int null`

- **Why:** Threshold for `policy='quorum'` completion.
- **Shape note:** CHECK `(policy <> 'quorum') OR (quorum_min > 0)`. Nullable so parallel/sequential reviews leave it blank.
- **Section:** §8 Reviewer model (G-8).
- **Priority:** High.
- **Blocks implementation:** v1 subset — pairs with policy column.

### 2.7 `reviews.require_comments_resolved boolean not null default false`

- **Why:** Opt-in completion gate — when true, `complete_review` refuses while any review-scoped root comment has `resolved_at IS NULL`. Enterprise QA workflows depend on this.
- **Section:** §12 Comments integration (G-20), D-7.
- **Priority:** High.
- **Blocks implementation:** v1 subset — flag itself is straightforward; the RPC gate is what unlocks the behavior. Ship together.

### 2.8 `reviews.cancellation_reason text null`

- **Why:** Auditable "why was this cancelled" — required per D-8.
- **Shape note:** CHECK `(status <> 'cancelled') OR (cancellation_reason IS NOT NULL AND length(cancellation_reason) BETWEEN 3 AND 500)`.
- **Section:** §8 (completion rules), §5 (cancel transitions), D-8 (G-21).
- **Priority:** High.
- **Blocks implementation:** v1 subset — cancel UX ships without it (defaulting reason to null) but D-8 says it's required, so ship together.

### 2.9 `review_participants.required boolean not null default true`

- **Why:** Required vs optional distinction; completion checks read this. Optional reviewers are courtesy notifications.
- **Section:** §8 Reviewer model (G-7), D-5.
- **Priority:** Critical.
- **Blocks implementation:** v1 entirely — without this, "required N of M" cannot be computed, and completion rules (§8) collapse to "all responded".

### 2.10 `review_participants.sequence_index int not null default 0`

- **Why:** Order in which reviewers unlock under `policy='sequential'`. Ignored for parallel/quorum.
- **Shape note:** CHECK `sequence_index >= 0`. Recommend a per-review partial unique `(review_id, sequence_index) where policy='sequential'` — enforced client-side because CHECK cannot reference other tables; a trigger is proposed below (§9).
- **Section:** §8 Reviewer model (G-15).
- **Priority:** High.
- **Blocks implementation:** v1 subset — parallel v1 doesn't read it; sequential feature blocks on it.

### 2.11 `review_participants.removed_at timestamptz null` + `removed_reason text null`

- **Why:** Soft-remove path for `remove_reviewer` RPC. Per §8, remove refuses on already-responded participants; those get soft-marked instead.
- **Shape note (recommended tight form):** CHECK `(removed_at IS NULL AND removed_reason IS NULL) OR (removed_at IS NOT NULL AND removed_reason IS NOT NULL)` — matches the mandatory-reason posture of `reviews.cancellation_reason` (§2.8). Every soft-removal is audit-traceable to a reason.
- **Alternative (looser form):** if reason should be optional, CHECK collapses to `(removed_reason IS NULL) OR (removed_at IS NOT NULL)` — enforces only the reverse implication. **Recommendation: use the tight form** for auditability consistency; matches D-8 cancellation-reason-required decision.
- **Section:** §8 Reviewer model (G-9).
- **Priority:** High.
- **Blocks implementation:** v1 subset — remove UI blocks on this. Add/reassign work independently.

---

## 3. New indexes

Every new column that participates in a WHERE, JOIN, or ORDER BY in the RPCs below gets a covering index. House rule from schema lock: **FK columns get a covering index in the same migration that adds them.**

| Index | Purpose | Priority | Blocks |
|---|---|---|---|
| `reviews_root_review_id_idx` on `reviews(root_review_id)` where `root_review_id IS NOT NULL` | Chain queries in `get_review_chain(root_id)` and dashboard grouping | Critical | v1 entirely |
| `reviews_parent_review_id_idx` on `reviews(parent_review_id)` where `parent_review_id IS NOT NULL` | Reopen chain-integrity checks; "prior round" lookups | Critical | v1 entirely |
| `reviews_project_status_round_idx` on `reviews(project_id, status, round_number desc)` | Project dashboard filter + sort | Critical | v1 entirely |
| `reviews_workspace_status_updated_idx` on `reviews(workspace_id, status, updated_at desc)` | Workspace dashboard filter + sort | Critical | v1 entirely |
| `reviews_due_at_partial_idx` on `reviews(due_at)` where `status in ('open','in_progress','waiting') and due_at is not null` | Overdue dashboard view + deadline-approached/passed cron | High | v1 subset (Overdue view degrades) |
| `reviews_coordinator_profile_id_idx` on `reviews(coordinator_profile_id)` where `coordinator_profile_id IS NOT NULL` | "Coordinated by me" filter + Coordinator column sort | High | v1 subset |
| `review_participants_review_required_status_idx` on `review_participants(review_id, required, status)` | Completion-check queries; "waiting on me" derivation | Critical | v1 entirely |
| `review_participants_wm_status_idx` on `review_participants(workspace_member_id, status) where workspace_member_id is not null` | "Assigned to me" inbox for members | Critical | v1 entirely |
| `review_participants_sh_status_idx` on `review_participants(stakeholder_id, status) where stakeholder_id is not null` | "Assigned to me" for stakeholders | Critical | v1 entirely |
| `user_bookmarks_user_subject_idx` on `user_bookmarks(user_id, subject_kind, subject_id)` | Membership check on every bookmark toggle | Medium | v1 subset (Bookmarks) |
| `user_bookmarks_workspace_user_idx` on `user_bookmarks(workspace_id, user_id)` | Workspace-scoped bookmark list | Medium | v1 subset |
| `user_saved_views_user_scope_idx` on `user_saved_views(user_id, workspace_id, scope)` | Load user's views on dashboard mount | Medium | v1 subset (Saved views) |

Existing indexes on `reviews(version_status, asset_status, open_due, created_by_profile_id)` remain unchanged.

---

## 4. New constraints

### 4.1 Composite tenancy FKs

Every new FK follows the frozen composite-tenancy pattern (per SCHEMA_V1_LOCK convention):
- `reviews.parent_review_id → reviews` via `(parent_review_id, workspace_id) → (id, workspace_id)` on delete restrict.
- `reviews.root_review_id → reviews` via same shape.
- `user_bookmarks.workspace_id → workspaces(id)` on delete restrict (bookmarks tenant-scoped).
- `user_saved_views.workspace_id → workspaces(id)` on delete restrict.

**Priority:** Critical (chain FKs); Medium (bookmark/saved-view FKs).
**Blocks:** v1 entirely (chain); v1 subset (others).

### 4.2 Chain integrity checks

- **Chain self-consistency:** `CHECK ((round_number = 1 AND parent_review_id IS NULL) OR (round_number > 1 AND parent_review_id IS NOT NULL))`.
- **Root self-reference on Round 1:** `CHECK ((round_number = 1 AND (root_review_id IS NULL OR root_review_id = id)) OR (round_number > 1 AND root_review_id IS NOT NULL))`.
- **Section:** §6 (rounds).
- **Priority:** Critical. **Blocks:** v1 entirely.

### 4.3 Policy consistency checks

- `CHECK (policy <> 'quorum' OR quorum_min IS NOT NULL)`.
- **Priority:** High. **Blocks:** v1 subset (quorum feature).

### 4.4 Coordinator/owner mutual exclusion (soft)

- No CHECK required; coordinator falls back to owner in application logic. Recommend an application-time invariant `coordinator_profile_id IS NULL OR coordinator_profile_id = created_by_profile_id OR is_project_participant(coordinator_profile_id, project_id)`. Enforcement via RPC only (trigger would need cross-table lookup — SECURITY DEFINER trigger acceptable but overkill for v1).
- **Priority:** Medium. **Blocks:** None.

### 4.5 Cancellation-reason presence

Covered in §2.8 above (CHECK on cancellation_reason).

### 4.6 Composite unique targets for reviewer chain scope

If we later need reviewer_history-style FKs to point at specific `(review_id, participant_id, workspace_id)` from another table (e.g. audit archive), the frozen `review_participants` already has `(id, workspace_id)` unique. No change needed today.

---

## 5. New enums / check constraints

### 5.1 Status enum expansion

**Change:** `reviews.status` CHECK constraint expands from `{draft, open, in_progress, completed, cancelled}` to `{draft, ready_for_review, open, in_progress, waiting, completed, cancelled}` (7 values).

- **Why:** Enterprise lifecycle needs `ready_for_review` (queued but not sent) and `waiting` (open but paused externally). Without them, both states collapse client-side into `draft`/`in_progress` with UI-only badges that don't survive across sessions.
- **Section:** §4 Lifecycle, §5 State machine (G-1).
- **Priority:** High.
- **Blocks implementation:** v1 subset — v1 can ship with the frozen 5-state enum if `ready_for_review` and `waiting` are deferred. But the two features degrade materially: no scheduled send, no paused-review recovery across sessions. Recommend landing together with the round-support wave.

### 5.2 Policy CHECK

`CHECK policy IN ('parallel','sequential','quorum')` — see §2.5.

### 5.3 Bookmark subject_kind — open vocabulary

No CHECK. Application-side vocabulary. Rationale: expected values grow as slices land (`asset`, `version`, `approval`, `release`).

### 5.4 Saved-view visibility CHECK

`CHECK visibility IN ('private','workspace')`. `workspace` reserved for v2; v1 enforces `private` in application logic.

- **Priority:** Medium. **Blocks:** None (v1 hardcodes private).

---

## 6. New capability keys

Two additions to the frozen catalog. Extends PERMISSIONS.md §2.6.

### 6.1 `review.coordinate`

- **Why:** Manage roster mid-review (add/remove/reassign), pause/resume (waiting), edit review metadata post-open. Distinct from `review.create` (initial creation) and `review.complete` (terminal transitions). Enterprise separation-of-duty: a lead may create; a project coordinator may drive; a governance role may complete.
- **Recommended role mapping:** granted to `lead` only by default. Confirmed in §19 role table.
- **Section:** §5 State machine (waiting transitions), §8 Reviewer model (roster mutation), §19 Capability model (G-16).
- **Priority:** Critical.
- **Blocks implementation:** v1 entirely — every roster mutation and pause/resume RPC checks it. Without it, we'd have to overload `review.create`, breaking the separation-of-duty invariant.

### 6.2 `review.reopen`

- **Why:** Create a new round from a completed review. Distinct capability so an org can allow completion without allowing reopen (governance).
- **Recommended role mapping:** `lead` and `contributor`. Confirmed in §19 role table.
- **Section:** §5 State machine (reopen), §6 Rounds (G-16).
- **Priority:** High.
- **Blocks implementation:** v1 subset — reopen is a major feature. Ships together with the round-support wave.

**No other capability additions.** `review.view / create / participate / complete` (frozen) cover everything else.

---

## 7. New RPCs

Enumerated by category in §12–§13 below. Summary counts:
- **3 read RPCs** (dashboard + detail + chain).
- **10 write RPCs** (state transitions + roster mutation + reopen + bookmarks + saved views), plus additive params on the frozen `create_review`.

All are `SECURITY DEFINER`, `search_path = ''` (matches frozen RPC convention), input-validated, capability-re-checked inside the body, and emit exactly one canonical event per success path.

Each RPC signature stays close to the frozen `create_review` / `respond_to_review` / `complete_review` style: uuid IDs, arrays for member/stakeholder rosters, text terminal values.

---

## 8. New RLS policies

Only the two new tables need policies. Existing `reviews` and `review_participants` policies are unchanged (frozen).

### 8.1 `user_bookmarks`

- **SELECT:** `user_id = auth.uid()` — a user only sees their own bookmarks.
- **INSERT:** `user_id = auth.uid()` + workspace membership check via `lign_is_workspace_member(workspace_id)`.
- **DELETE:** `user_id = auth.uid()`.
- **No UPDATE policy** — bookmarks are toggle-only (delete + insert).
- **Priority:** Medium. **Blocks:** v1 subset (Bookmarks view).

### 8.2 `user_saved_views`

- **SELECT:** `user_id = auth.uid() AND lign_is_workspace_member(workspace_id)`. (v2 will union with `visibility = 'workspace'` visibility.)
- **INSERT / UPDATE / DELETE:** `user_id = auth.uid()`.
- **Priority:** Medium. **Blocks:** v1 subset (Saved views).

### 8.3 `review_participants` — no new policy

Roster mutation is RPC-only (existing pattern). No new INSERT/UPDATE/DELETE policies added. The write RPCs proposed below are `SECURITY DEFINER` and manage the roster on the caller's behalf. This preserves the frozen "roster-writes-are-RPC-only" invariant (G-31).

### 8.4 Cross-project participant enforcement

The `add_reviewer` and `reassign_reviewer` RPCs must reject targets that are not active `project_participants` of the review's project (G-32). Enforced inside the RPC body (not via a trigger — trigger would need cross-table lookup and race with concurrent participant removal).

- **Priority:** Critical (correctness). **Blocks:** v1 subset (roster mutation feature).

---

## 9. New triggers

Minimal — the frozen backend prefers RPC-side validation over triggers. Only three trigger proposals, all defense-in-depth over the primary RPC enforcement.

### 9.1 `reviews_chain_immutable_after_creation`

- **Why:** Once inserted, `round_number`, `parent_review_id`, and `root_review_id` must never change (chain integrity). RPC layer is the primary enforcement — this trigger is defense-in-depth against direct SQL edits (which RLS on `reviews` UPDATE already denies). Matches the frozen precedent set by `annotations_position_immutable` and `enforce_version_files_parent_draft_mutation`, both of which are belt-and-suspenders over their respective RPC paths.
- **Behavior:** `BEFORE UPDATE ON reviews FOR EACH ROW` — raises if any of the three columns changes.
- **Section:** §6 Rounds.
- **Priority:** **High** (downgraded from Critical).
- **Blocks implementation:** **None (defense-in-depth over RPC-side enforcement).** RPCs already enforce; trigger is the recommended second line. Recommended in Wave 1 to match the frozen precedent.

### 9.2 `review_participants_response_terminal_gate` (optional)

- **Why:** Once a participant status is `signed_off` / `commented` / `declined`, the row should not silently regress to `pending`. Prevents "unresponse" accidents. `respond_to_review` is the only sanctioned transition path; a trigger seals that.
- **Behavior:** `BEFORE UPDATE ON review_participants FOR EACH ROW` — raises if `status` changes from a terminal response back to `pending`.
- **Section:** §8 (reviewer model), §22 (event integrity — `reviewer_responded` must be idempotent-safe).
- **Priority:** Medium.
- **Wave guidance:** **Recommended in Wave 2 as opt-in defense.** RPC-only writes make this redundant for the standard path; add if we later expose direct row updates for admin tooling. **Blocks:** None.

### 9.3 `reviews_sequential_policy_gate` (optional)

- **Why:** Under `policy='sequential'`, a reviewer's `respond_to_review` should only succeed if all earlier `sequence_index` slots have responded. This is naturally enforced in the RPC; a trigger provides DB-boundary defense.
- **Behavior:** `BEFORE UPDATE ON review_participants FOR EACH ROW` — when parent review has `policy='sequential'`, raise if updating from `pending` while an earlier `sequence_index` is still `pending`.
- **Section:** §8 Reviewer model.
- **Priority:** Medium.
- **Wave guidance:** **Required only in Wave 2 when the sequential policy is exercised.** Not needed for parallel-only v1. **Blocks:** None for v1; blocks sequential-policy feature.

**No trigger proposed** for state-machine transitions on `reviews` — the frozen pattern is RPC-only writes with no direct RLS UPDATE policy. Adding trigger validation over an RPC that already validates is redundant.

---

## 10. New event payload additions

**⚠️ Backwards-compatibility rule (applies to every extension in this section):** All payload extensions add new keys to existing frozen event types. **Consumers MUST ignore unknown keys** — this is the standard EVENT_MODEL.md forward-compatibility contract. Existing subscribers that read only the pre-extension keys continue to function unchanged. New keys are always additive; no key is ever removed, renamed, or repurposed.

**No new event types.** Payload extensions only.

### 10.1 `review.created` — payload additions

Add: `round_number`, `parent_review_id?`, `root_review_id`, `coordinator_profile_id?`, `policy`, `quorum_min?`.

- **Why:** APP 010 and dashboard invalidation need round context immediately on creation.
- **Section:** §22 Notification contracts.
- **Priority:** Critical.
- **Blocks:** v1 entirely — dashboard invalidation is broken without this.

### 10.2 `review.opened` — payload additions

Add: `round_number`, `roster: {wm_ids[], sh_ids[]}`, `due_at?`.

- **Why:** APP 010 notification recipients derive from `roster`; `round_number` for display.
- **Priority:** High. **Blocks:** v1 subset (notification content is degraded without the additions).

### 10.3 `review.reviewer_responded` — payload additions

Add: `note_snippet?` (first 200 chars of the review-scoped comment that accompanied the response, if any).

- **Why:** Notification previews. Not required for correctness.
- **Priority:** Medium. **Blocks:** None.

### 10.4 `review.completed` — payload additions

Add: `round_number`, `forced boolean` (per D-6), `outcome_summary jsonb` (`{signed_off_count, declined_count, commented_count, unresolved_comment_count}`).

- **Why:** Metrics + notification content + downstream slice inputs (APP 009 Releases reads `outcome_summary`).
- **Priority:** Critical.
- **Blocks:** v1 entirely — dashboard metrics and Release readiness depend on it.

### 10.5 `review.cancelled` — payload additions

Add: `round_number`, `cancellation_reason` (per D-8).

- **Priority:** High. **Blocks:** v1 subset.

---

## 11. New event types

Seven new types. Additions to EVENT_MODEL.md §4.7. All follow existing frozen event structure (event_type, actor_profile_id, subject_kind, subject_id, subject_label, subject_snapshot, payload) and the past-tense-verb naming convention.

| Event type | Emitted by | Payload | Priority | Blocks |
|---|---|---|---|---|
| `review.reopened` | `reopen_review` RPC | `{old_review_id, new_review_id, new_round_number, carry_forward_annotations, new_version_id?}` | High | v1 subset (reopen feature) |
| `review.state_changed` | `set_review_state` RPC | `{review_id, from, to}` (waiting ↔ in_progress) | High | v1 subset (pause/resume feature) |
| `review.reviewer_added` | `add_reviewer` RPC | `{review_id, participant_id, required, sequence_index, identity: 'member'\|'stakeholder'}` | High | v1 subset |
| `review.reviewer_removed` | `remove_reviewer` RPC | `{review_id, participant_id, reason, hard_deleted: bool}` | High | v1 subset |
| `review.reviewer_reassigned` | `reassign_reviewer` RPC | `{review_id, participant_id, from_identity, to_identity}` | High | v1 subset |
| `review.deadline_approached` (**RESERVED**) | Scheduled emitter (outside APP 006) | `{review_id, round_number, hours_remaining}` | Medium (name-only) | None |
| `review.deadline_passed` (**RESERVED**) | Scheduled emitter (outside APP 006) | `{review_id, round_number, hours_overdue}` | Medium (name-only) | None |

**RESERVED event types (`review.deadline_approached`, `review.deadline_passed`):** the type names are frozen here so APP 010 and future cron slices can reference them by exact string. **No emitter is implemented in APP 006.** These events are not emitted by any APP 006 RPC; the emitter is a separate cron / edge-function slice outside the APP 006 backend re-freeze. Consumers must accept that neither event will fire until that later slice ships.

Naming rationale: past-tense verb per EVENT_MODEL.md §2 (`deadline_approached` = "the deadline approached the review"; `deadline_passed` = "the deadline passed the review"). Consistent with the frozen vocab (`created`, `opened`, `completed`, `attached`, `purged`, etc.).

---

## 12. Read RPCs

All `SECURITY DEFINER`, capability-checked, read-only. Rationale: RLS on `review_participants` doesn't compose cleanly with per-row aggregations across reviews; per-row RLS SELECTs would N+1. Read RPCs precompute joined + aggregated results in one round trip.

### 12.1 `list_reviews_dashboard(scope, view, filters, cursor, limit)`

- **Purpose:** Powers every dashboard view. Returns paginated rows with precomputed `open_comment_count`, `open_reviewer_count`, `overdue_flag`, `my_slot_status`, `reviewer_response_distribution`, plus display fields (title, owner, coordinator, asset name, version sequence, due_at).
- **Params:**
  - `scope`: `{ws_id?, proj_id?}` — one of workspace or project scope.
  - `view`: `assigned_to_me | waiting_on_me | waiting_on_others | overdue | completed | recent | bookmarks | saved:<view_id>`.
  - `filters`: `{status?, owner_ids?, coordinator_ids?, reviewer_ids?, discipline_ids?, collection_ids?, date_from?, date_to?, round_number?}`.
  - `cursor`: **server-opaque string.** See "Cursor semantics" below.
  - `limit`: int (bounded 1..100).
- **Cursor semantics:** the cursor is a server-opaque token. Clients MUST NOT construct cursors; they receive one in each RPC response and re-submit it verbatim on the next page request. Recommended server-side encoding: `base64(json({updated_at, id}))`. Servers may change the encoding at any time without notifying clients. Passing `null` requests the first page. An empty-string cursor is treated as `null`. Passing a malformed cursor produces an error, not silent misbehavior.
- **Capability:** re-checks `review.view` on each returned row's project (via `lign_has_capability`).
- **Section:** §9 Dashboard, §17 Query architecture (G-19).
- **Priority:** Critical.
- **Blocks implementation:** v1 entirely — dashboard is one of the two primary APP 006 surfaces; without it, only Design Workspace surface ships.

### 12.2 `get_review(id)`

- **Purpose:** Powers Review Detail. Returns the review row + full participants list (member + stakeholder identities resolved) + precomputed metrics (durations, response distribution, unresolved comment count) + `chain_position` (`{round_number, is_latest, prior_review_id?, next_review_id?}`) + `newer_version_exists` flag.
- **Capability:** re-checks `review.view` on the review's project.
- **Section:** §10 Review Detail, §14 Metrics, §17 Query architecture (G-19).
- **Priority:** Critical.
- **Blocks implementation:** v1 entirely.

### 12.3 `get_review_chain(root_review_id)`

- **Purpose:** Returns all rounds in a chain ordered by `round_number asc`, with per-round summary (status, opened_at, completed_at, reviewer count, outcome). Powers the Timeline region of Review Detail.
- **Capability:** re-checks `review.view` on the project.
- **Section:** §6 Rounds, §10 Review Detail, §17 Query architecture (G-19).
- **Priority:** High.
- **Blocks implementation:** v1 subset — Timeline region degrades to a single-round view without it. Dashboard still works; Review Detail works with just `get_review`.

---

## 13. Write RPCs

All `SECURITY DEFINER`, `search_path = ''`, input-validated, capability-re-checked, and emit exactly one canonical event per success path (except roster-multi RPCs, which may emit multiple `reviewer_added` events in a single transaction).

### 13.1 `open_review(review_id)`

- **Purpose:** Transition `draft` or `ready_for_review` → `open`. Requires ≥1 participant. Emits `review.opened`.
- **Capability:** `review.create` on the review's project (creator/coordinator drive it).
- **Section:** §5 State machine (G-2).
- **Priority:** High.
- **Blocks implementation:** v1 subset — without it, `ready_for_review → open` has no path. Workaround: use `create_review(p_open=true)` up-front, losing the ready-for-review state. Ship together with G-1 status enum expansion.

### 13.2 `set_review_state(review_id, target)`

- **Purpose:** `in_progress` ↔ `waiting` transitions. **This is the ONLY sanctioned path for `waiting ↔ in_progress` transitions** — no other RPC modifies `reviews.status` between these two states, and no direct RLS UPDATE policy exists on `reviews.status`. Unifies waiting-state management with other coordinator duties (roster mutation, reopen). Emits `review.state_changed`.
- **Params:** `target ∈ {'waiting','in_progress'}`.
- **Capability:** `review.coordinate` on the review's project.
- **Audit trail:** every waiting-related state change is discoverable by filtering `activity_events` on `event_type = 'review.state_changed'` and matching the `review_id` in the payload.
- **Section:** §5 State machine (G-25).
- **Priority:** High.
- **Blocks implementation:** v1 subset — pause/resume feature. Depends on G-1 (waiting state).

### 13.3 `reopen_review(review_id, carry_forward_annotations, new_version_id?)`

- **Purpose:** Given a `completed` review, create a new `draft` review row with `round_number = old.round_number + 1`, `parent_review_id = old.id`, `root_review_id = old.root_review_id ?? old.id`. Inherits the roster by default. If `new_version_id` provided, targets that version; otherwise targets the same version as the old round. If `carry_forward_annotations = true`, duplicates active annotations from old version → new version. Emits `review.reopened`.
- **Capability:** `review.reopen` on the review's project.
- **Section:** §6 Rounds, §13 Version interaction (G-24, G-22).
- **Priority:** High.
- **Blocks implementation:** v1 subset — the entire "Round 2, 3, …" feature. If deferred, v1 ships single-round only.

### 13.4 `add_reviewer(review_id, wm_id?, sh_id?, required, sequence_index)`

- **Purpose:** Add a reviewer to an open/in_progress/waiting review. XOR member vs stakeholder. Re-checks project participation. Emits `review.reviewer_added`.
- **Capability:** `review.coordinate`.
- **Section:** §8 Reviewer model (G-9), §22 Notification.
- **Priority:** Critical.
- **Blocks implementation:** v1 entirely — roster is currently create-time-only; late additions have no path.

### 13.5 `remove_reviewer(participant_id, reason)`

- **Purpose:** Remove a reviewer. If participant has already responded, soft-mark (`removed_at` + `removed_reason` set; row preserved). If pending, hard-delete allowed. Emits `review.reviewer_removed`.
- **Capability:** `review.coordinate`.
- **Section:** §8 Reviewer model (G-9), §22 Notification.
- **Priority:** High.
- **Blocks implementation:** v1 subset — reviewer_added ships without this; remove UI blocks.

### 13.6 `reassign_reviewer(participant_id, new_wm_id?, new_sh_id?)`

- **Purpose:** Atomic remove-and-add preserving `sequence_index` and `required` flag. Refuses if participant has already responded. Emits `review.reviewer_reassigned`.
- **Capability:** `review.coordinate`.
- **Section:** §8 Reviewer model (G-10), §22 Notification.
- **Priority:** High.
- **Blocks implementation:** v1 subset — reassignment UI blocks.

### 13.7 `set_reviewer_required(participant_id, required)`

- **Purpose:** Flip a participant's `required` flag mid-review. No new event needed. Recommendation: **no event**, invalidate cache via return value.
- **Capability:** `review.coordinate`.
- **Section:** §8 Reviewer model.
- **Priority:** Medium.
- **Blocks implementation:** v1 subset — nice-to-have.

### 13.8 `toggle_bookmark(subject_kind, subject_id, workspace_id)`

- **Purpose:** Idempotent bookmark toggle. Insert if missing; delete if present. Returns new state.
- **Capability:** none beyond workspace membership.
- **Section:** §9 Dashboard (Bookmarks view).
- **Priority:** Medium.
- **Blocks implementation:** v1 subset (Bookmarks view).

### 13.9 `save_dashboard_view(view_id?, scope, name, definition, visibility)`

- **Purpose:** Create or update a saved view. `view_id = null` → INSERT; else UPDATE. Enforces uniqueness on (`user_id`, `workspace_id`, `scope`, `name`). `visibility = 'private'` only in v1.
- **Capability:** none beyond workspace membership.
- **Section:** §9 Dashboard (Saved views).
- **Priority:** Medium.
- **Blocks implementation:** v1 subset (Saved views).

### 13.10 `delete_dashboard_view(view_id)`

- **Purpose:** Remove a user's own saved view.
- **Section:** §9 Dashboard.
- **Priority:** Medium.
- **Blocks implementation:** v1 subset.

**No changes to frozen `respond_to_review`, `complete_review`, `edit_own_comment`.** New required parameters (coordinator, policy, quorum_min, required flags on initial roster, require_comments_resolved) require **either**:
- **Option A:** extend `create_review` signature additively with new optional params (backward-compatible for callers using default values), **or**
- **Option B:** introduce `create_review_v2(...)` and deprecate v1.

**Recommendation: Option A.** Frozen RPC signatures accept optional-tail params without breaking existing call sites. This means `create_review` grows params `(p_coordinator_profile_id uuid, p_policy text, p_quorum_min int, p_require_comments_resolved boolean, p_reviewer_required boolean[], p_reviewer_sequence_index int[])`.

**Blocks:** v1 entirely — every new review needs the ability to specify coordinator/policy/required-flags on creation.

---

## 14. Dashboard RPCs

Covered above in §12.1 (`list_reviews_dashboard`). Additional dashboard-supporting RPCs:

### 14.1 `get_review_inbox_count(ws_id)`

- **Purpose:** NavRail badge (D-19). Cheap COUNT query with predicate — returns `{assigned_to_me, waiting_on_me, overdue}`. Cached client-side aggressively.
- **Capability:** any authenticated caller (returns 0 for projects without `review.view`).
- **Section:** §11 Workspace integration, §20 Navigation ownership.
- **Priority:** High.
- **Blocks implementation:** v1 subset — badge shows nothing until this ships.

### 14.2 `get_project_review_metrics(proj_id)`

- **Purpose:** The metrics strip above the project dashboard (§14). Returns `{outstanding_count, overdue_count, avg_time_to_completion_days_30d, reviewer_throughput_top_5_30d}`.
- **Capability:** `review.view` on the project.
- **Section:** §14 Metrics.
- **Priority:** Medium.
- **Blocks implementation:** v1 subset — metrics strip degrades gracefully to hidden.

### 14.3 `get_workspace_review_metrics(ws_id)`

- **Purpose:** Workspace-level equivalent of §14.2.
- **Priority:** Medium.
- **Blocks implementation:** v1 subset.

---

## 15. Review chain support

Backend surface enabling the linked-rounds model (§6 of the freeze).

**Required schema:** §2.1 (`round_number`), §2.2 (`parent_review_id`), §2.3 (`root_review_id`), §3 chain indexes, §4.2 chain integrity checks, §9.1 chain immutability trigger (defense-in-depth, High priority).

**Required RPCs:** §13.3 (`reopen_review`), §12.3 (`get_review_chain`), §11 event (`review.reopened`).

**Priority (chain overall):** Critical for the schema/indexes/checks (v1 entirely); High for reopen_review + get_review_chain + trigger (v1 subset for reopen; trigger is defense only).

**Blocks:** v1 entirely for storage; v1 subset for the reopen/chain-view feature.

**Cross-slice hook:** APP 009 Releases will call `get_review_chain(root)` per asset to render "latest review outcome". Chain support is a shared prerequisite.

---

## 16. Reviewer management support

Backend surface enabling roster mutation and policy modes.

**Required schema:** §2.9 (`required`), §2.10 (`sequence_index`), §2.11 (`removed_at`, `removed_reason`), §2.5 (`policy`), §2.6 (`quorum_min`), §3 relevant indexes, §4.3 policy CHECK, §9.2/§9.3 optional response/sequential triggers.

**Required RPCs:** §13.4–§13.7 (`add_reviewer`, `remove_reviewer`, `reassign_reviewer`, `set_reviewer_required`). Plus additive params on `create_review` (§13 recommendation A) for initial roster required flags and sequence_index arrays.

**Required capability:** `review.coordinate` (§6.1).

**Required events:** `review.reviewer_added`, `review.reviewer_removed`, `review.reviewer_reassigned` (§11).

**Priority (management overall):** Critical for `required` column + `add_reviewer` (v1 entirely); High for policy modes + reassign/remove.

**Blocks:** v1 entirely for the `required` flag + `add_reviewer`; v1 subset for policy/reassign/remove.

**Cross-slice hook:** APP 007 Approvals will inherit the same roster-mutation pattern for approver rosters. RPC signatures for add/remove/reassign are designed to be copy-adaptable.

---

## 17. Round support

Full backend surface for the linked-round model.

**Required:**
- Chain schema (§15).
- Status enum expansion (§5.1) for `ready_for_review` and `waiting` — optional (High priority, not Critical). Even without it, rounds still work; just no scheduled-send limbo.
- `reopen_review` RPC + `review.reopen` capability (§13.3, §6.2).
- `get_review_chain` RPC (§12.3).
- `review.reopened` event (§11).
- Payload additions to `review.created` / `review.completed` for `round_number` (§10.1, §10.4).

**Priority:** Critical for storage + chain integrity; High for reopen behavior.

**Blocks:** v1 entirely for storage. v1 subset for full reopen UX.

---

## 18. Saved views

**Required:** `user_saved_views` table (§1.2), RLS policies (§8.2), save/delete RPCs (§13.9, §13.10), supporting index (§3).

**Priority:** Medium.

**Blocks:** v1 subset — dashboard ships with built-in views only until this lands.

**No new capability keys.** Membership check via `lign_is_workspace_member`.

**v2 hook:** `visibility='workspace'` sharing is out of v1 scope; the column exists so the migration doesn't need to touch the table again.

---

## 19. Bookmarks

**Required:** `user_bookmarks` table (§1.1), RLS policies (§8.1), `toggle_bookmark` RPC (§13.8), supporting indexes (§3).

**Priority:** Medium.

**Blocks:** v1 subset — Bookmarks view stubs to empty until this lands.

**Reusability:** downstream slices (Approvals, Assets, Releases) will insert with different `subject_kind` values. No coupling to reviews beyond the vocabulary token.

---

## 20. Metrics support

**Derivation strategy (recommended):** Compute at the RPC layer from the existing frozen `activity_events` table + `review_participants` state. No new metric-cache columns needed for v1.

**Per-review metrics** (delivered by `get_review`):
- `duration_open` — `now() - (opened_at derived from review.opened event)`.
- `time_to_first_comment` — `first comment.created event's occurred_at - opened_at`.
- `time_to_first_response` — `first review.reviewer_responded event - opened_at`.
- `time_to_completion` — `completed_at - opened_at`.
- `open_comment_count` — SELECT COUNT from comments per §12.
- `reviewer_response_distribution` — SELECT COUNT grouped by review_participants.status.

**Dashboard metrics** (delivered by `list_reviews_dashboard`, `get_project_review_metrics`, `get_workspace_review_metrics`):
- Outstanding count, overdue count — cheap COUNTs with predicate.
- Avg time-to-completion (trailing 30d) — event scan.
- Reviewer throughput (top-5 per user, trailing 30d) — event scan.

**Priority:** Metrics computation is Critical (needed by `list_reviews_dashboard`); dedicated metrics-strip RPCs (§14.2, §14.3) are Medium.

**Blocks:** v1 entirely for the counts in dashboard rows; v1 subset for the metrics strip.

**Escape hatch (G-23):** If derivation-from-events performance becomes an issue in scale testing, add cached `opened_at`, `first_responded_at`, `first_commented_at` columns to `reviews`. Not proposed for the initial re-freeze — treat as v2 hardening.

---

## Consolidated priority summary

### Critical (v1 entirely — must land in first re-freeze wave)

- §2.1 `round_number` column
- §2.2 `parent_review_id` column + composite FK
- §2.3 `root_review_id` column + composite FK
- §2.4 `coordinator_profile_id` column
- §2.9 `review_participants.required` column
- §3 chain and dashboard/inbox indexes (rows marked Critical)
- §4.1 composite tenancy FKs for chain
- §4.2 chain integrity CHECK constraints
- §6.1 `review.coordinate` capability
- §10.1, §10.4 payload additions (`round_number`, `outcome_summary`, `forced`)
- §12.1 `list_reviews_dashboard` RPC
- §12.2 `get_review` RPC
- §13 `create_review` additive params (Option A)
- §13.4 `add_reviewer` RPC
- §8.4 cross-project participant enforcement inside roster RPCs
- §20 dashboard-row count computation strategy

### High (v1 subset — first or second wave)

- §2.5 `policy` column + §4.3 CHECK
- §2.6 `quorum_min` column
- §2.7 `require_comments_resolved` column
- §2.8 `cancellation_reason` column
- §2.10 `sequence_index` column
- §2.11 `removed_at` / `removed_reason` columns
- §3 High-priority indexes (`due_at` partial, coordinator)
- §5.1 status enum expansion (`ready_for_review`, `waiting`)
- §6.2 `review.reopen` capability
- §9.1 chain-immutability trigger (defense-in-depth over RPC-side enforcement; recommended in Wave 1 to match frozen precedent)
- §10.2, §10.5 payload additions
- §11 High-priority events (`review.reopened`, `review.state_changed`, roster events)
- §12.3 `get_review_chain` RPC
- §13.1 `open_review` RPC
- §13.2 `set_review_state` RPC
- §13.3 `reopen_review` RPC
- §13.5 `remove_reviewer` RPC
- §13.6 `reassign_reviewer` RPC
- §14.1 `get_review_inbox_count` RPC

### Medium (v1 subset — third wave; graceful degradation acceptable)

- §1.1 `user_bookmarks` table + §8.1 policies + §13.8 RPC + §3 indexes
- §1.2 `user_saved_views` table + §8.2 policies + §13.9 / §13.10 RPCs + §3 index
- §9.2 optional response-terminal-gate trigger (Wave 2 opt-in defense)
- §9.3 optional sequential-policy-gate trigger (Wave 2, required only when sequential exercised)
- §10.3 `note_snippet` payload addition
- §11 RESERVED event type NAMES: `review.deadline_approached`, `review.deadline_passed` (name freeze only; no emitter in APP 006)
- §13.7 `set_reviewer_required` RPC
- §14.2, §14.3 project/workspace metrics RPCs
- §5.4 saved-view visibility CHECK (v1 hardcodes private in app)

### Future (v2 / later slice)

- §1.3 `project_review_settings` table (max_open_rounds)
- §2 multi-asset scope columns (G-11, G-12, G-13, G-14)
- §11 scheduled EMITTERS for `review.deadline_approached` / `review.deadline_passed` (belongs to cron slice; type names frozen in Wave 3, emitter deferred to that later slice)
- §20 cached `opened_at` / `first_responded_at` columns (perf escape hatch)
- Saved-view workspace-wide visibility (visibility='workspace')

---

## Re-freeze wave suggestion (not prescriptive)

**Wave 1 (Critical + chain trigger):** unblocks v1 minimal — dashboard + Review Detail + roster additions + coordinator + rounds storage + chain-immutability trigger (defense-in-depth). Roughly 12 schema additions + 4 RPCs + 1 capability + 3 event payload extensions + 1 trigger. **After Wave 1, APP 006 v1 implementation can start.**

**Wave 2 (High):** unblocks the enterprise feature set — policy modes, reopen, roster mutation full set, ready/waiting states, event vocabulary complete. Roughly 8 schema additions + 7 RPCs + 1 capability + 5 events. Optional §9.2 opt-in defense trigger lands here.

**Wave 3 (Medium):** polish — bookmarks, saved views, metrics strips, `set_reviewer_required`, RESERVED event type NAMES for the future cron slice. Roughly 2 tables + 4 RPCs + additive indexes + 2 reserved event type names.

**Wave 4 (Future):** v2 — multi-asset scope, bundles, workspace-wide saved views, cached metric columns, scheduled `deadline_approached` / `deadline_passed` cron emitters, sequential-policy trigger if exercised.

---

## Coverage matrix — Proposal section ↔ Freeze Index gap

For traceability: every proposal section maps to one or more G-# gaps from `APP_006_FREEZE_INDEX.md §26`.

| Proposal section | G-# gap(s) | Status in this proposal |
|---|---|---|
| §1.1 `user_bookmarks` | G-17 | Proposed (Medium) |
| §1.2 `user_saved_views` | G-18 | Proposed (Medium) |
| §1.3 `project_review_settings` | G-6 | Proposed as Future (deferred) |
| §2.1 `round_number` | G-3 | Proposed (Critical) |
| §2.2 `parent_review_id` | G-4 | Proposed (Critical) |
| §2.3 `root_review_id` | G-4 | Proposed (Critical) |
| §2.4 `coordinator_profile_id` | G-5 | Proposed (Critical) |
| §2.5 `policy` | G-8 | Proposed (High) |
| §2.6 `quorum_min` | G-8 | Proposed (High) |
| §2.7 `require_comments_resolved` | G-20 | Proposed (High) |
| §2.8 `cancellation_reason` | G-21 | Proposed (High) |
| §2.9 `review_participants.required` | G-7 | Proposed (Critical) |
| §2.10 `sequence_index` | G-15 | Proposed (High) |
| §2.11 `removed_at` / `removed_reason` | G-9 (sub-item) | Proposed (High) |
| §3 indexes | Support for G-3, G-4, G-5, G-7, G-9, G-15, G-17, G-18, G-19, G-29/G-30 | Proposed (mixed) |
| §4.1 composite tenancy FKs | Support for G-4, G-17, G-18 | Proposed (mixed) |
| §4.2 chain integrity CHECKs | G-3, G-4 | Proposed (Critical) |
| §4.3 policy CHECK | G-8 | Proposed (High) |
| §4.4 coordinator soft invariant | G-5 | Proposed (Medium, app-only) |
| §5.1 status enum expansion | G-1 | Proposed (High) |
| §6.1 `review.coordinate` capability | G-16 | Proposed (Critical) |
| §6.2 `review.reopen` capability | G-16 | Proposed (High) |
| §8.1 `user_bookmarks` RLS | G-17 (support) | Proposed (Medium) |
| §8.2 `user_saved_views` RLS | G-18 (support) | Proposed (Medium) |
| §8.3 no new `review_participants` RLS | G-31 | Proposed (invariant preserved) |
| §8.4 cross-project participant enforcement | G-32 | Proposed (Critical, RPC-body) |
| §9.1 chain-immutability trigger | G-4 (defense) | Proposed (High, defense-in-depth) |
| §9.2 response-terminal-gate trigger | G-9 (defense) | Proposed (Medium, Wave 2 opt-in) |
| §9.3 sequential-policy-gate trigger | G-8, G-15 (defense) | Proposed (Medium, Wave 2 if sequential exercised) |
| §10 payload extensions | Support for G-24 through G-30 payloads | Proposed (Critical–Medium) |
| §11 event: `review.reopened` | G-24 | Proposed (High) |
| §11 event: `review.state_changed` | G-25 | Proposed (High) |
| §11 event: `review.reviewer_added` | G-26 | Proposed (High) |
| §11 event: `review.reviewer_removed` | G-27 | Proposed (High) |
| §11 event: `review.reviewer_reassigned` | G-28 | Proposed (High) |
| §11 event: `review.deadline_approached` (RESERVED) | G-29 | Type name proposed (Medium); emitter deferred |
| §11 event: `review.deadline_passed` (RESERVED) | G-30 | Type name proposed (Medium); emitter deferred |
| §12.1 `list_reviews_dashboard` | G-19 | Proposed (Critical) |
| §12.2 `get_review` | G-19 | Proposed (Critical) |
| §12.3 `get_review_chain` | G-19 | Proposed (High) |
| §13.1 `open_review` | G-2 | Proposed (High) |
| §13.2 `set_review_state` | G-25 | Proposed (High) |
| §13.3 `reopen_review` | G-24, G-22 | Proposed (High) |
| §13.4 `add_reviewer` | G-9 | Proposed (Critical) |
| §13.5 `remove_reviewer` | G-9 | Proposed (High) |
| §13.6 `reassign_reviewer` | G-10 | Proposed (High) |
| §13.7 `set_reviewer_required` | G-9 (sub-item) | Proposed (Medium) |
| §13.8 `toggle_bookmark` | G-17 | Proposed (Medium) |
| §13.9 `save_dashboard_view` | G-18 | Proposed (Medium) |
| §13.10 `delete_dashboard_view` | G-18 | Proposed (Medium) |
| §13 `create_review` additive params | G-3, G-5, G-7, G-8, G-20 | Proposed (Critical) |
| §14.1 `get_review_inbox_count` | G-19 (sub-item) | Proposed (High) |
| §14.2 `get_project_review_metrics` | G-19, §14 | Proposed (Medium) |
| §14.3 `get_workspace_review_metrics` | G-19, §14 | Proposed (Medium) |
| §15 chain support | Aggregate of §2.1–§2.3, §3, §4.2, §9.1, §12.3, §13.3 | Proposed (Critical/High mix) |
| §16 reviewer management support | Aggregate of §2.9–§2.11, §2.5–§2.6, §6.1, §11 events, §13.4–§13.7 | Proposed (Critical/High mix) |
| §17 round support | Aggregate of §15 + §5.1 + §6.2 + §10 payload | Proposed (Critical/High mix) |
| §18 saved views | Aggregate of §1.2 + §8.2 + §13.9–§13.10 + §3 | Proposed (Medium) |
| §19 bookmarks | Aggregate of §1.1 + §8.1 + §13.8 + §3 | Proposed (Medium) |
| §20 metrics support | Derivation from `activity_events`; §14 RPCs | Proposed (Critical–Medium mix) |

**Gaps NOT covered by this proposal (deferred to later slices or explicitly out of scope):**
- G-6 (`max_open_rounds`) — Future; app-only warning today.
- G-11 (multi-asset review scope) — v2 backend re-freeze.
- G-12 (`collection_id` scope) — v2.
- G-13 (`discipline_id` scope) — v2.
- G-14 (Review Bundles) — v2.
- G-22 (annotation carry-forward on reopen) — bundled into §13.3 as an RPC param, not a separate table.
- G-23 (cached `opened_at` / `first_responded_at` / `first_commented_at`) — perf escape hatch; not proposed for v1 re-freeze.
- G-33 (per-round visibility) — v2 privacy model.
- G-29 / G-30 emitters (only the type NAMES are reserved; emitters belong to a later cron slice).

---

## What this proposal does NOT include

- SQL. No CREATE TABLE, ALTER TABLE, CREATE FUNCTION.
- Migration file naming or ordering.
- Backfill strategy for existing data (there is no production data yet; not applicable).
- Advisor-check design (frozen pattern: run advisors after each migration; expect zero new WARN/ERROR).
- Downstream slice (APP 007–011) backend proposals. APP 006 exports its contract; those slices propose their own re-freezes.
- Scheduled emitter for `review.deadline_approached` / `review.deadline_passed` — type names are frozen in this proposal; the emitter is a separate cron / edge-function slice.

---

## Ready for approval

On approval of this proposal (in full or wave-by-wave), a corresponding backend re-freeze migration set can be authored. Implementation of APP 006 v1 begins after Wave 1 lands and re-freeze is confirmed.
