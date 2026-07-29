#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
stamp=$(date -u +%Y-%m-%dT%H%M%SZ)
output=${1:-"$root/artifacts/performance/pmle-live-frame-authority/local-dpb2-soak-$stamp.log"}
e2e_log="${output%.log}-e2e.log"
polls=${DOOMDB_LIVE_FRAME_BATCH_SOAK_POLLS:-300}

[[ "$polls" =~ ^[1-9][0-9]*$ && "$polls" -le 1000 ]] ||
  { printf 'invalid DPB2 soak poll count: %s\n' "$polls" >&2; exit 2; }
[[ ! -e "$output" && ! -e "$e2e_log" ]] ||
  { printf 'refusing to overwrite DPB2 soak evidence\n' >&2; exit 2; }
mkdir -p "$(dirname "$output")"
umask 077

temporary_lobs() {
  "$root/scripts/db_sql.sh" - <<'SQL' |
set heading off feedback off pagesize 0
select 'PMLE_TEMPORARY_LOBS|total='||
  nvl(sum(nvl(cache_lobs,0)+nvl(nocache_lobs,0)+nvl(abstract_lobs,0)),0)
from v$temporary_lobs;
SQL
    awk -F= '/^PMLE_TEMPORARY_LOBS[|]total=/{print $2}' | tail -n 1
}

{
  before=$(temporary_lobs)
  [[ "$before" =~ ^[0-9]+$ ]]
  printf 'PMLE_DPB2_SOAK_BEGIN|polls=%s|temporary_lobs=%s\n' \
    "$polls" "$before"
  DOOMDB_LIVE_FRAME_BATCH_SOAK_POLLS="$polls" \
    "$root/tests/run-mle-live-frame-e2e.sh" "$e2e_log"
  marker=$(grep '^PMLE_LIVE_FRAME_E2E|PASS|' "$e2e_log")
  [[ -n "$marker" ]]
  field() {
    printf '%s\n' "$marker" | tr '|' '\n' |
      awk -F= -v key="$1" '$1==key {print $2}'
  }
  scored_polls=$(field batch_soak_polls)
  frames=$(field batch_soak_frames)
  first_tic=$(field batch_soak_first_tic)
  last_tic=$(field batch_soak_last_tic)
  elapsed_ms=$(field batch_soak_elapsed_ms)
  [[ "$scored_polls" = "$polls" ]]
  [[ "$frames" =~ ^[0-9]+$ && "$frames" -ge "$polls" ]]
  [[ "$first_tic" =~ ^[0-9]+$ && "$last_tic" =~ ^[0-9]+$ ]]
  [[ "$((last_tic-first_tic+1))" -eq "$frames" ]]
  awk -v elapsed="$elapsed_ms" 'BEGIN {exit !(elapsed>0)}'
  printf 'PMLE_DPB2_PROGRESSIVE|PASS|polls=%s|frames=%s|first_tic=%s|last_tic=%s|elapsed_ms=%s\n' \
    "$polls" "$frames" "$first_tic" "$last_tic" "$elapsed_ms"
  sleep 2
  after=$(temporary_lobs)
  [[ "$after" =~ ^[0-9]+$ ]]
  printf 'PMLE_DPB2_SOAK_END|polls=%s|temporary_lobs=%s|delta=%s\n' \
    "$polls" "$after" "$((after-before))"
  [[ "$after" -le "$before" ]]
  printf 'PMLE_DPB2_SOAK|PASS|polls=%s|frames=%s|progressive=1|temporary_lob_growth=0\n' \
    "$polls" "$frames"
} 2>&1 | tee "$output"

grep -q '^PMLE_DPB2_PROGRESSIVE|PASS|' "$output"
grep -q '^PMLE_DPB2_SOAK|PASS|' "$output"
