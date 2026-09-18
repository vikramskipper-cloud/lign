# LIGN Event Model (v1 — MVP frozen)

Append-oriented domain-event catalog powering Project Design History, Workspace audit, notifications, future analytics, and future AI context. Derived from the frozen `docs/DOMAIN_MODEL.md`, `docs/DATABASE_SCHEMA.md` v0.3, `docs/PERMISSIONS.md`, and `docs/STATE_MACHINES.md` v1.

**Scope.** This document defines the event vocabulary, phase classification (P0 vs P1/P2), routing rules (history / audit / notification), snapshot conventions, transaction-boundary rules, and the MVP notification policy. It **does not** implement SQL, triggers, notification transport, or delivery.

---

## 1. Principles

1. **Storage is `activity_events`**, as specified in `DATABASE_SCHEMA.md` v0.3. **This is a history/audit table, not an event-sourcing spine.** Domain tables remain the source of truth for state.
2. **Events represent committed facts.** An event is emitted from inside the same transaction that made the state change. If the transaction rolls back, no event exists. No fire-and-forget "queue then commit."
3. **Append-only.** No `UPDATE`, no `DELETE` on `activity_events`. Trigger-enforced.
4. **Three disjoint concerns**:
   - **Domain event** — the historical fact.
   - **Notification** — a targeted, actionable prompt to a specific person.
   - **Audit authorization** — who can read the event.
   Decided per event type.
5. **Not every event is a notification.** Design History may be comprehensive; notifications are selective and actionable.
6. **P0 / P1 classification.** The full vocabulary is documented for forward compatibility, but only **P0** events are emitted, delivered, and consumed by the MVP. `P1` and `P2` events are reserved slots — well-named, defined, and not shipped now.
7. **Naming convention** — `entity.action`, past tense where natural, lowercase, dot-separated.
8. **Snapshot minimalism.** `subject_snapshot` carries only fields needed to interpret the event historically.
9. **No new infrastructure.** No Kafka, no queues, no webhooks in MVP. Notifications derive from committed event rows via a Postgres-driven read path.

---

## 2. Naming convention

Format: `<entity>.<action>`. Sub-scoped: `<parent>.<child>.<action>`.

Rules:
- Actions are past-tense verbs.
- Sub-events use the child noun as a segment: `workspace.member.invited`, `project.participant.added`, `release.item_added`.
- Compound actions use snake_case within the segment (`current_version_changed`, `role_changed`, `item_added`).
- Outcome events for lifecycles with multiple terminal states share the entity prefix and diverge on action: `approval.approved`, `approval.rejected`, `approval.cancelled`, `approval.expired`.

---

## 3. Event routing model

For every event, three orthogonal routing decisions:

| Concern | Question | Column |
|---|---|---|
| **Project Design History** | Does this appear in the project's timeline? | `PDH` |
| **Workspace Audit** | Does this appear in the workspace admin audit? | `WA` |
| **Notification** | Does this generate targeted notifications, and to whom? | `Notify` |

Security-sensitive events always flow to workspace admins in the audit view (`Sec = ✓`).

---

## 4. P0 Event Vocabulary

The events LIGN emits, delivers, and consumes at MVP launch. **56 events**, grouped by domain area.

Columns:
- **Actor** — who fires (or `system`).
- **Subject** — `subject_kind` on the `activity_events` row.
- **Project** — populated on `activity_events.project_id` (per `DATABASE_SCHEMA.md` v0.3 §3.25). "—" means NULL (workspace-scoped).
- **PDH / WA / Notify / Sec** — routing decisions.

### 4.1 Workspace administration (11)

| Event | Actor | Subject | Project | Snapshot | PDH | WA | Notify | Sec |
|---|---|---|---|---|---|---|---|---|
| `workspace.created` | user | `workspace` | — | name, slug | — | ✓ | — | — |
| `workspace.member.invited` | user (admin) | `workspace_member` | — | email, role | — | ✓ | invitee (email) | — |
| `workspace.member.activated` | user (invitee) | `workspace_member` | — | role | — | ✓ | inviter | — |
| `workspace.member.role_changed` | user (admin) | `workspace_member` | — | from_role, to_role | — | ✓ | affected member | ✓ |
| `workspace.member.suspended` | user (admin) | `workspace_member` | — | reason (optional) | — | ✓ | affected member | ✓ |
| `workspace.member.removed` | user (admin) | `workspace_member` | — | previous role | — | ✓ | affected member | ✓ |
| `stakeholder.invited` | user (admin) | `stakeholder` | — | email, project(s) invited to | — | ✓ | invitee (email) | — |
| `stakeholder.claimed` | user (claimant) | `stakeholder` | — | invitation_id | — | ✓ | inviter | — |
| `stakeholder.revoked` | user (admin) | `stakeholder` | — | affected project(s) | — | ✓ | affected stakeholder | ✓ |
| `invitation.expired` | system | `invitation` | — | kind, email | — | ✓ | inviter (optional) | — |
| `invitation.revoked` | user (admin) | `invitation` | — | kind, email | — | ✓ | — | — |

### 4.2 Project structure (6)

| Event | Actor | Subject | Project | Snapshot | PDH | WA | Notify | Sec |
|---|---|---|---|---|---|---|---|---|
| `project.created` | user | `project` | self | name, slug | ✓ | ✓ | — | — |
| `project.archived` | user | `project` | self | — | ✓ | ✓ | project participants | — |
| `project.unarchived` | user | `project` | self | — | ✓ | ✓ | project participants | — |
| `project.participant.added` | user | `project_participant` | project | actor kind (member/stakeholder), role | ✓ | ✓ | added participant | — |
| `project.participant.role_changed` | user | `project_participant` | project | from_role, to_role | ✓ | ✓ | affected participant | — |
| `project.participant.removed` | user | `project_participant` | project | previous role | ✓ | ✓ | affected participant | ✓ |

### 4.3 Collections (2)

| Event | Actor | Subject | Project | Snapshot | PDH | WA | Notify | Sec |
|---|---|---|---|---|---|---|---|---|
| `collection.created` | user | `collection` | project | name | ✓ | — | — | — |
| `collection.archived` | user | `collection` | project | — | ✓ | — | — | — |

### 4.4 Design assets (4)

| Event | Actor | Subject | Project | Snapshot | PDH | WA | Notify | Sec |
|---|---|---|---|---|---|---|---|---|
| `asset.created` | user | `design_asset` | project | name, collection_id | ✓ | — | — | — |
| `asset.archived` | user | `design_asset` | project | current_version_id (preserved) | ✓ | — | project participants | — |
| `asset.unarchived` | user | `design_asset` | project | — | ✓ | — | project participants | — |
| `asset.current_version_changed` | user | `design_asset` | project | from_version_id, to_version_id (both nullable), from_sequence, to_sequence | ✓ | — | — (feed-only per D9) | — |

### 4.5 Versions (5)

| Event | Actor | Subject | Project | Snapshot | PDH | WA | Notify | Sec |
|---|---|---|---|---|---|---|---|---|
| `version.uploaded` | user | `asset_version` | project | sequence, asset_id, asset_name | ✓ | — | — | — |
| `version.published` | user | `asset_version` | project | sequence, asset_id, asset_name | ✓ | — | — (feed-only per D8) | — |
| `version.superseded` | user (explicit) | `asset_version` | project | sequence, superseded_by_version_id (optional) | ✓ | — | — | — |
| `version.deprecated` | user (explicit) | `asset_version` | project | sequence, deprecation_note | ✓ | — | — | — |
| `version.draft_discarded` | user | `asset_version` | project | sequence (last held) | ✓ | — | — | — |

`version.superseded` and `version.deprecated` are fired **only on explicit user action** — never as a side effect of `publish_version`.

### 4.6 Files (2)

| Event | Actor | Subject | Project | Snapshot | PDH | WA | Notify | Sec |
|---|---|---|---|---|---|---|---|---|
| `file.attached` | user | `version_file` | project | file_id, asset_version_id, role | ✓ | — | — | — |
| `file.purged` | system | `file` | — | checksum | — | ✓ | — | ✓ |

The meaningful moment for project history is `file.attached` (when a file joins a version). Raw upload without attach is deferred (P1) — a file that is never attached is a maintenance concern, not a design-history moment.

### 4.7 Reviews (5)

| Event | Actor | Subject | Project | Snapshot | PDH | WA | Notify | Sec |
|---|---|---|---|---|---|---|---|---|
| `review.created` | user | `review` | project | title, target version_id | ✓ | — | — | — |
| `review.opened` | user | `review` | project | title, reviewer count | ✓ | — | assigned reviewers | — |
| `review.reviewer_responded` | user (reviewer) | `review_participant` | project | review_id, reviewer_status (`commented` / `signed_off` / `declined`) | ✓ | — | review creator | — |
| `review.completed` | user | `review` | project | title, outcome summary | ✓ | — | review creator, assigned reviewers | — |
| `review.cancelled` | user | `review` | project | title, reason | ✓ | — | review creator, assigned reviewers | — |

### 4.8 Comments & annotations (8)

| Event | Actor | Subject | Project | Snapshot | PDH | WA | Notify | Sec |
|---|---|---|---|---|---|---|---|---|
| `comment.created` | user | `comment` | project | target_kind, target_id, parent_comment_id | ✓ | — | — | — |
| `comment.edited` | user | `comment` | project | revision number | ✓ | — | — | — |
| `comment.mentioned` | user (comment author) | `comment` | project | comment_id, target_kind, mentioned_profile_id | ✓ | — | mentioned participant | — |
| `comment.resolved` | user | `comment` | project | target_kind | ✓ | — | comment author | — |
| `comment.reopened` | user | `comment` | project | target_kind | ✓ | — | comment author | — |
| `comment.deleted` | user | `comment` | project | target_kind | ✓ | — | — | — |
| `annotation.created` | user | `annotation` | project | asset_version_id, version_file_id, anchor_kind, page_number | ✓ | — | — | — |
| `annotation.resolved` | user | `annotation` | project | — | ✓ | — | annotation author | — |
| `annotation.archived` | user | `annotation` | project | — | ✓ | — | — | — |

`comment.mentioned` is one event **per mentioned participant**. A single comment may emit multiple `comment.mentioned` rows. See §5.4 for mention scope and semantics.

### 4.9 Changes (4)

| Event | Actor | Subject | Project | Snapshot | PDH | WA | Notify | Sec |
|---|---|---|---|---|---|---|---|---|
| `change.created` | user | `change` | project | asset_id, title | ✓ | — | project leads | — |
| `change.accepted` | user | `change` | project | title, to_version_id (optional) | ✓ | — | change author | — |
| `change.rejected` | user | `change` | project | title | ✓ | — | change author | — |
| `change.withdrawn` | user | `change` | project | title | ✓ | — | change author | — |

### 4.10 Decisions (1)

| Event | Actor | Subject | Project | Snapshot | PDH | WA | Notify | Sec |
|---|---|---|---|---|---|---|---|---|
| `decision.recorded` | user | `decision` | project | title, target_kind, target_id | ✓ | — | project leads (feed) | — |

### 4.11 Approvals (6)

| Event | Actor | Subject | Project | Snapshot | PDH | WA | Notify | Sec |
|---|---|---|---|---|---|---|---|---|
| `approval.requested` | user | `approval_request` | project | asset_id, asset_name, version_id, version_sequence, policy, approver_count, due_at | ✓ | — | approvers (all slots) — **email-eligible** (see §5.6) | — |
| `approval.responded` | user (approver) | `approval_response` | project | request_id, decision (`approved` / `rejected` / `changes_requested`), asset_name, version_sequence | ✓ | — | request creator | — |
| `approval.approved` | system (inside RPC) | `approval_request` | project | asset_id, version_id, policy | ✓ | — | request creator, project leads (per D10) | — |
| `approval.rejected` | system (inside RPC) | `approval_request` | project | asset_id, version_id, policy | ✓ | — | request creator, project leads (per D10) | — |
| `approval.cancelled` | user | `approval_request` | project | asset_id, version_id, reason | ✓ | — | approvers | — |
| `approval.expired` | system | `approval_request` | project | asset_id, version_id | ✓ | — | request creator, project leads | — |

`approval.responded` fires per response and carries the individual `decision` value. Outcome events (`approval.approved` / `.rejected` / `.cancelled` / `.expired`) fire once when the request terminates.

### 4.12 Releases (5)

| Event | Actor | Subject | Project | Snapshot | PDH | WA | Notify | Sec |
|---|---|---|---|---|---|---|---|---|
| `release.created` | user | `release` | project | name | ✓ | — | — | — |
| `release.item_added` | user | `release_item` | project | release_id, asset_id, asset_name, version_id, version_sequence | ✓ | — | — | — |
| `release.item_removed` | user | `release_item` | project | release_id, asset_id, version_id | ✓ | — | — | — |
| `release.finalized` | user | `release` | project | name, item_count, channel | ✓ | ✓ | project participants | ✓ |
| `release.withdrawn` | user | `release` | project | reason | ✓ | ✓ | project participants | ✓ |

**APP 009 additive payload keys (per §11).** All five frozen `release.*` events gain optional additive keys under `subject_snapshot`; consumers ignore unknown keys per the APP 007 §17.1 precedent. Every frozen key above is preserved byte-for-byte:

- `release.created` — adds: `release_type`, `code`, `created_by_profile_id`, `channel`.
- `release.item_added` — adds: `release_type`, `item_id`, `sort_order`, `notes_snippet`.
- `release.item_removed` — adds: `release_type`, `item_id`.
- `release.finalized` — adds: `release_type`, `published_by_profile_id`, `approved_request_ids[]`, `requirement_readiness`, `review_count`, `superseded_prior_release_id` (NULL in v1).
- `release.withdrawn` — adds: `release_type`, `withdrawn_by_profile_id`, `admin_override`.

The `release.created` / `release.item_added` / `release.item_removed` names were already frozen in this document (below); APP 009 supplies the emitters (`create_release_draft`, `add_release_item`, `remove_release_item`).

### 4.13 Requirements (4)

Added by REQUIREMENTS 004. All emissions are user-actor; there is no system variant for the requirements lifecycle.

| Event | Actor | Subject | Project | Snapshot | PDH | WA | Notify | Sec |
|---|---|---|---|---|---|---|---|---|
| `requirement.created` | user | `requirement` | project | code, title, parent_requirement_id, initial_status | ✓ | — | — | — |
| `requirement.updated` | user | `requirement` | project | code, kind ∈ (`edit` / `supersede` / `applicability`), changed_fields[], previous_status, new_status, superseded_by_requirement_id, superseded_by_code, added, removed, kept, now_project_wide | ✓ | — | — | — |
| `requirement.archived` | user | `requirement` | project | code, previous_status | ✓ | — | — | — |
| `requirement.assessed` | user | `version_requirement_assessment` | project | code, requirement_id, asset_version_id, status, previous_status, action ∈ (`created` / `updated`) | ✓ | — | — | — |

`requirement.updated` is a single event type discriminated by `subject_snapshot.kind`. Emission rules:
- `create_requirement` → always emits `requirement.created`.
- `edit_requirement` → emits `requirement.updated` **iff at least one field actually changed** (no-op edits emit nothing and return `out_updated=false`).
- `archive_requirement` → emits `requirement.archived` **only on new transition** (idempotent second call emits nothing).
- `supersede_requirement` → always emits `requirement.updated` with `kind='supersede'`.
- `set_requirement_applicability` → emits `requirement.updated` with `kind='applicability'` **iff added + removed > 0** (no-op set emits nothing).
- `assess_version_requirement` → always emits `requirement.assessed` (on both insert and update; carries `previous_status`).

The `subject_kind='version_requirement_assessment'` on the assessment event is deliberate — assessments are their own subject, distinct from the requirement they measure. All other requirement events use `subject_kind='requirement'`. `subject_label` is the requirement `code` (e.g. `R-001`, `R-001.1`) for all four events.

Deferred (not emitted in MVP): `requirement.deleted` (requirements are archived, not deleted); `requirement.orphaned`; `requirement.stale`.

### 4.14 Summary counts

- **P0 events: 60** (56 pre-REQUIREMENTS + 4 requirement.*)
- With PDH visibility: **51**
- With Workspace Audit visibility: **20**
- With notifications: **24** (requirement.* events are feed-only in MVP — no notifications)
- Security-sensitive: **9**

---

## 4.15 Reserved (P1 / P2 — not emitted in MVP)

Documented so the vocabulary is forward-compatible. **These are not implemented, delivered, or read in MVP.** Reserved names are stable — MVP code should treat any of these appearing as unknown and ignore them.

| Reserved event | Reason deferred |
|---|---|
| `workspace.updated` | Trivial metadata change; not a design or audit priority for MVP. |
| `project.updated` | Trivial metadata change. |
| `project.activated` | Project draft workflow removed from MVP. |
| `project.on_hold` / `project.resumed` | On-hold workflow removed from MVP. |
| `project.closed` | Closure workflow removed from MVP. |
| `collection.updated` | Trivial metadata change. |
| `asset.updated` | Trivial metadata change. |
| `asset.deprecated` / `asset.reactivated` | Asset-level deprecation workflow removed from MVP; iteration handled via Versions. |
| `file.uploaded` | Redundant with `file.attached`. Bare uploads with no attachment are a maintenance concern. |
| `file.orphaned` | System maintenance; not a user-facing history moment. |
| `annotation.reopened` | Toggle; low audit value. |
| `change.under_review` / `change.implemented` | Not part of MVP Change lifecycle (`proposed → accepted | rejected | withdrawn`). |
| `decision.superseded` | Rare; deferred until the supersession UX exists. |
| `release.scheduled` | `scheduled` state removed from MVP release lifecycle. Reaffirmed by APP 009 F-5 Wave 1 doc-diff. |
| `release.superseded` | Automatic release supersession removed from MVP. Reaffirmed by APP 009 F-5 Wave 1 doc-diff. Wave 4 emitter attached to the reserved `create_release_superseding` RPC. |
| `release.item_removed` (P1 audit view) | Emitted P0 (item_removed is meaningful) — no change. |
| `release.notes_updated` | Reserved by APP 009 §12.2 for post-release note edits (§10.3 Notes tab v2). No emitter in v1. |
| `release.audit_exported` | Reserved by APP 009 §12.2 for PDF/CSV evidence export (Freeze Index §25.5). No emitter in v1. |
| `release.recalled` | Reserved by APP 009 §12.2 for the recall variant of withdrawal (G-35), distinct from `release.withdrawn`. No emitter in v1. |
| `release.ai_suggested` | Reserved by APP 009 §12.2 for AI-assisted release-notes generation. No emitter in v1. |
| `release.ai_classified` | Reserved by APP 009 §12.2 for AI-assisted `release_type` classification. No emitter in v1. |

**Total reserved: 20** (15 pre-APP 009 + 5 new APP 009 reservations). MVP will not emit these; the taxonomy is preserved for future compatibility.

---

## 5. Snapshot Conventions

`subject_snapshot` is a **JSONB dictionary** carrying only fields needed to interpret the event when the subject is later renamed, archived, or deleted.

**Rules:**
- Include human-readable identifiers (asset name, version sequence, project slug).
- Include ids referenced in the payload for cross-linking.
- **Never** include full row contents. Never include comment bodies, file contents, or annotation position blobs.
- **Never** include secrets (invitation tokens).
- `subject_label` is the short human string for feeds ("Kitchen Layout · v3"). Immutable after emission.

**Examples:**

| Event | `subject_label` | `subject_snapshot` |
|---|---|---|
| `version.published` | `Kitchen Layout · v3` | `{ "asset_id": "…", "asset_name": "Kitchen Layout", "sequence": 3 }` |
| `approval.approved` | `Approval on Kitchen Layout · v3` | `{ "asset_id": "…", "asset_name": "Kitchen Layout", "version_id": "…", "sequence": 3, "policy": "all", "response_count": 3 }` |
| `release.finalized` | `Release: Q1 Client Package` | `{ "release_id": "…", "name": "Q1 Client Package", "channel": "client", "item_count": 12 }` |
| `workspace.member.role_changed` | `Alice — admin → member` | `{ "member_id": "…", "profile_id": "…", "from_role": "admin", "to_role": "member" }` |
| `asset.current_version_changed` | `Kitchen Layout · Current v6 → v7` | `{ "asset_id": "…", "from_version_id": "…", "to_version_id": "…", "from_sequence": 6, "to_sequence": 7 }` |
| `comment.mentioned` | `@Alex in Kitchen Layout · v3` | `{ "comment_id": "…", "target_kind": "asset_version", "target_id": "…", "mentioned_profile_id": "…" }` |

Snapshot is the historical anchor. Once written, immutable.

---

## 6. Transaction Boundaries

Each important operation maps `State transition → DB transaction → Domain event(s) → Notification(s)`. Events are `INSERT`ed into `activity_events` inside the same transaction that commits the state change. Notifications derive from committed rows.

| Operation | RPC | State transitions | Events emitted (same TX) | Notifications derived |
|---|---|---|---|---|
| Create Project | `create_project` | `projects: ∅ → active`; `project_participants: ∅ → active (lead)` | `project.created`, `project.participant.added` | added participant |
| Add Project Participant | `add_project_participant` (RPC recommended for dual-path check) | `project_participants: ∅ → active` | `project.participant.added` | added participant |
| Upload / Create Version | `upload_and_attach_version_file` | `asset_versions: ∅ → draft`; may `files: ∅ → active`; `version_files: ∅ → attached` | `version.uploaded`, `file.attached` (per attached file) | — |
| Publish Version | `publish_version` | `asset_versions: draft → published` (no supersede side-effect) | `version.published` | — (feed-only per D8) |
| Set Current Version | `set_current_version` | `design_assets.current_version_id` reassigned | `asset.current_version_changed` | — (feed-only per D9) |
| Request Review | `create_review` (single-step create + open) | `reviews: ∅ → draft → open`; `review_participants: ∅ → pending` per slot | `review.created`, `review.opened` | assigned reviewers |
| Complete Review | `complete_review` | `reviews: * → completed`; freezes contained comments' editability | `review.completed` | review creator, assigned reviewers |
| Resolve Comment | direct write under RLS + capability | `comments.resolved_at` set | `comment.resolved` | comment author |
| Record Decision | direct write under RLS + capability | `decisions: ∅ → recorded` (immutable) | `decision.recorded` | project leads (feed) |
| Request Approval | `request_approval` | `approval_requests: ∅ → in_progress` (direct — no pending step); `approval_request_approvers: ∅ → pending` per slot | `approval.requested` | approvers (in-app + email per §5.6) |
| Respond to Approval | `respond_to_approval` | `approval_responses: ∅ → submitted`; may finalize parent request under row lock | `approval.responded`; possibly `approval.approved` or `approval.rejected` in same TX | in-app: request creator (always); on outcome: creator + project leads |
| Finalize Approval (expiry) | `finalize_approval` (scheduler) | `approval_requests: in_progress → expired` | `approval.expired` | request creator + project leads |
| Cancel Approval | `cancel_approval` | `approval_requests: in_progress → cancelled` | `approval.cancelled` | approvers |
| Create Release | `create_release` | `releases: ∅ → draft` | `release.created` | — |
| Add ReleaseItem | `add_release_item` | `release_items: ∅ → attached` (parent still draft) | `release.item_added` | — |
| Finalize Release | `finalize_release` | `releases: draft → released` (DB-boundary: every item's version has `approved` request) | `release.finalized` | project participants |
| Archive Design Asset | direct or RPC | `design_assets: active → archived`; `current_version_id` preserved | `asset.archived` | project participants |
| Remove WorkspaceMember | `remove_workspace_member` | `workspace_members: * → removed`; sole-owner check | `workspace.member.removed` | affected member |
| Revoke Stakeholder | `revoke_stakeholder` | `stakeholders: * → revoked`; related `project_participants → removed` | `stakeholder.revoked`, one `project.participant.removed` per revoked participation | affected stakeholder |
| Accept Invitation (member) | `accept_invitation` | `invitations: sent → accepted`; `workspace_members: invited → active` | `workspace.member.activated` | inviter |
| Claim Stakeholder Invitation | `claim_stakeholder_invitation` | `invitations: sent → accepted`; `stakeholders: invited → active`; `stakeholders.user_id = auth.uid()` | `stakeholder.claimed` | inviter |
| Edit Own Comment | `edit_own_comment` | `comments.body` updated; `comment_edits: ∅ → recorded`; may emit new mentions | `comment.edited`; possibly `comment.mentioned` per new mention | mentioned participants (in-app) |

**Notification derivation happens after commit.** No notification for an uncommitted event.

---

## 5. Notifications  <!-- (numbering kept from prior version; §7 below) -->

*(See §7.)*

---

## 7. Notifications

Selective and actionable. Project Design History carries the full record; notifications are the subset that require a person's attention.

### 7.1 Recipient tokens

- **assigned reviewers** — active `review_participants` on the review.
- **approvers** — `approval_request_approvers` for the request whose slot is not yet responded (or the full frozen set for outcome events).
- **request creator** — `approval_requests.created_by_profile_id`.
- **review creator** — `reviews.created_by_profile_id`.
- **project participants** — all active `project_participants` of the row's project.
- **project leads** — active participants with role `lead`.
- **affected member / stakeholder / participant** — the profile who is the subject.
- **inviter** — `invitations.invited_by_profile_id`.
- **comment / annotation / change / decision author** — the `author_profile_id` on the subject.
- **mentioned participant** — the `mentioned_profile_id` on a `comment.mentioned` event.
- **invitee (email)** — for events fired before the invitee has a profile.

### 7.2 MVP notification policy — always actionable

- `review.opened` → assigned reviewers.
- `approval.requested` → approvers (in-app **and** transactional email; §7.6).
- `approval.responded` → request creator.
- `approval.approved` / `approval.rejected` → **request creator + project leads** (per D10; not all approvers).
- `approval.expired` → request creator + project leads.
- `approval.cancelled` → approvers (they need to know it's no longer waiting on them).
- `release.finalized` / `release.withdrawn` → project participants (one notification per event, not per item).
- `workspace.member.role_changed` / `.suspended` / `.removed` → affected member (security-sensitive).
- `stakeholder.revoked` → affected stakeholder.
- `project.participant.added` / `.role_changed` / `.removed` → affected participant.
- `comment.mentioned` → mentioned participant (in-app).

### 7.3 Feed-only (no notification)

- `version.published` (D8).
- `asset.current_version_changed` (D9).
- `decision.recorded` (feed-only for leads; no push).
- `comment.created` (feed-only; only `comment.mentioned` generates a notification).
- `annotation.*` (feed-only, except `annotation.resolved` notifies annotation author).
- `change.*` (author + leads via feed; low broadcast).
- `asset.archived` / `asset.unarchived` / `project.archived` / `project.unarchived` — project participants notified.
- All workspace-admin events except member-affecting ones.

### 7.4 Events that never notify

Audit-only or feed-only: `workspace.created`, `project.created`, `collection.*`, `asset.created`, `version.uploaded`, `version.superseded`, `version.deprecated`, `version.draft_discarded`, `file.attached`, `file.purged`, `annotation.created`, `annotation.archived`, `comment.created`, `comment.edited`, `comment.deleted`, `invitation.expired`, `invitation.revoked`, `decision.recorded`, `release.created`, `release.item_added`, `release.item_removed`.

### 7.5 Mentions (§4.8 detail)

- MVP supports **simple person mentions**. A mention is an `@`-prefix token in a comment body that resolves to a profile who is an active `project_participants` of the comment's project.
- Unrecognized mentions produce no event.
- The parser is intentionally simple: no groups, no teams, no roles.
- `comment.mentioned` is emitted **once per resolved mention** inside the same transaction as `comment.created` or `comment.edited`.
- New mentions on `comment.edited` are notified; already-mentioned profiles are not re-notified.
- The mentioned profile receives an in-app notification. RLS still applies: the mentioned person must have access to the comment's target for the linked entity to load.
- No group mentions. No team mentions. No notification-preference infrastructure.

### 7.6 Delivery mechanism (MVP)

- **In-app notifications** — derived from committed `activity_events` rows targeting the recipient. No separate notifications persistence in MVP; per-user unread state deferred to P1.
- **Transactional email** — MVP email is limited to:
  - **Invitation email**: `workspace.member.invited` and `stakeholder.invited` (recipient has no profile yet — email is the only channel).
  - **`approval.requested`**: external approvers may not regularly open LIGN; a transactional email prompts them (per D13).
- **No push, no SMS, no configurable channels, no digest, no per-user preferences.**

### 7.7 What notifications never do

- Never bypass RLS. Recipients still need access to the underlying subject to read the linked entity.
- Never expose content the recipient could not otherwise see.
- Never fire before the transaction commits.

---

## 8. Event Immutability

- **Append-only.** `activity_events` INSERT is allowed only from RPCs and triggers. `UPDATE`/`DELETE` denied at DB level. (`DATABASE_SCHEMA.md` v0.3 §3.25.)
- **Who may create events.** Only server-side code paths: RPC functions and audit triggers. Direct user INSERT denied by RLS (`PERMISSIONS.md` §8 Group K).
- **Who may read events.** Workspace owner/admin see all workspace events; project participants see events for their accessible projects (`project_id IS NOT NULL AND lign_is_project_participant(project_id)`).
- **Why normal users cannot update/delete.** Audit integrity.
- **System-generated events.** `actor_kind='system'`, `actor_profile_id=NULL`. Examples: `invitation.expired`, `approval.expired`, `file.purged`, `approval.approved` / `.rejected` (outcome events fired inside RPC on final response).
- **Snapshot behavior.** `subject_snapshot` and `subject_label` are frozen at emission. Later renames or archives do not update historical events. `subject_id` is intentionally not a foreign key.

---

## 9. Non-goals

- No event sourcing.
- No message broker, no Kafka, no external event streaming.
- No webhooks in MVP.
- No configurable notification rules per user.
- No workflow builder, no automation engine.
- No comprehensive-notification firehose.
- No email digest, no push, no SMS in MVP.
- No cross-workspace notifications.
- No custom mention infrastructure (no groups, no teams, no roles as mention targets).

---

## 10. Resolved decisions

All prior open decisions resolved by approved product decisions:

| # | Question | Resolution |
|---|---|---|
| D1 | Auto-supersede on publish? | **No.** `publish_version` emits only `version.published`. Multiple published versions may coexist. `version.superseded` fires only on explicit action. |
| D2 | `pending → in_progress` for approval requests? | **Collapsed.** `request_approval` creates directly in `in_progress`; `approval.requested` is the sole creation event. |
| D3 | Release `scheduled` state? | **Removed from MVP.** `release.scheduled` is P1/P2 reserved. |
| D4 | Comment resolve/reopen toggle? | **Both allowed.** `comment.resolved` and `comment.reopened` are P0. |
| D5 | Annotation `archived` terminal? | **Yes.** `annotation.reopened` deferred as P1. |
| D6 | Accepted changes stay accepted? | **Yes**, indefinitely. Linking `to_version_id` is metadata, not a transition; no event. |
| D7 | Auto-supersede releases? | **No.** `release.superseded` is P1/P2 reserved. |
| D8 | `version.published` notification? | **None.** Feed-only. |
| D9 | `asset.current_version_changed` notification? | **None.** Feed-only. |
| D10 | Approval outcome notification recipients? | **Request creator + project leads.** Not all approvers. |
| D11 | Mentions in MVP? | **Yes (P0).** `comment.mentioned` event; in-app notification to mentioned participant. No groups, no teams, no preferences. |
| D12 | Per-user notification preferences UI? | **No** in MVP. |
| D13 | Email channels? | **Invitation emails** + **`approval.requested`** transactional email. No other channels; no digest. |

MVP-simplification decisions from `STATE_MACHINES.md` §18 are reflected in this vocabulary through the P1/P2 reserved list (§4.14).

---

## 11. APP 010 Wave 1 doc-diff — RESERVED `notification.*` event names

APP 010 introduces the `notification.*` event namespace. All names below are **RESERVED** (name-locked, past-tense, zero emitters in APP 010 v1). Future waves (AI slice, cron/digest slice) bind against fixed strings. APP 010's router explicitly ignores any event whose `event_type` matches `notification.%` (Freeze Index G-16, G-22; F-2 explicit recursion guard at step 1a of `resolve_notification_router_targets`).

| Event | Fires when (future) | Wave |
|---|---|---|
| `notification.ai_prioritized` | The AI slice re-orders the recipient's inbox by learned priority | Future (AI slice) |
| `notification.ai_summarized` | An AI-generated summary of a recipient's inbox is materialized | Future (AI slice) |
| `notification.digest_sent` | A batched digest is delivered to a recipient | Future (cron/digest slice) |

All three names are locked by APP 010 Wave 1. Zero emitters exist in APP 010 v1; the names are registered here so the AI/cron slices can bind against fixed strings without rename churn.

