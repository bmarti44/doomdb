#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$0")/.."

assertions=0
pass() {
  assertions=$((assertions + 1))
}
fail() {
  printf 'FAIL T1.1: %s\n' "$1" >&2
  exit 1
}
require_text() {
  local needle=$1 file=$2 label=$3
  grep -Fq -- "$needle" "$file" || fail "$label"
  pass
}
reject_text() {
  local needle=$1 file=$2 label=$3
  if grep -Fq -- "$needle" "$file"; then
    fail "$label"
  fi
  pass
}

tmp_dir=$(mktemp -d)
cleanup() {
  rm -rf "${tmp_dir}"
}
trap cleanup EXIT INT TERM

export DOOMDB_ORACLE_PASSWORD_FILE=./secrets/oracle_password.txt.example
export DOOMDB_APP_PASSWORD_FILE=./secrets/doom_password.txt.example
docker compose config > "${tmp_dir}/compose.config"

require_text 'gvenzl/oracle-free:23.26.2-full@sha256:df18ebc6b17107081b8bb8f1ee90e8018195dc9261e288100be99ef7bef268ff' "${tmp_dir}/compose.config" 'Oracle image is not pinned to the reviewed amd64 digest'
require_text 'container-registry.oracle.com/database/ords:26.2.0@sha256:ae9ae8cbbb0c00f25e9624e3b60ffb3838488ca1231d4c9ae4e0a2ab3f4b8930' "${tmp_dir}/compose.config" 'ORDS image is not pinned to the reviewed amd64 digest'
require_text 'cpuset: 0,1' "${tmp_dir}/compose.config" 'database is not pinned to exactly two CPUs'
require_text 'mem_limit: "4294967296"' "${tmp_dir}/compose.config" 'database memory limit is not exactly 4 GiB'
require_text '/opt/oracle/healthcheck.sh' "${tmp_dir}/compose.config" 'database health check is missing'
require_text 'condition: service_healthy' "${tmp_dir}/compose.config" 'ORDS is not health-gated on the database'
require_text 'DBSERVICENAME: FREEPDB1' "${tmp_dir}/compose.config" 'ORDS is not configured for FREEPDB1'
reject_text 'ORACLE_DATABASE:' "${tmp_dir}/compose.config" 'FREEPDB1 already exists and must not be recreated'
require_text '/run/secrets/oracle_password' "${tmp_dir}/compose.config" 'Oracle password is not supplied as a secret file'
require_text '/run/secrets/doom_password' "${tmp_dir}/compose.config" 'application password is not supplied as a secret file'
reject_text 'replace-with-a-local-sys-password' "${tmp_dir}/compose.config" 'Compose rendered a credential value'
reject_text 'replace-with-a-local-doom-schema-password' "${tmp_dir}/compose.config" 'Compose rendered an application credential value'
require_text 'target: /var/www/doomdb' "${tmp_dir}/compose.config" 'static document root is not mounted'
require_text 'read_only: true' "${tmp_dir}/compose.config" 'static document root and entrypoint mounts are not read-only'
require_text 'http://127.0.0.1:8080/health.txt' "${tmp_dir}/compose.config" 'ORDS/static health check is missing'

require_text 'sga_target=1024m' deploy/local/db-entrypoint.sh 'required SGA tuning is missing'
require_text 'pga_aggregate_target=256m' deploy/local/db-entrypoint.sh 'required PGA tuning is missing'
require_text "create spfile='%s' from pfile='/tmp/doomdb-init.ora'" deploy/local/db-entrypoint.sh 'SPFILE regeneration is missing'
require_text 'exec /opt/oracle/container-entrypoint.sh' deploy/local/db-entrypoint.sh 'database vendor entrypoint is not retained'
require_text 'IFS= read -r ORACLE_PWD' deploy/local/ords-entrypoint.sh 'ORDS does not read its secret from a file'
require_text 'ords uninstall' deploy/local/ords-entrypoint.sh 'fresh ORDS repository reconciliation is missing'
require_text '--password-stdin' deploy/local/ords-entrypoint.sh 'ORDS uninstall does not receive its credential through standard input'
require_text 'exec /usr/bin/docker-entrypoint.sh' deploy/local/ords-entrypoint.sh 'ORDS vendor entrypoint is not retained'
require_text 'standalone.doc.root /var/www/doomdb' deploy/local/ords-entrypoint.d/20-doomdb-static-root.sh 'ORDS static document root is not configured'
reject_text 'ORDS.DEFINE_MODULE' deploy/local/ords-entrypoint.d/20-doomdb-static-root.sh 'custom ORDS modules are forbidden'
require_text 'DOOMDB_ORDS_READY' client/dist/health.txt 'static health response is missing'
require_text '<h1>DoomDB</h1>' client/dist/index.html 'placeholder client is missing'

if [[ "${DOOMDB_T1_LIVE:-0}" != 1 ]]; then
  printf 'PASS T1.1-static (%d assertions); set DOOMDB_T1_LIVE=1 for fresh-volume acceptance\n' "${assertions}"
  exit 0
fi

live_dir="$(pwd)/secrets/.t1-live-$$"
mkdir -p "${live_dir}"
oracle_password='T1Live-Oracle-7f3d9a!'
doom_password='T1Live-Doom-8c4e2b!'
printf '%s\n' "${oracle_password}" > "${live_dir}/oracle.txt"
printf '%s\n' "${doom_password}" > "${live_dir}/doom.txt"
chmod 600 "${live_dir}/oracle.txt" "${live_dir}/doom.txt"

project="doomdb-t11-$$"
export DOOMDB_ORACLE_PASSWORD_FILE="${live_dir}/oracle.txt"
export DOOMDB_APP_PASSWORD_FILE="${live_dir}/doom.txt"
export DOOMDB_DB_PORT=${DOOMDB_T1_DB_PORT:-11521}
export DOOMDB_HTTP_PORT=${DOOMDB_T1_HTTP_PORT:-18080}

live_cleanup() {
  docker compose -p "${project}" down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -rf "${live_dir}"
  cleanup
}
trap live_cleanup EXIT INT TERM

docker compose -p "${project}" up --detach --wait --wait-timeout 1800

[[ "$(docker inspect "${project}-db-1" --format '{{.HostConfig.NanoCpus}}')" == 0 ]] || fail 'live database unexpectedly uses a CFS CPU quota'
pass
[[ "$(docker inspect "${project}-db-1" --format '{{.HostConfig.CpusetCpus}}')" == '0,1' ]] || fail 'live database CPU set differs from two CPUs'
pass
[[ "$(docker inspect "${project}-db-1" --format '{{.HostConfig.Memory}}')" == 4294967296 ]] || fail 'live database memory limit differs from 4 GiB'
pass

sql_result=$(docker compose -p "${project}" exec -T db bash -lc "printf \"set heading off feedback off pages 0\\nselect 'DOOMDB_SQL_READY' from dual;\\nexit\\n\" | sqlplus -s / as sysdba")
grep -Fq 'DOOMDB_SQL_READY' <<< "${sql_result}" || fail 'live SQL health query failed'
pass

static_body=$(/usr/bin/curl --fail --silent --show-error "http://127.0.0.1:${DOOMDB_HTTP_PORT}/health.txt")
[[ "${static_body}" == DOOMDB_ORDS_READY ]] || fail 'live static health endpoint returned unexpected content'
pass

page_body=$(/usr/bin/curl --fail --silent --show-error "http://127.0.0.1:${DOOMDB_HTTP_PORT}/")
grep -Fq '<h1>DoomDB</h1>' <<< "${page_body}" || fail 'live placeholder page failed'
pass

ords_status=$(/usr/bin/curl --silent --output /dev/null --write-out '%{http_code}' "http://127.0.0.1:${DOOMDB_HTTP_PORT}/ords/")
case "${ords_status}" in 200|302) pass ;; *) fail "live ORDS endpoint returned HTTP ${ords_status}" ;; esac

root_value=$(docker compose -p "${project}" exec -T ords ords config get standalone.doc.root | tail -1)
[[ "${root_value}" == /var/www/doomdb ]] || fail 'live ORDS document root differs from the mounted client'
pass

docker compose -p "${project}" logs --no-color > "${tmp_dir}/live.log"
inspect_args=$(docker inspect "${project}-db-1" "${project}-ords-1" --format '{{json .Config.Entrypoint}} {{json .Config.Cmd}}')
if grep -Fq "${oracle_password}" "${tmp_dir}/live.log" || grep -Fq "${doom_password}" "${tmp_dir}/live.log"; then
  fail 'credential appeared in container logs'
fi
pass
if grep -Fq "${oracle_password}" <<< "${inspect_args}" || grep -Fq "${doom_password}" <<< "${inspect_args}"; then
  fail 'credential appeared in process arguments'
fi
pass

printf 'PASS T1.1-live (%d assertions; fresh volumes)\n' "${assertions}"
