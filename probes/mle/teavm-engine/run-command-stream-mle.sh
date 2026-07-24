#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
stream="${1:-}"
mode="${2:-DEATHMATCH}"
tic_limit="${3:-5250}"
source_sql="$root/probes/mle/teavm-engine/replay-command-stream-mle.sql"

[[ "$stream" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || {
  printf 'usage: %s STREAM_NAME [COOP|DEATHMATCH] [TIC_LIMIT]\n' "$0" >&2
  exit 2
}
[[ "$mode" == COOP || "$mode" == DEATHMATCH ]] || {
  printf 'mode must be COOP or DEATHMATCH\n' >&2
  exit 2
}
[[ "$tic_limit" =~ ^[1-9][0-9]{1,5}$ && "$tic_limit" -le 5250 ]] || {
  printf 'tic limit must be between 10 and 5250\n' >&2
  exit 2
}
deathmatch=1
[[ "$mode" == COOP ]] && deathmatch=0

# The replay uses a separate retained MLE context and is intentionally never
# launched while a production/user match owns Free's single effective CPU.
active="$("$root/scripts/db_sql.sh" - <<SQL | awk -F= '/^ACTIVE_MATCHES=/{print $2}'
set heading off feedback off pagesize 0
select 'ACTIVE_MATCHES='||count(*) from doom_match
where match_state='ACTIVE' and expires_at>(localtimestamp at time zone 'UTC');
SQL
)"
[[ "$active" == 0 ]] || {
  printf 'refusing command replay while %s active match(es) own MLE capacity\n' \
    "$active" >&2
  exit 1
}

"$root/scripts/db_sql.sh" \
  "$root/probes/mle/teavm-engine/environment-metadata.sql"
printf 'PMLE_HOST_CONTEXT|phase=BEFORE|utc=%s|uname=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(uname -a)"
printf 'PMLE_HOST_CONTEXT|phase=BEFORE|model=%s|logical_cpu=%s\n' \
  "$(sysctl -n hw.model 2>/dev/null || printf unavailable)" \
  "$(sysctl -n hw.logicalcpu 2>/dev/null || printf unavailable)"
pmset -g therm 2>/dev/null | sed 's/^/PMLE_HOST_THERMAL|phase=BEFORE|/' || true
sed -e "s/__STREAM_NAME__/$stream/g" \
  -e "s/__DEATHMATCH__/$deathmatch/g" \
  -e "s/__TIC_LIMIT__/$tic_limit/g" "$source_sql" |
  "$root/scripts/db_sql.sh" -
printf 'PMLE_HOST_CONTEXT|phase=AFTER|utc=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
pmset -g therm 2>/dev/null | sed 's/^/PMLE_HOST_THERMAL|phase=AFTER|/' || true
