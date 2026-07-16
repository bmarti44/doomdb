#!/usr/bin/env bash
set -Eeuo pipefail

# Two connections are the smallest pool that preserves AutoREST discovery and
# request service concurrently. Long reuse limits avoid unrelated churn; ORDS
# still reinitializes package/OJVM application state after every request.
ords config --db-pool default set jdbc.InitialLimit 2 >/dev/null
ords config --db-pool default set jdbc.MinLimit 2 >/dev/null
ords config --db-pool default set jdbc.MaxLimit 2 >/dev/null
ords config --db-pool default set jdbc.MaxConnectionReuseCount 100000000 >/dev/null
ords config --db-pool default set jdbc.InactivityTimeout 86400 >/dev/null
ords config --db-pool default set jdbc.cleanup.mode RECYCLE >/dev/null
ords config --db-pool default set plsql.gateway.mode DISABLED >/dev/null
