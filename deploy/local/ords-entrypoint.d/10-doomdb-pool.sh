#!/usr/bin/env bash
set -Eeuo pipefail

# The selected browser pipeline can have four submits and two frame polls in
# flight. Keep exactly six physical sessions from startup: allowing UCP to grow
# the pool mid-route makes each new session describe generated AutoREST
# procedures through USER_PROCEDURES/USER_ARGUMENTS, which stalls every cursor
# sharing those metadata statements. Long reuse limits then preserve the warm
# statement caches. ORDS still reinitializes package/OJVM application state
# after every request.
ords config --db-pool default set jdbc.InitialLimit 6 >/dev/null
ords config --db-pool default set jdbc.MinLimit 6 >/dev/null
ords config --db-pool default set jdbc.MaxLimit 6 >/dev/null
ords config --db-pool default set jdbc.MaxConnectionReuseCount 100000000 >/dev/null
ords config --db-pool default set jdbc.InactivityTimeout 86400 >/dev/null
ords config --db-pool default set jdbc.MaxStatementsLimit 50 >/dev/null
ords config --db-pool default set jdbc.cleanup.mode RECYCLE >/dev/null
ords config --db-pool default set plsql.gateway.mode DISABLED >/dev/null
