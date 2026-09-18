# `_applied_snapshot/` — verbatim bodies of every applied migration

**This directory is NOT a migration path.** The Supabase CLI ignores it. Do not
apply, edit, or reorder anything in here.

Each file is the exact SQL text recorded in
`supabase_migrations.schema_migrations.statements[1]` on project
`hsfporioghapwghrvvzd` (Lign), extracted 2026-09-18 and verified by md5 against
the database. Files are named by migration **name** (no timestamp prefix),
because the prefix in `supabase/migrations/` is a local ordering convention that
does not match the remote apply version.

## Why this exists

Until 2026-09-18 the project had no version control, and `supabase/migrations/`
held only 38 of the 67 applied migrations. The database was the sole source of
truth for the remaining 29. This snapshot makes the deployed state reviewable
offline and gives `docs/PLATFORM_CHEATSHEET.md` rule 20 ("frozen migration files
SHA-verified byte-identical") something to verify against.

See `../migrations/RECONCILIATION.md` for the full audit.

## Refreshing

Re-extract with:

```sql
select name, encode(convert_to(statements[1],'UTF8'),'base64')
from supabase_migrations.schema_migrations order by version;
```

then base64-decode each row into `<name>.sql`. Verify with
`select md5(statements[1]), name from supabase_migrations.schema_migrations;`
against `md5 -q` locally.
