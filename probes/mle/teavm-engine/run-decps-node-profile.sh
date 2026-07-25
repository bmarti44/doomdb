#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
evidence="$root/artifacts/performance/pmle-decps-rank"
artifact="$project/target/javascript/doom-mle-simulation-engine-headless.js"
patch="$project/0006-teavm-authority-no-blocking-wait.patch"
candidate_sha=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3
expected_stream_sha=fa7637570c30d3a33cbf8456e98268890e9f5bd82f5ba39fd7f69b139ddc4085
evidence_tag="${PMLE_PROFILE_TAG:-}"
[[ -z "$evidence_tag" || "$evidence_tag" =~ ^[A-Za-z0-9._-]+$ ]] ||
  { printf 'invalid profile evidence tag: %s\n' "$evidence_tag" >&2; exit 2; }
profile_suffix="${evidence_tag:+-$evidence_tag}"
profile_artifact="$project/target/javascript/doom-mle-simulation-engine-decps-profile${profile_suffix}.js"
profile="$evidence/node-decps-peak-${candidate_sha:0:12}${profile_suffix}.cpuprofile"
build_log="$evidence/node-decps-peak-build-${candidate_sha:0:12}${profile_suffix}.log"
log="$evidence/node-decps-peak-${candidate_sha:0:12}${profile_suffix}.log"
validator="$project/validate-decps-node-profile.mjs"
build_extractor="$project/extract-build-sha.mjs"
stream_hasher="$project/hash-expanded-command-stream.mjs"
stream="$(mktemp "${TMPDIR:-/tmp}/doomdb-decps-profile-stream.XXXXXX")"
saved="$(mktemp "${TMPDIR:-/tmp}/doomdb-decps-profile-artifact.XXXXXX")"

restore() {
  local status=$?
  trap - EXIT
  if [[ -s "$saved" ]]; then
    cp "$saved" "$artifact" || status=1
  fi
  rm -f "$stream" "$saved"
  exit "$status"
}
trap restore EXIT

competing_gate="$(ps ax -o command= | awk '
  /[r]un-ledger-differential|[r]un-decps-ledger|[b]uild-ledger-differential|[r]un-worker-soak|[r]un-live-command-matrix-mle|[r]un-decps-rank-mle/ {print}
')"
[[ -z "$competing_gate" ]] || {
  printf 'de-CPS Node profile refuses a competing evidence gate:\n%s\n' \
    "$competing_gate" >&2
  exit 1
}
busy_host="$(ps ax -o command= | awk '
  /[d]ocker (build|compose .* build)|[b]uild-simulation[.]sh|[m]vn .*package|[j]avac|[v]erify-local-e2e/ {print}
')"
[[ -z "$busy_host" ]] || {
  printf 'de-CPS Node profile requires a quiet host:\n%s\n' \
    "$busy_host" >&2
  exit 1
}
for output in "$profile_artifact" "$profile" "$build_log" "$log"; do
  [[ ! -e "$output" ]] || {
    printf 'refusing to overwrite de-CPS Node profile evidence: %s\n' \
      "$output" >&2
    exit 1
  }
done
test -s "$artifact"
[[ "$(shasum -a 256 "$artifact" | awk '{print $1}')" == "$candidate_sha" ]] || {
  printf '%s\n' 'de-CPS Node profile requires the exact candidate artifact' >&2
  exit 1
}
cp "$artifact" "$saved"
node "$build_extractor" --self-test
node "$stream_hasher" --self-test

PMLE_AUTHORITY_CANDIDATE_BUILD=YES \
PMLE_AUTHORITY_CANDIDATE_REASON=decps-node-profile \
DOOMDB_TEAVM_AUTHORITY_EXTRA_PATCH="$patch" \
DOOMDB_TEAVM_MINIFYING=false \
  "$project/build-simulation.sh" | tee "$build_log"
grep -Eq '^PASS PMLE-TEAVM-SIMULATION-BUILD optimization_level=ADVANCED minifying=false .*classification=UNPROMOTED_CANDIDATE candidate_reason=decps-node-profile ' \
  "$build_log"
profile_artifact_sha="$(
  shasum -a 256 "$artifact" | awk '{print $1}'
)"
profile_artifact_bytes="$(wc -c <"$artifact" | tr -d '[:space:]')"
build_marker='PASS PMLE-TEAVM-SIMULATION-BUILD'
[[ "$(node "$build_extractor" "$build_log" "$build_marker" sha256)" \
      == "$profile_artifact_sha" &&
    "$(node "$build_extractor" "$build_log" "$build_marker" bytes integer)" \
      == "$profile_artifact_bytes" &&
    "$(node "$build_extractor" "$build_log" "$build_marker" classification token)" \
      == UNPROMOTED_CANDIDATE &&
    "$(node "$build_extractor" "$build_log" "$build_marker" candidate_reason token)" \
      == decps-node-profile ]] || {
  printf '%s\n' 'de-CPS Node profile artifact/build provenance mismatch' >&2
  exit 1
}
cp "$artifact" "$profile_artifact"
cmp -s "$artifact" "$profile_artifact" || {
  printf '%s\n' 'de-CPS Node profile artifact copy is not byte-identical' >&2
  exit 1
}

"$root/scripts/db_sql.sh" - <<'SQL' |
set heading off feedback off pagesize 0 linesize 32767 trimspool on
select tic||'|'||to_number(rawtohex(membership_bitmap),'XX')||'|'||
       lower(rawtohex(command_vector))
from doom_mle_perf_vector
where stream_name='live-dm-2026-07-23' and tic between 1 and 5250
order by tic;
SQL
  grep -E '^[1-9][0-9]*\|[0-9]+\|[0-9a-f]{64}$' >"$stream"

[[ "$(wc -l <"$stream" | tr -d '[:space:]')" == 5250 ]] || {
  printf '%s\n' 'de-CPS Node profile stream is not exactly 5,250 tics' >&2
  exit 1
}
stream_sha="$(node "$stream_hasher" "$stream")"
[[ "$stream_sha" == "$expected_stream_sha" ]] || {
  printf 'de-CPS Node profile stream SHA mismatch: %s expected %s\n' \
    "$stream_sha" "$expected_stream_sha" >&2
  exit 1
}

{
  printf 'PMLE_HOST_CONTEXT|phase=BEFORE_PROFILE|utc=%s|uname=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(uname -a)"
  printf 'PMLE_HOST_CONTEXT|phase=BEFORE_PROFILE|model=%s|logical_cpu=%s\n' \
    "$(sysctl -n hw.model 2>/dev/null || printf unavailable)" \
    "$(sysctl -n hw.logicalcpu 2>/dev/null || printf unavailable)"
  pmset -g therm 2>/dev/null |
    sed 's/^/PMLE_HOST_THERMAL|phase=BEFORE_PROFILE|/' || true
  printf 'PMLE_DECPS_NODE_PROFILE|START|authority_sha256=%s' "$candidate_sha"
  printf '|profile_artifact_sha256=%s' \
    "$profile_artifact_sha"
  printf '|stream_sha256=%s|tics=5250|host_quiet=YES\n' \
    "$stream_sha"
  DOOMDB_MLE_PROFILE_MODULE="$profile_artifact" \
  DOOMDB_MLE_PROFILE_OUTPUT="$profile" \
    node "$project/profile-command-stream-node.mjs" <"$stream"
  test -s "$profile"
  node "$project/rank-decps-node-profile.mjs" "$profile"
  printf 'PMLE_HOST_CONTEXT|phase=AFTER_PROFILE|utc=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  pmset -g therm 2>/dev/null |
    sed 's/^/PMLE_HOST_THERMAL|phase=AFTER_PROFILE|/' || true
  printf 'PMLE_DECPS_NODE_PROFILE|PASS|authority_sha256=%s' "$candidate_sha"
  printf '|profile_sha256=%s\n' \
    "$(shasum -a 256 "$profile" | awk '{print $1}')"
} | tee "$log"
node "$validator" --self-test
node "$validator" "$log" "$profile" | tee -a "$log"
