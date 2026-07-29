#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
loader="$root/probes/mle/teavm-engine/load-mle-module.sh"
source_file="${PMLE_DVL2_AUTHORITY_SOURCE:-$root/probes/mle/teavm-engine/target/javascript/doom-mle-presentation-engine-headless.js}"

[[ "${1:-}" == --emit-sql && "$#" == 1 ]] || {
  printf 'usage: %s --emit-sql\n' "$0" >&2
  exit 2
}
[[ -s "$source_file" && ! -L "$source_file" ]] || {
  printf 'DVL2 authority candidate is unavailable: %s\n' "$source_file" >&2
  exit 2
}
source_file="$(cd "$(dirname "$source_file")" && pwd)/$(basename "$source_file")"

# The standard loader is reused byte-for-byte, but every diagnostic object is
# namespaced so this measurement cannot replace the deployed authority.
"$loader" --javascript="$source_file" --emit-sql |
  sed 's/doom_teavm_/doom_dvl2_/g'
