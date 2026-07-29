#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
stamp=$(date -u +%Y-%m-%dT%H%M%SZ)
output=${1:-"$root/artifacts/performance/pmle-live-frame-authority/local-pixel-recovery-$stamp.log"}

[[ ! -e "$output" ]] || {
  printf 'refusing to overwrite pixel-recovery evidence: %s\n' "$output" >&2
  exit 2
}
mkdir -p "$(dirname "$output")"
umask 077

DOOMDB_LIVE_FRAME_RECOVERY=YES \
DOOMDB_LIVE_FRAME_TIMEOUT_MS="${DOOMDB_LIVE_FRAME_TIMEOUT_MS:-180000}" \
  node "$root/tests/verify-mle-live-frame-e2e.mjs" 2>&1 |
  tee "$output"

grep -Eq \
  '^PMLE_LIVE_FRAME_E2E[|]PASS[|].*[|]pixel_recovery=GENERATION_[0-9]+[|]' \
  "$output"
printf 'PMLE_LIVE_FRAME_RECOVERY_EVIDENCE|PASS|log=%s\n' \
  "$(basename "$output")"
