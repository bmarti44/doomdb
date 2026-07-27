#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
probe="$root/probes/mle"
source_file="$probe/free-raster-teavm/src/main/java/doomdb/mle/raster/FreeRasterKernel.java"
install="$probe/install-free-raster-teavm.sh"
runner="$probe/run-oci-free-raster-teavm.sh"
benchmark="$probe/benchmark-oci-free-raster-teavm.sql"

for input in "$source_file" "$install" "$runner" "$benchmark" \
  "$probe/build-free-raster-teavm.sh" "$probe/cleanup-free-raster-teavm.sql"; do
  [[ -s "$input" && ! -L "$input" ]] || {
    printf 'free-raster verifier: missing input %s\n' "$input" >&2
    exit 1
  }
done

bash -n \
  "$probe/build-free-raster-teavm.sh" \
  "$install" \
  "$runner"

require() {
  local pattern="$1" file="$2"
  grep -Fq -- "$pattern" "$file" || {
    printf 'free-raster verifier: missing %s in %s\n' "$pattern" "$file" >&2
    exit 1
  }
}

# Pin the selected exact bulk-reset/column-major shape.  Reintroducing the
# per-frame background loop or row-major source multiply invalidates the OCI
# rank even if a broad output checksum still happens to match.
require 'System.arraycopy(backgroundFrame, 0, frame, 0, PIXELS);' "$source_file"
require 'transposeReferencedColumns();' "$source_file"
require 'frame[output + pixel] = atlas[sourceBase + sourceY];' "$source_file"
if grep -Fq 'atlas[sourceBase + sourceY * width]' "$source_file"; then
  printf 'free-raster verifier: stale row-major hot path\n' >&2
  exit 1
fi

# Artifact loads are fail-closed in the database, and folded base64 must keep
# its final unterminated line.
require "dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256)" "$install"
require 'while IFS= read -r piece || [[ -n "$piece" ]]; do' "$install"
require "raise_application_error(-20796,'small raster staging mismatch')" "$install"

# Evidence is immutable, exact frames are compared before timing, and cleanup
# proves both diagnostic objects and the pinned authority were restored.
require '[[ ! -e "$output" ]]' "$runner"
require 'PMLE_FREE_RASTER_EQUIVALENCE|PASS|' "$runner"
require '[[ "$(grep -c '\''^PMLE_FREE_RASTER_EQUIVALENCE|PASS|'\'' "$rank_log")" == 3 ]]' "$runner"
require "l_sha<>'5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'" "$runner"
require 'PMLE_FREE_RASTER_POSTFLIGHT|PASS|diagnostic_objects=0' "$runner"
require 'utl_raw.compare(l_reference,l_candidate)<>0' "$benchmark"
require 'c_frames constant pls_integer:=500' "$benchmark"
require 'c_passes constant pls_integer:=12' "$benchmark"

printf '%s\n' 'PMLE_FREE_RASTER_SOURCE|PASS'
