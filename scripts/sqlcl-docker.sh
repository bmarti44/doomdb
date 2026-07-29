#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sqlcl_home="${DOOMDB_SQLCL_HOME:-$HOME/.doomdb-tools/sqlcl-26.2}"
image="${DOOMDB_SQLCL_JAVA_IMAGE:-maven:3.9.11-eclipse-temurin-17}"
sql="$sqlcl_home/sqlcl/bin/sql"

[[ -x "$sql" && ! -L "$sql" ]] || {
  printf 'SQLcl distribution is unavailable: %s\n' "$sql" >&2
  exit 2
}

docker_args=(
  run --rm -i
  -v "$root:$root"
  -v "$sqlcl_home:$sqlcl_home:ro"
  -w "$PWD"
)
if [[ -n "${TNS_ADMIN:-}" ]]; then
  [[ -d "$TNS_ADMIN" && ! -L "$TNS_ADMIN" ]] || {
    printf 'TNS_ADMIN is not a real directory: %s\n' "$TNS_ADMIN" >&2
    exit 2
  }
  docker_args+=(-v "$TNS_ADMIN:$TNS_ADMIN:ro" -e "TNS_ADMIN=$TNS_ADMIN")
fi

exec docker "${docker_args[@]}" "$image" "$sql" "$@"
