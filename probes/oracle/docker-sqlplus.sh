#!/bin/sh
set -eu

: "${ORACLE_CONTAINER:?set ORACLE_CONTAINER to the disposable Oracle container name}"
exec docker exec -i "$ORACLE_CONTAINER" sqlplus "$@"
