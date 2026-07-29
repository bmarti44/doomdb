#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
stamp=$(date -u +%Y-%m-%dT%H%M%SZ)
output=${1:-"$root/artifacts/performance/pmle-live-frame-authority/local-session-cleanup-$stamp.log"}

[[ ! -e "$output" ]] ||
  { printf 'refusing to overwrite session-cleanup evidence: %s\n' "$output" >&2; exit 2; }
mkdir -p "$(dirname "$output")"
umask 077

"$root/scripts/db_sql.sh" "$root/tests/verify-session-cleanup-live.sql" \
  2>&1 | tee "$output"
grep -q '^PASS SESSION-CLEANUP-LIVE abandoned browser lobby releases capacity$' \
  "$output"
grep -q '^PASS SESSION-CLEANUP-LIVE abandoned active browser releases retained slot$' \
  "$output"
grep -q '^PASS SESSION-CLEANUP-LIVE expired match cascade purged off request path$' \
  "$output"
printf 'PASS SESSION-CLEANUP-LIVE-EVIDENCE log=%s\n' "${output#"$root/"}"
