#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner="$root/probes/mle/teavm-engine/run-wan-matrix.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-wan-preflight.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

diagnostic="$(
  DOOMDB_WAN_LONG_POLL_ENABLED=0 \
  DOOMDB_WAN_HOLD_MS=0 \
  DOOMDB_WAN_PREFLIGHT_ONLY=YES \
    "$runner"
)"
grep -Fqx \
  'PMLE_WAN_PREFLIGHT|PASS|long_poll=OFF|hold_ms=0|transport_legs=2|classification=DIAGNOSTIC_NOT_GATE|duration=600|warmup=90|approval_sha256=NONE' \
  <<<"$diagnostic"

expect_rejected() {
  local expected=$1
  shift
  local output rc
  set +e
  output="$("$@" 2>&1)"
  rc=$?
  set -e
  [[ "$rc" -eq 2 ]]
  grep -Fqx "$expected" <<<"$output"
}

expect_rejected 'wait-free charter approval artifact is absent' \
  env DOOMDB_WAN_LONG_POLL_ENABLED=0 DOOMDB_WAN_HOLD_MS=0 \
    DOOMDB_WAN_QUALIFICATION=YES DOOMDB_WAN_PREFLIGHT_ONLY=YES \
    DOOMDB_WAN_APPROVAL_FILE="$tmp/absent.md" "$runner"

printf '%s\n' 'WAN_TRANSPORT_AMENDMENT|REJECTED' >"$tmp/wrong.md"
expect_rejected 'wait-free charter approval marker is absent' \
  env DOOMDB_WAN_LONG_POLL_ENABLED=0 DOOMDB_WAN_HOLD_MS=0 \
    DOOMDB_WAN_QUALIFICATION=YES DOOMDB_WAN_PREFLIGHT_ONLY=YES \
    DOOMDB_WAN_APPROVAL_FILE="$tmp/wrong.md" "$runner"

printf '%s\n' \
  'WAN_TRANSPORT_AMENDMENT|APPROVED|authority=Brian Martin|transport=WAIT_FREE_IMMEDIATE_BATCHING|transport_legs=2' \
  >"$tmp/approved.md"
expect_rejected 'qualification is authorized only for wait-free transport' \
  env DOOMDB_WAN_LONG_POLL_ENABLED=1 DOOMDB_WAN_HOLD_MS=500 \
    DOOMDB_WAN_QUALIFICATION=YES DOOMDB_WAN_PREFLIGHT_ONLY=YES \
    DOOMDB_WAN_APPROVAL_FILE="$tmp/approved.md" "$runner"
expect_rejected \
  'WAN qualification requires 600 scored seconds and 90 warmup seconds' \
  env DOOMDB_WAN_LONG_POLL_ENABLED=0 DOOMDB_WAN_HOLD_MS=0 \
    DOOMDB_WAN_QUALIFICATION=YES DOOMDB_WAN_PREFLIGHT_ONLY=YES \
    DOOMDB_MLE_WAN_SECONDS=599 \
    DOOMDB_WAN_APPROVAL_FILE="$tmp/approved.md" "$runner"
expect_rejected 'qualification may not filter WAN profiles' \
  env DOOMDB_WAN_LONG_POLL_ENABLED=0 DOOMDB_WAN_HOLD_MS=0 \
    DOOMDB_WAN_QUALIFICATION=YES DOOMDB_WAN_PREFLIGHT_ONLY=YES \
    DOOMDB_WAN_PROFILE_FILTER=rtt-200-jitter-40 \
    DOOMDB_WAN_APPROVAL_FILE="$tmp/approved.md" "$runner"

approval_sha="$(shasum -a 256 "$tmp/approved.md" | awk '{print $1}')"
qualification="$(
  DOOMDB_WAN_LONG_POLL_ENABLED=0 \
  DOOMDB_WAN_HOLD_MS=0 \
  DOOMDB_WAN_QUALIFICATION=YES \
  DOOMDB_WAN_PREFLIGHT_ONLY=YES \
  DOOMDB_WAN_APPROVAL_FILE="$tmp/approved.md" \
    "$runner"
)"
grep -Fqx \
  "PMLE_WAN_PREFLIGHT|PASS|long_poll=OFF|hold_ms=0|transport_legs=2|classification=QUALIFICATION|duration=600|warmup=90|approval_sha256=$approval_sha" \
  <<<"$qualification"

printf '%s\n' \
  'PASS PMLE-WAN-QUALIFICATION-PREFLIGHT (approval, topology, duration, and classification fail closed)'
