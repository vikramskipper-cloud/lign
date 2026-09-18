-- Produces the manifest consumed by ops/verify_migrations.sh.
--
-- One row per applied migration: "<md5 of the applied SQL> <migration name>",
-- ordered by apply version. Every migration in this project is recorded as a
-- single statement, so statements[1] is the whole migration body.
--
--   psql "$SUPABASE_DB_URL" -At -f ops/migration_manifest.sql > /tmp/manifest
--   ops/verify_migrations.sh /tmp/manifest
--
-- Target project: hsfporioghapwghrvvzd (Lign). Never nuesync.

select md5(statements[1]) || ' ' || name
from supabase_migrations.schema_migrations
order by version;
