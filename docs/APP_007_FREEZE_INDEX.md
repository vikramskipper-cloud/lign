# APP 007 — Freeze Index

**Canonical architecture reference for the Lign approval system.**

Implementation has not started. This document consolidates the APP 007 architecture into one navigational reference. It preserves every APP 001–006 contract; extension is additive only. Sections marked *"requires backend re-freeze"* are gated on additions enumerated in §21 (Backend Gaps) — those additions are identified only, not proposed with SQL or migration plans.

**Companion frozen documents:**
- [`docs/APP_006_FREEZE_INDEX.md`](APP_006_FREEZE_INDEX.md) — Reviews contract that APP 007 references without modifying.
- [`docs/freeze/APP_006_FINAL_CERTIFICATION.md`](freeze/APP_006_FINAL_CERTIFICATION.md) — APP 006 governance record.
- [`docs/DOMAIN_MODEL.md`](DOMAIN_MODEL.md), [`docs/PERMISSIONS.md`](PERMISSIONS.md), [`docs/EVENT_MODEL.md`](EVENT_MODEL.md), [`docs/SCHEMA_V1_LOCK.md`](SCHEMA_V1_LOCK.md).

---

## 1. Purpose of Approvals

An approval is a **governance gate**: a formal, auditable, binding record that grants or denies permission for a specific version of a design asset to proceed to a downstream action (typically a release, but potentially any gated action a future slice defines).

### 1.1 Fundamental distinction from Reviews (APP 006)

Approvals are **not** Reviews with a different name. They are architecturally, semantically, and legally distinct:

| Axis | Reviews (APP 006) | Approvals (APP 007) |
|---|---|---|
| **Purpose** | Collect feedback; iterate | Grant or deny authority to proceed |
| **Weight** | Advisory | Binding, auditable, contractual |
| **Response vocabulary** | `commented`, `signed_off`, `declined`, `pending` (4 values, opinion-shaped) | `approved`, `rejected`, `abstained`, `pending` (4 values, verdict-shaped) |
| **Response mutability** | Reviewers can respond, re-comment, edit their comment body | An approval decision is **immutable once cast**; changing your mind requires a new approval request |
| **Outcome** | "We discussed this" (soft close) | "Approved" / "Rejected" (binary+ verdict with legal weight) |
| **Blocking downstream** | Does not block releases, publishes, or other actions | **Blocks** downstream gated actions (release readiness, requirement waivers) |
| **Rounds / retries** | Rounds via `reopen_review` (new linked row) — same review conceptually iterates | No reopen. A rejected or expired approval is terminal; remediation requires a **new** approval request (optionally chained via `supersedes_approval_request_id`) |
| **Policy focus** | Collaboration: parallel / sequential / quorum for who talks first | Governance: unanimous / majority / quorum / veto for who has authority |
| **Expiry** | Reviews have `due_at` (deadline signal); no automatic terminal transition | Approvals have `expires_at` (hard deadline); auto-transition to `expired` state via scheduled emitter |
| **Audit posture** | Change history via `comment_edits` (append-only) | Immutable at row level; every decision preserved verbatim including timestamp, actor, reason |
| **Coordinator role** | Coordinator drives (roster, pause/resume) | No coordinator role — the requester is the only non-approver actor; approvers are the sole decision-makers |
| **Sign-off semantic** | `signed_off` is an opinion ("I've seen this and I'm OK with it") | `approved` is authorization ("I hereby grant permission to proceed") |

Every subsequent APP 007 design choice derives from this distinction. Where they look superficially similar (dashboard, roster, deep-links), the semantics diverge.

---

## 2. Ownership boundaries

### 2.1 Owned exclusively by APP 007

- Approval lifecycle (states, transitions, terminal semantics, expiry).
- Approval policies (unanimous, majority, quorum-N, single-approver, sequential, veto-enabled).
- The approver decision act (`approved` / `rejected` / `abstained`) and its immutability contract.
- Approval outcome computation (aggregate verdict from individual responses per policy).
- Approval chains (`supersedes_approval_request_id` for remediation cycles).
- Approval dashboards (workspace + project scopes).
- Approval Detail screen.
- Approval-related deep links (`/deep/approval/:id`, `/deep/approver/:id`).
- Approval-scoped URL grammar.
- New capabilities: `approval.veto`, `approval.expire` (proposed; see §21).
- Approval event vocabulary (existing frozen + new emitted).
- The Design Workspace RightPanel "Approvals" tab body (reserves the tab if APP 005/006 didn't).

### 2.2 Consumed only (never modified) from APP 001–006

- **APP 001 Domain Model:** the `ApprovalRequest / ApprovalResponse / Approval` triple already defined; the 7-way XOR comment target with `target_approval_request_id`; the roles-as-capability-sets principle; immutability rules on the outcome record.
- **APP 002 Application Shell:** router shape, `qk` registry, `CAPABILITY_KEYS`, `DeepLinkResolver` (extend additively with `approval` and `approver` kinds — `approval` was already reserved as a stub), `NavItem` (with `badge` prop from APP 006), `NavRail` extension pattern, workspace + project layouts.
- **APP 003 Projects & Design Workspace:** project + asset + discipline context; the Design Workspace shell and its RightPanel tab strip.
- **APP 004 Files & Viewer:** version context, `useSignedUrl` for approval-attached document previews (v2), `FilesPanel` reused in Approval Detail.
- **APP 005 Comments & Annotations:** `CommentsPanel` reused unchanged; `StateBadge`, `useCopyLink`, `useWorkspaceHotkeys` extended additively; comment target `target_approval_request_id` (schema already present).
- **APP 006 Reviews:** `RosterEditor` reused (approver rosters mirror reviewer rosters in shape); `ReviewsDashboardBody` pattern (dashboard shell reusable for approvals — abstracting into `DashboardBody` may be part of APP 007 primitives — see §22); `list_reviews_dashboard` pattern for pagination and cursor semantics; `user_bookmarks` and `user_saved_views` tables (reuse with `subject_kind='approval_request'` and `scope='approvals'`).

**APP 007 does not modify** any file, RPC, capability, event, policy, trigger, index, or public API owned by APP 001–006. Every extension is additive.

---

## 3. Domain model

APP 007 works with three linked domain entities already named in the frozen domain model and (partially) implemented in the frozen backend. APP 007 formalizes their semantics for the UI layer.

### 3.1 ApprovalRequest

**The ask.** Represents a formal request for approval on one specific `asset_version`. Contains:

- Target (`workspace_id`, `project_id`, `design_asset_id`, `version_id`) — immutable after creation.
- `title`, `description` — human-readable statement of what is being approved.
- `policy` — one of the policy modes in §5.
- `quorum_min` — used only when `policy = 'quorum'`.
- `expires_at` — deadline after which the request auto-transitions to `expired`.
- `requester_profile_id` — the person who requested approval.
- Optional `related_review_id` — informational FK to a completed APP 006 review that motivated this approval (loose coupling, not required, not enforced by the release/requirement layers).
- Optional `supersedes_approval_request_id` — link to a prior request that was rejected/expired/cancelled and this one replaces (chain support).
- `status` — lifecycle state (see §4).
- `outcome_summary` — computed and frozen once the request reaches a terminal state.

### 3.2 Approval participants (ApprovalResponse rows)

The frozen backend uses `approval_responses` as both the assignment slot and the decision record. Each row represents one approver's participation:

- Identity: XOR of `workspace_member_id` or `stakeholder_id` (mirrors APP 006 reviewer identity model).
- `status`: `pending` (assigned, not yet responded) → `approved` | `rejected` | `abstained` (terminal per row).
- `decided_at`, `decision_reason`, optional `decision_metadata` (jsonb for e-signature fingerprints, IP, etc. — reserved for v2).
- `required` boolean (mirrors APP 006 pattern) — required approvers block outcome computation.
- `sequence_index` (for sequential policy).
- `veto_power` boolean — approver whose `rejected` decision immediately terminates the request as `rejected` regardless of other responses.

**A single approver row is both the "slot" and the "verdict".** Once `status` transitions from `pending` to any terminal value, that row is immutable. Changing your mind requires a new `ApprovalRequest`.

### 3.3 Approval decisions

The **atomic act** of casting a decision. Each `respond_to_approval` invocation:
- Updates one `approval_responses` row from `pending` to `approved` | `rejected` | `abstained`.
- Records `decided_at`, `decision_reason` (mandatory text, min 3 chars — matches cancellation-reason posture in APP 006).
- Emits `approval.responded` event.
- Triggers outcome computation (§3.4). If policy is satisfied, the `ApprovalRequest.status` transitions to `approved` or `rejected` and an `Approval` record is written.

The response row is not deletable, not editable, not re-castable. Immutability is the entire point.

### 3.4 Approval outcomes (Approval)

The **aggregate verdict record** produced when the policy is satisfied. Contains:

- One-to-one with `approval_requests.id` on positive path — the frozen `approvals` table.
- `outcome`: `approved` | `rejected` | `expired` | `cancelled` | `superseded`.
- `outcome_computed_at` — the moment the policy first evaluated to a terminal state.
- `constituent_response_ids` — array of the `approval_responses.id` values that contributed to the outcome (audit trail).
- `outcome_snapshot` — jsonb capture of `{approved_count, rejected_count, abstained_count, pending_count, veto_cast: bool, policy, quorum_min}` at the moment of outcome.

The outcome record is **written once and never mutated**. If APP 009 Releases queries approval readiness later, it reads the frozen outcome.

### 3.5 Approval chains

Unlike Reviews (which iterate via `reopen_review` creating a new row in a rounds chain), Approvals **do not reopen**. Terminal is terminal. If the outcome is negative (rejected/expired/cancelled), remediation is a **brand-new `ApprovalRequest`** with `supersedes_approval_request_id` pointing at the prior one.

Chain semantics:
- The chain is directional: A ← B (B supersedes A).
- Chain lookup query: given the latest, walk backwards via `supersedes_approval_request_id`.
- The prior row's `status` is set to `superseded` when the new request is created (by explicit RPC action — see §21).
- Superseded requests remain queryable; their outcome record (if any) remains intact.

### 3.6 ApprovalRequests as first-class

An `ApprovalRequest` is the primary object users interact with in the UI. The word "approval" in day-to-day usage refers to the request, not the outcome record. Both `/deep/approval/:id` and dashboard rows use `approval_requests.id` as the canonical identifier.

---

## 4. Lifecycle

### 4.1 States

APP 007 defines the following lifecycle states on `approval_requests.status`:

- `draft` — requester is preparing the request; not yet sent to approvers.
- `pending` — request sent; approvers assigned; awaiting responses.
- `in_progress` — at least one approver has responded; policy not yet satisfied.
- `approved` — terminal. Policy satisfied positively.
- `rejected` — terminal. Policy satisfied negatively OR a veto approver rejected.
- `expired` — terminal. `expires_at` passed before policy was satisfied.
- `cancelled` — terminal. Requester or admin cancelled before terminal outcome.
- `superseded` — terminal. Replaced by a newer request via `supersedes_approval_request_id`.

Terminal set: `approved`, `rejected`, `expired`, `cancelled`, `superseded`. Non-terminal set: `draft`, `pending`, `in_progress`.

### 4.2 State machine

```
                  ┌───────┐   send    ┌──────────┐  first response  ┌───────────────┐
   create ──────▶ │ draft │──────────▶│ pending  │──────────────────▶│  in_progress  │
                  └───────┘           └──────────┘                    └───────────────┘
                       │  cancel            │  cancel                       │
                       ▼                    ▼                               │
                  ┌──────────┐         ┌──────────┐                         │
                  │cancelled │         │cancelled │◀────────────────────────┘  cancel
                  └──────────┘         └──────────┘
                                                                            policy satisfied
                                                                                     │
                                                    ┌──────────────┐  positive       ▼
                                                    │   approved   │◀────── outcome_computed
                                                    └──────────────┘
                                                                            policy satisfied
                                                    ┌──────────────┐  negative       │
                                                    │   rejected   │◀────── (incl. veto)
                                                    └──────────────┘
                                                                            expires_at
                                                    ┌──────────────┐  passes         │
                                                    │   expired    │◀───── (cron)
                                                    └──────────────┘
                                                                            new request
                                                    ┌──────────────┐  supersedes     │
                                                    │  superseded  │◀────── (explicit)
                                                    └──────────────┘
```

### 4.3 Transitions

| From | To | Actor | Capability | Reversible |
|---|---|---|---|---|
| ∅ | `draft` | Any project participant with `approval.request` | `approval.request` | Cancel |
| `draft` | `pending` | Requester | `approval.request` | No (see reopen rule) |
| `pending` | `in_progress` | Any assigned approver | `approval.respond` | No (auto on first response) |
| `pending` / `in_progress` | `approved` | Sum of responses satisfies policy positively | `approval.respond` (per response) | No |
| `pending` / `in_progress` | `rejected` | Policy satisfies negatively OR veto approver rejects | `approval.respond` | No |
| `pending` / `in_progress` | `expired` | Cron / scheduled emitter | `approval.expire` (new capability, invoked by service_role or authorized user) | No |
| `draft` / `pending` / `in_progress` | `cancelled` | Requester or workspace admin | `approval.cancel` | No |
| `pending` / `in_progress` | `superseded` | Requester or coordinator via `supersede_approval_request` RPC | `approval.request` (creating the new request) | No |

Terminal states cannot transition to any other state. Every attempt raises.

### 4.4 Reopen rules

**No reopen.** This is the defining architectural difference from Reviews. If an approval reaches a negative or expired outcome and remediation is needed, the flow is:

1. The version is revised (a new `asset_version` is uploaded and published via APP 004).
2. A brand-new `ApprovalRequest` is created against the new version, with `supersedes_approval_request_id` set to the prior request.
3. The prior request's `status` transitions to `superseded` (via `supersede_approval_request` RPC — proposed).
4. The new request begins its own lifecycle at `draft` or `pending`.

The prior request's outcome record remains intact. The audit trail is fully preserved: two requests, two outcomes, two chains of responses. Nothing about the prior approval is mutated.

---

## 5. Approval policies

Policies determine when an `ApprovalRequest` transitions to a terminal outcome.

### 5.1 `single`

Exactly one approver required. Their `approved` → request is `approved`. Their `rejected` → request is `rejected`. Simplest case.

### 5.2 `unanimous` (default)

Every required approver must respond `approved`. Any `rejected` → request is `rejected`. Any `abstained` on a required approver blocks completion unless coordinator promotes another. Optional approvers do not count.

**Recommended default policy** because it enforces the strongest audit guarantee: every gatekeeper explicitly consented.

### 5.3 `majority`

Simple majority (> 50%) of required approvers must respond `approved`. If more than 50% respond `rejected`, request is `rejected`. Abstentions do not count toward either side.

### 5.4 `quorum` (N-of-M)

Exactly N specific approvals required from the required approver set (`quorum_min`). If M − quorum_min + 1 approvers reject, the remaining cannot reach quorum → request is `rejected` early.

### 5.5 `sequential`

Approvers unlock in `sequence_index` order. The approver at `sequence_index = 0` responds first. Their `approved` unlocks index 1; their `rejected` immediately terminates the request as `rejected`. The final index's `approved` terminates as `approved`.

### 5.6 `veto`

Any approver whose row has `veto_power = true` can single-handedly reject regardless of other responses or policy. Used for legal, safety, executive overrides. Veto is an approver-row attribute, not a separate policy — it composes with any base policy. Any policy may have zero or more veto-power approvers.

### 5.7 Policy composition rules

- Every policy has an underlying `required` boolean per approver (mirrors APP 006 pattern).
- Optional approvers are courtesy-notified; their responses are recorded but never determine outcome.
- Veto composes orthogonally with any base policy (`unanimous | majority | quorum | sequential | single`).
- Only one veto rejection is needed to terminate the request as `rejected`.

### 5.8 Deferred (v2)

- **Weighted approvals** — approvers with different vote weights (e.g. Executive = 3, Manager = 1).
- **Hierarchical escalation** — automatic escalation to a superior if an approver doesn't respond within a threshold.
- **Delegation** — an approver may designate a delegate for the duration.

---

## 6. Approval dashboard

Two levels (mirroring APP 006 dashboards):

- **Workspace approvals dashboard** — `/workspace/:ws_id/approvals` — cross-project inbox.
- **Project approvals dashboard** — `/workspace/:ws_id/project/:proj_id/approvals` — project-scoped.

### 6.1 Views

- **Awaiting my decision** — I'm an assigned approver with `status='pending'` on a non-terminal request.
- **Awaiting others** — I'm the requester (or coordinator); approvers still pending.
- **Approved** — terminal-positive requests visible to me.
- **Rejected** — terminal-negative requests visible to me.
- **Expired / cancelled** — terminal without decision.
- **Recent** — sorted by `updated_at desc`, all statuses.
- **Bookmarks** — reuse `user_bookmarks` with `subject_kind='approval_request'`.
- **Saved views** — reuse `user_saved_views` with `scope='approvals'`.

### 6.2 Columns (dashboard table)

`Title · Asset · Version · Policy · Status · Requester · Approvers (avatars + response chips) · Deadline · Age · Last activity`.

Column set is stable within a slice; sorting is server-side.

### 6.3 Filters

- Status (multi-select).
- Requester, approver (people picker).
- Discipline, collection (from APP 003).
- Policy (multi-select of `single | unanimous | majority | quorum | sequential`).
- Date range (created, decided, expires_at).
- Has-veto flag.
- Related-review filter (`related_review_id IS NOT NULL`).

### 6.4 Bulk actions (v1 conservative)

- **Bookmark / unbookmark**
- **Cancel** (permission-gated; confirm dialog with reason)
- (No bulk-decide — decisions must be per-request for audit clarity)

### 6.5 Saved views + bookmarks

Reuse APP 006 infrastructure with different `scope` / `subject_kind` values:
- Saved view scope: `'approvals'`
- Bookmark subject_kind: `'approval_request'`

No new backend tables required for this feature.

### 6.6 Metrics strip

Above the table (collapsible, off by default):
- Outstanding count
- Overdue count (expires within 24h)
- Rejection rate (trailing 30d)
- Avg time-to-decision (trailing 30d)

---

## 7. Approval Detail

Full-page route: `/workspace/:ws_id/project/:proj_id/approval/:approval_request_id`.

### 7.1 Layout

```
Header:   ← Back · Asset · Approval Request title · [Status badge] · [Policy badge] · ⋮
Region A: Version card (compact viewer link, "open in workspace")
Region B: Decision panel — the primary interaction surface
Region C: Chain view — supersession lineage (prior/next requests in chain)
Tabs:     Comments | Decisions | Files | Activity
```

### 7.2 Decision panel

The Approval Detail's most distinctive surface. Distinct from APP 006 RosterEditor:

- **For approvers who have not yet decided (`status='pending'`)**: three large decision buttons (Approve / Reject / Abstain), a mandatory reason text area (min 3 chars), and — if `veto_power = true` — a "Cast veto" clarifying label.
- **For approvers who have decided**: a locked card showing their decision, timestamp, reason. Cannot edit.
- **For non-approvers**: read-only decision summary per approver, with a per-approver "Remind" affordance (v2) for the requester.

The decision act includes a confirmation step (are you sure?) for `rejected` and `abstained`, per D-9.

### 7.3 Timeline (chain)

Similar shape to APP 006's Timeline card but distinct semantics:
- Renders the supersession chain: prior superseded request → current request → (potentially) next superseded-by request.
- Each entry shows: request title, outcome, decided_at, and `related_review_id` if present.
- Clicking an entry navigates to that request's Approval Detail.

### 7.4 Tabs

- **Comments** — reuses APP 005 `CommentsPanel`, scoped to the approval request's version. Comments with `target_approval_request_id = current` are shown grouped under "Approval discussion" (analogous to APP 006's "Pins" / "General" grouping). No modification to `CommentsPanel` required.
- **Decisions** — full list of `approval_responses` for this request, sorted by `sequence_index asc, decided_at asc`. Read-only. Shows abstention reasons, veto flags.
- **Files** — read-only `FilesPanel` for the request's version.
- **Activity** — filtered `activity_events` for this approval request (all `approval.*` events matching `subject_id`).

### 7.5 Design Workspace ↔ Approval context banner

Navigating from an approval to the version opens the Design Workspace with a subtle top banner: *"In approval context — A-42 · Awaiting your decision"*, with a "Back to approval" link. Mirrors APP 006's review context banner pattern.

---

## 8. Relationship with Reviews (APP 006)

The relationship is **loose, informational, and non-blocking**.

### 8.1 When does a review "become" an approval?

**It doesn't.** A review is a discussion; an approval is authorization. A completed review may (or may not) precede an approval request on the same version. The transition is a **human decision**, not a state-machine transition:

- A completed review with positive outcome_summary may prompt the requester to open an approval on the same version.
- The requester can cite the review in the approval's `description` field or via the informational `related_review_id` FK (§3.1).
- APP 007 does **not** query or gate on review status. The approval flow proceeds independently.

### 8.2 Can approvals exist without reviews?

**Yes.** Emergency releases, small changes, contractual sign-offs, and hotfixes may be approved without any review having occurred. The two systems are orthogonal.

### 8.3 Can multiple approvals reference one review?

**Yes.** A single review may seed multiple approval requests (e.g. design approval, budget approval, legal approval — each with different approvers, different policies, but all citing the same review as evidence). The `related_review_id` FK is many-to-one (many approval requests → one review), never enforced as unique.

### 8.4 Can releases require approvals?

**Yes — and this is APP 009's contract, not APP 007's.** APP 007 provides the `get_approval` and `list_approvals_for_version` read RPCs. APP 009 decides:
- Which policies require approval before release
- What counts as a "release-blocking" approval
- Whether multiple approvals of different types are needed per release

APP 007 does not model release semantics.

### 8.5 UI cross-links

- Review Detail (APP 006) may show a "Approvals on this version" section (additive to APP 006 in an amendment if desired; not a v1 requirement).
- Approval Detail (APP 007) may show the linked review (if `related_review_id` is set) as a link in the header.

Neither cross-link creates a functional dependency.

---

## 9. Relationship with Requirements (APP 008)

APP 008 (Requirements UI) is not yet frozen; the requirements **backend** (Migrations 006–008) is frozen. APP 007's relationship to requirements is **read-side informational** in v1:

### 9.1 Requirement compliance

The Approval Detail may display a "Requirements status" panel showing how many applicable requirements are `assessed` vs `unassessed` vs `failed` for the request's version. This is a read of `list_applicable_requirements` (frozen RPC) — APP 007 doesn't modify the requirements layer.

### 9.2 Requirement acceptance

An approver's decision may **implicitly accept** a failed requirement (waiver). In v1, the requirement's own assessment is NOT modified by an approval decision — the two systems remain orthogonal. The approver's `decision_reason` should mention any waived requirement for the audit trail.

### 9.3 Exceptions / waivers

A waiver is captured as **text** in the approver's `decision_reason` in v1. Structured waiver support (a `requirement_waivers` table linking approval responses to specific requirements) is deferred to APP 008 or later — not APP 007's scope.

### 9.4 Blocking

APP 007 does not hard-block approval submission on failed requirements in v1. If an org wants that policy, the composer can render a warning; the approver can still proceed. Enforcement is a future capability (`approval.require_all_requirements` per-project setting — v2).

---

## 10. Relationship with Releases (APP 009)

APP 009 has not been frozen. APP 007 promises a **stable read contract** that APP 009 can build against without modifying APP 007:

### 10.1 Release readiness

APP 009 will read approval outcomes via:
- `get_approval(approval_request_id)` — one request's full state.
- `list_approvals_for_version(version_id)` — all approval requests targeting a version.
- `get_approval_readiness(version_id)` — a proposed convenience RPC returning `{ has_approved: bool, blocking_requests: [], latest_outcome: {...} }`.

### 10.2 Release blockers

APP 009 defines what a release blocker is. APP 007 supplies the raw approval data. Recommended blockers (for APP 009 to codify, not APP 007):
- Any `pending` / `in_progress` approval request on the version.
- Any `rejected` approval request that has not been superseded.
- Any `expired` request whose supersession has not completed a positive outcome.

### 10.3 Approval gates

An "approval gate" is a *policy* APP 009 defines: "release requires at least one `approved` outcome from an approval request of type X". APP 007 does not model gate types in v1 — every approval request is generic. APP 008 or APP 009 may introduce a `gate_kind` column later via amendment.

### 10.4 Event contract for APP 009

APP 007 emits `approval.approved` when an outcome is written. APP 009 subscribes via APP 011 realtime channels and re-runs release readiness computation on the affected version. This is APP 009's responsibility, not APP 007's.

---

## 11. Permissions

### 11.1 Existing frozen capabilities

- `approval.view` — read approval requests and responses.
- `approval.request` — create a new approval request.
- `approval.respond` — cast a decision (approve / reject / abstain).
- `approval.cancel` — cancel a non-terminal request.

### 11.2 New capabilities (APP 007 requires backend re-freeze)

- `approval.veto` — cast a decision with veto power. Distinct from `approval.respond` because vetos are governance-tier decisions typically limited to specific roles (legal, safety, executive).
- `approval.expire` — force-expire a stalled approval before `expires_at`. Rare; used by workspace admin to unstick a request whose approvers are unresponsive.
- `approval.supersede` — create a new approval request that supersedes a prior one. May be granted more narrowly than `approval.request` (only original requester or coordinator).

### 11.3 Recommended role mapping

| Capability | lead | contributor | reviewer | approver | observer |
|---|---|---|---|---|---|
| `approval.view` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `approval.request` | ✓ | ✓ | | | |
| `approval.respond` | | | | ✓ | |
| `approval.cancel` | ✓ | ✓ | | | |
| `approval.veto` | ✓ | | | | |
| `approval.expire` | ✓ | | | | |
| `approval.supersede` | ✓ | ✓ | | | |

`approval.veto` is a governance-tier key that gates *whether the requester can assign someone as a veto-power approver at request creation time*. Distinct from `approval.respond` (which every assigned approver holds). Default granted to `lead` only — matches APP 006's coordinator-capability pattern of restricting powerful capabilities to the lead role.

Workspace admin: `approval.view` only (per PERMISSIONS.md admin-override rule); admin can override to `cancel` / `expire` via `lign_is_workspace_admin` predicate in the relevant RPCs.

### 11.4 Enterprise separation of duties

- **Requester cannot approve their own request.** RPC-enforced: `respond_to_approval` refuses if `auth.uid() = approval_requests.requester_profile_id` and the response row's approver identity resolves to the same profile.
- **Coordinator role** is intentionally absent from APP 007. The requester is the sole non-approver actor. This is a deliberate simplification: approvals have exactly two role types (requester, approver), matching real-world contractual approval flows.
- **Admin override** for cancel/expire is available but every override emits an event with `admin_override=true` in payload for audit.

---

## 12. Query architecture

Append-only additions to `qk`:

```ts
qk.approvalsList(scope, view, filters)
qk.approvalsWorkspaceDashboard(wsId, view)
qk.approvalsProjectDashboard(projId, view)
qk.approvalRequest(id)              // one request + participants + metrics
qk.approvalChain(rootRequestId)     // supersession chain
qk.approvalResponses(requestId)     // response list (Decisions tab)
qk.approvalMetrics(scope)
qk.approvalInboxCount(wsId)
qk.approvalsForVersion(versionId)   // Design Workspace tab + APP 009 read path
```

Reused (unchanged) from prior slices:
- `qk.savedViews(wsId, 'approvals')` (APP 006)
- `qk.bookmarks(wsId, 'approval_request')` (APP 006)
- `qk.projectParticipants(id)` (APP 002)
- `qk.commentsForVersion(id)` (APP 005) — for Approval Detail Comments tab
- `qk.assetVersion(id)` (APP 003), `qk.versionFiles(id)` (APP 004)

Read RPCs (all `SECURITY DEFINER`, capability-checked; the same "RLS composition is expensive" rationale that motivated APP 006's dashboard RPCs applies):

- `list_approvals_dashboard(scope, view, filters, cursor, limit)` — mirrors `list_reviews_dashboard`.
- `get_approval(approval_request_id)` — mirrors `get_review`. Returns request + participants + metrics + chain position + outcome (if terminal).
- `get_approval_chain(root_request_id)` — mirrors `get_review_chain`. Walks supersession lineage.
- `list_approvals_for_version(version_id)` — powers Design Workspace tab and APP 009 release-readiness reads.
- `get_approval_readiness(version_id)` — convenience for APP 009 (summary of "does this version have any approved / any blocking approval").
- `get_approval_inbox_count(ws_id)` — NavRail badge; returns `{awaiting_my_decision, coordinating, expiring_soon}`.
- `get_project_approval_metrics(proj_id)` / `get_workspace_approval_metrics(ws_id)` — metrics strips.

Cache invalidation:

| Mutation | Invalidates |
|---|---|
| `create_approval_request` | `approvalsList(*)`, `approvalInboxCount`, `approvalMetrics(proj)` |
| `send_approval_request` (draft → pending) | same |
| `respond_to_approval` | `approvalRequest(id)`, `approvalResponses(id)`, `approvalsList(*)`, `approvalInboxCount`, `approvalMetrics(*)` |
| `cancel_approval` | `approvalRequest(id)`, `approvalsList(*)`, `approvalInboxCount` |
| `expire_approval` (cron / admin) | same |
| `supersede_approval_request` | `approvalChain(root)`, `approvalsList(*)`, `approvalRequest(id_old)`, `approvalRequest(id_new)` |

Cross-slice:
- APP 005 comment mutation with `target_approval_request_id != null` → additionally invalidate `approvalMetrics(request_id)` (mirrors the APP 006 pattern; APP 007's implementation slice will add the hook).
- APP 006 `review.completed` (via realtime) → APP 007 may refresh approval lists if any request references the review, but this is a **soft coupling** — not required for correctness.

Optimistic updates: **none in v1**. Every mutation is round-trip. Response-casting is deliberately non-optimistic because the outcome computation is authoritative and a race between clients could give inconsistent local state.

---

## 13. Routing

New routes (extending APP 002's authenticated tree):

```
/workspace/:ws_id/approvals                                             workspace dashboard
/workspace/:ws_id/project/:proj_id/approvals                            project dashboard
/workspace/:ws_id/project/:proj_id/approval/:approval_request_id        Approval Detail
```

APP 006 route grammar and every APP 002–005 route pattern remain unchanged.

---

## 14. Deep links

Extends APP 002's `DeepLinkResolver` additively:

```
/deep/approval/:id          → resolves to Approval Detail (previously stubbed since APP 002)
/deep/approver/:participant_id  → resolves to Approval Detail with ?participant=<pid> focused
```

`useCopyLink` (APP 005, extended by APP 006) receives two more `LinkKind` values: `'approval'`, `'approver'`. Purely additive.

---

## 15. URL grammar

Owned by APP 007:

| Param | Values | Meaning |
|---|---|---|
| `?view=<awaiting_me \| awaiting_others \| approved \| rejected \| expired_cancelled \| recent \| bookmarks \| saved:<id>>` | string | Dashboard view selector |
| `?status=<comma-list>` | comma-list of ApprovalRequest states | Status filter |
| `?policy=<comma-list>` | comma-list of policies | Policy filter |
| `?requester=<profile_id>` | uuid | Requester filter |
| `?approver=<profile_id>` | uuid | Approver filter |
| `?expiring=<24h \| week \| overdue>` | keyword | Expiry filter |
| `?participant=<participant_id>` | uuid | Focus a specific approver row in Approval Detail |
| `?tab=comments \| decisions \| files \| activity` | keyword | Approval Detail tab |
| `?approval=<id>` | uuid | Workspace ↔ Approval context flag (set when navigating from an approval into the Design Workspace) |

Reused (unchanged) from prior slices:
- `?discipline`, `?from` (APP 003)
- `?comment`, `?annotation`, `?comments`, `?tab=comments|...` (APP 005) — active in Approval Detail Comments tab
- `?review=<id>` (APP 006 workspace context) — coexists; APP 007 does not modify

No collisions with any prior slice's URL grammar.

---

## 16. Metrics

**Per-request** (delivered by `get_approval`):
- Time to first response (from `pending` → first `respond_to_approval`).
- Time to outcome (from `pending` → terminal state).
- Response distribution `{approved, rejected, abstained, pending}`.
- Whether outcome resulted from veto.
- Time remaining until `expires_at` (if non-terminal).

**Workspace / project** (delivered by `list_approvals_dashboard` and `get_*_approval_metrics`):
- Outstanding count, overdue count (expiring within 24h).
- Rejection rate (trailing 30d).
- Expiration rate (trailing 30d).
- Avg time-to-outcome (trailing 30d).
- Approver throughput (top-5, trailing 30d).

Derivation strategy (matches APP 006): compute from `activity_events` + `approval_responses` state at the RPC layer. No cached-metric columns needed in v1.

---

## 17. Notifications contract (APP 010 will consume)

APP 007 emits nothing client-side. Backend RPCs emit these events; APP 010 subscribes.

### 17.1 Existing frozen events (payload extensions proposed)

- `approval.requested` — extend payload with `policy`, `quorum_min`, `expires_at`, `approver_wm_ids[]`, `approver_sh_ids[]`, `has_veto_power_approver`, `supersedes_approval_request_id`.
- `approval.responded` — extend payload with `decision` (`approved` / `rejected` / `abstained`), `veto_cast`, `sequence_index`, `note_snippet` (first 200 chars of `decision_reason`).
- `approval.cancelled` — extend payload with `admin_override`, `cancellation_reason`.

### 17.2 New event types (APP 007 emits)

- `approval.sent` — `draft → pending` transition (analog of `review.opened`).
- `approval.state_changed` — reserved for any future non-terminal ↔ non-terminal transition (none in v1; type name locked for future policy extensions).
- `approval.approved` — outcome computed positively.
- `approval.rejected` — outcome computed negatively (including veto-triggered).
- `approval.expired` — cron/admin transition.
- `approval.superseded` — a superseding request was created.
- `approval.expired` also carries `admin_override` if triggered by `expire_approval` RPC.

### 17.3 RESERVED event type names (name-locked, emitter deferred)

- `approval.deadline_approached` — scheduled emitter, cron-triggered (analog of `review.deadline_approached`; past-tense per EVENT_MODEL.md §2 verb convention).
- `approval.reminder_sent` — reserved for APP 010 nudge feature.
- `approval.escalated` — reserved for v2 hierarchical policy.

**No emitter for these names is implemented in APP 007.** The names are frozen in the vocabulary so APP 010 / future slices can reference them by exact string.

### 17.4 Recipient rules (APP 010 will codify)

For reference:
- `approval.sent` → all assigned approvers + requester.
- `approval.responded` → requester + other approvers (excluding the responder).
- `approval.approved` / `rejected` / `expired` → requester + all approvers.
- `approval.superseded` → requester of the old + approvers of the old.
- `approval.deadline_approached` → all pending approvers.

---

## 18. Realtime contract (APP 011 will consume)

APP 007 does not implement subscriptions. Channel names to be exported from `src/features/approvals/realtime.ts` as constants:

| Channel | Scope | Invalidates on message |
|---|---|---|
| `workspace:{ws_id}:approvals` | Workspace inbox | `approvalsList(ws, *)`, `approvalInboxCount(ws)` |
| `project:{proj_id}:approvals` | Project dashboard | `approvalsList(proj, *)` |
| `approval:{approval_request_id}` | Single request updates | `approvalRequest(id)`, `approvalResponses(id)` |
| `approval-chain:{root_request_id}` | Supersession chain updates | `approvalChain(root)` |
| `user:{profile_id}:approval-inbox` | Per-user inbox additions | `approvalsList(*, 'awaiting_me')`, `approvalInboxCount` |
| `version:{version_id}:approvals` | Version-scoped approval changes | `approvalsForVersion(version_id)` — used by Design Workspace + APP 009 |

Subscription lifecycle (APP 011 implements):
- Dashboard mount → subscribe to workspace + user inbox channel.
- Approval Detail mount → subscribe to `approval:{id}`.
- Design Workspace mount → subscribe to `version:{id}:approvals` (used by both APP 007 tab and APP 009 readiness computation).

---

## 19. AI extension points

APP 007 does not implement AI. Reserved slots:

| Seam | Where | Purpose |
|---|---|---|
| Approver suggestion | Create-approval composer sidebar | Suggest approvers based on past decisions on similar assets |
| Risk assessment | Approval Detail header | AI-generated risk summary from decision_reasons + version diff |
| Auto-summary | Approval Detail description | Summarize what needs approval from linked review + version changes |
| Similar-outcome baseline | Decision panel | Show historical approval rates for similar requests |
| Rejection reason clustering | Metrics strip | Cluster rejection reasons across the workspace for governance insight |
| Waiver-language suggestion | Decision reason composer | Suggest phrasing for waiver text when a failed requirement is being accepted |

Rendered as `<AISlot kind="..." />` components (naming pattern shared with APP 006). Default: renders nothing. AI slice fills.

---

## 20. Mobile / Desktop behavior

### 20.1 Desktop (≥1024px)

Three-column Approval Detail (version card + decision panel + timeline/chain).
Dashboard table full-width with all columns.
Design Workspace RightPanel Approvals tab renders inline.

### 20.2 Tablet (768–1024px)

Approval Detail collapses to two columns.
Dashboard hides low-priority columns (age, activity); keeps title/status/approvers/deadline.

### 20.3 Mobile (<768px)

**Mobile is a primary use case for approvals** — approvers frequently decide on their phone during meetings.

- Dashboard is a stacked card list.
- Approval Detail single-column, tabs at top.
- Decision panel: three large full-width buttons (Approve / Reject / Abstain).
- Swipe-to-decide on dashboard cards (v1.1 candidate; requires touch gesture handling).
- Long-press card → context menu (bookmark, cancel, copy link).
- Reason field auto-focuses with mobile keyboard on button tap.

### 20.4 Keyboard shortcuts (additive to APP 005/006)

- `A` — approve (in Approval Detail decision panel, when the caller is a pending approver).
- `X` — reject (with confirmation).
- `Shift+A` — abstain.

Composes additively with APP 006's `R`/`E`/`Shift+Enter`. No conflict with APP 005's `C`/`P`/`Esc`.

---

## 21. Backend gaps

Enumerated only. Solutions and priorities belong to a future `APP_007_BACKEND_PROPOSAL.md`.

### 21.1 Schema gaps

- **G-1** `approval_requests.status` — verify enum values match APP 007 lifecycle (`draft`, `pending`, `in_progress`, `approved`, `rejected`, `expired`, `cancelled`, `superseded`). Frozen backend has some subset; verify and expand if needed.
- **G-2** `approval_requests.supersedes_approval_request_id` — likely absent; needed for chain semantics.
- **G-3** `approval_requests.related_review_id` — informational FK to APP 006 `reviews.id`; likely absent.
- **G-4** `approval_requests.policy` — verify enum matches `single | unanimous | majority | quorum | sequential`.
- **G-5** `approval_requests.quorum_min` — verify present.
- **G-6** `approval_requests.expires_at` — verify present.
- **G-7** `approval_requests.cancellation_reason` — mandatory-on-cancel per D-8 style; verify + CHECK.
- **G-8** `approval_responses.required` — required vs optional distinction per approver.
- **G-9** `approval_responses.sequence_index` — sequential policy support.
- **G-10** `approval_responses.veto_power` — per-approver veto flag.
- **G-11** `approval_responses.decision_reason` — mandatory reason on any terminal response.
- **G-12** `approval_responses.decision_metadata` — jsonb for e-signature / IP / device fingerprint (v2 reserved).
- **G-13** Chain integrity CHECK constraints (analogous to review chain).
- **G-14** Chain immutability trigger on `supersedes_approval_request_id` (defense-in-depth).
- **G-15** Response immutability trigger — once `status ≠ pending`, the row is frozen.

### 21.2 RPC gaps

- **G-16** `create_approval_request` — draft creation, additive params for policy/quorum/expires/roster/veto/related_review/supersedes.
- **G-17** `send_approval_request` — `draft → pending` transition (analog of `open_review`).
- **G-18** `expire_approval` — admin-triggered force-expire.
- **G-19** `supersede_approval_request` — creates a new draft that supersedes an existing terminal request; marks the old one `superseded`.
- **G-20** `list_approvals_dashboard` — paginated dashboard read.
- **G-21** `get_approval` — Approval Detail read.
- **G-22** `get_approval_chain` — supersession chain read.
- **G-23** `list_approvals_for_version` — version-scoped list for Design Workspace + APP 009.
- **G-24** `get_approval_readiness` — APP 009 convenience read.
- **G-25** `get_approval_inbox_count` — NavRail badge.
- **G-26** `get_project_approval_metrics`, `get_workspace_approval_metrics` — metrics strips.

### 21.3 RLS gaps

- **G-27** Verify existing `approval_requests` and `approval_responses` policies match the new capabilities (`approval.veto`, `approval.expire`, `approval.supersede`).
- **G-28** No new tables required (bookmarks + saved views reused from APP 006).

### 21.4 Trigger gaps

- **G-29** Response-row immutability trigger.
- **G-30** Chain-immutability trigger (parallel to APP 006's `reviews_chain_immutable`).

### 21.5 Capability gaps

- **G-31** `approval.veto` — new key.
- **G-32** `approval.expire` — new key.
- **G-33** `approval.supersede` — new key.

### 21.6 Event gaps

- **G-34** Payload extensions to `approval.requested`, `approval.responded`, `approval.cancelled` (backwards-compatible; consumers ignore unknown keys).
- **G-35** New event types: `approval.sent`, `approval.approved`, `approval.rejected`, `approval.expired`, `approval.superseded`.
- **G-36** RESERVED event names (name-only): `approval.deadline_approached`, `approval.reminder_sent`, `approval.escalated`. No emitter in APP 007.
- **G-37** Scheduled emitter for `approval.deadline_approached` and auto-expire — belongs to cron slice, outside APP 007.

### 21.7 Cross-slice gaps

- **G-38** APP 005 comment mutations targeting `target_approval_request_id` should invalidate `approvalMetrics(request_id)` — cross-slice hook (matches APP 006 pattern; declared here, implemented in APP 007 implementation slice).

**None of these are blocking to freeze APP 007 architecture** — they are additive backend work to be proposed in an `APP_007_BACKEND_PROPOSAL.md` following the APP 006 wave-based re-freeze pattern.

---

## 22. Open architectural decisions

D-1 through D-10 recorded from the architecture pass. Every decision may be overridden before implementation; each is a one-file adjustment.

| # | Decision | Recommendation |
|---|---|---|
| **D-1** | Rounds? | **No.** Terminal is terminal. Remediation is a new request with `supersedes_approval_request_id`. |
| **D-2** | Loose `related_review_id` link to APP 006? | **Yes**, nullable FK, informational only, not enforced by release/requirement layers. |
| **D-3** | New capabilities `approval.veto`, `approval.expire`, `approval.supersede`? | **Yes**, all three. See §11.3 role map. |
| **D-4** | Explicit `superseded` terminal state? | **Yes**, distinct from `cancelled` so audit shows remediation vs abandonment. |
| **D-5** | Where does approver assignment live — separate table or `approval_responses` with `pending`? | **`approval_responses` with `pending` status** (frozen backend already does this; do not introduce a second table). |
| **D-6** | Saved views + bookmarks? | **Yes**, reuse APP 006 infrastructure with distinct scope/subject_kind values. |
| **D-7** | Coordinator role like APP 006 has? | **No.** Approvals have exactly two roles: requester and approver. Deliberate simplification. |
| **D-8** | Default policy? | **`unanimous`.** Strongest audit posture; opt-in to weaker policies. |
| **D-9** | Confirm-on-decide for reject/abstain? | **Yes**, small confirm dialog. No confirm on approve unless per-project setting opts in (v2 setting). |
| **D-10** | E-signature / IP / device tracking on decisions? | **v2** via `decision_metadata jsonb` column (reserved now; no UI in v1). |
| **D-11** | Requester-cannot-approve-own-request enforcement? | **Yes**, RPC-enforced. Both a check inside `respond_to_approval` and a CHECK on `approval_responses` insertion. |
| **D-12** | Sequential policy: does `abstained` block or advance? | **Blocks**. Advancing requires an explicit `approved` on the current index. |
| **D-13** | Quorum with early rejection: if enough approvers reject that quorum is unreachable, terminate early? | **Yes**, early terminate as `rejected`. |
| **D-14** | Veto with sequential policy: does veto pre-empt sequence order? | **Yes**, veto is orthogonal — a veto approver can reject at any time regardless of sequence. |
| **D-15** | `related_review_id` — must the review be `completed` at time of link? | **No.** Loose FK; requester's responsibility to link a meaningful review. |
| **D-16** | Full-page vs modal Approval Detail? | **Full page** (parallel to APP 006). |
| **D-17** | NavRail badge source? | Workspace-scoped `awaiting_my_decision` count. Cap at 99+. Mirrors APP 006 pattern. |
| **D-18** | Show approval "context banner" when the caller opens the version from Approval Detail? | **Yes**, mirrors APP 006's review context banner. |
| **D-19** | Dashboard cursor semantics? | Server-opaque `(updated_at, id)` tuple, mirrors APP 006 `list_reviews_dashboard`. |
| **D-20** | Should `approvals` outcome table be updated by trigger or by RPC? | **RPC** (`respond_to_approval` computes outcome inline when policy is satisfied; writes `approvals` row transactionally). Matches frozen pattern. |

---

## 23. Freeze contract

On approval of this document, APP 007 architecture commits to:

### 23.1 What APP 007 will own exclusively

- Approval lifecycle, policies, decisions, chains, outcomes.
- Approval dashboards (workspace + project) and their grammar.
- Approval Detail screen and its URL structure.
- Approval-scoped URL parameters.
- New capabilities: `approval.veto`, `approval.expire`, `approval.supersede`.
- New event types: `approval.sent`, `approval.approved`, `approval.rejected`, `approval.expired`, `approval.superseded`.
- RESERVED event names: `approval.deadline_approached`, `approval.reminder_sent`, `approval.escalated`.
- Deep-link kinds: `approval`, `approver`.
- Realtime channel-name constants.
- The Design Workspace RightPanel Approvals tab body.
- Approval-related reusable primitives (see §22 for likely candidates: `DecisionPanel`, `ApprovalChainCard`, potentially a shared `DashboardBody` extracted from APP 006's `ReviewsDashboardBody`).

### 23.2 What APP 007 must not touch

- Comment/annotation semantics (APP 005) — consume only.
- Version-file relationships (APP 004) — read only.
- Project/collection/discipline models (APP 003) — filter/read only.
- Shell, router shape, capability primer, `qk` conventions (APP 002) — extend only.
- Domain-model invariants (APP 001) — honor 7-way XOR, immutability, roles-as-capability-sets.
- Review lifecycle, rounds model, review capabilities, review events (APP 006) — read only via `related_review_id`.
- Storage layer (STORAGE 001–004) — untouched.

### 23.3 What APP 007 promises to future slices

- **APP 008 Requirements UI:** Approval Detail may display a "Requirements status" panel; APP 008 owns the render; APP 007 provides the read hook. Waivers can be linked to approval decisions via a `requirement_waivers` table if introduced later.
- **APP 009 Releases:** Stable read contract via `list_approvals_for_version(version_id)` and `get_approval_readiness(version_id)`. Release readiness computation is APP 009's concern.
- **APP 010 Notifications:** Event vocabulary is stable; APP 010 subscribes without APP 007-side changes.
- **APP 011 Realtime:** Channel names are stable; APP 011 subscribes without APP 007-side changes.
- **AI slice:** `AISlot` seams named and typed; AI slice fills them.

### 23.4 What APP 007 will NOT do in v1

- Not implement realtime subscriptions.
- Not implement notification delivery.
- Not implement AI features.
- Not implement scheduled `expires_at` cron (belongs to the cron slice).
- Not implement e-signature / IP / device tracking (v2).
- Not implement weighted approvals or hierarchical escalation (v2).
- Not implement delegation (v2).
- Not implement release-blocking policies (APP 009's concern).
- Not implement requirement-waiver linkage (APP 008 or later).
- Not modify any file owned by APP 001–006 except by adding new tabs, deep-link kinds, hotkey handlers, URL params, query-key registry entries, and — if needed — extracting shared primitives (e.g. a generic `DashboardBody`) additively without breaking APP 006 consumers.

---

## Canonical routes

```
/workspace/:ws_id/approvals                                             workspace dashboard
/workspace/:ws_id/project/:proj_id/approvals                            project dashboard
/workspace/:ws_id/project/:proj_id/approval/:approval_request_id        Approval Detail
/deep/approval/:id                                                      deep-link resolver
/deep/approver/:participant_id                                          deep-link resolver
```

---

## Canonical query keys

```ts
qk.approvalsList(scope, view, filters)
qk.approvalsWorkspaceDashboard(wsId, view)
qk.approvalsProjectDashboard(projId, view)
qk.approvalRequest(id)
qk.approvalChain(rootRequestId)
qk.approvalResponses(requestId)
qk.approvalMetrics(scope)
qk.approvalInboxCount(wsId)
qk.approvalsForVersion(versionId)
```

Reused (unchanged): `qk.savedViews`, `qk.bookmarks`, `qk.projectParticipants`, `qk.commentsForVersion`, `qk.assetVersion`, `qk.versionFiles`, `qk.review` (informational, when hovering `related_review_id`).

---

## Canonical URL parameters

Owned by APP 007:
```
?view=<awaiting_me | awaiting_others | approved | rejected | expired_cancelled | recent | bookmarks | saved:<id>>
?status=<draft,pending,in_progress,approved,rejected,expired,cancelled,superseded>
?policy=<single,unanimous,majority,quorum,sequential>
?requester=<profile_id>
?approver=<profile_id>
?expiring=<24h | week | overdue>
?participant=<participant_id>
?tab=<comments | decisions | files | activity>
?approval=<id>                    (workspace ↔ approval context flag)
```

Reused (unchanged from prior slices): `?discipline`, `?from`, `?comment`, `?annotation`, `?comments`, `?review`.

---

## Canonical events

Owned by APP 007:

**Existing frozen (extending payload only):**
- `approval.requested`
- `approval.responded`
- `approval.cancelled`

**New (emitted):**
- `approval.sent`
- `approval.approved`
- `approval.rejected`
- `approval.expired`
- `approval.superseded`
- `approval.state_changed` (RESERVED — no non-terminal↔non-terminal transitions in v1; name locked)

**RESERVED (name-only, no emitter in APP 007):**
- `approval.deadline_approached`
- `approval.reminder_sent`
- `approval.escalated`

---

## Canonical reusable primitives

Introduced by APP 007 for downstream slices:

- `DecisionPanel` — the Approve/Reject/Abstain surface, with confirmation, reason field, veto handling. Reusable if any future slice ever needs a binary+ decision surface.
- `ApprovalChainCard` — supersession lineage visualization; pattern reusable for any chain-based domain.
- `ApproverAvatarStack` — variant of APP 006's `ReviewerAvatarStack` with decision chips instead of response chips.
- `useApprovalInboxCount` — hook exported for NavRail consumers.
- `useApprovalReadinessForVersion` — hook exported for APP 009 consumption.
- Realtime channel-name constants (`src/features/approvals/realtime.ts`).

**Potentially extracted from APP 006 as shared primitives** (would require an APP 006 amendment if signatures change; recommendation is APP 007 duplicates rather than modifying APP 006):

- `DashboardBody` — generic (scope, view, filters, RPC-driven) dashboard shell. **Recommended: APP 007 keeps `ApprovalsDashboardBody` as its own component in v1, and a future amendment considers a shared extraction once patterns stabilize across three slices (Reviews + Approvals + Releases).**
- `RosterEditor` — reusable directly from APP 006 without modification. Confirmed usable as-is for approver rosters.

**Extended additively (backward-compatible):**
- `StateBadge` — new `WorkflowState` union members: `approved`, `rejected`, `expired`, `superseded`. Existing 8 members and consumer sites preserved.
- `useCopyLink` — `LinkKind` gains `'approval'`, `'approver'`.
- `useWorkspaceHotkeys` — 3 additive handler slots (`onApprove`, `onReject`, `onAbstain`).
- `DeepLinkResolver` — 2 additive kinds handled with real resolution.

---

## Canonical design tokens

APP 007 introduces **no new design tokens**. Reuses APP 005's generic `--color-state-*` palette. Fills the currently-reserved `--color-state-blocked` token (for `rejected` state) as part of implementation. `--color-state-superseded` (reserved by APP 005) is used for `superseded` state.

Recommended token bindings:
- `approved` → existing `--color-state-resolved` (green).
- `rejected` → previously-reserved `--color-state-blocked` (red family — fills the reservation).
- `expired` → `--color-warning` (existing token).
- `superseded` → previously-reserved `--color-state-superseded` (neutral — fills the reservation).
- `pending` → `--color-state-open` (blue).
- `in_progress` → `--color-state-in-progress` (previously reserved — fill).
- `draft` → neutral surface tokens.

Filling the reserved tokens is additive (declarations added to `globals.css`); no existing token is redefined.

---

## Canonical extension seams

For APP 008–011 and AI:

| Seam | Location | Consumer |
|---|---|---|
| Event payload `admin_override` on `approval.cancelled` / `approval.expired` | Backend event emitter | APP 010 |
| Event payload `supersedes_approval_request_id` on `approval.requested` | Backend event emitter | APP 010, APP 009 |
| `AISlot kind="approver-suggestion"` | Create-approval composer | AI slice |
| `AISlot kind="risk-assessment"` | Approval Detail header | AI slice |
| `AISlot kind="waiver-language"` | Decision reason composer | AI slice |
| `AISlot kind="similar-outcomes"` | Decision panel | AI slice |
| `AISlot kind="rejection-clustering"` | Metrics strip | AI slice |
| Realtime channel constants | `src/features/approvals/realtime.ts` | APP 011 |
| `list_approvals_for_version` RPC | Read RPC | APP 009 |
| `get_approval_readiness` RPC | Read RPC | APP 009 |
| `related_review_id` FK | Schema | APP 006 (informational back-reference; requires no APP 006 change) |
| `decision_metadata jsonb` on responses | Schema (reserved column) | v2 e-signature/audit slice |
| `requirement_waivers` linkage | Not implemented in APP 007 | APP 008 or v2 |

---

## Canonical backend additions required

**Not proposed here** — this is an architecture document. A future `APP_007_BACKEND_PROPOSAL.md` will enumerate migrations, prioritize into waves, and detail exact SQL shapes. Preliminary count (from §21):

- ~15 schema additions (columns + constraints + triggers + chain-integrity CHECKs)
- 11 new RPCs (2 dashboard reads, 3 write flows, 6 support reads)
- Additive params on the frozen `request_approval`, `respond_to_approval`, `cancel_approval` (Option A pattern from APP 006)
- 3 new capability keys
- 5 new event types + 3 RESERVED names + payload extensions to 3 existing events
- 0 new tables (bookmarks + saved views reused from APP 006)
- 2 defense-in-depth triggers (response immutability, chain immutability)
- Scheduled `expires_at` emitter — outside APP 007 (belongs to cron slice)

---

**APP 007 architecture is defined. Ready for review and freeze.**

**Stop.** No backend proposal, no implementation, no code beyond this document.
