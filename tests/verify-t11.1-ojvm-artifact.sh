#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-t111-ojvm.XXXXXX")"
container="${DOOMDB_JAVA_TOOL_CONTAINER:-$(docker compose -f "$root/compose.yaml" ps -q db)}"
java_home="${DOOMDB_JAVA_TOOL_HOME:-/opt/oracle/product/26ai/dbhomeFree}"
schema=DOOM_T111_LOADJAVA
remote="/tmp/doomdb-t111-loadjava-$$"
password="$(openssl rand -hex 16)"
cleanup(){
  docker exec "$container" rm -rf "$remote" >/dev/null 2>&1 || true
  docker exec -i "$container" "$java_home/bin/sqlplus" -s / as sysdba <<SQL >/dev/null 2>&1 || true
alter session set container=FREEPDB1;
begin execute immediate 'drop user $schema cascade'; exception when others then if sqlcode != -1918 then raise; end if; end;
/
exit
SQL
  rm -rf "$tmp"
}
trap cleanup EXIT
[[ -n "$container" ]]

"$root/scripts/mochadoom/build-ojvm-jar.sh" "$tmp/mochadoom.jar" "$tmp/metadata.json" >/dev/null
node - "$tmp/mochadoom.jar" "$tmp/metadata.json" <<'NODE'
import assert from 'node:assert/strict';import crypto from 'node:crypto';import fs from 'node:fs';
const [jar,path]=process.argv.slice(2),m=JSON.parse(fs.readFileSync(path));
assert.deepEqual(m,{schema:1,javaRelease:8,revision:'c0af1322ee5fd168b5cf8aaaf504cab2d1aabe93',classCount:830,jarSha256:'a27903f2dcd81aecb0292f605453969ad3d4389382bebdb8386dff3cb13f23ab'});
assert.equal(crypto.createHash('sha256').update(fs.readFileSync(jar)).digest('hex'),m.jarSha256);
NODE
unzip -p "$tmp/mochadoom.jar" doomdb/mocha/DoomDbMochaAdapter.class >"$tmp/adapter.class"
header="$(od -An -t u1 -N8 "$tmp/adapter.class" | xargs)"
[[ "$header" == '202 254 186 190 0 0 0 52' ]]

docker exec "$container" mkdir -m 700 "$remote"
docker cp "$tmp/mochadoom.jar" "$container:$remote/mochadoom.jar" >/dev/null
printf '%s\n' "$password" | docker exec -i "$container" sh -c \
  "umask 077; cat > '$remote/password'"
docker exec -u 0 "$container" chown -R oracle:oinstall "$remote"
docker exec "$container" chmod -R go-rwx "$remote"
docker exec -i "$container" "$java_home/bin/sqlplus" -s / as sysdba <<SQL >/dev/null
whenever sqlerror exit sql.sqlcode rollback
alter session set container=FREEPDB1;
begin execute immediate 'drop user $schema cascade'; exception when others then if sqlcode != -1918 then raise; end if; end;
/
create user $schema identified by "$password" quota unlimited on users;
grant create session, create procedure, create table to $schema;
exit success commit
SQL
if ! docker exec "$container" sh -c \
  'password=$1; shift; exec "$@" < "$password"' sh "$remote/password" \
  "$java_home/bin/loadjava" -oci8 -force -resolve \
  -user "$schema@FREEPDB1" "$remote/mochadoom.jar" \
  >"$tmp/loadjava.log" 2>&1; then
  sed -E 's/(Password:).*/\1 [REDACTED]/' "$tmp/loadjava.log" >&2
  exit 1
fi
observation="$(docker exec -i "$container" "$java_home/bin/sqlplus" -s / as sysdba <<SQL
whenever sqlerror exit sql.sqlcode rollback
set feedback off heading off pages 0
alter session set container=FREEPDB1;
select count(*)||'|'||sum(case when status<>'VALID' then 1 else 0 end)
  from dba_objects where owner='$schema' and object_type='JAVA CLASS';
exit success commit
SQL
)"
[[ "$(tr -d '[:space:]' <<<"$observation")" == '830|0' ]]
printf 'PASS T11.1-OJVM-ARTIFACT (830 deterministic Java 8 classes; client load+resolve 830/830)\n'
