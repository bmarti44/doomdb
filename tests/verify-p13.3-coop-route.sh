#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node "$root/scripts/mochadoom/build-p13-coop-route-gate.mjs" \
  --route="$root/artifacts/t8.1-live/mocha-e1m1-no-cheat-route.json" \
  --guest-strafe=700-707 --side-adjust=78-90:1 \
  --forward-adjust=78-82:-1 |
  "$root/scripts/db_sql.sh" -
