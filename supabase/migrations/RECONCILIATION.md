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

## 3. Resolution — option 1 adopted (2026-09-18)

**Decision: the database is canonical.** Every file in `supabase/migrations/`
was replaced with the exact SQL statement that was applied to
`hsfporioghapwghrvvzd`, taken from `_applied_snapshot/`.

- **38 files replaced** — every pre-existing file, across all four drift
  classes: 24 structurally divergent, 11 differing only in `COMMENT ON` text and
  Unicode punctuation, 2 consolidated supersets, 1 documentation stub. The 11
  were replaced too: differing comment text still produces different object
  comments in the database, so leaving them would have kept the directory
  unverifiable as a whole.
- **29 files unchanged** — the reconstructed ones were already byte-exact.
- **Result: 67 of 67 files byte-identical to the applied statements**, in an
  order that matches the apply order exactly.

### Why this form

Byte-identity is what makes `PLATFORM_CHEATSHEET.md` rule 20 mechanically
checkable. Prepending preserved header comments would have kept the files
*semantically* equivalent but broken the md5 check, so prose was not grafted
back on. Nothing is lost: the prior content of every replaced file is in git
history — commits `a33f981` (initial import) and `764b068` (reconciliation).
Recover any of it with:

```bash
git show 764b068:supabase/migrations/<filename> > /tmp/prior.sql
```

The richest casualty is the old `app_010_notifications_authz_and_rpcs` file:
4.5 KB of design commentary with no executable SQL. It is preserved at that
commit and is worth mining into `docs/APP_010_FREEZE_INDEX.md` rather than
being carried in a migration.

### Two hazards this closed

1. **Double-apply.** `app_006_reviews_authz_and_rpcs` and
   `app_009_releases_authz_and_rpcs` were consolidated supersets — they held
   their base migration *plus* the follow-ups that were applied separately and
   now exist as their own files. Replaying the directory would have applied
   those statements twice. Both are now just their base body.
2. **Silent security divergence.** Several applied bodies carried RLS policy and
   grant statements the local files lacked. A fresh replay would have produced a
   weaker security surface than production. No longer possible.

### What did NOT change

**No deployed object was touched.** This was a repo-hygiene change only: files
were edited to match a database that was already correct. Schema, RLS, RPCs,
triggers, grants and data on `hsfporioghapwghrvvzd` are untouched, and every
`docs/freeze/` certification remains accurate about the deployed state. See
`docs/freeze/MIGRATION_ARTIFACT_AMENDMENT.md` for the governance record.

### Out-of-band objects — audited 2026-09-18, clean

The concern was that objects created by ad-hoc `execute_sql` or dashboard edits
would live in production while appearing in no migration. `ops/schema_inventory.sql`
+ `ops/audit_schema_provenance.py` check this exhaustively in three directions.
All **590** live objects were examined:

| Check | Result |
|---|---|
| **Forward** — every live object is `CREATE`d by a migration | 32 tables, 69 policies, 66 triggers, 160 functions, 263 indexes → **0 orphans** |
| **Reverse** — every migration-created object is live, or `DROP`ped by a later migration | 515 created → 512 live, 3 explicitly dropped → **0 unexplained absences** |
| **Bodies** — each function's `prosrc` is byte-identical to a definition in the files | **160/160 match** |

The body check is the sharpest of the three: it would catch an out-of-band
`CREATE OR REPLACE FUNCTION` that silently changed an RPC, and it covers every
`SECURITY DEFINER` RPC, trigger function and authorization helper. Nothing was
found.

### Replay verified — 2026-09-18, identical

The provenance audit above proves every deployed object traces to a migration.
The stronger question — does replaying the 67 files into an *empty* database
reproduce production? — was answered by an actual replay
(`ops/replay_check.sh`), not inference.

All 67 migrations applied cleanly, in order, into a fresh local Postgres 17.
The resulting schema was then compared to production object by object:

| Kind | Production | Shadow | prod-only | shadow-only | definition differs |
|---|---|---|---|---|---|
| TABLE | 32 | 32 | 0 | 0 | 0 |
| POLICY | 69 | 69 | 0 | 0 | 0 |
| TRIGGER | 66 | 66 | 0 | 0 | 0 |
| FUNCTION | 160 | 160 | 0 | 0 | 0 |
| INDEX | 263 | 263 | 0 | 0 | 0 |

**590 of 590 objects identical**, comparing full definitions — policy
`USING`/`WITH CHECK` predicates, trigger definitions, index definitions, table
column lists, and `md5(prosrc)` for every function.

This closes both gaps that the provenance audit left open:

- **Ordering** — the files do apply cleanly in sequence from empty. Verified,
  not assumed.
- **Out-of-band `ALTER`** — every policy predicate and column definition in
  production matches what the migrations produce. Nothing was altered outside
  the migration path.

`supabase/migrations/` reproduces the deployed database's **schema objects**,
not merely a byte-match of recorded statements.

> **Qualified 2026-09-18 (APP 011 behavioural testing).** The 590/590 result
> above covers tables, policies, triggers, functions and indexes. It does **not**
> cover table privileges, and privileges differ: production grants
> `SELECT/INSERT/UPDATE/DELETE` to `anon`, `authenticated` and `service_role` on
> all 32 tables, while a pristine replay grants none of it (96 grant pairs, zero
> holding SELECT). Those GRANTs are Supabase platform state applied at project
> creation, not emitted by any migration. A database rebuilt from this directory
> alone would reject every request with `42501` before RLS was consulted.
> `ops/schema_inventory.sql` now captures `GRANT` rows so future replay checks
> catch it. See `docs/APP_011_IMPLEMENTATION_REPORT.md` §3.

---

## 4. Staying in sync

`ops/verify_migrations.sh` enforces this. It compares every local file against
the md5 of the applied statement and fails on drift, on a migration applied with
no local file, and on a local file never applied:

```bash
psql "$SUPABASE_DB_URL" -At -f ops/migration_manifest.sql > /tmp/manifest
ops/verify_migrations.sh /tmp/manifest
```

Verified PASS at 67/67 on 2026-09-18, and confirmed to fail on a deliberately
tampered file. Wire it into CI when CI exists.

**Rule going forward:** apply migrations from the file, never by pasting SQL
into `execute_sql` or the dashboard. Every ad-hoc statement is drift this
script will catch but cannot fix.
