#!/usr/bin/env bash
# Runs once on first start of the postgres container.
set -euo pipefail
cd /sql
psql -v ON_ERROR_STOP=1 -U postgres -d butterfly -f schema/_all.sql
psql -v ON_ERROR_STOP=1 -U postgres -d butterfly -f seed/_seed_all.sql
psql -v ON_ERROR_STOP=1 -U postgres -d butterfly -f seed/_seed_story.sql
psql -v ON_ERROR_STOP=1 -U postgres -d butterfly -c "ALTER ROLE butterfly_app PASSWORD 'change_me'" -c "ALTER ROLE butterfly_gm PASSWORD 'change_me'"
