#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
stream="${1:-}"
source_sql="$root/probes/mle/teavm-engine/live-command-matrix-mle.sql"
alert_state="$(mktemp "${TMPDIR:-/tmp}/doom-mle-live-matrix-alert.XXXXXX")"

[[ "$stream" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]] || {
  printf 'usage: %s STREAM_NAME\n' "$0" >&2
  exit 2
}

active="$("$root/scripts/db_sql.sh" - <<SQL | awk -F= '/^ACTIVE_MATCHES=/{print $2}'
set heading off feedback off pagesize 0
select 'ACTIVE_MATCHES='||count(*) from doom_match
where match_state='ACTIVE' and expires_at>(localtimestamp at time zone 'UTC');
SQL
)"
[[ "$active" == 0 ]] || {
  printf 'refusing live matrix while %s active match(es) own MLE capacity\n' \
    "$active" >&2
  exit 1
}

"$root/scripts/oracle-alert-window.sh" begin "$alert_state" LIVE_COMMAND_MATRIX
status=0
sed "s/__STREAM_NAME__/$stream/g" "$source_sql" |
  "$root/scripts/db_sql.sh" - || status=$?
"$root/scripts/oracle-alert-window.sh" end "$alert_state" LIVE_COMMAND_MATRIX ||
  status=1
exit "$status"
