# LIGN Authorization Architecture (v1)

Final authorization design against the frozen structural schema (`SCHEMA_V1_LOCK.md`, Migrations 001–009). No SQL is written here; this document is the contract that the AUTH-series migrations must implement.

**Status**: architecture approved. Ready for AUTH 001 (helpers) to begin implementation.
**Target project**: `hsfporioghapwghrvvzd` (Lign, IWillBuild org). Never applied to `nuesync`.

---

## 1. Purpose and scope

This document specifies:
- The authorization helper functions LIGN will install.
- The RLS policy shape for every one of the 25 public tables.
- Which write paths must be RPC-only vs ordinary RLS-protected CRUD.
- Impersonation, cross-tenant, and recursion protections.
- The invitation bootstrap `SECURITY DEFINER` surface.
- An implementation sequence (AUTH 001 → AUTH 009).

It does **not** rewrite the frozen capability vocabulary from `PERMISSIONS.md` §2. It does **not** modify any structural schema.

---

## 2. Principles

1. **Capability-based, not class-based.** Membership class (WorkspaceMember vs Stakeholder) never gates any action. Every check is `lign_has_capability(...)`.
2. **Universal roles.** Workspace: `owner`, `admin`, `member`. Project: `lead`, `contributor`, `reviewer`, `approver`, `observer`. No professional titles.
3. **Profile = identity/attribution; membership rows = access relationship.** `auth.uid()` maps to `profiles.id`; `workspace_members`/`stakeholders`/`project_participants` are relationships.
4. **Central resolver.** `lign_has_capability(project_id, workspace_id, capability_key)` is the single source of truth for project-scoped authorization. Workspace-scoped capabilities resolve through `lign_is_workspace_admin(workspace_id)`.
5. **Administrative access ≠ creative access.** Workspace admins get audit + management access to any workspace project; creative operations (publish, approve, release) require actual project participation.
6. **Stakeholders are equal citizens for project capabilities**, gated only by their project role, and only when claimed (`stakeholders.user_id = auth.uid()`, `status='active'`).
7. **Impersonation is structurally impossible.** Every author-bearing INSERT policy requires `<author_column> = auth.uid()`.
8. **RLS is the primary defense; RPCs add atomicity and invariants.** Ordinary CRUD stays in RLS. Workflow transitions, immutable history writes, multi-row invariants, and identity/access mutations move to RPCs.
9. **Frozen structural schema stays frozen.** Authorization builds on top; no schema changes to enable RLS.

---

## 3. Identity model (recap of frozen concepts)

| Concept | Row | Purpose |
|---|---|---|
| **Profile** | `profiles` (1:1 with `auth.users`) | Global authenticated identity. Attribution anchor. `auth.uid() = profiles.id`. |
| **WorkspaceMember** | `workspace_members` | Organizational membership of a Profile in one workspace, with workspace role. |
| **Stakeholder** | `stakeholders` | External workspace-scoped identity (`workspace_id`, `email`), optionally linked to a Profile via `user_id`. |
| **ProjectParticipant** | `project_participants` | Sole authorization join for project access. XOR (`workspace_member_id` | `stakeholder_id`) + project role. |

**Access flow at every check**:
```
auth.uid()
  → workspace_members / stakeholders  (relationship in this workspace?)
  → project_participants               (participation in this project?)
  → project role
  → lign_has_capability(...) → boolean
```

---

## 4. Capability model

**Frozen vocabulary.** The 44 capabilities from `PERMISSIONS.md` §2 are used verbatim. No capabilities added or removed by this document.

**Deterministic function-based mapping.** MVP does not introduce `roles`, `capabilities`, `role_capabilities`, or `grants` tables. The role → capability matrix from `PERMISSIONS.md` §3.2 lives inside `lign_has_capability()` as a hard-coded, deterministic set. Adding/removing a capability is a one-line edit in one function.

**Two disjoint capability tiers inside `lign_has_capability()`**:

- **Administrative override set** — capabilities workspace admins/owners get on any project in their workspace, without participation:
  ```
  { project.view, project.edit, project.manage_access, project.archive,
    collection.view, collection.archive, asset.view, asset.archive,
    version.view, review.view, comment.view, annotation.view,
    change.view, decision.view, approval.view, release.view,
    file.download, activity.view }
  ```
- **Role-based grants** — per-role capability sets applied only when the caller has an active `project_participants` row of that role.

Creative capabilities (`version.publish`, `version.upload`, `asset.set_current`, `review.create`, `review.complete`, `review.participate`, `comment.create`, `comment.edit_own`, `comment.resolve`, `annotation.create`, `annotation.resolve`, `change.create`, `change.resolve`, `decision.create`, `approval.request`, `approval.respond`, `approval.cancel`, `release.create`, `release.finalize`, `release.withdraw`, `file.upload`, `file.attach`, `file.remove_orphaned`) are **never** in the admin override set.

Migration path to a table-driven system: rewrite `lign_has_capability()` body to read from tables; caller signature unchanged.

---

## 5. Authorization helper functions

All helpers are **STABLE, PARALLEL SAFE**, `SET search_path = ''`, fully-qualified references, `REVOKE ALL FROM PUBLIC`, `GRANT EXECUTE TO authenticated, service_role`.

`SECURITY DEFINER` is used only where RLS recursion or bootstrap genuinely requires it. `lign_current_profile_id()` does **not** use DEFINER.

### 5.1 `lign_current_profile_id() → uuid`
- **Purpose**: single point of truth for "who am I?". Wrapper on `auth.uid()`.
- **Security**: **INVOKER**. No privileged access needed. `search_path` pinned defensively.
- **Tables**: none.
- **Recursion**: none.

### 5.2 `lign_is_workspace_member(ws_id uuid) → boolean`
- **Purpose**: caller is an active `workspace_members` row of `ws_id`.
- **Predicate**: `EXISTS (SELECT 1 FROM public.workspace_members WHERE user_id = auth.uid() AND workspace_id = ws_id AND status = 'active')`.
- **Security**: **DEFINER** — callable from RLS policies that themselves protect `workspace_members`.
- **Indexes**: `workspace_members_workspace_user_key (workspace_id, user_id)` covers.

### 5.3 `lign_is_workspace_admin(ws_id uuid) → boolean`
- Same as 5.2 with `role IN ('owner','admin')` added.
- **Security**: **DEFINER**. Same index coverage.

### 5.4 `lign_is_active_stakeholder(ws_id uuid) → boolean`
- **Purpose**: caller is a claimed, active stakeholder of `ws_id`.
- **Predicate**: `EXISTS (… WHERE user_id = auth.uid() AND workspace_id = ws_id AND status = 'active')`.
- **Security**: **DEFINER**.
- **Indexes**: `stakeholders_workspace_user_key (workspace_id, user_id) WHERE user_id IS NOT NULL` covers.

### 5.5 `lign_project_role(project_id uuid) → text`
- **Purpose**: return the caller's active project role for `project_id`, or `NULL`.
- **Predicate**: JOIN `project_participants` → `workspace_members` and `stakeholders`; find the caller's participation via either identity path with `status='active'`; return `role`.
- **Deterministic tie-break** (defensive): if the dual-path invariant (`PERMISSIONS.md` §6.3 D1) is ever violated in the data, return the highest-ranked role using `lead > contributor > approver > reviewer > observer`. Normal operation returns exactly one row because the RPC-layer check prevents dual-path.
- **Security**: **DEFINER**.
- **Indexes**: `project_participants_project_member_key`, `project_participants_project_stakeholder_key`, `workspace_members_workspace_user_key`, `stakeholders_workspace_user_key` all cover.

### 5.6 `lign_has_capability(project_id uuid, workspace_id uuid, capability_key text) → boolean` — **central resolver**
- **Purpose**: the single authorization check for every project-scoped RLS predicate.
- **Signature**: three arguments per approved decision #1. The caller always has `workspace_id` in scope (denormalized on every domain table); passing it removes one internal JOIN and eliminates a potential recursion on `projects`.
- **Validation**: **first step of the function body validates that `project_id` belongs to `workspace_id`** (per decision #1). If a caller passes a mismatched pair (e.g. project from workspace A with workspace_id from workspace B), the function returns `false` deterministically. This prevents a spoofed `workspace_id` from granting capabilities via admin override on a workspace the caller doesn't actually admin. Validation query: `EXISTS (SELECT 1 FROM public.projects WHERE id = project_id AND workspace_id = workspace_id)`.
- **Logic** (conceptual):
  ```
  IF NOT project_belongs_to_workspace(project_id, workspace_id) → RETURN false

  IF capability_key ∈ admin_override_set
     AND lign_is_workspace_admin(workspace_id) → RETURN true

  role := lign_project_role(project_id)
  IF role IS NULL → RETURN false

  RETURN capability_key ∈ role_grants[role]
  ```
- **Security**: **DEFINER**. Recursion-safe because internal queries bypass RLS on `projects`, `workspace_members`, `stakeholders`, `project_participants`.
- **STABLE, PARALLEL SAFE, `search_path=''` pinned, REVOKE/GRANT as above.**

### 5.7 `lign_can_see_profile(target_profile_id uuid) → boolean`
- **Purpose**: kept per decision #8. Materially simplifies the `profiles` SELECT policy (which is otherwise 3–4 nested EXISTS chains) and makes it auditable.
- **Predicate**: true if `target_profile_id = auth.uid()` OR the target shares an active `workspace_members` relationship with the caller OR the target shares an active `project_participants` row (via either identity path) with the caller.
- **Security**: **DEFINER**.
- **Indexes**: uses the same indexes as helpers 5.2–5.5.

### Explicit non-helpers
- `lign_current_workspace()` — no ambient workspace; every call is explicit.
- Per-capability wrappers (`lign_can_publish_version`, etc.) — bloat, not built.

### SECURITY DEFINER inventory across auth helpers
| Helper | DEFINER? | Rationale |
|---|---|---|
| `lign_current_profile_id` | No | Trivial wrapper; INVOKER sufficient. |
| `lign_is_workspace_member` | Yes | Called from `workspace_members` policies; DEFINER avoids recursion. |
| `lign_is_workspace_admin` | Yes | Same. |
| `lign_is_active_stakeholder` | Yes | Same for `stakeholders`. |
| `lign_project_role` | Yes | Called from `project_participants` policies. |
| `lign_has_capability` | Yes | Called from every project-scoped policy; queries multiple membership tables. |
| `lign_can_see_profile` | Yes | Called from `profiles` policy; joins across membership tables. |

All DEFINER helpers: `SET search_path = ''`, fully-qualified references, `REVOKE ALL FROM PUBLIC`, `GRANT EXECUTE TO authenticated, service_role`. Immutable bodies, no dynamic SQL, no side effects. Narrow, auditable escalation surface.

---

## 6. General rule for RLS vs RPC

- **RLS**: ordinary collaboration CRUD (comments, annotations, changes, decisions, collections, design_assets, projects metadata edits, reviews metadata, releases metadata while draft, release_items while parent draft).
- **RPCs**: workflow transitions (publish version, respond to approval, finalize release), identity/access mutations (create workspace, invite/accept, claim stakeholder, add/remove project participant), immutable history writes (comment edits, activity events), and multi-row invariants (approval request creation with slots, release finalization prerequisites).

Do not wrap simple CRUD in RPCs. Do not enforce workflow invariants in RLS alone.

---

## 7. RLS architecture per table

Grouped where identical. Every authored-INSERT policy carries the impersonation guard `<author_column> = auth.uid()`.

### Group A — Global identity

**`profiles`**
- **SELECT**: `lign_can_see_profile(id)`.
- **INSERT**: denied. Only the existing `handle_new_auth_user` trigger populates.
- **UPDATE**: `id = auth.uid()`; `id` and `email` immutable via trigger (see §8).
- **DELETE**: denied.

### Group B — Tenant boundary

**`workspaces`**
- **SELECT**: `lign_is_workspace_member(id) OR lign_is_active_stakeholder(id)`.
- **INSERT**: denied for direct clients. Bootstrapped only via `create_workspace` SECURITY DEFINER RPC (§13).
- **UPDATE**: `lign_is_workspace_admin(id)` (workspace-level admin capability).
- **DELETE**: denied.

### Group C — Workspace access records

**`workspace_members`**
- **SELECT**: `lign_is_workspace_member(workspace_id)`. Stakeholders see individual member profiles only via the project-participant join surfaced by `lign_can_see_profile`; they do not see the raw `workspace_members` roster.
- **INSERT / UPDATE / DELETE**: **RPC-only** (`invite_workspace_member`, `accept_invitation`, `change_workspace_member_role`, `remove_workspace_member`). RLS denies direct writes.

**`stakeholders`**
- **SELECT**: `lign_is_workspace_admin(workspace_id) OR user_id = auth.uid() OR EXISTS(shared project via project_participants)`.
- **INSERT / UPDATE / DELETE**: **RPC-only** (`invite_stakeholder`, `claim_stakeholder_invitation`, `revoke_stakeholder`).

**`invitations`**
- **SELECT**: `lign_is_workspace_admin(workspace_id) OR email = auth.email()`.
- **INSERT / UPDATE / DELETE**: **RPC-only**.

### Group D — Projects & participation

**`projects`**
- **SELECT**: `lign_is_workspace_admin(workspace_id) OR lign_has_capability(id, workspace_id, 'project.view')`.
- **INSERT**: `lign_is_workspace_member(workspace_id) AND role IN ('owner','admin','member')` — recommended via `create_project` RPC to atomically create the first `project_participants` row (lead). RLS INSERT is permitted for the RPC path; direct-client INSERT is acceptable if the app inserts the participant row within the same transaction.
- **UPDATE**: `lign_has_capability(id, workspace_id, 'project.edit')`.
- **DELETE**: denied.

**`project_participants`** — **RPC-only for all writes** (per decision #2).
- **SELECT**: `lign_is_workspace_admin(workspace_id) OR lign_has_capability(project_id, workspace_id, 'project.view')` — fellow participants and admins see the roster.
- **INSERT / UPDATE / DELETE**: **RPC-only** (`add_project_participant`, `change_project_participant_role`, `remove_project_participant`). This is the decision that makes the dual-path-participation invariant (`PERMISSIONS.md` §6.3 D1) structurally enforceable — no admin can bypass the check via direct INSERT.

**`collections`**
- **SELECT / INSERT / UPDATE**: RLS with `collection.view` / `collection.create` / `collection.edit`; INSERT with impersonation guard on `created_by_profile_id`.
- **DELETE**: denied. Archive.

### Group E — Design objects

**`design_assets`**
- **SELECT**: `asset.view`.
- **INSERT**: `asset.create` + `created_by_profile_id = auth.uid()`.
- **UPDATE**: `asset.edit`. But `current_version_id` writes are gated to `asset.set_current` capability and go via the `set_current_version` RPC — RLS on UPDATE denies changes to `current_version_id` from a direct client update; the RPC path is DEFINER-privileged.
- **DELETE**: denied.

**`asset_versions`** — **RPC-only for all writes**.
- **SELECT**: `version.view`.
- **INSERT / UPDATE / DELETE**: **RPC-only** (`upload_and_attach_version_file`, `publish_version`, `discard_draft_version`, `deprecate_version`, `supersede_version`). Sequence assignment and publish invariants require atomicity.

**`files`** — **RPC-controlled writes** (per decision #5).
- **SELECT**: `lign_is_workspace_admin(workspace_id) OR EXISTS(version_files vf JOIN asset_versions av WHERE vf.file_id = files.id AND lign_has_capability(av.project_id, av.workspace_id, 'file.download'))`.
- **INSERT / UPDATE / DELETE**: **RPC-only**. There is **no generic workspace-level file INSERT**. Files are created only through the authorized Version upload/attach flow (the `upload_and_attach_version_file` RPC creates both the `files` row and the `version_files` row in one transaction, gated by `version.upload` + `file.attach` capabilities on the target project). Orphan purge via `purge_orphaned_file` RPC.

**`version_files`** — **RPC-controlled writes** (per decision #5).
- **SELECT**: same as parent version's `version.view`.
- **INSERT / UPDATE / DELETE**: **RPC-only**. The existing parent-draft mutation trigger enforces the timing; the RPCs enforce the capability.

### Group F — Collaboration

**`reviews`**
- **SELECT**: `review.view`.
- **INSERT**: `review.create` + `created_by_profile_id = auth.uid()`. RPC recommended for atomically seating initial reviewer slots and for future event emission; RLS INSERT permitted for the app path.
- **UPDATE**: metadata edits while `status ∈ ('draft','open')` under `review.create`; status transitions to `completed`/`cancelled` via `complete_review` RPC.
- **DELETE**: denied.

**`review_participants`**
- **SELECT**: `review.view` (fellow reviewers and admins).
- **INSERT / UPDATE / DELETE**: RPC-only (via `create_review` / `assign_reviewer` / `reviewer_respond`).

**`comments`** — direct RLS INSERT permitted (per decision #6).
- **SELECT**: `comment.view`.
- **INSERT**: RLS with `comment.create` + `author_profile_id = auth.uid()`. Direct client INSERT.
- **UPDATE**:
  - `body` mutation: **RPC-only** via `edit_own_comment()` — writes both `comments.body` and a `comment_edits` row atomically; enforces the review-completion gate (rejects if the containing/contextualizing review is `completed` or `cancelled`).
  - `resolved_at` toggle: RLS with `comment.resolve`.
  - `deleted_at` (soft-delete): RLS with `comment.edit_own` on own row.
- **DELETE** (hard): denied. Soft-delete via `deleted_at`.

**`comment_edits`** — RPC-only via `edit_own_comment`; append-only trigger already blocks UPDATE/DELETE.
- **SELECT**: same as parent comment access.
- **INSERT / UPDATE / DELETE**: RPC-only (only INSERT ever fires; UPDATE/DELETE blocked by trigger regardless).

**`annotations`**
- **SELECT**: `annotation.view`.
- **INSERT**: `annotation.create` + `author_profile_id = auth.uid()`.
- **UPDATE**: `annotation.resolve` on status (position immutability trigger prevents anchor changes).
- **DELETE**: denied. Soft resolve/archive via status.

### Group G — Change / Decision

**`changes`**
- **SELECT**: `change.view`.
- **INSERT**: `change.create` + `created_by_profile_id = auth.uid()`.
- **UPDATE**: `change.resolve` for status transitions.
- **DELETE**: denied.

**`decisions`**
- **SELECT**: `decision.view`.
- **INSERT**: `decision.create` + `author_profile_id = auth.uid()`. Direct RLS; the immutability + no-delete triggers already enforce the historical guarantees.
- **UPDATE**: RPC-only for `supersedes_decision_id` linkage (the only mutable column per the immutability trigger).
- **DELETE**: denied by trigger.

### Group H — Approvals — **all writes RPC-only**

- **`approval_requests`**: SELECT `approval.view`; INSERT/UPDATE/DELETE via `request_approval`, `respond_to_approval`, `cancel_approval`, `finalize_approval`. Target-eligibility trigger already installed.
- **`approval_request_approvers`**: SELECT `approval.view`; INSERT/UPDATE/DELETE RPC-only. Frozen-set enforcement via RPC + RLS (deny direct client writes).
- **`approval_responses`**: SELECT `approval.view`; INSERT via `respond_to_approval` RPC only. Coherence trigger + `responder_profile_id = auth.uid()` RLS INSERT guard as belt-and-suspenders. UPDATE/DELETE denied by trigger.

### Group I — Releases

- **`releases`**:
  - SELECT `release.view`.
  - INSERT `release.create` + `created_by_profile_id = auth.uid()`. Direct RLS.
  - UPDATE: metadata while `status='draft'` via RLS with `release.create`. Status transition to `released` via `finalize_release` RPC (existing DB-boundary trigger enforces prerequisites). Status transition to `withdrawn` via `withdraw_release` RPC.
  - DELETE: denied.
- **`release_items`**:
  - SELECT `release.view`.
  - INSERT / UPDATE / DELETE while parent draft: RLS OK (existing parent-draft mutation trigger enforces timing). Recommend `add_release_item` RPC for future event emission convenience.

### Group J — Audit

**`activity_events`**
- **SELECT**: `lign_is_workspace_admin(workspace_id) OR (project_id IS NOT NULL AND lign_has_capability(project_id, workspace_id, 'activity.view'))`. Per decision #4, visibility follows current authorization — a user who loses project participation loses access to historical events. No perpetual historical access.
- **INSERT / UPDATE / DELETE**: denied for direct users. Semantic RPCs emit events transactionally. Append-only trigger already blocks UPDATE/DELETE.

---

## 8. Impersonation and identity protection

- **Impersonation guard** on every direct-RLS INSERT with an author column:
  ```
  WITH CHECK (<author_column> = auth.uid())
  ```
  Tables: `comments`, `annotations`, `changes`, `decisions`, `collections`, `design_assets`, `projects`, `reviews`, `releases`.
- **RPC-set author columns** (`asset_versions.published_by_profile_id`, `approval_requests.created_by_profile_id`, `approval_responses.responder_profile_id`, `comment_edits.edited_by_profile_id`, `invitations.invited_by_profile_id`, `activity_events.actor_profile_id`): the RPC internally sets the field from `auth.uid()`. RLS additionally enforces `= auth.uid()` on `approval_responses` for defense-in-depth; the responder coherence trigger provides the third layer.

- **`profiles` identity immutability**: a trigger (to be added in AUTH 002) rejects `UPDATE` that changes `profiles.id` or `profiles.email`. `email` is denormalized from `auth.users` and kept in sync by the auth-signup trigger; user-initiated updates must not diverge.

---

## 9. Profiles RLS (special case)

Profiles are global (no `workspace_id`). Naïve `SELECT true` policy would leak every LIGN profile.

Policy: `USING (lign_can_see_profile(id))`.

`lign_can_see_profile(target_profile_id)`:
- Self: `target = auth.uid()`.
- Shared workspace: `EXISTS` join through `workspace_members`.
- Shared project via member path: `EXISTS` join through `project_participants` + `workspace_members`.
- Shared project via stakeholder path: `EXISTS` join through `project_participants` + `stakeholders`.

**UPDATE**: `USING (id = auth.uid())`; identity trigger blocks `id` and `email` mutations.

Never allow enumeration.

---

## 10. Files and version_files (per decision #5)

**No generic workspace-level file INSERT.** All file/version_file writes flow through the authorized Version workflow RPCs. The upload path is a **two-step reservation → physical upload → finalize-and-attach** sequence, per `docs/STORAGE_ARCHITECTURE.md`:

- `start_version_file_upload(asset_version_id, checksum_hex, mime_type, size_bytes, display_name, role, sort_order)` — server derives `project_id`/`workspace_id` from `asset_version_id`; gated by `version.upload` + `file.attach` on the resolved project; parent `asset_version.status` must be `'draft'`; server derives `files.storage_ref` as `{workspace_id}/{file_id}` — the client never supplies it. Race-safe dedup dispatch via `INSERT ... ON CONFLICT (workspace_id, checksum_sha256) WHERE status <> 'purged' DO NOTHING`. **Creates only the `files` reservation row** (status `uploaded`); does not create `version_files`.
- Client uploads the binary directly to Supabase Storage at the reserved path, gated by `storage.objects` INSERT RLS.
- `finalize_version_file_upload(file_id, asset_version_id)` — re-authorizes, re-verifies parent version is `draft`, verifies the Storage object exists and its metadata size matches, transitions `files.status` `uploaded → active`, and creates the `version_files` attachment atomically. Idempotent.
- `discard_draft_version(asset_version_id)` — atomically removes `version_files` and the `asset_versions` draft; for each affected `file_id`, transitions the file to `orphaned` iff no remaining `version_files` reference it (never orphans a still-referenced file).
- `list_purgeable_files()` / `mark_file_purged(file_id)` — physical purge is executed by a controlled service-role Supabase Storage delete (STORAGE 004 minimal Edge Function); the DB marks `files.status='purged'` only after the physical delete succeeds; capability `file.remove_orphaned`.
- **Removed**: the earlier single-RPC `upload_and_attach_version_file` abstraction and `attach_file_to_version(... p_storage_ref ...)`. Both accepted client-supplied paths/context and are replaced by the two-step reservation/finalize flow above.

**Invariant.** Every `version_files` row references a `files` row with `status = 'active'`. `publish_version` reasserts this at the workflow boundary: publication fails if any referenced file is not `active`.

**RLS on `files`**: SELECT is the deepest join in the schema — `admin OR EXISTS(version_files → asset_versions with file.download on project)`. Existing indexes (`version_files_file_workspace_idx`, `asset_versions_id_workspace_key`) cover.

**Storage bucket policies** (specified in `docs/STORAGE_ARCHITECTURE.md`, installed in STORAGE 002) mirror this authorization via two SECURITY DEFINER helpers, `lign_can_download_storage_object(text)` and `lign_can_upload_storage_object(text)`, so the `storage.objects` policies remain thin, do not cascade through `public.files` RLS, and constitute no second parallel authorization system. Bucket: `lign-files` (private). Path convention: `{workspace_id}/{file_id}`, server-derived only.

---

## 11. Approval authorization

- **`approval_requests` SELECT**: `approval.view` (all project roles).
- **`approval_requests` writes**: RPC-only.
  - `request_approval(project_id, workspace_id, design_asset_id, version_id, policy, approvers[])`: capability `approval.request`; target-eligibility trigger validates published version; approver-set frozen atomically.
  - `respond_to_approval(approver_slot_id, decision, comment)`: capability `approval.respond`; coherence trigger validates responder identity; may finalize request in same TX under row lock.
  - `cancel_approval(approval_request_id, reason)`: `approval.cancel`.
  - `finalize_approval(approval_request_id)`: scheduled sweep; `SECURITY DEFINER` for system context; user-initiated finalization is `respond_to_approval` completing the last slot.
- **`approval_request_approvers` and `approval_responses`**: writes RPC-only; direct writes denied. Immutability + coherence triggers already installed structurally.

---

## 12. Release authorization

- **`releases` SELECT**: `release.view`.
- **`releases` INSERT / draft edits**: direct RLS with `release.create` + author guard.
- **`releases` finalize (draft → released)**: `finalize_release` RPC with `release.finalize` capability (project lead only). Existing DB-boundary trigger enforces empty-release protection and per-item approved-version prerequisites.
- **`releases` withdraw (released → withdrawn)**: `withdraw_release` RPC with `release.withdraw` capability.
- **`release_items` while parent draft**: RLS OK for INSERT/UPDATE/DELETE with `release.create`; parent-draft mutation trigger enforces timing.
- Workspace admin without project participation cannot finalize/withdraw releases — those are creative capabilities.

---

## 13. Invitation and bootstrap SECURITY DEFINER RPCs

Two invitation-acceptance flows and one workspace bootstrap require narrow `SECURITY DEFINER` RPCs because the caller is not yet a member of the target scope:

- **`create_workspace(name, slug) → uuid`** — narrow `SECURITY DEFINER` bootstrap (per decision #3). The first user creating their first workspace has no existing `workspace_members` row that could satisfy a "workspace creator" RLS policy. The RPC atomically creates the `workspaces` row and the first `workspace_members` (owner) row; emits `workspace.created` activity event; returns the workspace id. Input validation strict; no free-form SQL; `SET search_path = ''`; `REVOKE ALL FROM PUBLIC`; `GRANT EXECUTE TO authenticated`.
- **`accept_invitation(token text) → uuid`** — `SECURITY DEFINER`. Validates token hash against active workspace-member invitation; verifies `auth.email() = invitations.email`; creates/activates `workspace_members`; marks invitation `accepted`; emits `workspace.member.activated`.
- **`claim_stakeholder_invitation(token text) → uuid`** — `SECURITY DEFINER`. Same shape for stakeholder invitations. Claims exactly one stakeholder record tied to the token (per PERMISSIONS.md §16 D7); no cross-workspace side effects.

All three: `SET search_path = ''`, fully-qualified references, `REVOKE ALL FROM PUBLIC`, `GRANT EXECUTE TO authenticated`. Fail-closed on any input mismatch. Rate-limit at API gateway (future).

**All other RPCs are `SECURITY INVOKER`** by default. `SECURITY DEFINER` is reserved for these bootstrap paths, scheduled system RPCs (`finalize_approval` expiry, `purge_orphaned_file` sweep), and the existing structural triggers.

---

## 14. RLS recursion analysis

The dangerous pattern: RLS policy on table X calls a helper that queries table X.

- **`workspace_members` policy calls `lign_is_workspace_admin`** — helper queries `workspace_members`. **Solved by DEFINER**.
- **`stakeholders` policy calls `lign_is_active_stakeholder`** — same.
- **`project_participants` policy calls `lign_has_capability`** which internally calls `lign_project_role` which reads `project_participants`. **Solved by DEFINER**.
- **`profiles` policy calls `lign_can_see_profile`** which joins `workspace_members`/`stakeholders`/`project_participants`. **Solved by DEFINER**.
- **`projects` policy calls `lign_has_capability(id, workspace_id, cap)`** — helper's project-belongs-to-workspace validation queries `projects`. **Solved by passing workspace_id as an argument (decision #1) and by DEFINER** — the internal `projects` read bypasses `projects` RLS.

**Every authorization helper is SECURITY DEFINER for exactly this reason.** No policy can trigger recursive RLS through a helper. Escalation surface remains narrow and auditable (7 helpers, fixed bodies, no dynamic SQL).

---

## 15. Auth-critical indexes

Verified against V1 schema. All authorization query paths have covering indexes:

| Auth query | Index used |
|---|---|
| `lign_is_workspace_member/admin` | `workspace_members_workspace_user_key (workspace_id, user_id)` unique |
| `lign_is_active_stakeholder` | `stakeholders_workspace_user_key (workspace_id, user_id) WHERE user_id IS NOT NULL` |
| `lign_project_role` — member path | `project_participants_project_member_key` + `workspace_members_workspace_user_key` |
| `lign_project_role` — stakeholder path | `project_participants_project_stakeholder_key` + `stakeholders_workspace_user_key` |
| `lign_has_capability` project-in-workspace validation | `projects_id_workspace_key UNIQUE (id, workspace_id)` |
| `files` SELECT chain | `version_files_file_workspace_idx` + `asset_versions_id_workspace_key` |
| `activity_events` project timeline | `activity_events_project_occurred_idx` |
| `activity_events` workspace timeline | `activity_events_workspace_occurred_idx` |
| `lign_can_see_profile` | member/stakeholder/participant indexes above |

**No missing critical indexes for MVP.** Optional future additions if profiling reveals hotspots:
- `workspace_members (user_id, workspace_id) WHERE status='active'` partial — for profile-sharing pattern.
- Materialized `(profile_id, project_id, role)` view — deferred, only if traffic proves need.

---

## 16. Adversarial authorization matrix

Every scenario passes with the proposed policies + helpers.

| # | Scenario | Result | Predicate |
|---|---|---|---|
| 1 | Workspace A member reads Workspace B project | DENY | `lign_has_capability(project_in_B, B, 'project.view') = false`; workspace-admin override on B fails |
| 2 | Workspace A admin reads Workspace B | DENY | `lign_is_workspace_admin(B) = false` |
| 3 | Participant in Project A reads Project B (same workspace) | DENY (unless workspace admin) | `lign_has_capability(B, ws, 'project.view')` fails; admin override is workspace-level |
| 4 | Observer reads authorized Design Asset | ALLOW | observer preset includes `asset.view` |
| 5 | Observer publishes Version | DENY | `version.publish` not in observer preset; also RPC rejects |
| 6 | Observer submits Approval response | DENY | `approval.respond` not in preset |
| 7 | Reviewer opens assigned review and comments | ALLOW | `review.view`, `comment.create` in reviewer preset |
| 8 | Reviewer finalizes Release | DENY | `release.finalize` not in reviewer preset |
| 9 | Designated Approver reads request | ALLOW | `approval.view` in approver preset |
| 10 | Approver responds through own slot | ALLOW | Coherence trigger + capability |
| 11 | Approver attempts response through another slot | DENY | Coherence trigger raises; RLS `responder_profile_id = auth.uid()` also fails |
| 12 | Workspace admin reads workspace projects | ALLOW | admin override on `project.view` |
| 13 | Admin manages project participants | ALLOW | `project.manage_access` in admin override; RPC-only path enforces dual-path invariant |
| 14 | Admin without participation publishes Version | DENY | `version.publish` not in admin override; `lign_project_role` returns NULL |
| 15 | Admin joins Project as contributor, then publishes | ALLOW | role now `contributor`; RPC succeeds |
| 16 | Active claimed Stakeholder reads assigned project | ALLOW | `lign_has_capability(project, ws, 'project.view')` via stakeholder path |
| 17 | Same Stakeholder attempts unrelated project | DENY | no participant row for that project |
| 18 | Revoked Stakeholder | DENY | `lign_is_active_stakeholder=false` |
| 19 | Unclaimed Stakeholder | DENY | `user_id` NULL ≠ `auth.uid()` |
| 20 | Contributor creates Comment with someone else's author | DENY | RLS INSERT WITH CHECK fails |
| 21 | User loses participation, accesses old Design History | DENY (per decision #4) | RLS on `activity_events` fails; no perpetual historical access |
| 22 | Caller passes spoofed `workspace_id` to `lign_has_capability` | DENY | first-step project-in-workspace validation returns false (per decision #1) |
| 23 | Cross-tenant FK write attempt | DENY (structural) | Composite FK fails before RLS runs |
| 24 | Direct INSERT to `activity_events` from client | DENY | RLS INSERT policy rejects |
| 25 | Direct DELETE on `approval_responses` | DENY | Trigger raises |
| 26 | Direct DELETE on `comment_edits` | DENY | Trigger raises |
| 27 | Direct INSERT to `project_participants` by admin (bypassing RPC) | DENY | RPC-only per decision #2; RLS denies direct INSERT |
| 28 | Direct INSERT to `files` outside version workflow | DENY | RPC-only per decision #5 |
| 29 | User attempts `create_workspace` while not signed in | DENY | RPC requires authenticated caller; `auth.uid()` NULL fails validation |

---

## 17. AUTH migration sequence

Order chosen for dependency correctness (helpers before policies), minimum recursion surface, and reviewability. Each migration self-verifies against Supabase advisors before proceeding.

| Migration | Contents |
|---|---|
| **AUTH 001 — helpers** | 7 helper functions from §5; `profiles` identity immutability trigger; `create_workspace`, `accept_invitation`, `claim_stakeholder_invitation` SECURITY DEFINER RPCs from §13. |
| **AUTH 002 — identity RLS** | Policies for `profiles`, `workspaces`, `workspace_members`, `stakeholders`, `invitations`. |
| **AUTH 003 — projects RLS** | Policies for `projects`, `project_participants` (RPC-only writes per decision #2), `collections`. Plus `create_project`, `add_project_participant`, `change_project_participant_role`, `remove_project_participant` RPCs. |
| **AUTH 004 — design objects RLS** | Policies for `design_assets`, `asset_versions` (RPC-only writes), `files` (RPC-only writes per decision #5), `version_files` (RPC-only writes). Plus `set_current_version`, `upload_and_attach_version_file`, `publish_version`, `discard_draft_version`, `deprecate_version` RPCs. |
| **AUTH 005 — collaboration RLS** | Policies for `reviews`, `review_participants` (RPC-only writes), `comments`, `comment_edits` (RPC-only writes), `annotations`. Plus `create_review`, `complete_review`, `edit_own_comment` RPCs. |
| **AUTH 006 — change/decision RLS** | Policies for `changes`, `decisions`. Plus optional `resolve_change` RPC for future event emission. |
| **AUTH 007 — approval RLS** | Policies for approval tables (all-writes RPC-only). Plus `request_approval`, `respond_to_approval`, `cancel_approval`, `finalize_approval` RPCs. |
| **AUTH 008 — release RLS** | Policies for `releases` and `release_items`. Plus `finalize_release`, `withdraw_release` RPCs. |
| **AUTH 009 — activity events RLS** | Read-only user policy per §7 Group J. Event emission wiring inside the RPCs above (retroactive updates to earlier AUTH migrations if needed). |

The order mirrors the structural migration order. If any policy refers to a helper that hasn't been created yet, the migration errors immediately; AUTH 001 landing all helpers first eliminates that risk.

---

## 18. Non-goals (MVP)

- No custom-role builder.
- No capability-management UI.
- No per-user permission overrides.
- No field-level ACLs.
- No asset-level ACLs.
- No policy DSL, no ABAC engine.
- No external IAM integration.
- No organization hierarchies beyond workspace/project.
- No mention parsing, notification dispatch, or AI infrastructure at the auth layer.

---

## 19. Modification policy while V1 authorization is in force

- Adding a capability: edit `lign_has_capability()` body only. No new tables.
- Adding a new role: same. Update `lign_project_role` tie-break ranking accordingly.
- Adding a new table: requires re-opening SCHEMA_V1_LOCK; AUTH policies added in a new AUTH-series migration.
- Changing a helper signature: touches every policy that calls it — requires an explicit review pass and version bump on this document.

Any change to this architecture that would weaken cross-tenant isolation, impersonation protection, RPC-only invariants, or the append-only history tables is a breaking change and requires explicit product approval.
