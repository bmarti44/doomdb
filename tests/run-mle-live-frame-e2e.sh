#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
stamp=$(date -u +%Y-%m-%dT%H%M%SZ)
output=${1:-"$root/artifacts/performance/pmle-live-frame-authority/local-e2e-$stamp.log"}

if [[ -e "$output" ]]; then
  printf 'refusing to overwrite live-frame evidence: %s\n' "$output" >&2
  exit 2
fi
mkdir -p "$(dirname "$output")"
umask 077
node "$root/tests/verify-mle-live-frame-e2e.mjs" 2>&1 | tee "$output"
grep -q '^PMLE_LIVE_FRAME_E2E|PASS|' "$output"
printf 'PMLE_LIVE_FRAME_E2E_EVIDENCE|PASS|log=%s\n' \
  "${output#"$root/"}"
