# Migration Artifact Reconciliation Amendment

**Date:** 2026-09-18
**Scope:** `supabase/migrations/` file contents only.
**Deployed state changed:** **None.**

---

## 1. What this is

`PLATFORM_CHEATSHEET.md` rule 19 requires a governance record for any change
touching a frozen slice's artifacts. This is that record. It is filed once and
referenced from each affected certification rather than reopening five frozen
reports, because **no certified claim is affected**.

Every `docs/freeze/APP_0NN_FINAL_CERTIFICATION.md` certifies the state of the
**deployed database** — schema, RLS policies, triggers, RPC signatures, grants,
capability maps, advisor posture. None of that was touched. What changed is the
local `.sql` files that were supposed to *describe* that deployment and did not.

## 2. Why it was needed

When the project was placed under version control on 2026-09-18, an audit found
that `supabase/migrations/` was not a faithful record of the deployed database:

- 29 of the 67 applied migrations had **no local file at all**. The database was
  their only copy.
- All 38 files that did exist **differed from the statement actually applied**.
  24 differed structurally, several by carrying fewer RLS policy and grant
  statements than production — a fresh replay would have produced a *weaker
  security surface* than the certified one.
- 2 files were consolidated supersets that would have **double-applied**
  statements on replay.
- 1 file — `app_010_notifications_authz_and_rpcs` — contained **no executable
  SQL at all**, only commentary. Its 948 applied lines existed nowhere outside
  the database.

Rule 20 ("frozen migration files SHA-verified byte-identical") was therefore
unverifiable, and had been for the life of the project.

## 3. What was done

1. All 29 missing migrations were recovered from
   `supabase_migrations.schema_migrations` and md5-verified.
2. All 38 pre-existing files were replaced with the exact applied statement.
3. Result: **67 of 67 files byte-identical to what was applied**, ordered to
   match apply order.
4. `supabase/_applied_snapshot/` retains a verbatim copy, named by migration.
5. `ops/verify_migrations.sh` now enforces rule 20 mechanically. Verified PASS
   at 67/67, and confirmed to fail on a deliberately tampered file.

Full detail: `supabase/migrations/RECONCILIATION.md`.

## 4. Affected slices

Files were replaced in every slice below. In each case the replacement is the
SQL that slice's own certification already describes as deployed, so the
certification becomes *more* accurate, not less.

| Slice | Migrations replaced |
|---|---|
| Foundation (Migrations 001-009) | `foundation_profiles`, `workspaces_identity`, `projects_participants_collections`, `design_assets_versions_files`, `reviews_comments_annotations`, `changes_decisions`, `approval_model`, `releases`, `activity_events` |
| AUTH 001-009 | all 13 `auth_*` migrations |
| STORAGE 002-004 | `storage_002_bucket_and_policies`, `storage_003_upload_finalize_workflow`, `storage_004_orphan_purge_lifecycle` |
| REQUIREMENTS 002-004 | `requirements_002_schema`, `requirements_003_authz_and_rpcs`, `requirements_004_events_and_traceability` |
| APP 003 | `app_003_disciplines` |
| APP 004 | `app_004_version_files_write_rls` |
| APP 006 | `app_006_reviews_schema`, `app_006_reviews_authz_and_rpcs` |
| APP 008 | `app_008_requirements_schema`, `app_008_requirements_authz_and_rpcs` |
| APP 009 | `app_009_releases_schema`, `app_009_releases_authz_and_rpcs` |
| APP 010 | `app_010_notifications_schema`, `app_010_notifications_authz_and_rpcs` |

## 5. Prior content

Preserved in git history. Recover any replaced file with:

```bash
git show 764b068:supabase/migrations/<filename> > /tmp/prior.sql
```

The old `app_010_notifications_authz_and_rpcs` file is the one worth revisiting:
4.5 KB of design commentary that belongs in `docs/APP_010_FREEZE_INDEX.md`.

## 6. Standing rule

Apply migrations **from the file**. Never by pasting SQL into `execute_sql` or
the dashboard. Ad-hoc statements are drift that `ops/verify_migrations.sh`
will detect but cannot repair.

## 7. Residual risk — closed

Two independent verifications were run on 2026-09-18.

**Provenance** (`ops/audit_schema_provenance.py`) over all 590 live objects:
every object is `CREATE`d by a migration (0 orphans); every migration-created
object is live or explicitly dropped (0 unexplained absences); every function
body is byte-identical to a migration definition (160/160).

**Replay equivalence** (`ops/replay_check.sh`) — the decisive test. All 67
migrations were replayed into an empty local Postgres 17 and the resulting
schema compared to production object by object:

| Kind | Production | Shadow | Differences |
|---|---|---|---|
| TABLE | 32 | 32 | 0 |
| POLICY | 69 | 69 | 0 |
| TRIGGER | 66 | 66 | 0 |
| FUNCTION | 160 | 160 | 0 |
| INDEX | 263 | 263 | 0 |

**590/590 identical**, comparing full definitions including policy
`USING`/`WITH CHECK` predicates and `md5(prosrc)` for every function.

Migration ordering is verified, and no out-of-band `ALTER` exists. The residual
risk recorded in earlier revisions of this document is closed. Re-run either
script after any migration to keep it closed.
