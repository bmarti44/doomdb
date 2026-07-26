#!/usr/bin/env bash
set -Eeuo pipefail

spike="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$spike/../../../.." && pwd)"
artifact="${1:-}"
wrapper="$spike/presentation-cost-wrapper.mjs"
loader="$root/tools/cloud/DoomDiagnosticBlobLoader.java"
container="${DOOMDB_ASSET_TOOL_CONTAINER:-$(docker compose -f "$root/compose.yaml" ps -q db)}"
java_home="${DOOMDB_ASSET_TOOL_HOME:-/opt/oracle/product/26ai/dbhomeFree}"
ojdbc="$java_home/jdbc/lib/ojdbc11.jar"
runtime="$ojdbc:$java_home/jlib/oraclepki.jar:$java_home/OPatch/modules/oracle.osdt/osdt_core.jar:$java_home/OPatch/modules/oracle.osdt/osdt_cert.jar"
host_tmp=
remote=

for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR; do
  [[ -n "${!name:-}" ]] || {
    printf 'required JDBC loader authority absent: %s\n' "$name" >&2; exit 2; }
done
[[ "$ADB_USERNAME" == DOOM && -n "$container" ]]
artifact="$(cd "$(dirname "$artifact")" && pwd)/$(basename "$artifact")"
[[ "$artifact" == "$spike/target/wasm/doom-wasm2js-presentation.o0.bundle.mjs" ]]
for input in "$artifact" "$wrapper" "$loader"; do
  [[ -s "$input" && ! -L "$input" ]]
done
artifact_sha="$(shasum -a 256 "$artifact" | awk '{print $1}')"
artifact_bytes="$(wc -c <"$artifact" | tr -d '[:space:]')"
wrapper_sha="$(shasum -a 256 "$wrapper" | awk '{print $1}')"
wrapper_bytes="$(wc -c <"$wrapper" | tr -d '[:space:]')"
terminal="${artifact%.o0.bundle.mjs}.log"
[[ "$(grep -Ec "^PMLE_WASM2JS_PRESENTATION_BUILD\\|PASS\\|.*\\|bundle_sha256=$artifact_sha\\|bundle_bytes=$artifact_bytes$" "$terminal" || true)" == 1 ]]

cleanup() {
  [[ -z "$remote" ]] ||
    docker exec "$container" rm -rf "$remote" >/dev/null 2>&1 || true
  [[ -z "$host_tmp" ]] || rm -rf "$host_tmp"
}
trap cleanup EXIT HUP INT TERM

"$root/scripts/adb-doom-sql.sh" - <<SQL
begin
  for ddl_ in (
    select 'drop procedure doom_wasm2js_cost_release' text from dual union all
    select 'drop function doom_wasm2js_cost_memory' from dual union all
    select 'drop function doom_wasm2js_cost_lowering' from dual union all
    select 'drop function doom_wasm2js_cost_js' from dual union all
    select 'drop function doom_wasm2js_cost_linear' from dual union all
    select 'drop mle module doom_wasm2js_cost_bridge' from dual union all
    select 'drop mle env doom_wasm2js_cost_env' from dual union all
    select 'drop mle module doom_wasm2js_cost_engine' from dual union all
    select 'drop table doom_wasm2js_cost_source purge' from dual
  ) loop
    begin execute immediate ddl_.text;
    exception when others then
      if sqlcode not in(-4043,-4080,-4103,-4104,-4105,-942) then raise;end if;
    end;
  end loop;
end;
/
create table doom_wasm2js_cost_source(
  source_kind varchar2(16) primary key,source_blob blob not null,
  expected_bytes number not null,expected_sha256 varchar2(64) not null);
insert into doom_wasm2js_cost_source values(
  'ENGINE',empty_blob(),$artifact_bytes,'$artifact_sha');
insert into doom_wasm2js_cost_source values(
  'BRIDGE',empty_blob(),$wrapper_bytes,'$wrapper_sha');
commit;
SQL

host_tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-diagnostic-blob.XXXXXX")"
remote="/tmp/doomdb-diagnostic-blob-$$"
mkdir -p "$host_tmp/wallet"
cp -R "$ADB_WALLET_DIR/." "$host_tmp/wallet"
cp "$artifact" "$host_tmp/engine.mjs"
cp "$wrapper" "$host_tmp/bridge.mjs"
cp "$loader" "$host_tmp/"
chmod -R go-rwx "$host_tmp"
docker exec "$container" install -d -m 700 "$remote" "$remote/wallet"
docker cp "$host_tmp/." "$container:$remote/" >/dev/null
printf '%s\n' "$ADB_PASSWORD" | docker exec -i "$container" sh -c \
  "umask 077; cat > '$remote/password'"
docker exec -u 0 "$container" chown -R oracle:oinstall "$remote"
docker exec "$container" chmod -R go-rwx "$remote"
docker exec "$container" "$java_home/jdk/bin/javac" --release 11 \
  -cp "$ojdbc" -d "$remote" "$remote/DoomDiagnosticBlobLoader.java"
docker exec -e "TNS_ADMIN=$remote/wallet" "$container" sh -c \
  'password=$1;shift;exec "$@" <"$password"' sh "$remote/password" \
  "$java_home/jdk/bin/java" -Xms32m -Xmx256m -cp "$remote:$runtime" \
  DoomDiagnosticBlobLoader "jdbc:oracle:thin:@$ADB_CONNECTION_STRING" \
  "$ADB_USERNAME" "$remote/engine.mjs" "$artifact_sha" \
  "$remote/bridge.mjs" "$wrapper_sha" DOOM_WASM2JS_COST_SOURCE

"$root/scripts/adb-doom-sql.sh" - <<'SQL'
set serveroutput on size unlimited heading off feedback off pagesize 0
declare l_count number;begin
  select count(*) into l_count from doom_wasm2js_cost_source
  where dbms_lob.getlength(source_blob)=expected_bytes
  and lower(rawtohex(dbms_crypto.hash(
    source_blob,dbms_crypto.hash_sh256)))=expected_sha256;
  if l_count<>2 then
    raise_application_error(-20796,'presentation-cost database SHA mismatch');
  end if;
  dbms_output.put_line('PMLE_WASM2JS_COST_STAGING|PASS|objects=2');
end;
/
declare
  l_started timestamp with time zone;l_ms number;
  function elapsed_ms(p interval day to second)return number is begin return
    extract(day from p)*86400000+extract(hour from p)*3600000+
    extract(minute from p)*60000+extract(second from p)*1000;end;
begin
  l_started:=systimestamp;
  execute immediate q'[create mle module doom_wasm2js_cost_engine
    language javascript using blob
    (select source_blob from doom_wasm2js_cost_source
      where source_kind='ENGINE')]';
  l_ms:=elapsed_ms(systimestamp-l_started);
  dbms_output.put_line(
    'PMLE_WASM2JS_COST_MODULE_CREATE|engine_ms='||round(l_ms,3));
end;
/
create mle env doom_wasm2js_cost_env imports(
  'doom_wasm2js_presentation_cost_engine' module doom_wasm2js_cost_engine);
create mle module doom_wasm2js_cost_bridge language javascript using blob
  (select source_blob from doom_wasm2js_cost_source where source_kind='BRIDGE');
/
create function doom_wasm2js_cost_linear(p_frames number)return number
as mle module doom_wasm2js_cost_bridge env doom_wasm2js_cost_env
signature 'renderCostWasm2js(number)';
/
create function doom_wasm2js_cost_js(p_frames number)return number
as mle module doom_wasm2js_cost_bridge env doom_wasm2js_cost_env
signature 'renderCostJs(number)';
/
create function doom_wasm2js_cost_lowering return varchar2
as mle module doom_wasm2js_cost_bridge env doom_wasm2js_cost_env
signature 'loweringStatus()';
/
create function doom_wasm2js_cost_memory return varchar2
as mle module doom_wasm2js_cost_bridge env doom_wasm2js_cost_env
signature 'memoryStatus()';
/
create procedure doom_wasm2js_cost_release
as mle module doom_wasm2js_cost_bridge env doom_wasm2js_cost_env
signature 'release()';
/
declare
  l_started timestamp with time zone;l_ms number;l_value varchar2(200);
  function elapsed_ms(p interval day to second)return number is begin return
    extract(day from p)*86400000+extract(hour from p)*3600000+
    extract(minute from p)*60000+extract(second from p)*1000;end;
begin
  l_started:=systimestamp;l_value:=doom_wasm2js_cost_lowering;
  l_ms:=elapsed_ms(systimestamp-l_started);
  if l_value<>'i64=exact|values=15,15,23,7,15,15' then
    raise_application_error(-20796,'presentation-cost lowering mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_WASM2JS_COST_FIRST_CALL|PASS|elapsed_ms='||round(l_ms,3)||
    '|memory='||doom_wasm2js_cost_memory);
end;
/
commit;
SQL
