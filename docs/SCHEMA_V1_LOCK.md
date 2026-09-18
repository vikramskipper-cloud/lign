# LIGN Structural Schema V1 — LOCKED

**Locked:** 2026-07-29
**Target project:** `hsfporioghapwghrvvzd` (Lign, IWillBuild org, us-east-2, Postgres 17.6)
**Migrations 001–009 applied and verified.**

This document is the authoritative marker that the LIGN structural database schema is frozen at V1. No further structural table migrations are planned before the authorization / RPC / storage / notification / AI stages.

## Frozen migration set

| # | Version | Name | File |
|---|---|---|---|
| 001 | `20260728205411` | `foundation_profiles` | `supabase/migrations/20260728160001_foundation_profiles.sql` |
| 002 | `20260728210648` | `workspaces_identity` | `supabase/migrations/20260728220000_workspaces_identity.sql` |
| 003 | `20260729150249` | `projects_participants_collections` | `supabase/migrations/20260729140000_projects_participants_collections.sql` |
| 004 | `20260729151614` | `design_assets_versions_files` | `supabase/migrations/20260729180000_design_assets_versions_files.sql` |
| 005 | `20260729153013` | `reviews_comments_annotations` | `supabase/migrations/20260729190000_reviews_comments_annotations.sql` |
| 006 | `20260729154155` | `changes_decisions` | `supabase/migrations/20260729210000_changes_decisions.sql` |
| 007 | `20260729155431` | `approval_model` | `supabase/migrations/20260729220000_approval_model.sql` |
| 008 | `20260729160424` | `releases` | `supabase/migrations/20260729230000_releases.sql` |
| 009 | `20260729162255` | `activity_events` | `supabase/migrations/20260729235959_activity_events.sql` |

## Locked inventory

- **25 public tables**, 100% RLS-enabled, 0 policies (staged).
- **15 user-created functions**, all with `search_path = ''` pinned. 6 SECURITY DEFINER (all REVOKE ALL from public/anon/authenticated).
- **41 triggers**.
- Advisor state at lock: **0 unindexed_foreign_keys**, **0 duplicate_index**, **0 function_search_path_mutable**, **0 security WARN/ERROR**. 25 rls_enabled_no_policy INFOs (expected staged); 117 unused_index INFOs (zero-traffic pattern); 1 auth_db_connections_absolute INFO (pre-existing).

## Locked table inventory

```
Identity (5):        profiles, workspaces, workspace_members, stakeholders, invitations
Projects (3):        projects, project_participants, collections
Design (4):          design_assets, asset_versions, files, version_files
Collaboration (5):   reviews, review_participants, comments, comment_edits, annotations
History (2):         changes, decisions
Approval (3):        approval_requests, approval_request_approvers, approval_responses
Release (2):         releases, release_items
Audit (1):           activity_events
```

## Locked DB-boundary invariants

Enforced by triggers and composite FKs; MUST remain intact in any future migration.

1. `workspace_members.user_id` immutability after insert.
2. `asset_versions` content immutability after publish (allows status, deprecated_at, deprecation_note only).
3. `asset_versions.updated_at` frozen once past draft (WHEN clause).
4. `version_files` mutation only while parent asset_version is `'draft'`.
5. `annotations.anchor_kind` / `page_number` / `position` / anchor references immutable after insert.
6. `comment_edits` append-only (UPDATE + DELETE blocked).
7. `decisions` immutable after insert except `supersedes_decision_id`.
8. `decisions` never deleted.
9. `approval_requests.version_id` must reference a `published` asset_version (checked at insert).
10. `approval_responses.responder_profile_id` must equal the profile behind the approver slot (unclaimed stakeholders cannot respond).
11. `approval_responses` immutable after insert (UPDATE + DELETE blocked).
12. `release_items` mutation only while parent release is `'draft'`.
13. `releases` transition to `'released'` requires ≥1 `release_items` **and** every item's `(design_asset_id, version_id)` has an `approval_requests` row with `status='approved'`.
14. `activity_events` append-only (UPDATE + DELETE blocked).
15. Every non-workspace, non-profile row carries `workspace_id`; cross-workspace relationships are structurally impossible via composite FKs.
16. `design_assets.current_version_id` references a Version OF the same asset (composite FK). Never auto-set by publish, approval, or release.
17. `release_item.version_id` belongs to `release_item.project_id` and its parent release has the same project.
18. Files dedup is workspace-scoped only (`UNIQUE (workspace_id, checksum_sha256)`).
19. Comments' **8-way** and Decisions' 5-way target XOR checks. (Comments shipped 7-way in Migration 005; APP 008 added `target_requirement_id` as the eighth arm under an approved re-freeze. Live constraint verified 2026-09-18.)
20. Roster XOR (workspace_member_id | stakeholder_id) on `project_participants`, `review_participants`, `approval_request_approvers`.

## Locked deviations from `DATABASE_SCHEMA.md v0.3`

All defensive strengthenings; none weaken spec:

1. `workspace_members.role` CHECK omits `guest` (reconciled with PERMISSIONS.md §3.1; DATABASE_SCHEMA.md v0.3 §3.3 updated in Migration 003 to match).
2. `comments.parent_fk` is composite `(parent_comment_id, workspace_id)` — spec declared single-column.
3. `decisions.supersedes_decision_fk` is composite `(supersedes_decision_id, workspace_id)` — spec declared single-column.
4. Release finalization trigger requires ≥1 `release_items` (spec silent; product preference).
5. `release_items` parent-draft mutation trigger — spec said "application-enforced"; implemented as DB-boundary trigger for defense-in-depth.
6. `releases_id_workspace_key UNIQUE (id, workspace_id)` — added to serve `decisions.resulting_release_fk` (workspace-scoped decisions cannot include project_id in composite FK).

## What comes next (NOT part of V1 lock)

The lock covers **structural schema only**. Future stages operate against V1 without modifying it:

- **Authorization stage** — RLS policies, `lign_has_capability` and helper functions per PERMISSIONS.md §7.
- **RPC stage** — `create_workspace`, `publish_version`, `respond_to_approval`, `finalize_release`, `edit_own_comment`, `claim_stakeholder_invitation`, etc. per PERMISSIONS.md §10.
- **Event emission stage** — transactional `activity_events` inserts inside every state-changing RPC, per EVENT_MODEL.md §6.
- **Storage stage** — Supabase Storage buckets and object policies per (future) STORAGE_ARCHITECTURE.md.
- **Notification stage** — derivation from committed events per EVENT_MODEL.md §7.
- **AI stage** — historical context derived from activity_events + domain tables.

If any future stage needs a structural addition (new column, new table, new FK), it re-opens the schema and requires explicit re-freeze.

## Modification policy while locked

- **No new tables** may be added under lock.
- **No column additions or removals** to existing tables under lock.
- **No FK, CHECK, UNIQUE constraint additions or removals** on existing structural columns under lock.
- **Index tuning** is permitted (adding covering indexes, removing verifiably unused indexes) if it does not change semantics.
- **RLS policies, RPCs, and triggers that add domain logic on top** are permitted and expected — those are the next stages.

Any breach of the modification policy requires an explicit re-freeze checkpoint.
