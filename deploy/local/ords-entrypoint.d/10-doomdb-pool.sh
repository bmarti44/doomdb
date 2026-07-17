#!/usr/bin/env bash
set -Eeuo pipefail

# Four warm connections leave metadata/health headroom while the bounded
# depth-two game pipeline holds two AutoREST calls. Long reuse limits avoid
# unrelated churn; ORDS still reinitializes package/OJVM application state
# after every request.
ords config --db-pool default set jdbc.InitialLimit 4 >/dev/null
ords config --db-pool default set jdbc.MinLimit 4 >/dev/null
ords config --db-pool default set jdbc.MaxLimit 4 >/dev/null
ords config --db-pool default set jdbc.MaxConnectionReuseCount 100000000 >/dev/null
ords config --db-pool default set jdbc.InactivityTimeout 86400 >/dev/null
ords config --db-pool default set jdbc.MaxStatementsLimit 50 >/dev/null
ords config --db-pool default set jdbc.cleanup.mode RECYCLE >/dev/null
ords config --db-pool default set plsql.gateway.mode DISABLED >/dev/null
