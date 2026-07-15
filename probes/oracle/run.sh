#!/bin/sh
set -eu

PROBE_SCHEMA=DOOMDB_PROBE
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROBE_SQL=${PROBE_SQL:-$SCRIPT_DIR/capabilities.sql}
SQL_CLIENT=${SQL_CLIENT:-}

fail() {
  printf '%s\n' "oracle capability probe: $*" >&2
  exit 1
}

if [ -z "$SQL_CLIENT" ]; then
  if command -v sqlplus >/dev/null 2>&1; then
    SQL_CLIENT=sqlplus
  elif command -v sql >/dev/null 2>&1; then
    SQL_CLIENT=sql
  else
    fail 'SQL*Plus or SQLcl is required'
  fi
fi

command -v "$SQL_CLIENT" >/dev/null 2>&1 || fail "SQL client not found: $SQL_CLIENT"
: "${ORACLE_ADMIN_CONNECT:?set ORACLE_ADMIN_CONNECT to an administrative SQL connect string}"
: "${ORACLE_CONNECT_IDENTIFIER:?set ORACLE_CONNECT_IDENTIFIER to the service used by the probe schema}"

case "$ORACLE_CONNECT_IDENTIFIER" in
  *[!A-Za-z0-9._:/?=@-]*) fail 'ORACLE_CONNECT_IDENTIFIER contains unsupported characters' ;;
esac

if command -v openssl >/dev/null 2>&1; then
  PROBE_PASSWORD=$(openssl rand -hex 24)
else
  fail 'openssl is required to generate the disposable schema password'
fi

run_admin_sql() {
  action=$1
  {
    printf 'whenever oserror exit failure rollback\n'
    printf 'whenever sqlerror exit sql.sqlcode rollback\n'
    printf 'set echo off heading off feedback off verify off\n'
    printf 'connect %s\n' "$ORACLE_ADMIN_CONNECT"
    if [ "$action" = create ]; then
      printf 'create user %s identified by "%s" quota unlimited on users;\n' "$PROBE_SCHEMA" "$PROBE_PASSWORD"
      printf 'grant create session, create table, create procedure, create sequence, create trigger, create property graph to %s;\n' "$PROBE_SCHEMA"
      printf 'grant execute on dbms_crypto to %s;\n' "$PROBE_SCHEMA"
      printf 'grant execute on utl_compress to %s;\n' "$PROBE_SCHEMA"
    else
      printf 'drop user %s cascade;\n' "$PROBE_SCHEMA"
    fi
    printf 'exit success commit\n'
  } | "$SQL_CLIENT" -s /nolog
}

schema_created=false
output_file=$(mktemp "${TMPDIR:-/tmp}/doomdb-oracle-probe.XXXXXX")
cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  if [ "$schema_created" = true ]; then
    drop_attempt=1
    schema_dropped=false
    while [ "$schema_dropped" = false ]; do
      if run_admin_sql drop; then
        schema_dropped=true
        break
      fi
      if [ "$drop_attempt" -ge 5 ]; then
        break
      fi
      drop_attempt=$((drop_attempt + 1))
      sleep 1
    done
    if [ "$schema_dropped" = false ]; then
      printf '%s\n' 'oracle capability probe: failed to drop DOOMDB_PROBE' >&2
      status=1
    fi
  fi
  rm -f "$output_file"
  PROBE_PASSWORD=
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

run_admin_sql create
schema_created=true

{
  printf 'connect %s/"%s"@%s\n' "$PROBE_SCHEMA" "$PROBE_PASSWORD" "$ORACLE_CONNECT_IDENTIFIER"
  cat "$PROBE_SQL"
} | "$SQL_CLIENT" -s /nolog >"$output_file"

cat "$output_file"
for marker in \
  SDO_GEOMETRY_INDEX_OK CONNECT_BY_OK MODEL_OK MATCH_RECOGNIZE_OK \
  JSON_RETURNING_CLOB_OK SQL_PROPERTY_GRAPH_OK DBMS_CRYPTO_OK \
  UTL_COMPRESS_OK ORDS_ENABLE_OBJECT_OK
do
  count=$(grep -c "$marker" "$output_file" || true)
  [ "$count" -eq 1 ] || fail "live result marker $marker occurred $count times"
done
grep -q '^ALL_ORACLE_CAPABILITY_PROBES_OK$' "$output_file" || \
  fail 'capability probe did not reach its terminal marker'
printf '%s\n' 'PASS T0.2 (9/9 capabilities)'
