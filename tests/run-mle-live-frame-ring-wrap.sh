#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
stamp=$(date -u +%Y-%m-%dT%H%M%SZ)
output=${1:-"$root/artifacts/performance/pmle-live-frame-authority/local-ring-wrap-$stamp.log"}

[[ ! -e "$output" ]] ||
  { printf 'refusing to overwrite live-frame ring-wrap evidence\n' >&2; exit 2; }
mkdir -p "$(dirname "$output")"
umask 077

DOOMDB_LIVE_FRAME_RING_WRAP=YES \
DOOMDB_LIVE_FRAME_TIMEOUT_MS="${DOOMDB_LIVE_FRAME_TIMEOUT_MS:-300000}" \
  node "$root/tests/verify-mle-live-frame-e2e.mjs" 2>&1 |
  tee "$output"

grep -q '^PMLE_LIVE_FRAME_E2E|PASS|.*|ring_wrap=RESET_GAP|' "$output"
printf 'PMLE_LIVE_FRAME_RING_WRAP_EVIDENCE|PASS|log=%s\n' \
  "$(basename "$output")"
