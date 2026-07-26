#!/usr/bin/env bash
set -Eeuo pipefail

container="${DOOMDB_SQLCL_CONTAINER:-doomdb-db-1}"
sqlcl="${DOOMDB_SQLCL_PATH:-/tmp/sqlcl26/bin/sql}"
wallet="${DOOMDB_SQLCL_WALLET:-/tmp/adb_wallet}"

docker inspect "$container" >/dev/null 2>&1 || {
  printf 'SQLcl container is unavailable: %s\n' "$container" >&2;exit 2; }
docker exec -i -e "TNS_ADMIN=$wallet" "$container" "$sqlcl" "$@"
