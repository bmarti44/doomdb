#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOCAL_SQL=$ROOT/probes/oracle/capabilities.sql
CLOUD_SQL=$ROOT/cloud/probes/oracle/capabilities.sql
RUNNER=$ROOT/probes/oracle/run.sh

fail() {
  printf '%s\n' "verify oracle probes: $*" >&2
  exit 1
}

[ -f "$LOCAL_SQL" ] || fail 'missing local capability probe'
[ -f "$CLOUD_SQL" ] || fail 'missing cloud capability probe'
[ -x "$RUNNER" ] || fail 'probe runner is not executable'
cmp -s "$LOCAL_SQL" "$CLOUD_SQL" || fail 'cloud probe differs from reviewed local probe'

for marker in \
  SDO_GEOMETRY_INDEX_OK \
  CONNECT_BY_OK \
  MODEL_OK \
  MATCH_RECOGNIZE_OK \
  JSON_RETURNING_CLOB_OK \
  SQL_PROPERTY_GRAPH_OK \
  DBMS_CRYPTO_OK \
  UTL_COMPRESS_OK \
  ORDS_ENABLE_OBJECT_OK
do
  count=$(grep -c "$marker" "$LOCAL_SQL" || true)
  [ "$count" -eq 1 ] || fail "expected exactly one result marker for $marker, found $count"
done

grep -q '^whenever sqlerror exit ' "$LOCAL_SQL" || fail 'SQL errors are not fatal'
grep -q '^whenever oserror exit ' "$LOCAL_SQL" || fail 'OS errors are not fatal'
grep -q 'drop user %s cascade' "$RUNNER" || fail 'runner does not drop the disposable schema'
grep -q "PROBE_SCHEMA=DOOMDB_PROBE" "$RUNNER" || fail 'runner schema name is not fixed'

printf '%s\n' 'oracle capability probe package: PASS'
