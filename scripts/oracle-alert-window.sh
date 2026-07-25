#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
alert='/opt/oracle/diag/rdbms/free/FREE/trace/alert_FREE.log'
command="${1:-}"
state="${2:-}"
label="${3:-UNNAMED}"

usage() {
  printf 'usage: %s begin|end STATE_FILE [LABEL]\n' "$0" >&2
  exit 2
}

[[ -n "$state" ]] || usage

alert_bytes() {
  docker compose -f "$root/compose.yaml" exec -T db sh -c \
    'test -r "$1" && wc -c <"$1"' _ "$alert" | tr -d '[:space:]'
}

case "$command" in
  begin)
    bytes="$(alert_bytes)"
    [[ "$bytes" =~ ^[0-9]+$ ]] || {
      printf 'unable to snapshot Oracle alert log\n' >&2
      exit 1
    }
    printf 'offset=%s\nstarted_utc=%s\n' "$bytes" \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >"$state"
    printf 'PMLE_ALERT_WINDOW|BEGIN|label=%s|offset=%s\n' "$label" "$bytes"
    ;;
  end)
    # shellcheck disable=SC1090
    source "$state"
    [[ "${offset:-}" =~ ^[0-9]+$ ]] || {
      printf 'invalid Oracle alert-window state: %s\n' "$state" >&2
      exit 1
    }
    current="$(alert_bytes)"
    [[ "$current" =~ ^[0-9]+$ && "$current" -ge "$offset" ]] || {
      printf 'PMLE_ALERT_WINDOW|FAIL|label=%s|reason=rotation_or_truncation\n' "$label" >&2
      exit 1
    }
    delta="$(docker compose -f "$root/compose.yaml" exec -T db sh -c \
      'tail -c +"$1" "$2"' _ "$((offset + 1))" "$alert")"
    # ORA-00000 is Oracle's explicit successful-completion code and appears in
    # normal ALTER SYSTEM KILL SESSION audit records as "Result = ORA-00000".
    # Every nonzero ORA code remains a blocking incident.
    expected_code="${DOOMDB_ALERT_EXPECT_CODE:-}"
    expected_count=0
    if [[ -n "$expected_code" ]]; then
      [[ "$expected_code" =~ ^ORA-[0-9]{5}$ && "$expected_code" != ORA-00000 ]] || {
        printf 'PMLE_ALERT_WINDOW|FAIL|label=%s|reason=invalid_expected_code\n' \
          "$label" >&2
        exit 1
      }
      expected_count="$(printf '%s\n' "$delta" |
        grep -Eo "$expected_code" | wc -l | tr -d '[:space:]')"
      [[ "$expected_count" == 1 ]] || {
        printf 'PMLE_ALERT_WINDOW|FAIL|label=%s|expected_code=%s|expected_count=%s\n' \
          "$label" "$expected_code" "$expected_count" >&2
        exit 1
      }
    fi
    incidents="$(printf '%s\n' "$delta" |
      grep -E 'ORA-[0-9]{5}' | grep -v 'ORA-00000' |
      { if [[ -n "$expected_code" ]]; then grep -v "$expected_code"; else cat; fi; } ||
      true)"
    if [[ -n "$incidents" ]]; then
      printf 'PMLE_ALERT_WINDOW|FAIL|label=%s|new_ora_incidents=1\n%s\n' \
        "$label" "$incidents" >&2
      exit 1
    fi
    printf 'PMLE_ALERT_WINDOW|PASS|label=%s|new_ora_incidents=0|bytes=%s|expected_code=%s|expected_count=%s\n' \
      "$label" "$((current - offset))" "${expected_code:-NONE}" "$expected_count"
    ;;
  *)
    usage
    ;;
esac
