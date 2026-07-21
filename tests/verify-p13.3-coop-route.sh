#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node "$root/scripts/mochadoom/build-p13-coop-route-gate.mjs" \
  --canonical --kill-at=400 |
  "$root/scripts/db_sql.sh" -
