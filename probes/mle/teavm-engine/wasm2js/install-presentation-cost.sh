#!/usr/bin/env bash
set -Eeuo pipefail

spike="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
artifact=
emit_only=0
fold_width=2000
wrapper="$spike/presentation-cost-wrapper.mjs"
predeclaration="$spike/../../../../artifacts/performance/pmle-database-frames/wasm2js-presentation-cost-predeclaration-2026-07-26.md"

for option in "$@"; do
  case "$option" in
    --artifact=*) artifact="${option#--artifact=}" ;;
    --emit-sql) emit_only=1 ;;
    *) printf 'unsupported presentation-cost loader option: %s\n' "$option" >&2; exit 2 ;;
  esac
done
[[ -n "$artifact" ]] || {
  printf '%s\n' 'presentation-cost loader requires --artifact=PATH' >&2
  exit 2
}
artifact="$(cd "$(dirname "$artifact")" && pwd)/$(basename "$artifact")"
[[ "$artifact" == "$spike/target/wasm/doom-wasm2js-presentation.o0.bundle.mjs" ]] || {
  printf 'presentation-cost loader rejects artifact path: %s\n' "$artifact" >&2
  exit 2
}
for input in "$artifact" "$wrapper" "$predeclaration"; do
  [[ -s "$input" && ! -L "$input" ]] || {
    printf 'presentation-cost loader input unavailable: %s\n' "$input" >&2
    exit 1
  }
done
grep -Fq 'Classification: `DIAGNOSTIC_NOT_GATE`.' "$predeclaration"
grep -Fq '`DVR_ONLY_ON_COST`' "$predeclaration"

artifact_sha="$(shasum -a 256 "$artifact" | awk '{print $1}')"
artifact_bytes="$(wc -c <"$artifact" | tr -d '[:space:]')"
wrapper_sha="$(shasum -a 256 "$wrapper" | awk '{print $1}')"
wrapper_bytes="$(wc -c <"$wrapper" | tr -d '[:space:]')"
terminal="${artifact%.o0.bundle.mjs}.log"
[[ -s "$terminal" && ! -L "$terminal" ]]
[[ "$(grep -Ec "^PMLE_WASM2JS_PRESENTATION_BUILD\\|PASS\\|.*\\|bundle_sha256=$artifact_sha\\|bundle_bytes=$artifact_bytes$" "$terminal" || true)" == 1 ]] || {
  printf '%s\n' 'presentation-cost artifact lacks its exact build terminal' >&2
  exit 1
}

emit_blob_append() {
  local kind="$1" file="$2"
  printf '%s\n' \
    'declare l_blob blob;l_raw raw(32767);begin' \
    "select source_blob into l_blob from doom_wasm2js_cost_source where source_kind='$kind' for update;"
  base64 <"$file" | tr -d '\r\n' | fold -w "$fold_width" |
    while IFS= read -r piece || [[ -n "$piece" ]]; do
      printf "l_raw:=utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));\n" "$piece"
      printf '%s\n' 'dbms_lob.writeappend(l_blob,utl_raw.length(l_raw),l_raw);'
    done
  printf '%s\n' 'end;' '/'
}

emit_sql() {
  printf '%s\n' \
    'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set define off echo off verify off feedback off heading off pages 0 lines 32767 trimspool on serveroutput on size unlimited' \
    "begin execute immediate 'drop procedure doom_wasm2js_cost_release';exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_wasm2js_cost_memory';exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_wasm2js_cost_lowering';exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_wasm2js_cost_js';exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_wasm2js_cost_linear';exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop mle module doom_wasm2js_cost_bridge';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop mle env doom_wasm2js_cost_env';exception when others then if sqlcode not in(-4080,-4103,-4104,-4105) then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop mle module doom_wasm2js_cost_engine';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop table doom_wasm2js_cost_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;" \
    '/' \
    'create table doom_wasm2js_cost_source(' \
    'source_kind varchar2(16) primary key,source_blob blob not null,' \
    'expected_bytes number not null,expected_sha256 varchar2(64) not null);' \
    "insert into doom_wasm2js_cost_source values('ENGINE',empty_blob(),$artifact_bytes,'$artifact_sha');" \
    "insert into doom_wasm2js_cost_source values('BRIDGE',empty_blob(),$wrapper_bytes,'$wrapper_sha');"
  emit_blob_append ENGINE "$artifact"
  emit_blob_append BRIDGE "$wrapper"
  printf '%s\n' \
    'declare l_count number;begin' \
    'select count(*) into l_count from doom_wasm2js_cost_source' \
    'where dbms_lob.getlength(source_blob)=expected_bytes' \
    'and lower(rawtohex(dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256)))=expected_sha256;' \
    "if l_count<>2 then raise_application_error(-20796,'presentation-cost staging hash mismatch');end if;" \
    "dbms_output.put_line('PMLE_WASM2JS_COST_STAGING|PASS|engine_bytes=$artifact_bytes|engine_sha256=$artifact_sha|bridge_bytes=$wrapper_bytes|bridge_sha256=$wrapper_sha');" \
    'end;' \
    '/' \
    'declare l_started timestamp with time zone;l_ms number;' \
    'function elapsed_ms(p interval day to second)return number is begin return' \
    'extract(day from p)*86400000+extract(hour from p)*3600000+' \
    'extract(minute from p)*60000+extract(second from p)*1000;end;' \
    'begin l_started:=systimestamp;' \
    "execute immediate q'[create mle module doom_wasm2js_cost_engine language javascript using blob (select source_blob from doom_wasm2js_cost_source where source_kind='ENGINE')]';" \
    'l_ms:=elapsed_ms(systimestamp-l_started);' \
    "dbms_output.put_line('PMLE_WASM2JS_COST_MODULE_CREATE|engine_ms='||round(l_ms,3));end;" \
    '/' \
    "create mle env doom_wasm2js_cost_env imports('doom_wasm2js_presentation_cost_engine' module doom_wasm2js_cost_engine);" \
    "create mle module doom_wasm2js_cost_bridge language javascript using blob (select source_blob from doom_wasm2js_cost_source where source_kind='BRIDGE');" \
    '/' \
    "create function doom_wasm2js_cost_linear(p_frames number)return number as mle module doom_wasm2js_cost_bridge env doom_wasm2js_cost_env signature 'renderCostWasm2js(number)';" \
    '/' \
    "create function doom_wasm2js_cost_js(p_frames number)return number as mle module doom_wasm2js_cost_bridge env doom_wasm2js_cost_env signature 'renderCostJs(number)';" \
    '/' \
    "create function doom_wasm2js_cost_lowering return varchar2 as mle module doom_wasm2js_cost_bridge env doom_wasm2js_cost_env signature 'loweringStatus()';" \
    '/' \
    "create function doom_wasm2js_cost_memory return varchar2 as mle module doom_wasm2js_cost_bridge env doom_wasm2js_cost_env signature 'memoryStatus()';" \
    '/' \
    "create procedure doom_wasm2js_cost_release as mle module doom_wasm2js_cost_bridge env doom_wasm2js_cost_env signature 'release()';" \
    '/' \
    'declare l_started timestamp with time zone;l_ms number;l_value varchar2(200);' \
    'function elapsed_ms(p interval day to second)return number is begin return' \
    'extract(day from p)*86400000+extract(hour from p)*3600000+' \
    'extract(minute from p)*60000+extract(second from p)*1000;end;' \
    'begin l_started:=systimestamp;l_value:=doom_wasm2js_cost_lowering;' \
    'l_ms:=elapsed_ms(systimestamp-l_started);' \
    "if l_value<>'i64=exact|values=15,15,23,7,15,15' then raise_application_error(-20796,'presentation-cost lowering mismatch');end if;" \
    "dbms_output.put_line('PMLE_WASM2JS_COST_FIRST_CALL|PASS|elapsed_ms='||round(l_ms,3)||'|memory='||doom_wasm2js_cost_memory);end;" \
    '/' \
    'commit;'
}

if [[ "$emit_only" == 1 ]]; then
  emit_sql
else
  printf '%s\n' 'presentation-cost loader is emit-only; pass --emit-sql' >&2
  exit 2
fi
