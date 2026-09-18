# Migration reconciliation — 2026-09-18

Audit of `supabase/migrations/` against the migrations actually applied to
Supabase project `hsfporioghapwghrvvzd` (Lign), performed when the project was
first placed under version control.

**Ground truth:** `supabase_migrations.schema_migrations` on the live project.
67 migrations applied. Verbatim bodies snapshotted to `../_applied_snapshot/`.

---

## 1. What was missing

29 of the 67 applied migrations had **no local `.sql` file at all**. They were
recovered from the database, written to `supabase/migrations/`, and verified
**byte-identical by md5** against `statements[1]` for every one:

| Reconstructed file | Applied version |
|---|---|
| `20260802180001_storage_003_test_fixtures.sql` | `20260730154026` |
| `20260802180002_storage_003_rename_out_columns.sql` | `20260730154725` |
| `20260803120001_storage_004_rename_out_columns.sql` | `20260730161535` |
| `20260803120002_storage_004_release_conflict_guard.sql` | `20260730161727` |
| `20260803180000_realtime_002_publication_scope.sql` | `20260730172330` |
| `20260804120001_requirements_002_revoke_trigger_execute.sql` | `20260803080408` |
| `20260806120001_requirements_004_fix_array_append.sql` | `20260803082800` |
| `20260808180001_app_006_create_review_extended.sql` | `20260804063034` |
| `20260808180002_app_006_complete_open_state_reopen.sql` | `20260804063131` |
| `20260808180003_app_006_roster_mutation_rpcs.sql` | `20260804063220` |
| `20260808180004_app_006_bookmark_and_view_rpcs.sql` | `20260804063244` |
| `20260808180005_app_006_dashboard_read_rpcs.sql` | `20260804063351` |
| `20260808180006_app_006_create_review_root_init_fix.sql` | `20260804071313` |
| `20260810120000_app_007_approvals_schema.sql` | `20260804125736` |
| `20260810180000_app_007_approvals_authz_and_rpcs.sql` | `20260804125820` |
| `20260810180001_app_007_write_rpcs.sql` | `20260804125920` |
| `20260810180002_app_007_respond_and_supersede.sql` | `20260804130049` |
| `20260810180003_app_007_cancel_expire_roster_rpcs.sql` | `20260804130150` |
| `20260810180004_app_007_read_rpcs.sql` | `20260804130319` |
| `20260812180001_app_008_fix_pg_trgm_extension_schema.sql` | `20260804152729` |
| `20260812180002_app_008_fk_covering_indexes.sql` | `20260804152904` |
| `20260814180001_app_009_release_read_rpcs.sql` | `20260805115012` |
| `20260814180002_app_009_release_read_rpcs_pt2.sql` | `20260805115042` |
| `20260814180003_app_009_release_read_rpcs_pt3.sql` | `20260805115129` |
| `20260814180004_app_009_release_read_rpcs_pt4.sql` | `20260805115157` |
| `20260814180005_app_009_release_write_rpcs.sql` | `20260805115242` |
| `20260814180006_app_009_publish_finalize_withdraw.sql` | `20260805115339` |
| `20260814180007_app_009_drop_frozen_overloads_f2.sql` | `20260805115404` |
| `20260816180001_app_010_router_fix_partial_index_inference.sql` | `20260805154843` |

### Filename prefixes

The applied version (`20260804125736`) is the wall-clock apply time. The local
prefix (`20260810120000`) follows the pre-existing local convention of narrative
timestamps that sort in dependency order. Reconstructed files were slotted into
that scheme so `supabase/migrations/` replays in true apply order. **Local
prefixes are ordering only — they are not the applied versions.**

---

## 2. What drifted

All 38 pre-existing local files differ from the applied body by md5. Classified:

| Class | Count | Meaning |
|---|---|---|
| Structurally equivalent | 15 | Identical DDL/DML once `COMMENT ON` statements and Unicode punctuation (`…` `—`) are normalized. Safe. |
| Structurally divergent | 21 | Real differences in statements beyond comments. Local file will not reproduce the deployed object set. |
| Consolidated superset | 2 | `app_006_reviews_authz_and_rpcs`, `app_009_releases_authz_and_rpcs`. Local file contains everything applied in the base migration **plus** the follow-up migrations that were applied separately. Replaying both local and reconstructed files would double-apply. |
| Documentation stub | 1 | `app_010_notifications_authz_and_rpcs` — 4.5 KB of comments describing the migration, **zero executable SQL**. The 948 applied lines exist only in the database and in `_applied_snapshot/`. |

### Structurally divergent files

| Migration | Applied statements absent from local |
|---|---|
| `app_010_notifications_authz_and_rpcs` | 521 of 948 |
| `auth_005_collaboration_rls` | 114 of 305 |
| `requirements_004_events_and_traceability` | 103 of 332 |
| `app_010_notifications_schema` | 96 of 230 |
| `auth_004_design_objects_rls` | 92 of 232 |
| `auth_007_approval_rls` | 79 of 168 |
| `requirements_003_authz_and_rpcs` | 75 of 327 |
| `storage_004_orphan_purge_lifecycle` | 62 of 231 |
| `requirements_002_schema` | 51 of 228 |
| `auth_006_change_decision_rls` | 43 of 157 |
| `auth_008_release_rls` | 39 of 109 |
| `storage_002_bucket_and_policies` | 8 of 53 |
| `storage_003_upload_finalize_workflow` | 8 of 340 |
| `app_008_requirements_schema` | 2 of 95 |
| `auth_003_projects_participants_collections_rls` | 2 of 248 |
| `activity_events` | 1 of 56 |
| `design_assets_versions_files` | 1 of 233 |
| `releases` | 1 of 177 |

The two largest classes of divergence observed in sampling were (a) `COMMENT ON
TABLE/COLUMN/CONSTRAINT` statements present on one side only, and (b) additional
RLS policy / grant statements in the applied body. Category (a) is cosmetic;
category (b) is not — it means the local file, if replayed into a fresh
database, produces a **different security surface** than production.

---

## 3. Open decision — NOT resolved here

The 24 non-equivalent files were **left untouched**. Rewriting them to match the
database would modify artifacts that `docs/freeze/` certifies as permanently
frozen, which `PLATFORM_CHEATSHEET.md` rule 19 says requires an explicit
re-freeze. That is an architectural decision, not a bookkeeping one.

Options, in rough order of preference:

1. **Adopt the database as canonical.** Replace each divergent local file with
   its `_applied_snapshot/` body, and record a re-freeze note in each affected
   APP's freeze report. Makes `supabase db reset` reproduce production exactly.
   Loses the richer prose comments in some local files.
2. **Merge per file.** Keep local prose, graft in the applied statements the
   local file is missing. Highest fidelity, slowest, and every merge needs
   review against the freeze report for that slice.
3. **Leave as-is and treat `_applied_snapshot/` as canonical** for replay, with
   `migrations/` demoted to design-intent documentation. Cheapest, but it means
   the migrations directory is decorative and will keep drifting.

Until one is chosen, **`_applied_snapshot/` is the only faithful record of the
deployed schema**, and `supabase/migrations/` must not be assumed replayable.

---

## 4. Verification commands

```bash
# applied md5s
#   select md5(statements[1]) || '  ' || name from supabase_migrations.schema_migrations;
# local md5
md5 -q supabase/_applied_snapshot/<name>.sql
```

Every file in `_applied_snapshot/` matched its database md5 at the time of
writing (67/67).
