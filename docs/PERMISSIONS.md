# LIGN Authorization & RLS Architecture (v0)

This document specifies LIGN's authorization model and Supabase Row-Level-Security (RLS) design against the approved `docs/DOMAIN_MODEL.md` and `docs/DATABASE_SCHEMA.md` (v0.2). **No RLS SQL, migrations, or Supabase changes are implemented here** — this is a spec awaiting review.

---

## 1. Principles

Identity, participation, and authorization are three separate concepts that never fuse.

| Concept | Row(s) | Purpose |
|---|---|---|
| **Identity** | `auth.users` + `profiles` | Who the person is. Global. Authenticated. The historical-attribution anchor. |
| **Workspace membership** | `workspace_members` | A `Profile`'s organizational relationship to one workspace, with a workspace role. Not the same as project access. |
| **Workspace stakeholder directory** | `stakeholders` | An external identity scoped by (workspace, email). Not the same as project access. |
| **Project participation** | `project_participants` | A member or stakeholder on the roster of one project, with a project role. The sole authorization join for project access. |
| **Role** | text on `workspace_members.role` / `project_participants.role` | A named preset of capabilities. |
| **Capability** | conceptual verb (`version.publish`, etc.) | The actual authorization decision. Every check in the system evaluates a capability. |

**Rules of engagement.**
1. Authorization is **capability-based**, never class-based. Membership class (WorkspaceMember vs Stakeholder) never gates any action.
2. Authorship (`author_profile_id`, `published_by_profile_id`, etc.) is not authorization. It is a historical record of *who did* the action, validated *when* the action was performed.
3. Professional titles (architect, contractor, client, vendor, designer) are metadata only. They never appear in an authorization predicate.
4. A `WorkspaceMember` does **not** automatically have access to every project of the workspace. Project access is separately granted via `project_participants` — **except** for workspace administrators who hold an *administrative* access path (see §5).
5. Nothing in the schema or in the frontend is trusted. All authorization is enforced by RLS + controlled RPC functions at the database boundary.

---

## 2. Capability Catalog

Capabilities are enforceable verbs. They live in application code (as constants) and are evaluated by RLS predicates and RPC functions. Roles map to capability sets; the mapping table is authoritative.

The catalog below is deliberately compact — 44 capabilities. Anything finer-grained (e.g., "asset.rename" vs "asset.change_status") is folded into a broader verb (`asset.edit`).

### 2.1 Workspace
- `workspace.view` — see workspace metadata.
- `workspace.manage` — edit workspace name, branding, settings.
- `workspace.manage_members` — invite/remove/change-role `workspace_members`.
- `workspace.manage_stakeholders` — invite/revoke `stakeholders` at the workspace directory level (specific project assignments still use `project.manage_access`).

### 2.2 Project
- `project.view`
- `project.create` — create a new project in the workspace.
- `project.edit`
- `project.manage_access` — add/remove/change-role `project_participants`.
- `project.archive`

### 2.3 Collection
- `collection.view`
- `collection.create`
- `collection.edit`
- `collection.archive`

### 2.4 Design Asset
- `asset.view`
- `asset.create`
- `asset.edit`
- `asset.archive`
- `asset.set_current` — the sole path to change `design_assets.current_version_id`.

### 2.5 Version
- `version.view`
- `version.upload` — create a `draft` `asset_version` and attach `version_files` to it.
- `version.publish` — transition a version `draft → published`.
- `version.discard_draft` — hard-delete a not-yet-published draft.

### 2.6 Review
- `review.view`
- `review.create`
- `review.participate` — act as an assigned reviewer (respond, sign off, decline).
- `review.complete` — finalize or cancel a review.

### 2.7 Comment
- `comment.view`
- `comment.create`
- `comment.edit_own` — edit a comment you authored (produces a `comment_edits` row).
- `comment.resolve` — mark a comment as resolved.

### 2.8 Annotation
- `annotation.view`
- `annotation.create`
- `annotation.resolve`

### 2.9 Change
- `change.view`
- `change.create`
- `change.resolve` — transition to `accepted`/`rejected`/`implemented`/`withdrawn`.

### 2.10 Decision
- `decision.view`
- `decision.create`

### 2.11 Approval
- `approval.view`
- `approval.request` — create an `approval_requests` (freezing an approver set).
- `approval.respond` — submit an `approval_responses` against a slot you hold.
- `approval.cancel`

### 2.12 Release
- `release.view`
- `release.create`
- `release.finalize` — transition `draft → released` (enforces the release-approval invariant).
- `release.withdraw`

### 2.13 File / storage-adjacent
- `file.upload` — create a `files` row (independent of any version).
- `file.attach` — insert a `version_files` row against a draft version.
- `file.download` — read file bytes via Supabase Storage.
- `file.remove_orphaned` — trigger the orphan-purge for a file with zero references.

### 2.14 Audit
- `activity.view` — read `activity_events` for the accessible scope.

### 2.14a Requirement (added by REQUIREMENTS 003)
- `requirement.view` — read requirements, applicability, and version-requirement assessments. **View-class**: workspace administrators receive it via admin override (mirrors `project.view`, `asset.view`).
- `requirement.create` — insert a new requirement into a project (server generates the code `R-NNN` root or `<parent>.<n>` sub).
- `requirement.edit` — mutate non-structural fields (title, description, category, source, source_ref), toggle status draft↔active, supersede a requirement, and change applicability. Does NOT allow editing code, workspace_id, project_id, or parent_requirement_id (immutable per REQUIREMENTS 002 triggers).
- `requirement.archive` — transition a draft/active requirement to archived. Not granted to contributors (creative-vs-lead split preserved).
- `requirement.assess` — record or update a `version_requirement_assessment` (status ∈ satisfied / partial / not_satisfied / not_applicable). Assessor is always `auth.uid()`.

### 2.15 Capabilities identified as missing from the task list
- `workspace.manage_stakeholders` — necessary because Stakeholder identity management is workspace-scoped and distinct from adding a participant to a specific project.
- `project.create` — the "create a project inside my workspace" verb, at workspace scope.
- `collection.archive`, `version.discard_draft`, `change.create` / `change.resolve`, `annotation.create` / `annotation.resolve`, `approval.cancel`, `release.withdraw`, `file.upload` / `file.attach` / `file.download` / `file.remove_orphaned`, `activity.view` — all needed to cover the lifecycle described in the domain model.

---

## 3. Role Presets

Roles are named capability bundles. They are **presets**, not authorization classes — a workspace may in future customize the mapping. Membership class (WorkspaceMember vs Stakeholder) does not restrict which project roles are available; **any project role listed below may be held by either a WorkspaceMember or a Stakeholder**.

### 3.1 Workspace roles

Applies to `workspace_members.role`. Distinct from project participation; workspace administrators do not automatically hold project capabilities.

**MVP workspace roles: `owner`, `admin`, `member`.** `guest` is **not** part of the MVP model — external / project-limited participation is expressed through `stakeholders`, not through a workspace role.

| Capability | `owner` | `admin` | `member` |
|---|---|---|---|
| `workspace.view` | ✓ | ✓ | ✓ |
| `workspace.manage` | ✓ | ✓ | |
| `workspace.manage_members` | ✓ | ✓ | |
| `workspace.manage_stakeholders` | ✓ | ✓ | |
| `project.create` | ✓ | ✓ | ✓ |
| **Administrative access to any project** (see §5) | ✓ | ✓ | |
| `activity.view` at workspace scope | ✓ | ✓ | |

`member` can create projects and must be added to specific projects to see their content. Creating a project makes them the first `project_participants` with role `lead`.

`project.create` is granted to `member` by default in MVP. There is no configurable workspace-level setting to change this in MVP.

### 3.2 Project roles (task-list presets ↔ domain roles)

| Task-list preset | Domain role (`project_participants.role`) |
|---|---|
| Creator | `lead` |
| Collaborator | `contributor` |
| Reviewer | `reviewer` |
| Approver | `approver` |
| Viewer | `observer` |

Default capability matrix (project-scoped verbs — plus `file.download` which is scoped to a project's files):

| Capability | Creator (`lead`) | Collaborator (`contributor`) | Reviewer (`reviewer`) | Approver (`approver`) | Viewer (`observer`) |
|---|---|---|---|---|---|
| `project.view` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `project.edit` | ✓ | | | | |
| `project.manage_access` | ✓ | | | | |
| `project.archive` | ✓ | | | | |
| `collection.view` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `collection.create` / `edit` / `archive` | ✓ | ✓ | | | |
| `asset.view` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `asset.create` / `edit` / `archive` | ✓ | ✓ | | | |
| `asset.set_current` | ✓ | ✓ | | | |
| `version.view` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `version.upload` / `publish` / `discard_draft` | ✓ | ✓ | | | |
| `review.view` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `review.create` | ✓ | ✓ | | | |
| `review.participate` | | | ✓ | | |
| `review.complete` | ✓ | ✓ | | | |
| `comment.view` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `comment.create` / `edit_own` | ✓ | ✓ | ✓ | ✓ | |
| `comment.resolve` | ✓ | ✓ | | | |
| `annotation.view` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `annotation.create` | ✓ | ✓ | ✓ | ✓ | |
| `annotation.resolve` | ✓ | ✓ | | | |
| `change.view` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `change.create` | ✓ | ✓ | ✓ | ✓ | |
| `change.resolve` | ✓ | ✓ | | | |
| `decision.view` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `decision.create` | ✓ | ✓ | | | |
| `approval.view` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `approval.request` | ✓ | ✓ | | | |
| `approval.respond` | | | | ✓ | |
| `approval.cancel` | ✓ | ✓ | | | |
| `release.view` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `release.create` | ✓ | ✓ | | | |
| `release.finalize` / `withdraw` | ✓ | | | | |
| `file.upload` / `attach` | ✓ | ✓ | | | |
| `file.download` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `file.remove_orphaned` | ✓ | | | | |
| `activity.view` (project scope) | ✓ | ✓ | ✓ | ✓ | ✓ |
| `requirement.view` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `requirement.create` / `edit` | ✓ | ✓ | | | |
| `requirement.archive` | ✓ | | | | |
| `requirement.assess` | ✓ | ✓ | ✓ | ✓ | |

`release.finalize` and `release.withdraw` are deliberately restricted to `lead` — release is a high-consequence transition that should have concentrated accountability. Same for `file.remove_orphaned` and `requirement.archive`.

**Workspace administration and project collaboration are strictly separate role systems.** A workspace `owner` who is *not* on a project's roster does not automatically have `version.upload` or `approval.respond`. They may, however, view and manage project *administration* (§5).

---

## 4. Access Hierarchy

The access chain is:

```
Workspace  →  Project  →  Collection / DesignAsset / Version / File / Review / Change / Approval / Release / Comment / Annotation / Decision / Activity
```

**MVP inheritance model:**
1. Workspace membership grants **presence** in a workspace (see it, know its projects exist, hold a workspace role).
2. **Project participation** grants access to every project-scoped row: its collections, its design assets, all their versions, all attached files (via version_files), reviews, changes, decisions, approval requests, releases, and their comments/annotations.
3. **Workspace administrator override** grants administrative access to any project in the workspace *without* requiring a `project_participants` row. Administrative access is described in §5 — it is a **different** capability set from project participation, not "auto-participant."
4. **Asset-level restriction hooks** — MVP does not implement per-asset ACLs. However, the authorization predicates route capability checks through a single helper function per verb; adding a per-asset ACL later is a matter of extending that helper, not rewriting every RLS policy. See §7.

There is no cross-workspace access, ever. This is enforced by the composite FK strategy already present in the schema plus the RLS predicates below.

---

## 5. Workspace Administrators — Administrative vs. Participation

Administrative access is a **separate** capability class from project participation. It exists to let workspace `owner` / `admin` manage the workspace's projects, users, and settings without being individually rostered on every project.

### 5.1 What administrators may do (via administrative access)

- **See** every project in their workspace: metadata, participants, collections, assets, versions, files (metadata + download), reviews, changes, decisions, approvals, releases, activity events.
- **Manage projects**: edit metadata, archive/unarchive, transfer participants (via `project.manage_access`).
- **Manage members and stakeholders** at the workspace level.
- **Read the workspace audit trail** in full.

### 5.2 What administrators may *not* do without project participation

- **Create or modify design content**: publish versions, upload versions, create reviews, create changes, record decisions, respond to approvals, create releases.
- **Participate in reviews or approvals**: cannot appear on `review_participants` or `approval_request_approvers` unless explicitly added, and cannot submit `approval_responses` for a slot they do not hold.

This preserves the domain principle that administrative authorization ≠ project participation. If a workspace admin needs to publish a version, they must be added to that project as a `project_participants` row (with an appropriate role) — as a deliberate act.

### 5.3 Rationale

- Prevents "shadow authoring" — a workspace admin cannot silently produce content in a project they aren't on the roster of. Attribution stays honest.
- Allows admins to unblock stuck projects (participant management, archive/unarchive) without requiring them to first inject themselves as a roster entry.

---

## 6. Stakeholder Access Model

Stakeholders (`stakeholders` rows) are workspace-scoped external identities. Access is granted **only** through `project_participants` rows and only within projects they are explicitly rostered on.

### 6.1 Access rules

1. A Stakeholder can access a row if and only if:
   - The row's `workspace_id` matches a workspace in which the authenticated `profile.id` is linked as `stakeholders.user_id` with `status='active'`.
   - **AND** the row's `project_id` corresponds to a project where that stakeholder is an active `project_participants` (status `'active'`).
   - **AND** the capability required for the operation is granted by the stakeholder's project role.
2. A Stakeholder never satisfies "administrative access" (§5).
3. A Stakeholder never sees `workspace_members` (except perhaps display names of members they have interacted with in their projects — MVP will restrict this to project-scoped participant lists only).
4. A Stakeholder never sees other `stakeholders` outside projects they share.
5. A Stakeholder never sees `projects` they are not on.
6. A Stakeholder can hold any project role (including `lead`).

### 6.2 Unregistered stakeholders

An invited Stakeholder whose `user_id` is `NULL` cannot perform any authenticated action. RLS predicates require `stakeholders.user_id = auth.uid()` to grant access via the stakeholder path. First-time authentication produces an `auth.users` row → `profiles` row → and then the `claim_stakeholder_identity` RPC (§10) links `stakeholders.user_id` to the profile.

### 6.3 Same person as WorkspaceMember and Stakeholder in the same workspace

The same `profiles.id` may appear as both:
- `workspace_members.user_id = P` (with some workspace role), and
- `stakeholders.user_id = P` (with matching `workspace_id`).

The two records coexist at the workspace level — this reflects a real scenario (an internal designer on one project who is also an invited external reviewer on a separate project of the same workspace).

**Within any single project, however, a Profile has exactly one participation path.** The application/DB-boundary check rejects the state in which the same Profile appears in `project_participants` for the same project via both a `workspace_member_id`-based row **and** a `stakeholder_id`-based row. Enforced in the `project.manage_access` RPC path: before inserting a new `project_participants` row that would create the dual-path state, the RPC verifies no existing active participant row for that project already resolves to the same `profiles.id` through the other path.

This invariant is centralized in one place (the RPC) rather than expressed as a compound DB constraint — expressing it structurally would require a materialized join column or a partial-unique index over a derived value, both of which add more machinery than the risk warrants. The RPC is the single enforcement point; direct table inserts into `project_participants` are denied by RLS for non-admin callers so the RPC is the only path.

---

## 7. Authorization Helpers (Conceptual Functions)

RLS predicates are built out of a small set of SQL helper functions. These are **conceptual specifications** — no SQL is written here. All helpers must be `STABLE PARALLEL SAFE` (or `IMMUTABLE` where possible) so the planner can inline and cache them.

| Helper | Returns | Purpose |
|---|---|---|
| `lign_current_profile_id()` | `uuid` | Alias for `auth.uid()`. Single point of truth for "who am I?" |
| `lign_is_authenticated()` | `boolean` | `auth.uid() IS NOT NULL`. |
| `lign_is_workspace_member(ws_id)` | `boolean` | Row in `workspace_members` for `(user_id=auth.uid(), workspace_id=ws_id, status='active')`. |
| `lign_is_workspace_admin(ws_id)` | `boolean` | Same as above with `role IN ('owner','admin')`. |
| `lign_is_workspace_owner(ws_id)` | `boolean` | `role='owner'`. |
| `lign_is_active_stakeholder(ws_id)` | `boolean` | Row in `stakeholders` for `(user_id=auth.uid(), workspace_id=ws_id, status='active')`. |
| `lign_is_project_participant(project_id)` | `boolean` | Active `project_participants` for that project pointing at the caller's `workspace_members.id` OR `stakeholders.id`. |
| `lign_project_role(project_id)` | `text NULL` | The caller's active project role, or `NULL` if none. Returns the most permissive if two paths exist (see §16). |
| `lign_has_capability(project_id, capability_key)` | `boolean` | Central authorization function. Evaluates workspace-admin override AND project-role capability map. |
| `lign_workspace_of_project(project_id)` | `uuid` | Cached lookup. Helper to short-circuit RLS predicates that need workspace_id. |

The **only** place the role→capability map lives is inside `lign_has_capability`. Changing a preset means editing one function. This is auditability by design.

Composite check pattern used by nearly every table's RLS:

```
(row.workspace_id is accessible to me)  AND  ( lign_is_workspace_admin(row.workspace_id)
                                              OR lign_has_capability(row.project_id, 'capability.name') )
```

For workspace-scoped tables without a `project_id`, the second half degenerates to workspace-role checks.

---

## 8. Row-Level-Security per Table

Grouped by identical access logic. Every table has RLS **enabled**; no table is "public." Every check assumes `auth.uid()` is non-null unless stated otherwise.

### Group A — Global identity (no `workspace_id`)

**`profiles`**
- SELECT: caller's own row; OR any profile that shares at least one active `workspace_members` row with the caller (so members can see each other's names/avatars). Stakeholders can see profiles of members in projects they share (join through `project_participants`).
- INSERT: **not user-initiated**. Populated by a `SECURITY DEFINER` trigger on `auth.users` insert.
- UPDATE: caller's own row only. Immutable columns (`email` sync, `id`) protected by trigger.
- DELETE: never. Deactivation via status.
- Workspace check: N/A (global).
- Capability: implicit ("read own profile" is not a capability; it's the auth boundary).

### Group B — Tenant boundary

**`workspaces`**
- SELECT: caller is an active `workspace_members` or active `stakeholders` (any status other than a fully revoked one) of this workspace. Rationale: stakeholders need `workspaces.name`/`slug` to render their access UI.
- INSERT: any authenticated caller **via `create_workspace` RPC only** (RPC creates workspace + owner membership atomically). Direct table INSERT denied by RLS.
- UPDATE: `lign_is_workspace_admin(id)` with capability `workspace.manage`.
- DELETE: never. Archive via `workspace.manage`.
- Workspace check: `id` is the workspace.
- Capability: `workspace.view` / `workspace.manage`.

### Group C — Workspace-scoped access records

**`workspace_members`, `stakeholders`, `invitations`** (grouped; slight per-table differences noted).

- SELECT
  - `workspace_members`: any active workspace_member of the same workspace may see the full workspace roster. **Stakeholders may see a workspace_member only when they share at least one active project with them** — the RLS predicate joins through `project_participants` of shared projects. The general workspace-member directory is never exposed to stakeholders.
  - `stakeholders`: workspace admin sees all; project participants (member or stakeholder) see stakeholders who share a project with them (join via `project_participants`); the stakeholder sees their own row.
  - `invitations`: workspace admin sees all workspace invitations; caller may see invitations addressed to their `auth.email()`.
- INSERT
  - `workspace_members`: only via `invite_workspace_member` and `accept_invitation` RPCs. Direct INSERT denied.
  - `stakeholders`: workspace admin (`workspace.manage_stakeholders`); or via `claim_stakeholder_identity` RPC when a first-time login binds `user_id`.
  - `invitations`: `workspace.manage_members` for member invites; `workspace.manage_stakeholders` for stakeholder invites.
- UPDATE
  - `workspace_members`: workspace admin (`workspace.manage_members`); own row for `activated_at` (via invitation acceptance RPC).
  - `stakeholders`: workspace admin; own row for `user_id` linking (via claim RPC).
  - `invitations`: admin for revoke/expire; self for accept (via RPC).
- DELETE
  - Never. Soft transitions only.
- Workspace check: `workspace_id` on each row.

### Group D — Projects & participation

**`projects`, `project_participants`, `collections`** (grouped).

- SELECT
  - `projects`: `lign_is_workspace_admin(workspace_id)` OR `lign_is_project_participant(id)`.
  - `project_participants`: same as projects (caller can see fellow participants of projects they access).
  - `collections`: `lign_has_capability(project_id, 'collection.view')`.
- INSERT
  - `projects`: workspace role check for `project.create`. Recommended to route through `create_project` RPC that atomically creates the initial `project_participants` row (creator as `lead`).
  - `project_participants`: `lign_has_capability(project_id, 'project.manage_access')`.
  - `collections`: `lign_has_capability(project_id, 'collection.create')`.
- UPDATE
  - `projects`: `lign_has_capability(id, 'project.edit')` OR `lign_is_workspace_admin(workspace_id)` for admin operations (archive/status).
  - `project_participants`: `project.manage_access`.
  - `collections`: `collection.edit`.
- DELETE
  - Never. Archive via status. Empty draft `projects` and empty `collections` may be hard-deleted through an admin RPC.
- Workspace check: `workspace_id` direct.
- Project check: `project_id` on collections and project_participants; `id` on projects.

### Group E — Design objects (`design_assets`, `asset_versions`, `version_files`)

- SELECT: `lign_is_workspace_admin(workspace_id)` OR `lign_has_capability(project_id, 'asset.view' | 'version.view')`.
  - `version_files` derives project_id via `asset_versions`; RLS predicate joins.
- INSERT
  - `design_assets`: `asset.create`.
  - `asset_versions`: **RPC only** (`upload_and_attach_version_file` / `publish_version`) — direct INSERT denied because sequence assignment and target-eligibility invariants require atomicity.
  - `version_files`: `file.attach` **and** parent `asset_versions.status = 'draft'`. Direct INSERT allowed if predicate satisfied, but recommended via RPC.
- UPDATE
  - `design_assets`: `asset.edit` (name/description/collection_id/status/current_version_id, but `current_version_id` restricted to `asset.set_current` capability path — implemented as an RPC).
  - `asset_versions`: only while `status = 'draft'`. Publishing is via `publish_version` RPC.
  - `version_files`: only while parent is `draft`; immutable after (also trigger-enforced).
- DELETE
  - `design_assets`: never. Archive.
  - `asset_versions`: only via `version.discard_draft` while `status = 'draft'` and no downstream refs. RPC preferred.
  - `version_files`: only alongside parent draft version discard.
- Special rule: `design_assets.current_version_id` writes require the `asset.set_current` capability path (RPC).

### Group F — Files (workspace-scoped, project-visibility fan-out)

**`files`**
- SELECT: `lign_is_workspace_admin(workspace_id)` OR EXISTS a `version_files` row joining to an `asset_versions` in a project where the caller has `file.download` (typically any project participant of any project referencing the file).
- INSERT: any active workspace member OR active stakeholder in the workspace *who holds `file.upload` on at least one project* — MVP simplifies to "active workspace member OR active stakeholder in the workspace" (the attach step at `version_files` re-checks project scope). The refined check may be added later.
- UPDATE: never at the row-content level. Status transitions (`orphaned`, `purged`) via cleanup RPC.
- DELETE: never through the table. Purge via `file.remove_orphaned` RPC (workspace admin or `lead` in a project).

Storage-bucket policies (in `STORAGE_ARCHITECTURE.md` later) mirror this: bucket key is `workspace_id/…`, download requires the same predicate as the `files` SELECT policy.

### Group G — Collaboration content (`reviews`, `review_participants`, `comments`, `comment_edits`, `annotations`)

- SELECT
  - `reviews`, `review_participants`, `comments`, `annotations`: `lign_is_workspace_admin(workspace_id)` OR `lign_has_capability(project_id, 'review.view' | 'comment.view' | 'annotation.view')` (`project.view` is the umbrella).
  - `comment_edits`: same as `comments` (project-view + workspace-admin).
- INSERT
  - `reviews`: `review.create`. RPC preferred to enforce version-published invariant.
  - `review_participants`: `project.manage_access` OR `review.create` (author may seat reviewers at review creation). RPC recommended.
  - `comments`: `comment.create`, plus **CHECK constraint that `author_profile_id = auth.uid()`** — prevents impersonation.
  - `comment_edits`: never direct; append via `comment.edit_own` RPC only. RLS otherwise denies INSERT.
  - `annotations`: `annotation.create`, plus impersonation guard (`author_profile_id = auth.uid()`).
- UPDATE
  - `reviews`: `review.complete` / `review.create` (metadata mutable while `draft`/`open`).
  - `review_participants`: reviewer may update own row's `status` (`declined`, `signed_off`) via RPC; project lead may reassign.
  - `comments`: **only own row** AND capability `comment.edit_own`; body change goes via RPC that also inserts `comment_edits`. Resolve toggle via `comment.resolve` (any capability holder). **Once the containing/contextualizing Review is `completed` or `cancelled`, `comment.edit_own` is denied** — the historical review record is preserved. A comment is considered "in a review" if its `target_review_id` is that review, or its `target_annotation_id` points at an annotation whose author-time context is that review (application-tracked). The `edit_own_comment` RPC re-checks this at write time.
  - `annotations`: status transitions only; position immutable (trigger).
- DELETE
  - `comments`: soft via `deleted_at`, allowed for own row (`comment.edit_own`) or for `comment.resolve` (project lead/contributor).
  - Others: never.
- Impersonation guard: for every insert into `comments`, `annotations`, and any table with an `author_profile_id`, the RLS INSERT policy requires `author_profile_id = auth.uid()`. This is the schema-level defense against a client supplying someone else's identity.

### Group H — Change / Decision (`changes`, `decisions`)

- SELECT: `change.view` / `decision.view` (project scope).
- INSERT: `change.create` / `decision.create`; **`author_profile_id = auth.uid()`** required by RLS.
- UPDATE:
  - `changes`: `change.resolve` for status transitions; immutable after terminal state.
  - `decisions`: never (immutable after insert — trigger-enforced).
- DELETE: never.

### Group I — Approvals (`approval_requests`, `approval_request_approvers`, `approval_responses`)

- SELECT: `approval.view` (project scope).
- INSERT
  - `approval_requests`: **RPC only** (`request_approval`) — enforces the target-eligibility DB-boundary invariant (target must be a `published` version) and approver-slot creation atomically.
  - `approval_request_approvers`: **created only inside the `request_approval` RPC**. Direct INSERT denied by RLS unless the caller is the RPC path.
  - `approval_responses`: **RPC only** (`respond_to_approval`) — enforces slot-membership (caller's profile matches the slot's WorkspaceMember/Stakeholder profile), immutability, and post-response finalization under a row lock.
- UPDATE
  - `approval_requests`: only while `status='pending'` (before send); metadata edits by `approval.request` holder. Terminal transitions via RPC only.
  - `approval_request_approvers`: never after `sent_at`. Adding an approver requires a new request.
  - `approval_responses`: never. Immutable.
- DELETE: never.
- Impersonation guard: `approval_responses.responder_profile_id = auth.uid()` required by RLS at INSERT.

### Group J — Releases (`releases`, `release_items`)

- SELECT: `release.view` (project scope).
- INSERT
  - `releases`: `release.create` — may be direct INSERT with RLS check; recommended via `create_release` RPC.
  - `release_items`: `release.create` and parent `releases.status = 'draft'`.
- UPDATE
  - `releases`: metadata mutable only while `status='draft'`. Transition to `released` **RPC only** (`finalize_release`) — enforces the release-approval invariant.
  - `release_items`: mutable only while parent release is `draft`.
- DELETE
  - `release_items`: allowed while parent is `draft`; forbidden after.
  - `releases`: never after `released`.

### Group K — Audit (`activity_events`)

- SELECT
  - Workspace-level events (`project_id IS NULL`): visible to workspace `owner`/`admin` only. **Workspace-wide audit is admin-only in MVP.**
  - Project-level events (`project_id IS NOT NULL`): visible to workspace `owner`/`admin` OR any active `project_participants` of that project.
  - Predicate: `lign_is_workspace_admin(workspace_id) OR (project_id IS NOT NULL AND lign_is_project_participant(project_id))`.
- INSERT: **denied for direct user calls.** All activity events are emitted from RPC functions or triggers running under a controlled path.
- UPDATE: never (trigger-enforced).
- DELETE: never (trigger-enforced).

---

## 9. Files & Storage Authorization (Database Layer)

Storage bucket policies live in `STORAGE_ARCHITECTURE.md` (future). At the database layer, the authorization intent is:

| Operation | Who | Capability | Enforcement |
|---|---|---|---|
| Upload raw file bytes | Active workspace member or stakeholder | `file.upload` on at least one project (MVP: any active workspace member or stakeholder in the workspace, refined via the attach step) | RLS on `files` INSERT; storage bucket ownership; RPC preferred. |
| Attach a file to a Version | Project lead / contributor of the version's project | `file.attach` | RLS on `version_files` INSERT + parent version must be `draft`. |
| View file metadata | Any active project participant of any project referencing the file (via `version_files → asset_versions`) | `file.download` (project scope) | RLS on `files` SELECT (join through `version_files`). |
| Download file bytes | Same as view | `file.download` | Storage bucket policy mirrors DB SELECT. |
| Remove an unattached file | Workspace admin or project lead | `file.remove_orphaned` | RPC that verifies orphan status; RLS denies direct DELETE. |

**Published-version files are structurally immutable.** `version_files` rows may only be modified while the parent `asset_versions.status='draft'`. Once the version publishes, `version_files` and the referenced `files` become immutable historical content. Physical file bytes are content-addressed (`checksum_sha256`), so a new upload with different content is a new `files` row, not a mutation.

---

## 10. Sensitive Operations — Controlled RPC Functions

The following operations should not be performed by direct table writes even with RLS. Each is implemented as a Postgres function (RPC), typically `SECURITY INVOKER` (RLS still enforced during the function body) unless a specific step legitimately needs `SECURITY DEFINER` (called out).

| RPC | Why RPC (integrity, atomicity, or invariant enforcement) | Security mode |
|---|---|---|
| `create_workspace(name, slug)` | Atomic: create `workspaces` + first `workspace_members` (role `owner`). Also creates initial `activity_events`. | INVOKER; the workspace INSERT itself is definer-scoped for bootstrap. |
| `invite_workspace_member(...)` / `invite_stakeholder(...)` | Token generation; capability check; activity event. | INVOKER. |
| `accept_invitation(token)` | Verifies token; creates `workspace_members` or `stakeholders`; audit. Caller may not yet be a member of the workspace — this step needs DEFINER on the specific INSERT with tight input validation. | DEFINER for the INSERT only. |
| `claim_stakeholder_invitation(invitation_token)` | **Invitation-driven**, not blanket. Verifies the invitation token, verifies the invitation's email matches `auth.email()`, then binds `stakeholders.user_id = auth.uid()` **for the specific `stakeholders` row referenced by that invitation** and activates the appropriate `project_participants` row(s). Does **not** silently claim other stakeholder rows in other workspaces sharing the same email — those require their own invitation acceptance. Idempotent per invitation. **Critical** — this is how pre-account stakeholders become able to act. | DEFINER for the specific INSERT/UPDATE (must write into rows the caller cannot yet see); input strictly validated against the token. |
| `create_project(...)` | Atomic: `projects` + first `project_participants` (creator as `lead`) + activity. | INVOKER. |
| `set_current_version(design_asset_id, version_id)` | Enforces `asset.set_current` capability; validates version belongs to asset (already composite-FK-enforced but reasserted); emits activity. | INVOKER. |
| `publish_version(asset_version_id)` | Draft → published transition; assigns publish metadata; marks any earlier published version as `superseded` per policy; emits activity. Sequence assignment happens at draft creation, not publish; publish only flips status. | INVOKER. |
| `upload_and_attach_version_file(asset_version_id, file_id, ...)` | Ensures version is `draft`; workspace scope matches; version_files insert; activity. | INVOKER. |
| `discard_draft_version(asset_version_id)` | Only while `draft`; deletes version_files and asset_versions atomically; activity. | INVOKER. |
| `request_approval(...)` | Enforces the **approval-target-eligibility DB-boundary invariant** (target must be `published`); creates request + `approval_request_approvers`; activity. | INVOKER. |
| `respond_to_approval(approver_slot_id, decision, comment)` | Under `SELECT … FOR UPDATE` on `approval_requests`: verifies slot ↔ caller profile coherence (matches the DB-boundary trigger), inserts response, and evaluates policy termination in the same transaction. | INVOKER. |
| `finalize_approval(approval_request_id)` | System-callable for expiry sweep. Locks the request, evaluates terminal state, records outcome. | DEFINER when invoked by scheduler; INVOKER when a lead invokes it explicitly (e.g., cancel). |
| `cancel_approval(approval_request_id)` | Sets status to `cancelled`; capability check. | INVOKER. |
| `create_release(...)` / `add_release_item(...)` | Validates every item's version belongs to the release's project (composite-FK enforced but re-checked); validates each item's version has an `approved` `approval_request` (per project policy); activity. | INVOKER. |
| `finalize_release(release_id)` | **Enforces the release-approval DB-boundary invariant** in a single transaction: locks the release, re-verifies every item's approval, transitions to `released`. | INVOKER. |
| `withdraw_release(release_id, reason)` | Capability + activity. | INVOKER. |
| `edit_own_comment(comment_id, new_body)` | Inserts a `comment_edits` row with the prior body and updates `comments.body`; enforces caller is author; **rejects if the comment's containing/contextualizing Review is `completed` or `cancelled`** (preserves the historical review record). | INVOKER. |
| `change_workspace_member_role(member_id, new_role)` | Preserves at-least-one-owner invariant (blocks demotion if this member is the sole owner); activity. **Cannot change the `user_id` of a membership — identity is immutable (see §13).** | INVOKER. |
| `remove_workspace_member(member_id)` | Soft `status='removed'`; enforces at-least-one-owner; activity. | INVOKER. |
| `revoke_stakeholder(stakeholder_id)` | Soft `status='revoked'`; activity. | INVOKER. |
| `purge_orphaned_file(file_id)` | Only when `status='orphaned'` beyond retention window; transitions to `purged`; activity. | INVOKER for user-triggered; DEFINER for scheduled job. |

**Operations that do NOT need RPC** (plain table writes with RLS are sufficient):
- Creating a `comments` or `annotations` row (RLS + impersonation CHECK).
- Editing project/collection/asset metadata (RLS on the row).
- Marking a comment/annotation resolved (RLS on the row).
- Creating a `changes` row (RLS + author check; state transitions may still benefit from RPC for audit but are not integrity-critical).

Rationale for the RPC posture: RPC is used **only** where atomicity across tables, invariant enforcement that CHECK cannot express, or audit-event emission is required. It is not the default. Ordinary CRUD stays under RLS.

---

## 11. Service-Role Boundary

Supabase's service_role bypasses RLS. It is used only for:

1. **Auth trigger** on `auth.users → profiles` (bootstrap a profile at signup).
2. **Scheduled system jobs**: approval-expiry sweeper (`finalize_approval` on due-past requests), orphaned-file detector, cold-storage archival, workspace-owner-invariant sanity check.
3. **Support / operational admin**: LIGN staff tooling, backups, tenant-data-export for GDPR/DSR, forced purge. These operate outside the product surface.
4. **Webhook receivers**: e.g., email provider bounce/delivery callbacks on invitations.

Explicitly **not** for:
- Normal application flow. If a normal-user operation currently "requires" service_role, the correct fix is an RPC with the right capability check, not routing through service_role.
- Bypassing RLS as a shortcut. Every service_role usage must be documented in the migration/deployment plan and justified.

Every RPC that is `SECURITY DEFINER` is a service-role-equivalent surface and receives the same scrutiny: input validation, capability re-checks inside the function body, and audit-event emission.

---

## 12. RLS Performance Considerations

Nested RLS lookups can compound quickly (project participation → workspace membership → capability lookup). The MVP posture:

1. **Every domain table carries `workspace_id` directly.** This is already the case in the schema. First-cut RLS filter is a single indexed column check.
2. **Helper functions must be `STABLE PARALLEL SAFE`** so Postgres can cache and inline them.
3. **`lign_has_capability` is the only place the role→capability map lives.** Simple `text` matching inside; no joins beyond `project_participants`.
4. **Avoid `EXISTS` chains longer than 2 levels** in RLS predicates. The `files` table SELECT (joins `version_files → asset_versions`) is the deepest; MVP accepts this cost.
5. **Indexes already in the schema** (unique on `workspace_members(workspace_id, user_id)`, `project_participants(project_id, workspace_member_id)` and `(project_id, stakeholder_id)`, `files.workspace_id`) support the helpers efficiently.
6. **Materialized `user_project_access` view** — deferred. If profiling shows repeated deep joins, we may add a materialized view keyed `(profile_id, project_id, role)` refreshed on membership change. **Not in MVP.**

No clever RLS. No dynamic-SQL policies. No trigger-driven per-user permission tables. Simple, auditable predicates that a security reviewer can read.

---

## 13. Security Enforcement Rules

These are the invariants RLS + RPC enforcement guarantees, independent of application correctness:

1. **Tenant isolation is structural.** A row from workspace A is unreachable from a caller whose profile has no active workspace_member or stakeholder relationship in workspace A. Composite FKs plus RLS ensure this even under buggy application code.
2. **Client-supplied identifiers are ignored for authorization.** RLS predicates read the row's `workspace_id`/`project_id` and evaluate against `auth.uid()`. Any `workspace_id` the client sends in an insert is validated against composite FK targets — cross-workspace inserts fail structurally, not by application choice.
3. **`author_profile_id = auth.uid()` at insert.** Every table that carries an author FK enforces this equality in its INSERT RLS policy. A user cannot impersonate another profile by supplying a different `author_profile_id`.
4. **No frontend authorization is trusted.** Every capability check happens at the RPC or RLS layer.
5. **Historical attribution is preserved.** Removing a member or stakeholder never destroys authored rows; `author_profile_id` on the historical row remains valid (the profile itself is retained).
6. **Membership class does not gate any capability.** RLS predicates evaluate roles, not "is this a member or a stakeholder."
7. **All administrative access is auditable.** Every RPC emits an `activity_events` row; workspace admins acting outside of participation leave a trace.
8. **DB-boundary invariants are non-negotiable.** The release-approval invariant and the approval-target-eligibility invariant are enforced by RPC/trigger, not by frontend validation.
9. **`workspace_members.user_id` is immutable after insert.** DB-boundary trigger rejects any `UPDATE` that changes `user_id`. Role and status may change; the identity behind the membership may not. This closes the class of attacks that would rebind a workspace-member row (and its authorized capabilities) to a different profile.
10. **Stakeholder claim is invitation-scoped.** A first-time authentication does not silently link every matching `stakeholders` row across every workspace. Each stakeholder-workspace binding requires its own invitation acceptance via `claim_stakeholder_invitation`. Cross-workspace access is never created as a side effect of signing in.
11. **Dual-path project participation is rejected.** A single `profiles.id` cannot appear on `project_participants` for the same project via both a `workspace_member_id`-based row and a `stakeholder_id`-based row. Enforced in the `project.manage_access` RPC.

---

## 14. Security Scenarios Walkthrough

Each scenario: **ALLOW / DENY** with the decisive predicate.

### 1. WorkspaceMember opens a Project they participate in
**ALLOW.** RLS on `projects.SELECT`: `lign_is_project_participant(id)` returns true (their `workspace_members` row is referenced by an active `project_participants` row for this project). Capability `project.view` is held by every project role.

### 2. WorkspaceMember attempts to open a Project they do not participate in
**DENY.** `lign_is_project_participant(id)` returns false. They are not a workspace admin. `lign_is_workspace_admin` returns false. Both branches of the RLS predicate fail. Row filtered from result set.

### 3. Workspace admin opens a Project without being a ProjectParticipant
**ALLOW for SELECT and administrative UPDATE; DENY for creative writes.** `lign_is_workspace_admin(workspace_id)` returns true — grants SELECT and administrative operations (`project.edit`, `project.archive`, `project.manage_access`). Does **not** grant `version.publish`, `approval.respond`, etc. — those require project participation. Their reads emit an `activity_events` row tagged as administrative for audit.

### 4. External Stakeholder opens their assigned Project
**ALLOW.** The caller's `auth.uid()` matches `stakeholders.user_id` with `status='active'`; `project_participants` has an active row for `(project_id, stakeholder_id)`. `lign_is_project_participant(id)` returns true. Capability `project.view` granted.

### 5. External Stakeholder attempts another Project in the same Workspace
**DENY.** No `project_participants` row for that stakeholder against that project. `lign_is_project_participant` false; `lign_is_workspace_admin` false (stakeholders can never be admins). RLS filters row.

### 6. External Stakeholder attempts another Workspace
**DENY.** No `stakeholders` row for `(auth.uid(), other_workspace_id, status='active')`. `lign_is_active_stakeholder(other_workspace_id)` false. No workspace-member fallback. RLS filters row.

### 7. Viewer attempts to upload a Version
**DENY.** `lign_project_role(project_id)` returns `'observer'`. `lign_has_capability(project_id, 'version.upload')` false (observer preset lacks it). `upload_and_attach_version_file` RPC raises; direct INSERT on `asset_versions` blocked by RLS predicate.

### 8. Collaborator uploads a Version
**ALLOW.** Role is `contributor`; `lign_has_capability(project_id, 'version.upload')` true. RPC path succeeds; version created in `draft`; version_files inserted; activity emitted. `current_version_id` unchanged (per invariant §7 of DOMAIN_MODEL).

### 9. Reviewer attempts to create a Release
**DENY.** Role is `reviewer`; capability `release.create` not in preset. `create_release` RPC rejects with capability failure. Direct INSERT on `releases` blocked by RLS.

### 10. Approver responds to an ApprovalRequest assigned to them
**ALLOW.** Caller holds a slot in `approval_request_approvers` matching their `workspace_members.id` (or `stakeholders.id`). `respond_to_approval` RPC verifies:
- Caller's `auth.uid()` matches the slot's underlying profile (`workspace_members.user_id` or `stakeholders.user_id`).
- Request status is `pending`/`in_progress`.
- No prior response for this slot.

Insert succeeds; RPC evaluates policy; may finalize the request.

### 11. Approver attempts to respond to an ApprovalRequest not assigned to them
**DENY.** No `approval_request_approvers` row exists for `(this request, this caller's member/stakeholder id)`. RPC's slot-lookup fails. Direct INSERT on `approval_responses` blocked by:
- RLS predicate requiring caller's profile to match the slot.
- `UNIQUE (approver_slot_id)` — even if slot spoofing were attempted, it targets a slot the caller does not hold.
- Composite FK `(approver_slot_id, approval_request_id)` — cannot forge slot membership for another request.

### 12. User attempts to set another Profile as `author_profile_id`
**DENY.** Every table with `author_profile_id` (comments, annotations, changes, decisions, approval_responses, etc.) has an INSERT RLS policy: `author_profile_id = auth.uid()`. Cross-profile insert filtered before the row hits the table. Also protects `responder_profile_id` on approval_responses.

### 13. User attempts to reference a DesignAsset from another Workspace
**DENY (structurally).** Every child table that references `design_assets` uses a composite FK `(design_asset_id, workspace_id) → design_assets(id, workspace_id)`. The referring row's own `workspace_id` is validated against the caller's memberships by RLS. Cross-workspace reference fails at the FK, not at RLS — a stronger guarantee.

### 14. User attempts to access a File belonging to a Project they cannot access
**DENY.** `files.SELECT` predicate: `EXISTS (version_files vf JOIN asset_versions av ON av.id = vf.asset_version_id WHERE vf.file_id = files.id AND (lign_is_workspace_admin(av.workspace_id) OR lign_has_capability(av.project_id, 'file.download')))`. If the file is only attached to versions in projects the caller cannot access, the EXISTS is empty; the file row is filtered.

### 15. Removed WorkspaceMember attempts to access historical Projects
**DENY (going forward).** Their `workspace_members.status='removed'`. Every helper (`lign_is_workspace_member`, `lign_is_project_participant`) requires `status='active'`. All predicates fail. Historical authorship (their `author_profile_id` on old comments, versions, etc.) is preserved for audit but grants no access. Their profile can still authenticate (auth is separate from LIGN membership) but sees nothing in this workspace.

### 16. Revoked Stakeholder attempts to access their former Project
**DENY.** `stakeholders.status='revoked'`. `lign_is_active_stakeholder` false. `lign_is_project_participant` returns false because the participant row also transitions to `status='removed'` (or the stakeholder-side check fails). Authored artifacts remain historically attributed via `author_profile_id`.

---

## 15. Schema-Level Additions Applied

The permissions design surfaced one small, non-breaking schema addition, which has been **approved and applied** to `DATABASE_SCHEMA.md`:

### 15.1 `activity_events.project_id UUID NULL` — applied

**Semantics.**
- Nullable. Not a foreign key (`activity_events.subject_id` is also intentionally FK-less; audit rows must survive subject deletion).
- **Workspace-level administrative events** (e.g., `workspace.manage`, `workspace.member.invited`, `workspace.member.role_changed`, `stakeholder.invited`, `stakeholder.revoked`): `project_id = NULL`. Visible only to workspace `owner`/`admin`.
- **Project-level design-history events** (e.g., `version.published`, `approval.responded`, `release.finalized`, `decision.recorded`, `comment.created`): `project_id` populated with the row's project. Visible to workspace `owner`/`admin` **or** active `project_participants` of that project.
- Every RPC and trigger that emits an `activity_events` row is responsible for setting `project_id` correctly.

**RLS predicate** (as documented in §8 Group K):
`lign_is_workspace_admin(workspace_id) OR (project_id IS NOT NULL AND lign_is_project_participant(project_id))`.

### 15.2 No other schema changes required.

`DATABASE_SCHEMA.md` (bumped to v0.3 for this addition and the trigger-enforced immutability of `workspace_members.user_id`) remains consistent with `DOMAIN_MODEL.md` and this permissions spec.

---

## 16. Resolved Product/Security Decisions

All open decisions have been resolved. Documented here for traceability.

| # | Decision | Resolution |
|---|---|---|
| D1 | Same person as both member-path and stakeholder-path `project_participants` on the same project. | **Rejected for MVP.** A single Profile has one participation path per project. Centralized in the `project.manage_access` RPC (§6.3). |
| D2 | `activity_events.project_id` addition. | **Applied.** Nullable, non-FK. §15.1. |
| D3 | Stakeholder visibility of Workspace Members. | **Yes, project-scoped only.** RLS on `workspace_members.SELECT` joins through `project_participants` for the stakeholder path. General workspace-member directory is not exposed to stakeholders. (§8 Group C.) |
| D4 | `guest` workspace role. | **Removed from MVP.** Workspace roles are `owner`, `admin`, `member`. External participation is expressed via `stakeholders`. (§3.1.) |
| D5 | Comment editing after Review completion. | **Denied.** Once the containing/contextualizing Review is `completed` or `cancelled`, `comment.edit_own` is denied. Prior `comment_edits` remain historically preserved. Enforced in `edit_own_comment` RPC. (§8 Group G, §10.) |
| D6 | `workspace_members.user_id` immutability. | **DB-boundary trigger-enforced.** `UPDATE` that changes `user_id` is rejected. Role and status remain mutable. (§13 rule 9. Also reflected in `DATABASE_SCHEMA.md` v0.3.) |
| D7 | Stakeholder claim scope on account authentication. | **Invitation-driven, not blanket.** `claim_stakeholder_invitation(token)` claims exactly one stakeholder record per invitation acceptance. A Profile may later accept additional invitations. No silent cross-workspace access. (§10, §13 rule 10.) |
| D8 | Default `project.create` grant. | **`member` may create projects by default in MVP.** No configurable workspace-level setting. (§3.1.) |
| D9 | Non-admin access to workspace-wide audit. | **Not granted in MVP.** Workspace-wide administrative audit is `owner`/`admin` only. Project participants see the project-scoped subset via `activity_events.project_id`. (§8 Group K, §15.1.) |

## 17. Non-Goals for MVP

Reiterated from the approved decisions so scope stays honest:

- **No custom-roles UI.** The five project role presets and three workspace roles are fixed. The capability layer exists so authorization is not hard-coded to roles, but MVP does not expose role customization to users.
- **No capability-management UI.** Capabilities are internal constants and not exposed.
- **No per-user custom capability overrides.** Capability grants come from the role preset alone.
- **No guest workspace role**, no anonymous access, no public-share links (deferred to P1 per `DOMAIN_MODEL.md` §5.2).
- **No RPC wrappers around ordinary CRUD** that is safely handled by RLS. RPC is reserved for atomic transactions, DB-boundary invariants, frozen historical state, security-sensitive identity transitions, and coordinated event emission (§10).
