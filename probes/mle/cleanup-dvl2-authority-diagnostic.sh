#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cleanup="$root/probes/mle/teavm-engine/cleanup-mle.sql"

[[ "${1:-}" == --emit-sql && "$#" == 1 ]] || {
  printf 'usage: %s --emit-sql\n' "$0" >&2
  exit 2
}

sed 's/doom_teavm_/doom_dvl2_/g' "$cleanup"
