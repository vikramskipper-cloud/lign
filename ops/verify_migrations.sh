#!/usr/bin/env bash
#
# Verifies PLATFORM_CHEATSHEET.md rule 20 — "frozen migration files SHA-verified
# byte-identical" — against the live database.
#
# Since 2026-09-18 every file in supabase/migrations/ is byte-identical to the
# SQL statement actually applied to project hsfporioghapwghrvvzd. This script
# proves that is still true.
#
# Usage:
#   ops/verify_migrations.sh <manifest-file>
#   psql "$SUPABASE_DB_URL" -At -f ops/migration_manifest.sql | ops/verify_migrations.sh -
#
# The manifest is two whitespace-separated columns, "<md5> <migration_name>",
# one per applied migration. Produce it with ops/migration_manifest.sql, or via
# the Supabase MCP server:
#
#   select md5(statements[1]) || ' ' || name
#   from supabase_migrations.schema_migrations order by version;
#
# Exit codes: 0 all verified · 1 drift detected · 2 usage or environment error.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIG_DIR="$REPO_ROOT/supabase/migrations"

if [ $# -ne 1 ]; then
  sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
fi

[ -d "$MIG_DIR" ] || { echo "error: $MIG_DIR not found" >&2; exit 2; }

if command -v md5 >/dev/null 2>&1; then           # macOS
  md5_of() { md5 -q "$1"; }
elif command -v md5sum >/dev/null 2>&1; then      # Linux
  md5_of() { md5sum "$1" | cut -d' ' -f1; }
else
  echo "error: neither md5 nor md5sum available" >&2; exit 2
fi

ok=0; drift=0; missing=0; applied=0
declare -a seen=()

while read -r want name; do
  [ -z "${name:-}" ] && continue
  applied=$((applied + 1))
  seen+=("$name")
  file=$(find "$MIG_DIR" -maxdepth 1 -name "*_${name}.sql" | head -1)
  if [ -z "$file" ]; then
    printf 'MISSING   %s  (applied to the database, no local file)\n' "$name"
    missing=$((missing + 1)); continue
  fi
  got=$(md5_of "$file")
  if [ "$want" = "$got" ]; then
    ok=$((ok + 1))
  else
    printf 'DRIFT     %-50s local=%.8s applied=%.8s\n' "$name" "$got" "$want"
    drift=$((drift + 1))
  fi
done < <(if [ "$1" = "-" ]; then cat; else cat "$1"; fi)

# Local files with no corresponding applied migration.
extra=0
while IFS= read -r file; do
  base=$(basename "$file" .sql); name=${base#*_}
  found=0
  for s in ${seen+"${seen[@]}"}; do [ "$s" = "$name" ] && { found=1; break; }; done
  if [ "$found" -eq 0 ]; then
    printf 'UNAPPLIED %s  (local file never applied to the database)\n' "$name"
    extra=$((extra + 1))
  fi
done < <(find "$MIG_DIR" -maxdepth 1 -name '*.sql' | sort)

echo "---"
printf 'applied migrations: %s\n' "$applied"
printf 'byte-identical:     %s\n' "$ok"
printf 'drifted:            %s\n' "$drift"
printf 'missing locally:    %s\n' "$missing"
printf 'unapplied locally:  %s\n' "$extra"

if [ "$drift" -eq 0 ] && [ "$missing" -eq 0 ] && [ "$extra" -eq 0 ]; then
  echo "RESULT: PASS — supabase/migrations/ matches the deployed database exactly."
  exit 0
fi
echo "RESULT: FAIL — see supabase/migrations/RECONCILIATION.md"
exit 1
