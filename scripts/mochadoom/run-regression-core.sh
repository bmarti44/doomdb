#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
container="${DOOMDB_MOCHA_CONTAINER:-$(docker compose -f "$root/compose.yaml" ps -q db)}"
java_home="/opt/oracle/product/26ai/dbhomeFree"

gates=(
  control-codec-gate.sql
  initial-frame-gate.sql
  replay-gate.sql
  save-load-gate.sql
  durable-bridge-gate.sql
  durable-audio-ledger-gate.sql
  crash-reconstruction-gate.sql
  concurrent-session-gate.sql
  gameplay-defect-gate.sql
  presentation-controls-gate.sql
)

[[ -n "$container" ]] || { printf 'database container is not running\n' >&2; exit 1; }
for gate in "${gates[@]}"; do
  {
    printf 'connect DOOM/"'
    docker exec "$container" sh -c "tr -d '\\r\\n' < /run/secrets/doom_password"
    printf '"@FREEPDB1\n'
    cat "$root/scripts/mochadoom/$gate"
  } | docker exec -i "$container" "$java_home/bin/sqlplus" -s /nolog
done
