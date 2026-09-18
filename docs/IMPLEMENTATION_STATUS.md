# LIGN Implementation Status

Operational log of database migrations, RPCs, storage, and notification wiring applied to the Lign Supabase project. **Not architecture.** The frozen architecture lives in `DOMAIN_MODEL.md`, `DATABASE_SCHEMA.md`, `PERMISSIONS.md`, `STATE_MACHINES.md`, and `EVENT_MODEL.md`.

**Target project:** `Lign` (`hsfporioghapwghrvvzd`) — IWillBuild org, us-east-2, Postgres 17.6.
**All migrations target this project ID only.** The `nuesync` project is never touched.

---

## Implementation stages

| Stage | Status |
|---|---|
| 1. Structural database schema | **COMPLETE** (Migrations 001–009 applied — all 25 domain tables, 15 functions, 41 triggers, 0 policies, 0 unindexed FKs, 0 duplicate indexes) |
| 2. RLS + authorization helpers | Not started |
| 3. Transactional/domain RPCs | Not started |
| 4. Events | Not started |
| 5. Storage | Not started |
| 6. Notifications | Not started |

## Documentation reconciliations

| Date | File | Change | Reason |
|---|---|---|---|
| 2026-07-29 | `DATABASE_SCHEMA.md` §3.3 | Removed `guest` from `workspace_members.role` CHECK vocabulary. | Documentation-only reconciliation with the later frozen `PERMISSIONS.md` §3.1 decision and the already-applied Migration 002. No architectural change. |

---

## Migrations

### Migration 001 — `foundation_profiles`

- **File:** `supabase/migrations/20260728160001_foundation_profiles.sql`
- **Applied at:** `20260728205411` (Supabase migration version)
- **Target project:** `hsfporioghapwghrvvzd` (Lign)
- **Result:** `success: true`
- **Spec references:** `DATABASE_SCHEMA.md v0.3` §3.1 (profiles); `PERMISSIONS.md` §10 (auth trigger); `DOMAIN_MODEL.md` §0 (Historical attribution — RESTRICT rule).

#### Objects created

| Kind | Schema.Name | Notes |
|---|---|---|
| Extension | `extensions.citext` v1.6 | Required by `profiles.email` and many downstream tables. |
| Function | `public.set_updated_at()` | Reusable `updated_at` trigger. Not SECURITY DEFINER. |
| Table | `public.profiles` | Exact match to `DATABASE_SCHEMA.md v0.3` §3.1. RLS enabled, no policies (deferred to auth stage). |
| Trigger | `public.profiles.profiles_set_updated_at` | `BEFORE UPDATE` → `public.set_updated_at()`. |
| Function | `public.handle_new_auth_user()` | SECURITY DEFINER, pinned `search_path = ''`. Creates the profile on auth signup. `REVOKE ALL` from `public`, `anon`, `authenticated`. |
| Trigger | `auth.users.on_auth_user_created` | `AFTER INSERT` → `public.handle_new_auth_user()`. |

#### Verification performed (all read-only)

- Migration recorded in `supabase_migrations.schema_migrations` ✓
- `citext` extension installed in schema `extensions` ✓
- `public.profiles` structure matches spec:
  - PK `id uuid` with FK to `auth.users(id) ON DELETE RESTRICT` ✓
  - `email citext NOT NULL UNIQUE` ✓
  - `display_name text NOT NULL` ✓
  - `avatar_url text NULL` ✓
  - `status text NOT NULL DEFAULT 'active' CHECK IN ('provisioned','active','deactivated')` ✓
  - `deactivated_at timestamptz NULL` ✓
  - `created_at`, `updated_at timestamptz NOT NULL DEFAULT now()` ✓
- RLS enabled on `public.profiles` ✓; no policies (as required by the stage plan)
- `public.set_updated_at` exists, PLPGSQL, not SECURITY DEFINER ✓
- `public.handle_new_auth_user` exists, SECURITY DEFINER = true, `search_path = ""` pinned ✓
- Function privileges on `handle_new_auth_user`: only `postgres` and `service_role` hold EXECUTE (public / anon / authenticated revoked) ✓
- Trigger `on_auth_user_created` on `auth.users` AFTER INSERT invoking `handle_new_auth_user` ✓
- Trigger `profiles_set_updated_at` on `public.profiles` BEFORE UPDATE invoking `set_updated_at` ✓
- No other public-schema objects created ✓
- `pg_cron`, `pg_net` remain NOT installed (per stage instructions) ✓

#### Advisor findings after apply

**Security advisors:**
- INFO `rls_enabled_no_policy` on `public.profiles` — **expected and intentional per this stage's plan.** Policies land in the dedicated authorization migration stage. Will clear when Group A policies are created.
- WARN `function_search_path_mutable` on `public.set_updated_at` — new finding introduced by this migration. See "Warnings" below.

**Performance advisors:**
- INFO `auth_db_connections_absolute` — pre-existing project-level configuration; unrelated to Migration 001. Address in project settings, not a schema concern.

#### Deviations from `DATABASE_SCHEMA.md v0.3`

**None.** One deliberate deviation from the standard Supabase quickstart (not from our spec): `profiles.id → auth.users(id) ON DELETE RESTRICT` instead of the quickstart's `CASCADE`. This is exactly what `DATABASE_SCHEMA.md v0.3` §3.1 and the DOMAIN_MODEL historical-retention rule require.

#### Warnings

- **`set_updated_at` search_path is not pinned** (advisor WARN). The function body only touches `NEW.updated_at` and calls `now()` (a `pg_catalog` builtin), so the practical risk is low, but the Supabase linter recommends pinning `search_path` on every function as defense-in-depth. Recommended follow-up: a small hardening patch (`ALTER FUNCTION public.set_updated_at() SET search_path = ''`) bundled into the next migration or as a standalone hardening migration. **Not applied here** — sticking to the "STOP after Migration 001" instruction.

#### Deferred (intentionally not yet implemented)

- All other tables (`workspaces`, `workspace_members`, `stakeholders`, `invitations`, `projects`, `project_participants`, `collections`, `design_assets`, `asset_versions`, `files`, `version_files`, `reviews`, `review_participants`, `comments`, `comment_edits`, `annotations`, `changes`, `decisions`, `approval_requests`, `approval_request_approvers`, `approval_responses`, `releases`, `release_items`, `activity_events`).
- RLS policies on `profiles` (Group A) and every downstream table.
- Authorization helpers (`lign_has_capability`, etc.).
- Domain RPCs (`create_workspace`, `publish_version`, `respond_to_approval`, `finalize_release`, etc.).
- Event emission wiring.
- Storage buckets and policies.
- Notification derivation and email dispatch.
- `pg_cron` and `pg_net` extensions.
- Scheduled jobs (`expire_invitation`, `finalize_approval`, orphaned-file sweeps).

---

### Migration 002 — `workspaces_identity`

- **File:** `supabase/migrations/20260728220000_workspaces_identity.sql`
- **Applied at:** `20260728210648` (Supabase migration version)
- **Target project:** `hsfporioghapwghrvvzd` (Lign)
- **Result:** `success: true`
- **Spec references:** `DATABASE_SCHEMA.md v0.3` §§3.2–3.5; `PERMISSIONS.md` §3.1 (workspace roles), §13 rule 9 (user_id immutability); `DOMAIN_MODEL.md` §0 (historical retention).

#### Hardening applied first

- `ALTER FUNCTION public.set_updated_at() SET search_path = ''` — resolves the `function_search_path_mutable` WARN from Migration 001. Function behavior unchanged.

#### Objects created

| Kind | Schema.Name | Notes |
|---|---|---|
| Table | `public.workspaces` | RLS enabled, no policies. `settings` JSONB is the only JSONB entry point. |
| Table | `public.workspace_members` | RLS enabled, no policies. Composite `(id, workspace_id)` UNIQUE serves as FK target for downstream roster tables. Role vocabulary is MVP `(owner, admin, member)` — see deviations below. |
| Table | `public.stakeholders` | RLS enabled, no policies. Two partial indexes: `stakeholders_workspace_user_key` (partial UNIQUE) and `stakeholders_user_id_idx` (partial), both `WHERE user_id IS NOT NULL`. |
| Table | `public.invitations` | RLS enabled, no policies. `workspace_id` is the one CASCADE FK in the foundation. Partial UNIQUE on active invites `WHERE status='sent'`. |
| Function | `public.enforce_workspace_members_user_id_immutable()` | PLPGSQL, invoker context, `search_path=''` pinned. |
| Trigger | `public.workspace_members.workspace_members_user_id_immutable` | BEFORE UPDATE, enforces DB-boundary user_id immutability. |
| Trigger | 4× `*_set_updated_at` on workspaces / workspace_members / stakeholders / invitations | BEFORE UPDATE → `public.set_updated_at()`. |

#### Important constraints & indexes

- **Foreign keys with ON DELETE behavior**:
  - `workspace_members.workspace_id → workspaces(id) RESTRICT` ✓
  - `workspace_members.user_id → profiles(id) RESTRICT` ✓
  - `stakeholders.workspace_id → workspaces(id) RESTRICT` ✓
  - `stakeholders.user_id → profiles(id) RESTRICT` (nullable) ✓
  - `invitations.workspace_id → workspaces(id) CASCADE` ✓
  - `invitations.invited_by_profile_id → profiles(id) SET NULL` ✓
- **Composite FK targets** (for downstream projects/participants/rosters/etc.):
  - `workspace_members UNIQUE (id, workspace_id)` ✓
  - `stakeholders UNIQUE (id, workspace_id)` ✓
- **Identity uniqueness**:
  - `workspaces UNIQUE (slug)` ✓
  - `workspace_members UNIQUE (workspace_id, user_id)` ✓
  - `stakeholders UNIQUE (workspace_id, email)` (citext, case-insensitive) ✓
  - `stakeholders UNIQUE (workspace_id, user_id) WHERE user_id IS NOT NULL` (partial) ✓
  - `invitations UNIQUE (workspace_id, email, kind) WHERE status='sent'` (partial) ✓
- **Domain query indexes**:
  - `workspace_members (user_id)` — "workspaces this user belongs to"
  - `workspace_members (workspace_id, status)` — "members of a workspace"
  - `stakeholders (user_id) WHERE user_id IS NOT NULL` — "stakeholder records for a claimed profile"
  - `invitations (workspace_id, status)`, `invitations (token_hash)` — invite dashboard + acceptance lookup

#### Structural triggers

- `set_updated_at` attached to all 4 new tables (BEFORE UPDATE).
- `enforce_workspace_members_user_id_immutable` on `workspace_members` (BEFORE UPDATE) — the DB-boundary invariant from PERMISSIONS.md §13 rule 9.
- No workspace-owner minimum enforcement (deferred to RPC stage).
- No invitation acceptance / claim triggers (deferred to RPC stage).
- No activity_events emission (deferred to Events stage).

#### Verification performed (all read-only)

- Migration recorded in `supabase_migrations.schema_migrations` ✓
- All 4 tables exist in `public` schema with matching column types, defaults, nullability, and comments ✓
- All CHECK constraints match spec (statuses, kinds; MVP role vocabulary) ✓
- All FKs match spec (composite targets present) ✓
- All partial indexes match spec (WHERE clauses correct) ✓
- All 5 public tables have `rls_enabled = true` ✓
- `pg_policies` query on `public` returns empty ✓ (no policies created)
- `set_updated_at` triggers on all 4 new tables ✓
- `workspace_members_user_id_immutable` trigger exists ✓
- All 3 public functions (`set_updated_at`, `handle_new_auth_user`, `enforce_workspace_members_user_id_immutable`) have `search_path=''` pinned ✓
- No unexpected public objects (no stray tables, no policies, no extra functions) ✓
- No changes to `nuesync` project ✓

#### Advisor findings after apply

**Security advisors:**
- INFO ×5 `rls_enabled_no_policy` on `public.workspaces`, `public.workspace_members`, `public.stakeholders`, `public.invitations`, and `public.profiles` — **expected**. Policies deferred to the authorization migration stage. Will clear when Group A–C policies are created.
- **WARN `function_search_path_mutable` on `public.set_updated_at` is RESOLVED** (no longer appears). ✓

**Performance advisors:**
- INFO `unindexed_foreign_keys` on `invitations.invited_by_profile_id_fkey` — **new finding**. See warnings below.
- INFO ×4 `unused_index` on the four newly created domain indexes — expected noise; indexes just created with zero workload.
- INFO `auth_db_connections_absolute` — pre-existing project-level configuration; unrelated to schema.

#### Deviations from `DATABASE_SCHEMA.md v0.3`

- **`workspace_members.role` CHECK omits `guest`** — MVP uses `('owner','admin','member')` only, per PERMISSIONS.md §3.1 and the explicit Migration 002 instruction ("Do NOT add the removed guest Workspace role"). The frozen `DATABASE_SCHEMA.md` v0.3 still lists `guest` in §3.3's role vocabulary, so this is a documented deviation from the schema doc but consistent with the frozen permissions decision and the user's most recent instruction. The two frozen docs disagree on this point; the migration follows the more recent decision.

No other deviations.

#### Warnings

- **`invitations.invited_by_profile_id` lacks a covering index** (performance advisor INFO). Not called out in the schema's index list for §3.5, so my migration matched the spec — but the Supabase linter recommends indexing every FK. Practical impact: cascading `SET NULL` scans and lookups by inviter are unindexed. Recommended small hardening (`CREATE INDEX invitations_invited_by_profile_id_idx ON public.invitations (invited_by_profile_id) WHERE invited_by_profile_id IS NOT NULL`) — deferred; will bundle into next migration or a hardening pass, matching the pattern used for `set_updated_at` search_path in this migration.
- The four `unused_index` INFOs are cold-cache/zero-workload artefacts and will clear on their own once traffic starts.
- The five `rls_enabled_no_policy` INFOs are deliberate per the staged plan.

#### Deferred (intentionally not yet implemented)

- RLS policies on all four tables.
- Authorization helpers (`lign_is_workspace_member`, `lign_is_workspace_admin`, `lign_is_project_participant`, `lign_has_capability`, etc.).
- `create_workspace`, `invite_workspace_member`, `invite_stakeholder`, `accept_invitation`, `claim_stakeholder_invitation`, `revoke_stakeholder`, `remove_workspace_member`, `change_workspace_member_role` RPCs.
- Workspace-owner minimum invariant enforcement.
- Invitation expiration cron job.
- `activity_events` emission from any of these operations.
- All downstream tables (projects, collections, design objects, collaboration, approvals, releases, audit).

---

### Migration 003 — `projects_participants_collections`

- **File:** `supabase/migrations/20260729140000_projects_participants_collections.sql`
- **Applied at:** `20260729150249` (Supabase migration version)
- **Target project:** `hsfporioghapwghrvvzd` (Lign)
- **Result:** `success: true`
- **Spec references:** `DATABASE_SCHEMA.md v0.3` §§3.6–3.8; `STATE_MACHINES.md v1` §§6–7; `PERMISSIONS.md` §§3.2, 6.3.

#### Hardening applied first

- `CREATE INDEX IF NOT EXISTS invitations_invited_by_profile_id_idx ON public.invitations (invited_by_profile_id) WHERE invited_by_profile_id IS NOT NULL` — resolves the Migration 002 `unindexed_foreign_keys` INFO on this FK.

#### Objects created

| Kind | Schema.Name | Notes |
|---|---|---|
| Table | `public.projects` | RLS enabled, no policies. Full frozen status vocabulary preserved (`draft`, `active`, `on_hold`, `archived`, `closed`); MVP exercises only `active` ↔ `archived` per STATE_MACHINES.md v1 §6. Composite `UNIQUE (id, workspace_id)` supports every child table's tenant composite FK. |
| Table | `public.project_participants` | RLS enabled, no policies. XOR CHECK on `(workspace_member_id, stakeholder_id)`. Three composite FKs: to `projects`, `workspace_members`, `stakeholders` — all on `workspace_id`, all `ON DELETE RESTRICT`. Composite `UNIQUE (id, project_id, workspace_id)` reserved per spec. |
| Table | `public.collections` | RLS enabled, no policies. Composite FK to `projects(id, workspace_id)`. Composite `UNIQUE (id, project_id, workspace_id)` will target `design_assets`' collection FK. Active-name uniqueness via partial `UNIQUE (project_id, LOWER(name)) WHERE status='active'`. |
| Trigger | 3× `*_set_updated_at` on projects / project_participants / collections | BEFORE UPDATE → `public.set_updated_at()`. |
| Index | `invitations_invited_by_profile_id_idx` | Migration 002 hardening (partial). |

#### Important constraints

- **Tenant integrity via composite FKs:**
  - `project_participants (project_id, workspace_id) → projects(id, workspace_id)` — project cannot be in a different workspace than the participant.
  - `project_participants (workspace_member_id, workspace_id) → workspace_members(id, workspace_id)` — member must belong to the participant's workspace.
  - `project_participants (stakeholder_id, workspace_id) → stakeholders(id, workspace_id)` — stakeholder must belong to the participant's workspace.
  - `collections (project_id, workspace_id) → projects(id, workspace_id)` — collection cannot reference a project in a different workspace.
- **XOR** on `project_participants`: `(workspace_member_id IS NOT NULL) <> (stakeholder_id IS NOT NULL)`. Dual-path invariant (same profile via both paths on the same project) enforced separately in the future `project.manage_access` RPC per PERMISSIONS.md §6.3 — not a static DB constraint.
- **Role vocabulary**: `('lead','contributor','reviewer','approver','observer')` — universal, industry-neutral. No professional titles.
- **Composite FK targets prepared for Migration 004:**
  - `projects UNIQUE (id, workspace_id)` — consumed by `design_assets`, `collections`, `releases`, `project_participants`.
  - `collections UNIQUE (id, project_id, workspace_id)` — will be consumed by `design_assets` for the `(collection_id, project_id, workspace_id) → collections(...)` composite FK.

#### Structural triggers

- `set_updated_at` attached to all three new tables (BEFORE UPDATE).
- No RPCs, no participation-management logic, no activity emission (all deferred).

#### Verification performed (all read-only)

- Migration recorded ✓
- All 3 tables exist with matching columns, types, defaults, nullability ✓
- All CHECK constraints match spec (statuses, XOR, roles) ✓
- All FKs and composite FKs match spec ✓
- All partial and composite unique constraints/indexes present ✓
- All 8 public tables have `rls_enabled = true` ✓
- `pg_policies` on `public` returns empty ✓
- 3 new `set_updated_at` triggers present ✓
- Migration 002 FK-index hardening index present ✓
- No unexpected objects, no `nuesync` changes ✓

#### Advisor findings after apply

**Security advisors:**
- INFO ×8 `rls_enabled_no_policy` on all public tables — expected staged finding. Clears when RLS policies land in the authorization stage.
- No WARN or ERROR.
- The `set_updated_at` search_path finding remains resolved from Migration 002.

**Performance advisors:**
- INFO ×6 `unindexed_foreign_keys` — **new, genuine findings**:
  1. `collections.collections_created_by_profile_id_fkey`
  2. `collections.collections_project_fk` (composite `(project_id, workspace_id)`)
  3. `project_participants.project_participants_project_fk` (composite `(project_id, workspace_id)`)
  4. `project_participants.project_participants_stakeholder_fk` (composite `(stakeholder_id, workspace_id)`)
  5. `project_participants.project_participants_workspace_member_fk` (composite `(workspace_member_id, workspace_id)`)
  6. `projects.projects_created_by_profile_id_fkey`
  
  These correspond to FKs whose exact column-order isn't covered by an existing index. Same pattern as the Migration 002 invitations FK we just hardened. All INFO. Recommended to bundle a small hardening block at the start of Migration 004.
- INFO ×9 `unused_index` — expected zero-traffic pattern; will clear as workload materializes.
- INFO `auth_db_connections_absolute` — pre-existing project-level setting.

#### Deviations from `DATABASE_SCHEMA.md v0.3`

**None** (after the 2026-07-29 documentation reconciliation removing `guest` from `workspace_members.role`).

The `projects.status` default is `'draft'` per the frozen schema. MVP `create_project` RPC will insert with `'active'` explicitly per STATE_MACHINES.md v1 §6. Non-MVP status values remain structurally supported but are not exercised.

#### Deferred (intentionally not yet implemented)

- Design objects (`design_assets`, `asset_versions`, `files`, `version_files`) and everything downstream.
- RLS policies for all 8 public tables.
- Authorization helpers (`lign_is_workspace_member`, `lign_is_project_participant`, `lign_has_capability`, etc.).
- Domain RPCs (`create_project`, `add_project_participant`, `archive_project`, etc.).
- Dual-path project-participation invariant (deferred to the `project.manage_access` RPC).
- All event emission and notification wiring.

---

### Migration 004 — `design_assets_versions_files`

- **File:** `supabase/migrations/20260729180000_design_assets_versions_files.sql`
- **Applied at:** `20260729151614` (Supabase migration version)
- **Target project:** `hsfporioghapwghrvvzd` (Lign)
- **Result:** `success: true`
- **Spec references:** `DATABASE_SCHEMA.md v0.3` §§3.9–3.12; `STATE_MACHINES.md v1` §§7–8; `PERMISSIONS.md` §§7, 9.

#### Hardening applied first (Migration 003 follow-up)

Six covering indexes created for the previous batch's `unindexed_foreign_keys` findings:
- `projects_created_by_profile_id_idx` (partial, WHERE created_by_profile_id IS NOT NULL)
- `collections_created_by_profile_id_idx` (partial)
- `collections_project_workspace_idx` composite (project_id, workspace_id)
- `project_participants_project_workspace_idx` composite (project_id, workspace_id)
- `project_participants_workspace_member_workspace_idx` composite partial
- `project_participants_stakeholder_workspace_idx` composite partial

#### Tables created

| Table | Notes |
|---|---|
| `public.design_assets` | Persistent identity of design work. RLS enabled, no policies. Circular current_version_id FK added after asset_versions exists. |
| `public.asset_versions` | Immutable-once-published iteration. RLS enabled, no policies. Sequence uniqueness scoped to design_asset. Multiple published versions may coexist. |
| `public.files` | Content-addressed workspace-owned artifact metadata. RLS enabled, no policies. Dedup is workspace-scoped only. |
| `public.version_files` | Attachment of file to version. RLS enabled, no policies. Composite tenant FKs. Draft-only mutation trigger. |

#### Core Design Asset → Version → File invariants — verified

| # | Invariant | Enforcement |
|---|---|---|
| A | Design Asset belongs to exactly one Project/Workspace | Composite FK `(project_id, workspace_id) → projects(id, workspace_id)` |
| B | Version belongs to exactly one Design Asset | `design_asset_id NOT NULL` + composite FK |
| C | Version cannot cross workspace/project from its Asset | Composite FK `(design_asset_id, project_id, workspace_id) → design_assets(...)` |
| D | Version sequence unique within asset | `UNIQUE (design_asset_id, sequence)` |
| E | Multiple published versions may coexist | No auto-supersede trigger; no single-published constraint |
| F | `current_version_id` may be NULL | Nullable column |
| G | `current_version_id` refers to a Version OF this Asset | Composite FK `(current_version_id, id) → asset_versions(id, design_asset_id)` |
| H | Version creation/publish does not change `current_version_id` | No trigger touches design_assets.current_version_id |
| I | File belongs to exactly one Workspace | `workspace_id NOT NULL` FK RESTRICT |
| J | File dedup is workspace-scoped | `UNIQUE (workspace_id, checksum_sha256)` (no cross-workspace uniqueness) |
| K | Cross-workspace attachment impossible | Composite FKs on version_files share `workspace_id` in both branches |
| L | Downstream project integrity preserved | `UNIQUE (id, workspace_id)`, `(id, project_id)`, `(id, design_asset_id)` on asset_versions; `(id, asset_version_id)` on version_files |
| M | No professional/vertical terminology | Only industry-neutral columns and vocabulary |
| N | No Storage buckets or storage.objects policies | Only `files` (metadata) table |
| O | No RLS policies or workflow RPCs | Only immutability triggers |

#### Important constraints & mechanisms

- **Circular FK handling**: `design_assets.current_version_id → asset_versions(id, design_asset_id)` added via `ALTER TABLE` after both tables exist. Composite unique target `asset_versions_id_design_asset_key UNIQUE (id, design_asset_id)` provides the reference.
- **Sequence integrity**: `UNIQUE (design_asset_id, sequence)` + `CHECK sequence > 0`. Sequences in different assets may overlap; within one asset they're unique. This also serves as the concurrency backstop for simultaneous version inserts.
- **Publish metadata check**: `CHECK ((status = 'draft') OR (published_at IS NOT NULL AND published_by_profile_id IS NOT NULL))` — non-draft versions must carry publish metadata.
- **File dedup**: `UNIQUE (workspace_id, checksum_sha256)` on `files` — workspace-scoped, never global.
- **version_files composite FKs**: both `(asset_version_id, workspace_id)` and `(file_id, workspace_id)` share `workspace_id`, structurally preventing cross-workspace attachment.

#### Structural triggers

- `design_assets_set_updated_at` (BEFORE UPDATE, standard).
- `asset_versions_set_updated_at` (BEFORE UPDATE, **WHEN `OLD.status = 'draft'`**). Once past draft, `updated_at` is frozen per the immutable-once-published policy.
- `asset_versions_publish_immutability` (BEFORE UPDATE, custom). Blocks content-column changes on non-draft rows; allows status transitions, `deprecated_at`, `deprecation_note`.
- `files_set_updated_at` (BEFORE UPDATE, standard).
- `version_files_set_updated_at` (BEFORE UPDATE, standard).
- `version_files_parent_draft_mutation` (BEFORE INSERT/UPDATE/DELETE, SECURITY DEFINER, custom). Blocks all mutations when the parent asset_version is not in draft. `SECURITY DEFINER` so the parent-status lookup bypasses RLS on `asset_versions`.

#### Verification performed (all read-only)

- Migration recorded ✓
- 4 new tables exist with matching columns and defaults ✓
- All 33 constraints across the four tables match spec ✓
- All FKs and composite FKs match spec, including the circular `current_version_fk` added via ALTER ✓
- All partial and composite unique constraints present ✓
- All indexes present, including the DESC sequence index and the partial `published_recent` index ✓
- Migration 003 hardening indexes present ✓
- All 12 public tables have `rls_enabled = true` ✓
- `pg_policies` on `public` returns empty ✓
- All 5 public functions have `search_path = ""` pinned ✓
- SECURITY DEFINER only on `handle_new_auth_user` and `enforce_version_files_parent_draft_mutation` ✓
- Conditional trigger `WHEN (old.status = 'draft')` correctly present on `asset_versions_set_updated_at` ✓
- Immutability triggers present on both `asset_versions` and `version_files` ✓
- No `nuesync` changes ✓

#### Advisor findings after apply

**Security advisors:**
- INFO ×12 `rls_enabled_no_policy` — expected staged finding. All 12 public tables. Clears when authorization stage lands.
- No WARN or ERROR.

**Performance advisors:**
- INFO ×8 `unindexed_foreign_keys` — **new, genuine findings**. Same pattern as prior batches:
  - `asset_versions.design_asset_fk` (3-col composite)
  - `asset_versions.published_by_profile_id_fkey`
  - `design_assets.collection_fk` (3-col composite)
  - `design_assets.created_by_profile_id_fkey`
  - `design_assets.current_version_fk` (2-col composite `(current_version_id, id)`)
  - `design_assets.project_fk` (2-col composite)
  - `version_files.file_fk` (2-col composite `(file_id, workspace_id)`)
  - `version_files.version_fk` (2-col composite `(asset_version_id, workspace_id)`)
  
  All INFO. Recommended to bundle a small hardening block at the start of Migration 005 (same pattern used successfully in Migrations 003 and 004).
- INFO ×~26 `unused_index` — **expected zero-traffic pattern**. Will clear as workload materializes.
- INFO `auth_db_connections_absolute` — pre-existing project-level setting.

#### Deviations from `DATABASE_SCHEMA.md v0.3`

**None.**

Notes on faithful implementation of subtle requirements:
- `asset_versions.updated_at` freezes past draft (WHEN clause on the trigger) — matches "Immutable-once-published tables do not update updated_at after they lock" from `DATABASE_SCHEMA.md v0.3` §3.
- `enforce_asset_version_publish_immutability` blocks only content-column mutations on non-draft rows, permitting legitimate status/deprecated_at/deprecation_note transitions per state machine.
- `enforce_version_files_parent_draft_mutation` is `SECURITY DEFINER` to correctly resolve parent status independent of RLS on `asset_versions`, avoiding a class of RLS-aware false rejections once policies are added.

#### Deferred (intentionally not yet implemented)

- Collaboration tier (`reviews`, `review_participants`, `comments`, `comment_edits`, `annotations`).
- Change / decision (`changes`, `decisions`).
- Approvals (`approval_requests`, `approval_request_approvers`, `approval_responses`).
- Releases (`releases`, `release_items`).
- Audit (`activity_events`).
- All RLS policies (Group A–K per PERMISSIONS.md §8).
- Authorization helpers (`lign_current_profile_id`, `lign_is_workspace_admin`, `lign_is_project_participant`, `lign_has_capability`, etc.).
- Domain RPCs (`upload_and_attach_version_file`, `publish_version`, `set_current_version`, `discard_draft_version`, `deprecate_version`, `file.remove_orphaned`, etc.).
- Storage buckets and storage.objects policies (STORAGE_ARCHITECTURE.md).
- Event emission and notification wiring.
- `pg_cron`, `pg_net`, scheduled jobs.

---

### Migration 005 — `reviews_comments_annotations`

- **File:** `supabase/migrations/20260729190000_reviews_comments_annotations.sql`
- **Applied at:** `20260729153013` (Supabase migration version)
- **Target project:** `hsfporioghapwghrvvzd` (Lign)
- **Result:** `success: true`
- **Spec references:** `DATABASE_SCHEMA.md v0.3` §§3.13–3.17; `STATE_MACHINES.md v1` §§9–11; `PERMISSIONS.md` §8 Groups G–H.

#### Hardening applied first (Migration 004 follow-up)

Eight covering indexes created for the previous batch's `unindexed_foreign_keys` findings:
- `asset_versions_design_asset_project_workspace_idx (design_asset_id, project_id, workspace_id)`
- `asset_versions_published_by_profile_id_idx` (partial)
- `design_assets_collection_project_workspace_idx (collection_id, project_id, workspace_id)` (partial)
- `design_assets_created_by_profile_id_idx` (partial)
- `design_assets_current_version_idx (current_version_id, id)` (partial)
- `design_assets_project_workspace_idx (project_id, workspace_id)`
- `version_files_file_workspace_idx (file_id, workspace_id)`
- `version_files_version_workspace_idx (asset_version_id, workspace_id)`

#### Collaboration tables created

| Table | Notes |
|---|---|
| `public.reviews` | First-class review targeting a specific version. RLS enabled, no policies. Full 5-value status enum preserved; MVP uses `draft → open → in_progress → completed | cancelled`. |
| `public.review_participants` | Reviewer roster. XOR (member \| stakeholder). Composite tenant FKs. RLS enabled, no policies. |
| `public.annotations` | Spatial/positional feedback on a version. Position immutable after insert (trigger). Industry-neutral geometry via `anchor_kind` + JSONB `position`. RLS enabled, no policies. |
| `public.comments` | Threaded typed-target feedback. Seven target columns with XOR CHECK. Composite tenant FKs on all four currently-attachable targets (asset_version, review, annotation, design_asset). RLS enabled, no policies. |
| `public.comment_edits` | Append-only relational edit history. UPDATE and DELETE blocked by trigger. RLS enabled, no policies. |

#### Review integrity

- `reviews_design_asset_fk` composite `(design_asset_id, project_id, workspace_id) → design_assets(id, project_id, workspace_id)` — review scoped to asset's project + workspace.
- `reviews_version_fk` composite `(version_id, design_asset_id) → asset_versions(id, design_asset_id)` — **structurally enforces that the reviewed version belongs to the reviewed asset**. Cross-asset targeting impossible.
- `review_participants` composite FKs on all three actor paths ensure roster is same-workspace.

#### Comment target model

- Seven typed target columns: `target_version_id`, `target_review_id`, `target_annotation_id`, `target_change_id`, `target_decision_id`, `target_design_asset_id`, `target_approval_request_id`.
- `comments_target_xor_check` — exactly one target column is non-null (sum-of-non-null pattern).
- Four target FKs added now (asset_version, review, annotation, design_asset), each composite with `workspace_id`.
- Three target FKs deferred: `target_change_id` and `target_decision_id` land in Migration 006; `target_approval_request_id` in Migration 007. Columns and XOR check are declared here so downstream migrations only ADD CONSTRAINT.
- `comments_parent_fk` is **composite** `(parent_comment_id, workspace_id) → comments(id, workspace_id)` — defensive strengthening beyond the schema's single-column FK, satisfying pre-application invariant H (thread integrity across scope).
- `comments.author_profile_id → profiles(id) ON DELETE SET NULL` — profile-level attribution; no workspace_member/stakeholder XOR on the comment row itself.

#### Comment edit history model

- Relational append-only table `comment_edits`. No JSONB body-edit blob.
- `UNIQUE (comment_id, revision)` — monotonic revision per comment.
- `enforce_comment_edits_append_only` trigger blocks both UPDATE and DELETE, raising with errcode `23514`.
- No `updated_at` column — spec-consistent (immutable-once-written row).
- No `created_at` column — `edited_at` is the single timestamp per spec §3.16.
- Completed-review edit gate deferred to the `edit_own_comment` RPC (application layer, not a structural trigger).

#### Annotation model

- Composite tenant FK on `(asset_version_id, workspace_id) → asset_versions(id, workspace_id)`.
- Optional file anchor: composite FK `(version_file_id, asset_version_id) → version_files(id, asset_version_id)` guarantees the file belongs to the annotation's version.
- Universal geometry via `anchor_kind ∈ (point, region, page_point, page_region, time, three_d_node, document)`. No PDF/CAD/BIM-specific fields.
- `position JSONB NOT NULL` — variable shape per anchor kind, deliberately.
- `page_number` only permitted when `anchor_kind ∈ (page_point, page_region)`.
- `enforce_annotation_position_immutable` trigger locks `anchor_kind`, `page_number`, `position`, `asset_version_id`, `version_file_id` after insert. Moving a pin creates a new annotation.

#### Composite tenant / project integrity — pre-application invariants A–P

All 16 invariants verified. Highlights:
- Reviews, participants, comments, edits, annotations all carry `workspace_id` directly.
- Every FK to an existing table uses composite `workspace_id` where the schema requires it.
- XOR constraints on review_participants (actor) and comments (target) enforce required cardinality.
- No professional/vertical terminology.
- No generic chat / channels / DM architecture.
- No RLS policies, RPCs, mention parsing, or notification logic added.

#### Structural triggers

- `reviews_set_updated_at`, `review_participants_set_updated_at`, `comments_set_updated_at`, `annotations_set_updated_at` — standard `set_updated_at()`.
- `annotations_position_immutable` — custom, `search_path=''` pinned, invoker context.
- `comment_edits_no_update`, `comment_edits_no_delete` — custom, `search_path=''` pinned, invoker context.

#### Verification performed (all read-only)

- Migration recorded ✓
- 5 new tables exist with matching structure ✓
- All 34 constraints across the five tables match spec ✓
- All FKs including composite tenant FKs match spec ✓
- All partial and composite indexes present ✓
- Migration 004 hardening indexes all in place ✓
- All 17 public tables have RLS enabled ✓
- `pg_policies` on public returns 0 rows ✓
- All 7 public functions have `search_path=''` pinned ✓
- SECURITY DEFINER correctly limited to `handle_new_auth_user` and `enforce_version_files_parent_draft_mutation` ✓
- 7 new triggers present, no unintended triggers ✓
- No `nuesync` changes ✓

#### Advisor findings after apply

**Security advisors:**
- INFO ×17 `rls_enabled_no_policy` — expected staged; all 17 public tables. Clears when authorization stage lands.
- No WARN or ERROR.
- No new `function_search_path_mutable` findings.

**Performance advisors:**
- INFO ×13 `unindexed_foreign_keys` — new findings from Migration 005 (composite FKs where the covering index doesn't lead with the FK's exact column order):
  - `annotations.asset_version_fk`, `annotations.version_file_fk`
  - `comment_edits.comment_fk`
  - `comments.parent_fk`, `comments.target_annotation_fk`, `comments.target_design_asset_fk`, `comments.target_review_fk`, `comments.target_version_fk`
  - `review_participants.review_fk`, `review_participants.stakeholder_fk`, `review_participants.workspace_member_fk`
  - `reviews.design_asset_fk`, `reviews.version_fk`
  
  All INFO. Same pattern as prior batches. Recommended to bundle a hardening block at the start of Migration 006.
- INFO ×~40 `unused_index` — expected zero-traffic pattern.
- INFO `auth_db_connections_absolute` — pre-existing project-level setting.

**No duplicate/redundant indexes flagged. No function search_path warnings. No security WARN or ERROR.**

#### Deviations from `DATABASE_SCHEMA.md v0.3`

**One defensive strengthening**, no substantive deviation:

- **`comments.parent_fk` is composite** `(parent_comment_id, workspace_id) → comments(id, workspace_id)` rather than the schema's single-column `parent_comment_id → comments(id)`. This satisfies pre-application invariant H ("Comment reply/thread relationships cannot cross scope") structurally rather than at the application layer. Composite FK is stronger than single-column; no downstream table is broken by the stricter form. Documented in the migration file.

#### Deferred (intentionally not yet implemented)

- Comment target FKs for `target_change_id`, `target_decision_id`, `target_approval_request_id` — added in Migrations 006 and 007 when target tables exist.
- Change / decision (Migration 006).
- Approvals (Migration 007).
- Releases (Migration 008).
- Activity events (Migration 009).
- All RLS policies (authorization stage).
- Authorization helpers (`lign_current_profile_id`, `lign_is_project_participant`, `lign_has_capability`, etc.).
- Domain RPCs (`create_review`, `reviewer_respond`, `complete_review`, `edit_own_comment`, etc.).
- Comment mention parsing and `comment.mentioned` event emission.
- Completed-review comment-editing gate (deferred to `edit_own_comment` RPC).
- Storage buckets, `pg_cron`, `pg_net`.

---

### Migration 006 — `changes_decisions`

- **File:** `supabase/migrations/20260729210000_changes_decisions.sql`
- **Applied at:** `20260729154155` (Supabase migration version)
- **Target project:** `hsfporioghapwghrvvzd` (Lign)
- **Result:** `success: true`
- **Spec references:** `DATABASE_SCHEMA.md v0.3` §§3.18–3.19; `STATE_MACHINES.md v1` §12; `DOMAIN_MODEL.md` §1.4–§1.5.

#### Hardening applied first (Migration 005 follow-up)

Thirteen covering indexes created for the previous batch's `unindexed_foreign_keys` findings:
- `annotations_asset_version_workspace_idx` (composite)
- `annotations_version_file_version_idx` (composite partial)
- `comment_edits_comment_workspace_idx` (composite)
- `comments_parent_workspace_idx` (composite partial)
- `comments_target_annotation_workspace_idx` (composite partial)
- `comments_target_design_asset_workspace_idx` (composite partial)
- `comments_target_review_workspace_idx` (composite partial)
- `comments_target_version_workspace_idx` (composite partial)
- `review_participants_review_workspace_idx` (composite)
- `review_participants_stakeholder_workspace_idx2` (composite partial)
- `review_participants_workspace_member_workspace_idx2` (composite partial)
- `reviews_asset_project_workspace_idx` (3-col composite)
- `reviews_version_asset_idx` (composite)

**Post-hardening: zero remaining `unindexed_foreign_keys` findings from any prior migration.**

#### Tables created

| Table | Notes |
|---|---|
| `public.changes` | Recorded proposed/requested design modifications. Universal — no RFI/variation-order/change-order terminology. Full 6-value status enum preserved; MVP exercises `proposed → accepted | rejected | withdrawn` per STATE_MACHINES.md v1 §12. RLS enabled, no policies. |
| `public.decisions` | Durable recorded outcomes with 5-way typed target XOR. Workspace-scoped only (no project_id column) — project context resolved through target. Immutable-once-written with `supersedes_decision_id` as the sole permitted post-insert mutation. Never deleted. RLS enabled, no policies. |

#### Change model

- **Scope**: composite tenant/scope FK `(design_asset_id, project_id, workspace_id) → design_assets(id, project_id, workspace_id)` — change cannot cross workspace/project.
- **Author**: `created_by_profile_id → profiles(id) ON DELETE SET NULL` — profile-level attribution.
- **Version context** (both optional): composite FKs `(from_version_id, design_asset_id)` and `(to_version_id, design_asset_id)` — enforce same-asset when set. `CHECK` prevents self-comparison.
- **Origin references** (both optional): composite FKs `(origin_review_id, workspace_id)` and `(origin_comment_id, workspace_id) ON DELETE RESTRICT` — preserves originating context.
- **Status**: full 6-value enum kept; MVP uses 3 transitions from `proposed`.
- Composite unique target `(id, workspace_id)` prepared for comments/decisions FKs.

#### Decision model

- **Workspace-scoped only** (no `project_id` column). Project context resolved through typed target.
- **Author**: `author_profile_id → profiles(id) ON DELETE SET NULL`.
- **Standard columns pattern**: `created_at`/`updated_at` are absent per DATABASE_SCHEMA.md v0.3 §3 (immutable-once-written tables). Only `recorded_at`.
- **Composite FK to workspaces** directly (`workspace_id → workspaces(id) ON DELETE RESTRICT`) — decisions are directly workspace-scoped.
- **Supersession self-reference**: composite `(supersedes_decision_id, workspace_id) → decisions(id, workspace_id) ON DELETE RESTRICT` — defensive strengthening beyond the schema's single-column form.

#### Decision target integrity

- Five typed target columns: `target_design_asset_id`, `target_version_id`, `target_review_id`, `target_change_id`, `target_approval_request_id`.
- `decisions_target_xor_check` — exactly one primary target is non-null (sum-of-non-null pattern).
- Four target FKs added now, each composite with `workspace_id`. `target_approval_request_id` FK is deferred to Migration 007; column and XOR check exist from day one.
- Two resulting cross-references: `resulting_version_id` FK added now, `resulting_release_id` FK deferred to Migration 008.
- All target FKs use `ON DELETE RESTRICT` — no historical erasure.
- Cross-workspace targeting is structurally impossible.

#### Deferred Comment FKs completed

Two `ALTER TABLE public.comments ADD CONSTRAINT` statements executed:
- `comments_target_change_fk (target_change_id, workspace_id) → changes(id, workspace_id) ON DELETE RESTRICT` ✓
- `comments_target_decision_fk (target_decision_id, workspace_id) → decisions(id, workspace_id) ON DELETE RESTRICT` ✓

Comments' 7-way target XOR check is unchanged and remains valid. Composite covering indexes added:
- `comments_target_change_workspace_idx` (partial)
- `comments_target_decision_workspace_idx` (partial)

Remaining deferred: `comments_target_approval_request_fk` (Migration 007).

#### Structural immutability

- `changes_set_updated_at` — standard `set_updated_at()` BEFORE UPDATE trigger.
- `decisions_immutable` (BEFORE UPDATE) — custom, invoker context, `search_path=''` pinned. Rejects UPDATE that changes any column except `supersedes_decision_id`.
- `decisions_no_delete` (BEFORE DELETE) — custom, invoker context, `search_path=''` pinned. Blocks all deletes.
- No `set_updated_at` trigger on `decisions` (immutable-once-written).

#### Index coverage — new same-migration FK discipline

**Result: zero new `unindexed_foreign_keys` findings after Migration 006.**

Every new FK introduced by this migration has a covering index in the same migration:
- 6 covering indexes for `changes` FKs (design_asset composite, from/to version partial composites, origin_review/origin_comment partial composites, created_by partial).
- 8 covering indexes for `decisions` FKs (5 target partial composites incl. deferred approval_request, 2 resulting partial composites incl. deferred release, supersedes partial composite, author partial).
- 2 covering indexes for the newly added Comment FKs (target_change and target_decision partial composites).
- Plus 13 hardening indexes for prior-batch FKs.

Two forward-looking indexes prepared for Migrations 007 and 008 (`decisions_target_approval_request_workspace_idx`, `decisions_resulting_release_workspace_idx`) so their ADD CONSTRAINT will not introduce new unindexed-FK findings either.

#### Verification performed (all read-only)

- Migration recorded ✓
- 2 new tables exist ✓
- 10 + 11 constraints across the two tables match spec ✓
- All composite FKs, XOR checks, and unique targets present ✓
- Deferred Comment FKs applied ✓; 7-way comment target XOR unchanged ✓
- 3 new triggers present (changes/set_updated_at + decisions/immutable + decisions/no_delete) ✓
- 9 public functions all with `search_path=''` pinned; SECURITY DEFINER limited to 2 unchanged ✓
- 0 policies on public ✓
- All 19 public tables have RLS enabled ✓
- No unexpected public objects ✓
- No `nuesync` changes ✓

#### Advisor findings after apply

**Security advisors:**
- INFO ×19 `rls_enabled_no_policy` — expected staged (all public tables incl. new changes/decisions). Clears when authorization stage lands.
- No WARN, no ERROR.
- No function search_path warnings.

**Performance advisors:**
- **INFO ×0 `unindexed_foreign_keys`** — 🎯 **goal achieved**. All 13 prior-batch findings resolved by hardening; zero new findings introduced by Migration 006.
- INFO ×89 `unused_index` — expected zero-traffic pattern.
- INFO ×1 `auth_db_connections_absolute` — pre-existing project-level setting.

#### Deviations from `DATABASE_SCHEMA.md v0.3`

**One defensive strengthening**, no substantive deviation:

- **`decisions.supersedes_decision_fk` is composite** `(supersedes_decision_id, workspace_id) → decisions(id, workspace_id)` rather than the schema's single-column `supersedes_decision_id → decisions(id)`. Consistent with the same-pattern strengthening applied to `comments.parent_fk` in Migration 005. Structurally prevents cross-workspace supersession chains without weakening any spec behavior.

No other deviations.

#### Deferred (intentionally not yet implemented)

- `comments.target_approval_request_fk` (Migration 007).
- `decisions.target_approval_request_fk` (Migration 007).
- `decisions.resulting_release_fk` (Migration 008).
- Approvals (Migration 007).
- Releases (Migration 008).
- Activity events (Migration 009).
- All RLS policies (authorization stage).
- Domain RPCs (`change.resolve`, `record_decision`, etc.).
- Event emission and notification wiring.
- Storage buckets, `pg_cron`, `pg_net`.

---

### Migration 007 — `approval_model`

- **File:** `supabase/migrations/20260729220000_approval_model.sql`
- **Applied at:** `20260729155431` (Supabase migration version)
- **Target project:** `hsfporioghapwghrvvzd` (Lign)
- **Result:** `success: true`
- **Spec references:** `DATABASE_SCHEMA.md v0.3` §§3.20–3.22, §8; `STATE_MACHINES.md v1` §§13–14; `PERMISSIONS.md` §10; `EVENT_MODEL.md` §10.

#### Tables created

| Table | Notes |
|---|---|
| `public.approval_requests` | Formal request for approval on a specific version. Policy `any | all`. Full 6-value status vocabulary preserved. Active-target partial unique. RLS enabled, no policies. |
| `public.approval_request_approvers` | Frozen approver-slot roster. XOR (workspace_member \| stakeholder). RLS enabled, no policies. |
| `public.approval_responses` | One immutable response per approver slot. Decision vocabulary: `approved | rejected | changes_requested`. RLS enabled, no policies. |

#### ApprovalRequest model

- Composite tenant/scope FK `(design_asset_id, project_id, workspace_id)` to design_assets.
- Composite scope FK `(version_id, design_asset_id)` — target version must belong to the reviewed asset.
- Policy CHECK restricted to `('any','all')`.
- Status CHECK enforces the 6-value enum.
- `sent_metadata_check`: `status = 'pending' OR sent_at IS NOT NULL`.
- `outcome_metadata_check`: terminal statuses require `outcome_at`.
- Composite unique `(id, workspace_id)` target for approval_responses, approver slots, comments, and decisions.

#### Active-request uniqueness

`UNIQUE INDEX approval_requests_active_target_key ON (design_asset_id, version_id) WHERE status IN ('pending','in_progress')` — at most one active request per (asset, version). Terminal historical rows preserved.

#### Approver-slot model

- XOR CHECK on `(workspace_member_id, stakeholder_id)`.
- Three composite tenant FKs (request, workspace_member, stakeholder) all ON DELETE RESTRICT.
- Two partial unique indexes prevent duplicate slots per identity.
- Composite unique `(id, approval_request_id)` target for approval_responses.
- `sort_order` retained for future `sequential` policy.

#### Frozen approver-set enforcement — where it lives

**Enforced at the RPC + RLS layers, NOT via a static DB constraint.** DATABASE_SCHEMA.md v0.3 §8 and PERMISSIONS.md §10 both locate this invariant at:
- The `request_approval` RPC, which creates request + slots atomically (Migration 010+).
- RLS policies on `approval_request_approvers` that deny direct client INSERTs (authorization stage).

Since RLS is currently enabled without policies, direct writes are already blocked by "deny-by-default" behavior. No trigger added in Migration 007.

#### ApprovalResponse model

- One immutable response per approver slot.
- Composite scope FK `(approver_slot_id, approval_request_id) → approval_request_approvers(id, approval_request_id)` — response's slot must match response's request.
- Composite tenant FK `(approval_request_id, workspace_id) → approval_requests(id, workspace_id)`.
- Decision CHECK: `('approved','rejected','changes_requested')` — no `abstain`.
- `UNIQUE (approver_slot_id)` — exactly one response per slot.

#### Responder coherence implementation

DB-boundary trigger `enforce_approval_response_slot_coherence` (BEFORE INSERT, SECURITY DEFINER, `search_path=''` pinned, REVOKE ALL from public/anon/authenticated):
- Looks up the slot's identity path (workspace_member or stakeholder).
- For workspace_member slots: expected profile = `workspace_members.user_id`.
- For stakeholder slots: expected profile = `stakeholders.user_id`. Raises if `NULL` (unclaimed stakeholder cannot submit).
- Rejects if `responder_profile_id` differs from expected profile.

Errcode `23514` (check_violation) on rejection.

#### Response immutability

DB-boundary trigger `enforce_approval_response_immutable` (invoker context, `search_path=''` pinned) attached to both UPDATE and DELETE. Rejects all mutations with errcode `23514`. Responses are frozen at insert.

#### Approval-target eligibility

DB-boundary trigger `enforce_approval_request_target_eligibility` (BEFORE INSERT, SECURITY DEFINER, `search_path=''` pinned, REVOKE ALL from public/anon/authenticated):
- Looks up `asset_versions.status` for the target `version_id`.
- Rejects if status is not `'published'`.
- Fires on INSERT only (version_id is not expected to change post-insert; approval requests are single-target).

Per DATABASE_SCHEMA.md v0.3 §8 this is a critical DB-boundary invariant, not frontend-only.

#### Deferred FKs completed

- **`comments.target_approval_request_fk`** added: `(target_approval_request_id, workspace_id) → approval_requests(id, workspace_id) ON DELETE RESTRICT`. Covering index added: `comments_target_approval_request_workspace_idx` (partial). Seven-way comment target XOR check from Migration 005 unchanged.
- **`decisions.target_approval_request_fk`** added: `(target_approval_request_id, workspace_id) → approval_requests(id, workspace_id) ON DELETE RESTRICT`. Covering index (`decisions_target_approval_request_workspace_idx`) already existed from preemptive placement in Migration 006. Five-way decision target XOR check unchanged.

#### Index coverage

**Zero new `unindexed_foreign_keys` findings.** Every new FK introduced by Migration 007 has a covering index in the same migration:
- `approval_requests`: 4 covering indexes (design_asset 3-col composite, version composite, created_by partial, outcome_actor partial). Plus 4 spec-required domain indexes (asset_status, workspace_open_due partial, project_status_outcome, version_outcome).
- `approval_request_approvers`: 3 covering indexes (request composite, member composite partial, stakeholder composite partial).
- `approval_responses`: 4 indexes (slot_request composite, request_workspace composite, request_responded, responder_profile).
- `comments.target_approval_request_fk`: covering index added.
- `decisions.target_approval_request_fk`: covering index preexisted from Migration 006.

#### Verification performed (all read-only)

- Migration recorded ✓
- 3 new tables exist with matching structure ✓
- All 20 constraints across the three tables match spec ✓
- Both deferred Comment/Decision approval-request FKs applied ✓
- 7-way comment target XOR and 5-way decision target XOR both intact ✓
- 5 new triggers correctly attached (target eligibility + coherence + immutability × 2 + updated_at) ✓
- 12 public functions all with `search_path=''` pinned ✓
- SECURITY DEFINER limited to 4 justified functions ✓
- 0 policies on public ✓
- All 22 public tables have RLS enabled ✓
- No unexpected objects ✓
- No `nuesync` changes ✓

#### Advisor findings after apply

**Security advisors:**
- INFO ×22 `rls_enabled_no_policy` — expected staged (all 22 public tables).
- No WARN, no ERROR.
- No `function_search_path_mutable` findings.

**Performance advisors:**
- **INFO ×0 `unindexed_foreign_keys`** — 🎯 goal achieved. Zero new findings.
- INFO ×0 `duplicate_index` — no redundant indexes introduced.
- INFO ×105 `unused_index` — expected zero-traffic pattern.
- INFO ×1 `auth_db_connections_absolute` — pre-existing project-level setting.

#### Deviations from `DATABASE_SCHEMA.md v0.3`

**None.** All elements match §§3.20–3.22 exactly.

Notes on subtle spec adherence:
- Approval-target eligibility trigger implemented per §8's "DB-boundary invariant" elevation (§3.20's note about "application-level check acceptable in MVP" treated as fallback wording).
- Approver-slot table has `created_at`/`updated_at` but no `set_updated_at` trigger — slots are frozen once the request is active.
- `approval_responses` has standard timestamps present but no `set_updated_at` — immutable-once-written; timestamps never advance.
- Frozen-approver-set invariant deliberately not enforced by a static trigger; enforced at RPC + RLS per PERMISSIONS.md §10 / §8.

#### Deferred (intentionally not yet implemented)

- Releases (Migration 008).
- Activity events (Migration 009).
- All RLS policies (authorization stage).
- Authorization helpers.
- Approval RPCs: `request_approval`, `respond_to_approval`, `finalize_approval`, `cancel_approval`.
- Automatic policy evaluation (any/all).
- Automatic terminal-status transitions.
- Expiry cron job.
- Approval event emission and notification wiring.
- Frozen-approver-set trigger (deferred to RPC + RLS layers).

---

### Migration 008 — `releases`

- **File:** `supabase/migrations/20260729230000_releases.sql`
- **Applied at:** `20260729160424` (Supabase migration version)
- **Target project:** `hsfporioghapwghrvvzd` (Lign)
- **Result:** `success: true`
- **Spec references:** `DATABASE_SCHEMA.md v0.3` §§3.23–3.24, §9; `STATE_MACHINES.md v1` §15; `DOMAIN_MODEL.md` §1.7.

#### Tables created

| Table | Notes |
|---|---|
| `public.releases` | Project-scoped bundle. Full 5-value status enum preserved; MVP uses `draft → released → withdrawn` per STATE_MACHINES.md v1 §15. Two composite unique targets `(id, project_id, workspace_id)` and `(id, workspace_id)`. RLS enabled, no policies. |
| `public.release_items` | Version inclusion in a release. Three composite FKs enforce same-project bundling. Duplicate-version-per-release prevented. RLS enabled, no policies. |

#### Release model

- Composite tenant/scope FK `(project_id, workspace_id) → projects(id, workspace_id)`.
- `created_by_profile_id → profiles(id) ON DELETE SET NULL`.
- Two composite unique targets:
  - `(id, project_id, workspace_id)` — for `release_items` 3-col composite FK.
  - `(id, workspace_id)` — for `decisions.resulting_release_fk` (decisions are workspace-scoped only).
- Metadata CHECKs: released/superseded/withdrawn require `released_at`; withdrawn requires `withdrawn_at`.
- Status enum: `draft | scheduled | released | superseded | withdrawn`. MVP exercises draft/released/withdrawn.

#### ReleaseItem model

- Denormalized `workspace_id`, `project_id`, `design_asset_id` alongside `release_id` and `version_id`.
- `UNIQUE (release_id, version_id)` — a version appears at most once per release.
- `UNIQUE (release_id, sort_order)` — deterministic ordering.
- `sort_order >= 0` CHECK.
- No author column (releases carry `created_by_profile_id`).

#### Same-project enforcement (structural)

Three composite FKs on `release_items`, all `ON DELETE RESTRICT`:

1. `(release_id, project_id, workspace_id) → releases(id, project_id, workspace_id)` — item's project matches release's project.
2. `(version_id, project_id) → asset_versions(id, project_id)` — version's project matches item's project.
3. `(version_id, design_asset_id) → asset_versions(id, design_asset_id)` — denormalized asset matches version's asset.

Combined effect: **cross-project version inclusion is structurally impossible.** No frontend or future-RLS check required.

#### Version/Asset coherence

The `version_asset_fk` composite ensures a release_item's `design_asset_id` matches the version's actual owning asset. An item cannot claim `design_asset_id = Asset A` while referencing a version from Asset B — that combination fails the FK.

#### Approved-Version prerequisite (DB-boundary trigger)

`enforce_release_finalization_prerequisites` — SECURITY DEFINER, `search_path=''` pinned, REVOKE ALL from public/anon/authenticated:
- Attached to `releases` BEFORE INSERT and BEFORE UPDATE OF status.
- Runs only when transition target is `'released'` (and only when it's a real transition, not a no-op).
- Verifies at least one `release_items` row exists (see Empty-release policy).
- Verifies every item's `(design_asset_id, version_id)` has a matching `approval_requests` row with `status = 'approved'`.
- Approval state derived from `approval_requests.status`, not from response reduction.
- Never modifies data — pure guard.

Errcode `23514` on rejection.

Fires only on transition into `released`; not on withdraw, supersede, or any other status update. Idempotent for released → released (no-op).

#### Empty-release policy

**Product-preference addition beyond frozen spec.** The frozen `DATABASE_SCHEMA.md v0.3` and `STATE_MACHINES.md v1 §15` do not explicitly forbid an empty release from being finalized. The Migration 008 task stated the product preference clearly: "A Release must contain at least one ReleaseItem before it can become released."

Implemented in the finalization trigger: transition to `'released'` fails if `SELECT COUNT(*) FROM release_items WHERE release_id = new.id = 0`. Reported as a documented deviation (strengthening) below.

#### Released-bundle immutability (DB-boundary trigger)

`enforce_release_items_parent_draft_mutation` — SECURITY DEFINER, `search_path=''` pinned, REVOKE ALL from public/anon/authenticated:
- Attached to `release_items` BEFORE INSERT, UPDATE, DELETE.
- Reads parent `releases.status`; rejects mutation unless status is `'draft'`.
- Mirrors the version_files pattern from Migration 004.

Note: the frozen schema §9 documents this as "application-enforced." The DB-boundary trigger is a defense-in-depth strengthening consistent with STATE_MACHINES.md v1 §15 ("draft ↔ item mutations"). Documented as a deviation (strengthening) below.

Withdraw path is unaffected: withdrawing a release updates the release row's status, not release_items rows.

#### Current / Approval independence (verified)

- **Release does NOT modify `design_assets.current_version_id`.** No trigger touches design_assets.
- **Release does NOT publish or supersede asset_versions.** No trigger touches asset_versions.
- **Release does NOT modify approval_requests.** The finalization trigger only READS approval_requests.status; no writes.
- Approval and Release remain orthogonal per DOMAIN_MODEL.md §1.7.

#### Decision resulting_release FK completed

`ALTER TABLE public.decisions ADD CONSTRAINT decisions_resulting_release_fk FOREIGN KEY (resulting_release_id, workspace_id) REFERENCES releases(id, workspace_id) ON DELETE RESTRICT` applied.

- Uses `releases_id_workspace_key` composite unique target (added specifically for this in the same migration).
- Decisions remain workspace-scoped; no `project_id` added.
- Covering index `decisions_resulting_release_workspace_idx` (partial composite) was preemptively created in Migration 006 and correctly covers this FK.
- Decision target XOR unchanged: `resulting_release_id` is a cross-reference, not a primary target.

#### Index coverage

**Zero new `unindexed_foreign_keys` findings.** Every new FK introduced by Migration 008 has a covering index in the same migration:

- `releases_project_workspace_idx (project_id, workspace_id)` — covers `releases.project_fk`.
- `releases_created_by_profile_id_idx` (partial) — covers `releases.created_by`.
- `release_items_release_project_workspace_idx (release_id, project_id, workspace_id)` — covers `release_fk`.
- `release_items_version_project_idx (version_id, project_id)` — covers `version_project_fk` (also serves "releases containing a version" query).
- `release_items_version_asset_idx (version_id, design_asset_id)` — covers `version_asset_fk`.
- `decisions.resulting_release_fk` — covered by preexisting `decisions_resulting_release_workspace_idx` from Migration 006.

Plus spec-required domain indexes:
- `releases_project_status_released_idx`, `releases_workspace_status_idx`.
- `release_items_release_sort_order_key` (UNIQUE) — covers `release_id`-only queries via leading column.
- `release_items_release_version_key` (UNIQUE).

#### Verification performed (all read-only)

- Migration recorded ✓
- 2 new tables exist with matching structure ✓
- 15 constraints across the two tables match spec (+ product-preference empty-release check enforced by trigger) ✓
- Both composite unique targets on releases present ✓
- Deferred Decision FK applied ✓; decision target XOR unchanged ✓
- 5 new triggers correct (release_items parent_draft × 3 op timings, releases finalization_prerequisites × 2 op timings, plus 2 set_updated_at) ✓
- 2 new SECURITY DEFINER functions, both with `search_path=''` pinned ✓
- SECURITY DEFINER limited to 6 justified functions total ✓
- 0 policies on public ✓
- All 24 public tables have RLS enabled ✓
- No unexpected objects ✓
- No `nuesync` changes ✓

#### Advisor findings after apply

**Security advisors:**
- INFO ×24 `rls_enabled_no_policy` — expected staged (all public tables).
- No WARN, no ERROR, no `function_search_path_mutable`.

**Performance advisors:**
- **INFO ×0 `unindexed_foreign_keys`** — goal achieved (third migration in a row).
- **INFO ×0 `duplicate_index`** — no redundant indexes introduced.
- INFO ×112 `unused_index` — expected zero-traffic pattern.
- INFO ×1 `auth_db_connections_absolute` — pre-existing project-level setting.

#### Deviations from `DATABASE_SCHEMA.md v0.3`

**Two documented defensive strengthenings.** No substantive deviations from the frozen data model.

1. **Empty-release protection.** Finalization trigger requires at least one `release_items` row before allowing transition to `released`. The frozen spec is silent on this; product preference stated in Migration 008 task instructions. Behavior is stricter than spec, does not weaken anything.
2. **Released-bundle mutation protection via DB trigger.** Schema §9 says "release_items immutable after parent status='released' — application-enforced". Implemented as a DB-boundary trigger for defense-in-depth, consistent with the version_files pattern in Migration 004 and STATE_MACHINES.md v1 §15 ("draft ↔ item mutations"). Withdraw path unaffected.

Additional structural addition (not a deviation, an explicit new composite unique target): **`releases_id_workspace_key UNIQUE (id, workspace_id)`** was added on releases to serve as the FK target for `decisions.resulting_release_fk`. The frozen spec declared only `(id, project_id, workspace_id)`; the 2-col composite is required because decisions are workspace-scoped and cannot join through project.

#### Deferred (intentionally not yet implemented)

- Activity events (Migration 009).
- All RLS policies (authorization stage).
- Domain RPCs: `create_release`, `add_release_item`, `remove_release_item`, `finalize_release`, `withdraw_release`.
- Release event emission and notification wiring.
- Storage buckets, `pg_cron`, `pg_net`.

---

### Migration 009 — `activity_events`

- **File:** `supabase/migrations/20260729235959_activity_events.sql`
- **Applied at:** `20260729162255` (Supabase migration version)
- **Target project:** `hsfporioghapwghrvvzd` (Lign)
- **Result:** `success: true`
- **Spec references:** `DATABASE_SCHEMA.md v0.3` §3.25; `PERMISSIONS.md` §8 Group K & §15.1; `EVENT_MODEL.md` v1.

#### Table created

- **`public.activity_events`** — append-only historical event log. RLS enabled, no policies.

#### ActivityEvent model

- 12 columns per spec: `id`, `workspace_id`, `project_id` (nullable, non-FK per v0.3 §3.25), `occurred_at`, `event_type`, `actor_profile_id`, `actor_kind`, `subject_kind`, `subject_id` (non-FK), `subject_label`, `subject_snapshot jsonb`, `payload jsonb`.
- No `updated_at`, no `created_at` — immutable, only `occurred_at`.
- Not a source of truth; historical record derived from committed domain actions.

#### Actor model

- `actor_profile_id → profiles(id) ON DELETE SET NULL`.
- `actor_kind CHECK IN ('user','system')`.
- Coherence CHECK: `(actor_kind='user' AND actor_profile_id IS NOT NULL) OR (actor_kind='system' AND actor_profile_id IS NULL)`.
- Profile-based only; no member/stakeholder XOR.

#### Subject model

- `subject_id` deliberately NOT a foreign key — audit rows survive subject deletion.
- `project_id` deliberately NOT a foreign key — audit rows survive project deletion.
- `subject_label` for durable human-readable snapshot.
- `subject_snapshot jsonb` for minimal structured historical context (not a copy of the row).
- `event_type` is plain text — no enum, extensible without migration.

#### Project/Workspace history model

- `workspace_id NOT NULL FK → workspaces(id) ON DELETE RESTRICT` — every event belongs to a workspace.
- `project_id NULLABLE` — populated for project-scoped events; NULL for workspace-level admin events.
- Two orthogonal query paths supported by dedicated indexes:
  - Workspace Audit: `(workspace_id, occurred_at DESC)` and `(workspace_id, event_type, occurred_at DESC)`.
  - Project Design History: `(project_id, occurred_at DESC) WHERE project_id IS NOT NULL`.

#### Immutability

- `enforce_activity_events_append_only` trigger (invoker context, `search_path=''` pinned).
- Attached BEFORE UPDATE and BEFORE DELETE.
- Rejects all mutations with errcode 23514.
- No RPC or bulk-purge path implemented in this migration.

#### Index coverage

**Zero new `unindexed_foreign_keys` findings.** Every FK is covered:
- `workspace_id → workspaces(id)`: covered by `activity_events_workspace_occurred_idx (workspace_id, occurred_at DESC)` (leading column).
- `actor_profile_id → profiles(id)`: covered by `activity_events_actor_occurred_idx (actor_profile_id, occurred_at DESC) WHERE actor_profile_id IS NOT NULL` (leading column, partial).

Five indexes total, matching DATABASE_SCHEMA.md v0.3 §3.25 exactly.

#### Advisor findings after apply

**Security:**
- INFO ×25 `rls_enabled_no_policy` — expected staged (all 25 public tables).
- No WARN, no ERROR.

**Performance:**
- INFO ×0 `unindexed_foreign_keys` — fourth consecutive migration achieving this.
- INFO ×0 `duplicate_index`.
- INFO ×0 `function_search_path_mutable`.
- INFO ×117 `unused_index` — expected zero-traffic.
- INFO ×1 `auth_db_connections_absolute` — pre-existing.

#### Deviations from `DATABASE_SCHEMA.md v0.3`

**None.** Matches §3.25 exactly.

---

## MILESTONE — STRUCTURAL SCHEMA V1 LOCKED

See [`SCHEMA_V1_LOCK.md`](SCHEMA_V1_LOCK.md) for the authoritative lock record.
Modifications to the structural schema are frozen. Future stages (RLS, RPCs, storage, notifications, AI) build on top.



**Date:** 2026-07-29
**Migrations applied:** 001–009 (nine migrations, all successful)
**Target project:** `hsfporioghapwghrvvzd` (Lign)

### Full structural schema audit

**Public tables: 25** (all with RLS enabled, all with 0 policies — awaiting authorization stage).

| Tier | Tables |
|---|---|
| Identity (5) | `profiles`, `workspaces`, `workspace_members`, `stakeholders`, `invitations` |
| Projects (3) | `projects`, `project_participants`, `collections` |
| Design (4) | `design_assets`, `asset_versions`, `files`, `version_files` |
| Collaboration (5) | `reviews`, `review_participants`, `comments`, `comment_edits`, `annotations` |
| History/Reasoning (2) | `changes`, `decisions` |
| Approval (3) | `approval_requests`, `approval_request_approvers`, `approval_responses` |
| Release (2) | `releases`, `release_items` |
| Audit (1) | `activity_events` |

No unexpected tables. All match the expected structural inventory.

**User-created functions in public: 15**
- `set_updated_at` (reusable)
- `handle_new_auth_user` (SECURITY DEFINER — auth-signup trigger)
- `enforce_workspace_members_user_id_immutable`
- `enforce_asset_version_publish_immutability`
- `enforce_version_files_parent_draft_mutation` (SECURITY DEFINER)
- `enforce_annotation_position_immutable`
- `enforce_comment_edits_append_only`
- `enforce_decisions_immutable_except_supersedes`
- `enforce_decisions_no_delete`
- `enforce_approval_request_target_eligibility` (SECURITY DEFINER)
- `enforce_approval_response_slot_coherence` (SECURITY DEFINER)
- `enforce_approval_response_immutable`
- `enforce_release_items_parent_draft_mutation` (SECURITY DEFINER)
- `enforce_release_finalization_prerequisites` (SECURITY DEFINER)
- `enforce_activity_events_append_only`

**All 15 functions have `search_path=''` pinned.**

**SECURITY DEFINER functions: 6** — each justified by cross-table lookup requirements that must bypass RLS. All revoke ALL from public/anon/authenticated.

**Total triggers in public: 41.**

**RLS coverage: 25/25 tables** (100%). Policy count: 0 (staged for authorization migration).

### Advisor state at freeze

| Advisor | Count | Notes |
|---|---|---|
| Security: `rls_enabled_no_policy` | 25 (INFO) | Expected. Clears when RLS policies land. |
| Security: `function_search_path_mutable` | 0 | All functions pinned. |
| Security: any WARN/ERROR | 0 | Clean. |
| Performance: `unindexed_foreign_keys` | 0 | Same-migration FK discipline succeeded across all migrations. |
| Performance: `duplicate_index` | 0 | No redundant indexes. |
| Performance: `unused_index` | 117 (INFO) | Zero-traffic pattern; clears with workload. |
| Performance: `auth_db_connections_absolute` | 1 (INFO) | Pre-existing project-level config, unrelated. |

### Core structural relationship audit

The domain chain is structurally coherent:

```
Workspace (tenant)
  → Project
    → Collection (optional grouping)
    → DesignAsset
      → AssetVersion (immutable, sequence-scoped per asset)
        → VersionFile → File (workspace-scoped, dedup by checksum)
        → Annotation (permanent to origin version)
      → Review (targets a published version of the asset)
        → ReviewParticipant, Comment
      → Change (proposal on the asset)
      → ApprovalRequest (targets a published version)
        → ApprovalRequestApprover (frozen slot roster)
          → ApprovalResponse (1:1 with slot, immutable)
      → Decision (workspace-scoped, targets any of the above)
    → Release (project-scoped bundle)
      → ReleaseItem (version × release, same-project structurally)
  → ActivityEvent (workspace-scoped audit log)
```

**Every cross-table relationship uses composite FKs with `workspace_id` (and often `project_id`) so cross-tenant and cross-scope relationships are structurally impossible, not just discouraged.**

### Independence of the four version-facing concepts — reconfirmed

- **Latest** ≠ **Current** ≠ **Approved** ≠ **Released**.
- `version.publish` does NOT change `design_assets.current_version_id` (no trigger).
- `version.publish` does NOT auto-supersede prior published versions (per D1; no side effect).
- `approval.approved` outcome does NOT change `current_version_id`.
- `release.finalized` does NOT change `current_version_id`.
- Archiving a design_asset preserves `current_version_id`.

No migration accidentally introduced automatic coupling. Verified via absence of triggers on `design_assets.current_version_id` from any migration except explicit `asset.set_current` (which is deferred to the RPC stage).

### Structural schema — **FROZEN**

No further structural table migrations are planned. The public schema is complete and ready for:
- **Authorization stage**: RLS policies + `lign_has_capability` helpers + related functions.
- **Domain RPC stage**: `create_workspace`, `publish_version`, `respond_to_approval`, `finalize_release`, and the rest of the RPC catalog.
- **Event emission stage**: transactional event inserts inside every state-changing RPC.
- **Notification stage**: derivation from committed events.
- **Storage stage**: buckets and object policies.
- **AI stage**: derived infrastructure against activity_events and domain tables.

All of these operate against the frozen structural schema.
