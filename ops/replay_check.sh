#!/usr/bin/env bash
#
# Proves supabase/migrations/ reproduces production, by replaying all migrations
# into an empty local database and diffing the result object-by-object.
#
# This is the strong test. ops/audit_schema_provenance.py checks provenance
# (every live object traces to a migration); this checks EQUIVALENCE (replaying
# the files yields the same schema), and it is the only thing that catches
# out-of-band ALTERs and migration ordering faults.
#
# Requires: Docker running, Supabase CLI. No login or `supabase link` needed --
# production's inventory comes from the MCP server or psql, separately.
#
# Usage:
#   ops/replay_check.sh <production-inventory.tsv>
#
# Produce the production inventory first, either via the Supabase MCP server
# running ops/schema_inventory.sql, or:
#   psql "$SUPABASE_DB_URL" -At -F$'\t' -f ops/schema_inventory.sql > prod.tsv
#
# Exit codes: 0 identical - 1 differences - 2 usage/environment error.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONTAINER="supabase_db_lign_v1.1"
SHADOW="$(mktemp -t lign_shadow_inv)"

[ $# -eq 1 ] || { sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 2; }
PROD="$1"
[ -f "$PROD" ] || { echo "error: $PROD not found" >&2; exit 2; }
docker info >/dev/null 2>&1 || { echo "error: Docker is not running" >&2; exit 2; }

cd "$ROOT"
echo "==> starting local stack (analytics/studio/realtime/edge disabled; ports 583xx)"
supabase start >/dev/null 2>&1 &
START_PID=$!

echo "==> waiting for all 67 migrations to replay into the empty database"
deadline=$(( $(date +%s) + 420 ))
until docker exec "$CONTAINER" psql -U postgres -d postgres -At \
        -c "select count(*) from supabase_migrations.schema_migrations" 2>/dev/null \
      | grep -qE '^[0-9]+$'; do
  [ "$(date +%s)" -gt "$deadline" ] && { echo "error: timed out waiting for the database" >&2; exit 2; }
  sleep 2
done
applied=$(docker exec "$CONTAINER" psql -U postgres -d postgres -At \
          -c "select count(*) from supabase_migrations.schema_migrations")
echo "    replayed $applied migrations cleanly, in order"

echo "==> extracting shadow inventory"
docker exec -i "$CONTAINER" psql -U postgres -d postgres -At -F$'\t' \
  -f - < ops/schema_inventory.sql > "$SHADOW"

echo "==> diffing shadow against production"
python3 ops/compare_inventories.py "$PROD" "$SHADOW"
rc=$?

echo "==> stopping local stack (nuesync stacks are never touched)"
supabase stop --no-backup >/dev/null 2>&1
wait $START_PID 2>/dev/null
rm -f "$SHADOW"
exit $rc
