#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
image="${DOOMDB_SQLCL_IMAGE:-eclipse-temurin:17-jdk}"
# Docker Desktop's daemon cannot bind the host's /tmp namespace reliably.
# Keep the verifier's externally scoped ADB_WALLET_DIR unchanged, while this
# explicit ignored-path override supplies the same wallet to the client JVM.
wallet="${DOOMDB_SQLCL_DOCKER_WALLET:-${DOOMDB_SQLCL_WALLET:-${ADB_WALLET_DIR:-/tmp/adb_wallet}}}"
sqlcl="$root/.artifacts/sqlcl-26.2/sqlcl"

[[ -d "$sqlcl" && ! -L "$sqlcl" ]] || {
  printf 'Pinned SQLcl directory is unavailable\n' >&2; exit 2; }
[[ -d "$wallet" && ! -L "$wallet" ]] || {
  printf 'SQLcl wallet directory is unavailable\n' >&2; exit 2; }
docker image inspect "$image" >/dev/null 2>&1 || {
  printf 'Pinned Java client image is unavailable: %s\n' "$image" >&2
  exit 2
}

# SQLcl is deliberately isolated from the Oracle database container. Running
# both JVMs inside doomdb-db-1 lets the client compete with SGA/PGA and can
# OOM-kill SQLcl while streaming the production seed manifest.
exec docker run --rm -i \
  --memory 1536m --memory-swap 1536m --cpus 1 \
  --read-only --tmpfs /tmp:rw,nosuid,size=512m \
  -e HOME=/tmp -e TNS_ADMIN=/wallet \
  -v "$sqlcl:/opt/sqlcl:ro" -v "$wallet:/wallet:ro" \
  "$image" /opt/sqlcl/bin/sql "$@"
