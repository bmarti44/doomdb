#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
evidence="$root/artifacts/performance/pmle-exact-live"
tag="${PMLE_TEMPORAL_KERNEL_TAG:-temporal-frame-kernel-2026-07-30}"
log="$evidence/$tag.log"

[[ "${PMLE_TEMPORAL_KERNEL_EXECUTE:-NO}" == YES ]] || {
  printf '%s\n' 'set PMLE_TEMPORAL_KERNEL_EXECUTE=YES to run the OCI cell' >&2
  exit 2
}
for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
  SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'required OCI authority is absent: %s\n' "$name" >&2
    exit 2
  }
done
[[ ! -e "$log" ]] || {
  printf 'refusing to overwrite temporal-kernel evidence: %s\n' "$log" >&2
  exit 1
}

"$root/scripts/adb-doom-sql.sh" \
  "$root/probes/mle/temporal-frame-kernel.sql" | tee "$log"
[[ "$(grep -c '^PMLE_TEMPORAL_KERNEL|PASS|' "$log")" == 5 ]]
if "$root/scripts/adb-doom-sql.sh" - <<'SQL' |
set heading off feedback off pages 0
select object_name from user_objects
where object_name in('DOOM_TEMPORAL_SYNTH','DOOM_TEMPORAL_SYNTH_MODULE');
SQL
  grep -q '[^[:space:]]'; then
  printf '%s\n' 'temporal-kernel cleanup left diagnostic objects' >&2
  exit 1
fi
printf 'PASS PMLE-OCI-TEMPORAL-FRAME-KERNEL log=%s\n' "$log"
