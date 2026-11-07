#!/usr/bin/env bash
# Each SQL suite runs on a freshly rebuilt, seeded scratch database.  WARNING: drops the schema in $DB.
set -uo pipefail
cd "$(dirname "$0")/.."
DB="${PGDATABASE:-butterfly_test}"; U="${PGUSER:-postgres}"; : "${PGPASSWORD:?Set PGPASSWORD}"
psql -X -t -A -U "$U" -d postgres -c "SELECT 1 FROM pg_database WHERE datname='$DB'" | grep -q 1 || psql -X -q -U "$U" -d postgres -c "CREATE DATABASE $DB"
pass=0; fail=0
for t in db/tests/*.sql; do
  for f in db/schema/drop_all.sql db/schema/_all.sql db/seed/_seed_all.sql; do psql -X -q -v ON_ERROR_STOP=1 -U "$U" -d "$DB" -f "$f" >/dev/null 2>&1; done
  if out=$(psql -X -v ON_ERROR_STOP=1 -U "$U" -d "$DB" -f "$t" 2>&1); then echo "PASS  $(basename "$t")"; pass=$((pass+1));
  else echo "FAIL  $(basename "$t")"; echo "$out" | tail -8 | sed 's/^/      /'; fail=$((fail+1)); fi
done
echo; echo "$pass passed, $fail failed."; [[ $fail -eq 0 ]]
