#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
probe="$root/probes/mle"
source_file="$probe/free-raster-teavm/src/main/java/doomdb/mle/raster/FreeRasterKernel.java"
full_source="$probe/free-raster-teavm/src/main/java/doomdb/mle/raster/FullCommandRasterKernel.java"
install="$probe/install-free-raster-teavm.sh"
runner="$probe/run-oci-free-raster-teavm.sh"
benchmark="$probe/benchmark-oci-free-raster-teavm.sql"
full_install="$probe/install-full-command-raster-pack.sh"
full_runner="$probe/run-oci-full-command-raster.sh"
full_benchmark="$probe/benchmark-oci-full-command-raster.sql"
node_rank="$probe/rank-full-command-raster-node.mjs"
capture_patch="$probe/teavm-engine/0006-teavm-presentation-command-capture.patch"
capture_build="$probe/teavm-engine/build-presentation.sh"
capture_pom="$probe/teavm-engine/pom.xml"
capture_probe="$probe/teavm-engine/src/presentation-command-capture-engine/java/doomdb/mle/engine/PresentationCommandCaptureProbe.java"
capture_metrics="$probe/teavm-engine/src/presentation-command-capture/java/rr/drawfuns/FrameCommandMetrics.java"
capture_runner="$probe/teavm-engine/run-presentation-command-census.sh"

for input in "$source_file" "$full_source" "$install" "$runner" "$benchmark" \
  "$full_install" "$full_runner" "$full_benchmark" "$node_rank" \
  "$capture_patch" "$capture_build" "$capture_pom" "$capture_probe" "$capture_metrics" \
  "$capture_runner" \
  "$probe/build-free-raster-teavm.sh" "$probe/cleanup-free-raster-teavm.sql"; do
  [[ -s "$input" && ! -L "$input" ]] || {
    printf 'free-raster verifier: missing input %s\n' "$input" >&2
    exit 1
  }
done

bash -n \
  "$probe/build-free-raster-teavm.sh" \
  "$install" \
  "$runner" \
  "$full_install" \
  "$full_runner"

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

# The promoted authentic viewport path resolves captured bytes once into
# primitive arrays. Reintroducing per-frame command decoding forfeits the
# measured 59 FPS result even when the eventual pixels remain exact.
require 'resolveCommand(command++, commandAt);' "$full_source"
require 'int command = commandStarts[frameIndex];' "$full_source"
require 'frame[output] = pack[source + spot];' "$full_source"
require 'output += FRAME_HEIGHT;' "$full_source"
require 'throw new IllegalStateException(' "$full_source"
require '"fuzz command requires the separately gated fuzz path"' "$full_source"

# Pack and module staging are byte-length/SHA fail-closed, and exact viewport
# evidence precedes both per-call and retained timing.
require "dbms_crypto.hash(pack_blob,dbms_crypto.hash_sh256)" "$full_install"
require 'while IFS= read -r piece || [[ -n "$piece" ]]; do' "$full_install"
require "raise_application_error(-20796,'full-command staging mismatch')" "$full_install"
require 'PMLE_FULL_COMMAND_RASTER_NODE|PASS|frames=${frames}' "$node_rank"
require 'viewport_exact=${frames}' "$node_rank"
require 'PMLE_FULL_COMMAND_EQUIVALENCE|PASS|' "$full_benchmark"
require 'c_frames constant pls_integer:=192' "$full_benchmark"
require 'c_passes constant pls_integer:=12' "$full_benchmark"
require 'PMLE_FULL_COMMAND_VERDICT|' "$full_runner"
require 'final_two_worst_p95_ms=%s' "$full_runner"
require 'hud=NOT_INCLUDED' "$full_runner"
require 'PMLE_FULL_COMMAND_POSTFLIGHT|PASS|diagnostic_objects=0' "$full_runner"

# Capture reachability is a candidate-only overlay. The shipping authority
# sources must not import the retained command/asset registry.
require '0006-teavm-presentation-command-capture.patch' "$capture_build"
require 'presentation-command-capture-engine/java' "$capture_pom"
require 'DOOMDB_MOCHA_EXTRA_ADAPTER_SOURCE=' "$capture_build"
require 'doomdbEnableFrameCommandMetrics();' "$capture_patch"
require 'FrameCommandMetrics.enable();' "$capture_patch"
require 'class PresentationCommandCaptureProbe' "$capture_probe"
require 'private static final int COMMAND_BYTES = 28;' "$capture_metrics"
require "header.writeUInt32LE(3, 4);" \
  "$probe/teavm-engine/run-presentation-node.mjs"
require "version=3|frames=192" "$capture_runner"
if grep -Fq 'FrameCommandMetrics' \
  "$probe/teavm-engine/src/main/java/doomdb/mle/engine/SimulationEngineReachabilityProbe.java"; then
  printf 'free-raster verifier: capture state reached shipping authority source\n' >&2
  exit 1
fi

printf '%s\n' 'PMLE_FREE_RASTER_SOURCE|PASS'
