#!/usr/bin/env bash
# Usage: PGPASSWORD=... ./experiments/partitioning/run_experiment8.sh [events]
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p experiments/results
psql -X -U "${PGUSER:-postgres}" -d "${PGDATABASE:-butterfly}" -v n="${1:-400000}" \
  -v out=experiments/results/exp8_partitioning.csv -f experiments/partitioning/exp8_partitioning.sql
