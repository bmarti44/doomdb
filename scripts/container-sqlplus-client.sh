#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
wallet="${DOOMDB_CONTAINER_ADB_WALLET:-/tmp/adb_wallet}"

docker compose -f "$root/compose.yaml" exec -T \
  -e "TNS_ADMIN=$wallet" db sqlplus "$@"
