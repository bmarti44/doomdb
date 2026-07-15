#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
compose_file="$root/deploy/local/t10.3/compose.yaml"
fixtures="$root/evaluator/t10.3/fixtures.json"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-t103.XXXXXXXX")"
chmod 700 "$tmp"
project=''
evaluator_container=''
started_at=$SECONDS
whole_gate_seconds=14400
bootstrap_seconds=1800
shutdown_seconds=180

cleanup_project() {
  if [[ -n "$evaluator_container" ]]; then
    docker rm -f "$evaluator_container" >/dev/null 2>&1 || :
    evaluator_container=''
  fi
  if [[ -n "$project" ]]; then
    bounded "$shutdown_seconds" docker compose -f "$compose_file" -p "$project" down --volumes --remove-orphans >/dev/null
    if docker ps -a --filter "label=com.docker.compose.project=$project" --format '{{.ID}}' | grep -q .; then
      printf 'project containers survived cleanup\n' >&2
      return 1
    fi
    if docker volume ls --filter "label=com.docker.compose.project=$project" --format '{{.Name}}' | grep -q .; then
      printf 'project volumes survived cleanup\n' >&2
      return 1
    fi
    project=''
  fi
}

cleanup_all() {
  status=$?
  trap - EXIT INT TERM HUP
  cleanup_project || status=1
  rm -rf "$tmp"
  exit "$status"
}
trap cleanup_all EXIT INT TERM HUP

# Portable timeout: every operation is also clipped to the remaining whole-gate budget.
bounded() {
  local requested=$1 remaining
  shift
  remaining=$((whole_gate_seconds - (SECONDS - started_at)))
  (( remaining > 0 )) || { printf 'whole-gate timeout exhausted\n' >&2; return 124; }
  (( requested < remaining )) || requested=$remaining
  perl -e '$seconds=shift; $SIG{ALRM}=sub{kill q(TERM),$pid if $pid; die qq(timeout\n)}; $pid=fork(); die qq(fork failed\n) unless defined $pid; if(!$pid){exec @ARGV or die qq(exec failed\n)} alarm $seconds; waitpid $pid,0; alarm 0; exit(($? >> 8) || ($? & 127 ? 128+($? & 127) : 0))' "$requested" "$@"
}

new_password() {
  local destination=$1 value
  value="T103_$(openssl rand -hex 24)"
  (umask 077; printf '%s' "$value" > "$destination")
  chmod 600 "$destination"
}

assert_fresh_project() {
  local candidate=$1
  [[ "$candidate" =~ ^doomdb-t103-[0-9a-f]{24}$ ]] || return 1
  ! docker ps -a --filter "label=com.docker.compose.project=$candidate" --format '{{.ID}}' | grep -q .
  ! docker volume ls --filter "label=com.docker.compose.project=$candidate" --format '{{.Name}}' | grep -q .
  ! docker network ls --filter "label=com.docker.compose.project=$candidate" --format '{{.Name}}' | grep -q .
}

secret_clean() {
  local log=$1 oracle_file=$2 app_file=$3
  ! grep -F -f "$oracle_file" "$log" >/dev/null
  ! grep -F -f "$app_file" "$log" >/dev/null
}

run_once() {
  local ordinal=$1 run_hex run_dir oracle_file app_file db_id log_file record_file inspect_output exit_code
  run_hex="$(openssl rand -hex 12)"
  project="doomdb-t103-$run_hex"
  assert_fresh_project "$project"
  run_dir="$tmp/run-$ordinal"
  mkdir -m 700 "$run_dir"
  oracle_file="$run_dir/oracle_password"
  app_file="$run_dir/doom_password"
  new_password "$oracle_file"
  new_password "$app_file"
  export DOOMDB_ORACLE_PASSWORD_FILE="$oracle_file"
  export DOOMDB_APP_PASSWORD_FILE="$app_file"
  export T103_RUN_ID="$project"
  export T103_EVIDENCE_DIR="$tmp"
  export T103_INFRASTRUCTURE_JSON='{"services":["db:healthy","ords:healthy","evaluator:exited-0"],"nanoCpus":2000000000,"memoryBytes":2147483648,"evaluatorSandbox":true,"timeoutsEnforced":true,"credentialsClean":true,"startedFromNoResources":true,"volumesRemoved":true}'

  bounded "$bootstrap_seconds" docker compose -f "$compose_file" -p "$project" build evaluator
  bounded "$bootstrap_seconds" docker compose -f "$compose_file" -p "$project" up --detach --wait --wait-timeout "$bootstrap_seconds" db ords
  db_id="$(docker compose -f "$compose_file" -p "$project" ps -q db)"
  [[ -n "$db_id" ]] || { printf 'database container missing\n' >&2; return 1; }

  evaluator_container="$project-evaluator-run"
  bounded 60 docker compose -f "$compose_file" -p "$project" run --detach --name "$evaluator_container" evaluator >/dev/null
  inspect_output="$run_dir/inspect.txt"
  # The inspector fails closed on HostConfig.NanoCpus, HostConfig.Memory,
  # ReadonlyRootfs/read_only, CapDrop, no-new-privileges, mounts and namespaces.
  docker inspect "$db_id" "$evaluator_container" | node "$root/scripts/t10.3-inspect.mjs" | tee "$inspect_output"

  exit_code="$(bounded "$whole_gate_seconds" docker wait "$evaluator_container")"
  [[ "$exit_code" == 0 ]] || { docker logs "$evaluator_container" >&2; printf 'evaluator exited %s\n' "$exit_code" >&2; return 1; }
  log_file="$run_dir/evaluator.log"
  docker logs "$evaluator_container" > "$log_file" 2>&1
  secret_clean "$log_file" "$oracle_file" "$app_file"
  record_file="$tmp/run-$ordinal.json"
  node "$root/scripts/t10.3-extract-record.mjs" "$log_file" "$record_file"

  docker rm "$evaluator_container" >/dev/null
  evaluator_container=''
  cleanup_project
  rm -f "$oracle_file" "$app_file"
  [[ ! -e "$oracle_file" && ! -e "$app_file" ]] || { printf 'ephemeral file cleanup failed\n' >&2; return 1; }
  printf 'PASS T10.3-FRESH-RUN-%d (24/24 visible suite families)\n' "$ordinal"
}

[[ -f "$fixtures" && -f "$compose_file" ]] || { printf 'T10.3 evaluator assets missing\n' >&2; exit 1; }
for run in 1 2; do
  run_once "$run"
done

compare_hex="$(openssl rand -hex 12)"
project="doomdb-t103-$compare_hex"
assert_fresh_project "$project"
export T103_RUN_ID="$project"
export T103_EVIDENCE_DIR="$tmp"
new_password "$tmp/compare-oracle"
new_password "$tmp/compare-app"
export DOOMDB_ORACLE_PASSWORD_FILE="$tmp/compare-oracle"
export DOOMDB_APP_PASSWORD_FILE="$tmp/compare-app"
export T103_INFRASTRUCTURE_JSON='{"services":["db:healthy","ords:healthy","evaluator:exited-0"],"nanoCpus":2000000000,"memoryBytes":2147483648,"evaluatorSandbox":true,"timeoutsEnforced":true,"credentialsClean":true,"startedFromNoResources":true,"volumesRemoved":true}'
bounded 1800 docker compose -f "$compose_file" -p "$project" run --rm --no-deps evaluator evaluator/t10.3/run-container.mjs compare /evidence/run-1.json /evidence/run-2.json
cleanup_project
rm -f "$tmp/compare-oracle" "$tmp/compare-app"
printf 'PASS T10.3-LOCAL-E2E (2/2 independent fresh-volume runs)\n'
