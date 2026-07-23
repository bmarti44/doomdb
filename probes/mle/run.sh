#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
OUTPUT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/doomdb-pmle.XXXXXX")
installed_mle=false
installed_native=false
installed_hybrid=false
installed_bind=false

cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  if [ "$installed_hybrid" = true ]; then
    "$ROOT/scripts/db_sql.sh" "$ROOT/probes/mle/hybrid-cleanup.sql" >/dev/null || status=1
  fi
  if [ "$installed_bind" = true ]; then
    "$ROOT/scripts/db_sql.sh" "$ROOT/probes/mle/bind-cleanup.sql" >/dev/null || status=1
  fi
  if [ "$installed_native" = true ]; then
    "$ROOT/scripts/db_sql.sh" "$ROOT/probes/mle/native-cleanup.sql" >/dev/null || status=1
  fi
  if [ "$installed_mle" = true ]; then
    "$ROOT/scripts/db_sql.sh" "$ROOT/probes/mle/cleanup.sql" >/dev/null || status=1
  fi
  rm -rf "$OUTPUT_DIR"
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

run_sql() {
  label=$1
  file=$2
  output=$OUTPUT_DIR/$label.log
  printf 'PMLE: running %s...\n' "$label"
  if "$ROOT/scripts/db_sql.sh" "$file" >"$output" 2>&1; then
    result=0
  else
    result=$?
  fi
  cat "$output"
  if [ "$result" -ne 0 ]; then
    printf 'PMLE %s SQL failed with status %s\n' "$label" "$result" >&2
    exit "$result"
  fi
}

"$ROOT/scripts/db_sql.sh" "$ROOT/probes/mle/install.sql" >/dev/null
installed_mle=true
"$ROOT/scripts/db_sql.sh" "$ROOT/probes/mle/native-install.sql" >/dev/null
installed_native=true
"$ROOT/scripts/db_sql.sh" "$ROOT/probes/mle/hybrid-install.sql" >/dev/null
installed_hybrid=true
"$ROOT/scripts/db_sql.sh" "$ROOT/probes/mle/bind-install.sql" >/dev/null
installed_bind=true

run_sql pure-mle "$ROOT/probes/mle/benchmark.sql"
run_sql native-plsql "$ROOT/probes/mle/native-benchmark.sql"
run_sql ffi-frame-return "$ROOT/probes/mle/hybrid-benchmark.sql"
run_sql command-boundary "$ROOT/probes/mle/command-benchmark.sql"
run_sql non-pure-bind "$ROOT/probes/mle/bind-benchmark.sql"

PURE=$OUTPUT_DIR/pure-mle.log
NATIVE=$OUTPUT_DIR/native-plsql.log
FFI=$OUTPUT_DIR/ffi-frame-return.log
COMMAND=$OUTPUT_DIR/command-boundary.log
BIND=$OUTPUT_DIR/non-pure-bind.log

grep -q '^PMLE_VERSION|Oracle AI Database 26ai' "$PURE"
grep -q '^PMLE_CAPABILITY|.*"webAssembly":"undefined"' "$PURE"
grep -q '^PMLE_STATE|counter=1,2$' "$PURE"
grep -q '^PMLE_GATE|FAIL_FAST|reason=optimized_dynamic_columns_over_budget' "$PURE"
grep -q '^PMLE_NATIVE|translated_columns|' "$NATIVE"
grep -q '^PMLE_NATIVE|gathered_columns|' "$NATIVE"
grep -q '^PMLE_NATIVE|hex_block_columns|' "$NATIVE"
grep -q '^PMLE_NATIVE|buffered_frame|' "$NATIVE"
grep -q '^PMLE_HYBRID|ffi_translated_columns|' "$FFI"
grep -q '^PMLE_COMMAND_GATE|PASS|' "$COMMAND"
grep -q '^PMLE_BIND|non_pure_session_execute_blob|bytes=64000' "$BIND"

printf '%s\n' 'PMLE_GATE|PASS|scope=mechanics_only|architecture=mle_command_stream_plus_native_plsql_compositor'
printf '%s\n' 'PASS PMLE (26ai mechanics only; production-shaped renderer is rejected)'
