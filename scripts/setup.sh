#!/usr/bin/env bash
# One-command setup (Linux/macOS/WSL):  PGPASSWORD=... ./scripts/setup.sh [--reset]
set -euo pipefail
cd "$(dirname "$0")/.."
DB="${PGDATABASE:-butterfly}"; USER_="${PGUSER:-postgres}"; APPPW="${APP_PASSWORD:-change_me}"
: "${PGPASSWORD:?Set PGPASSWORD to your PostgreSQL password first}"
command -v psql >/dev/null || { echo "psql not found"; exit 1; }
P=(psql -X -q -v ON_ERROR_STOP=1 -U "$USER_")
if ! psql -X -t -A -U "$USER_" -d postgres -c "SELECT 1 FROM pg_database WHERE datname='$DB'" | grep -q 1; then
  echo "Creating database $DB ..."; "${P[@]}" -d postgres -c "CREATE DATABASE $DB"
elif [[ "${1:-}" == "--reset" ]]; then
  echo "Resetting $DB ..."; "${P[@]}" -d "$DB" -f db/schema/drop_all.sql >/dev/null
elif [[ "$(psql -X -t -A -U "$USER_" -d "$DB" -c "SELECT to_regclass('public.event') IS NOT NULL")" == "t" ]]; then
  echo "Schema already present. Use --reset to rebuild."; SKIP=1
fi
if [[ -z "${SKIP:-}" ]]; then
  echo "Applying schema ...";  "${P[@]}" -d "$DB" -f db/schema/_all.sql >/dev/null
  echo "Seeding Alderbrook ..."; "${P[@]}" -d "$DB" -f db/seed/_seed_all.sql >/dev/null
  "${P[@]}" -d "$DB" -c "ALTER ROLE butterfly_app PASSWORD '$APPPW'" -c "ALTER ROLE butterfly_gm PASSWORD '$APPPW'"
fi
if [[ ! -f backend/.env ]]; then
  SECRET="$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  sed -e "s|PG_APP_PASSWORD=.*|PG_APP_PASSWORD=$APPPW|" -e "s|PG_GM_PASSWORD=.*|PG_GM_PASSWORD=$APPPW|" -e "s|SESSION_SECRET=.*|SESSION_SECRET=$SECRET|" backend/.env.example > backend/.env
  echo "Wrote backend/.env"
fi
(cd backend && npm install --no-audit --no-fund)
echo; echo "Done.  cd backend && npm start   ->  http://localhost:4000   (or: npm run mock -> :4100, no database)"
