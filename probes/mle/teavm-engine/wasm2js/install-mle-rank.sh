#!/usr/bin/env bash
set -Eeuo pipefail

spike="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$spike/../../../.." && pwd)"
wrapper="$spike/mle-rank-wrapper.mjs"
artifact=
emit_only=0
self_test=0
base64_fold_width=2000

for option in "$@"; do
  case "$option" in
    --artifact=*) artifact="${option#--artifact=}" ;;
    --emit-sql) emit_only=1 ;;
    --self-test) self_test=1 ;;
    *) printf 'unsupported wasm2js MLE loader option: %s\n' "$option" >&2;exit 2 ;;
  esac
done

if [[ "$self_test" == 1 ]]; then
  [[ "$emit_only" == 0 && -z "$artifact" ]] || {
    printf '%s\n' '--self-test cannot be combined with loader inputs' >&2
    exit 2
  }
  artifact="$wrapper"
else
  [[ -n "$artifact" ]] || {
    printf '%s\n' 'wasm2js MLE loader requires --artifact=PATH' >&2
    exit 2
  }
  artifact="$(cd "$(dirname "$artifact")" && pwd)/$(basename "$artifact")"
  case "$artifact" in
    "$spike"/target/wasm/*.serializer-workaround.o0.bundle.mjs) ;;
    *)
      printf 'wasm2js MLE loader rejects non-workaround artifact: %s\n' \
        "$artifact" >&2
      exit 2
      ;;
  esac
fi
for input in "$artifact" "$wrapper"; do
  [[ -s "$input" ]] || {
    printf 'wasm2js MLE loader input missing: %s\n' "$input" >&2
    exit 1
  }
done

artifact_sha="$(shasum -a 256 "$artifact" | awk '{print $1}')"
artifact_bytes="$(wc -c <"$artifact" | tr -d '[:space:]')"
wrapper_sha="$(shasum -a 256 "$wrapper" | awk '{print $1}')"
wrapper_bytes="$(wc -c <"$wrapper" | tr -d '[:space:]')"
if [[ "$self_test" == 0 ]]; then
  workaround_log="${artifact%.o0.bundle.mjs}.log"
  workaround_stem="${artifact%.o0.bundle.mjs}"
  tic0_log="$workaround_stem.tic0.log"
  parity_log="$workaround_stem.100tic.log"
  wasm="${artifact%.serializer-workaround.o0.bundle.mjs}.wasm"
  patch="$spike/0004-canonical-save-low-word-workaround.patch"
  for evidence_input in "$workaround_log" "$tic0_log" "$parity_log" \
      "$wasm" "$patch"; do
    [[ -s "$evidence_input" ]] || {
      printf 'wasm2js workaround evidence missing: %s\n' \
        "$evidence_input" >&2
      exit 1
    }
  done
  workaround_terminal="PMLE_WASM2JS_SERIALIZER_WORKAROUND|PASS"
  workaround_terminal+="|classification=CANDIDATE_FOR_DIRECT_MLE_RANK"
  workaround_terminal+="|source_patch_sha256=$(shasum -a 256 "$patch" | awk '{print $1}')"
  workaround_terminal+="|wasm_sha256=$(shasum -a 256 "$wasm" | awk '{print $1}')"
  workaround_terminal+="|bundle_sha256=$artifact_sha"
  workaround_terminal+="|tic0_log_sha256=$(shasum -a 256 "$tic0_log" | awk '{print $1}')"
  workaround_terminal+="|parity_log_sha256=$(shasum -a 256 "$parity_log" | awk '{print $1}')"
  [[ "$(grep -c '^PMLE_WASM2JS_SERIALIZER_WORKAROUND|' \
      "$workaround_log" || true)" == 1 &&
      "$(grep -Fxc "$workaround_terminal" "$workaround_log" || true)" == 1 ]] || {
    printf '%s\n' \
      'wasm2js artifact lacks one exact hash-bound parity-approved terminal' >&2
    exit 1
  }
fi

emit_blob_append() {
  local source_kind="$1"
  local source_file="$2"
  printf '%s\n' \
    'declare' \
    '  l_blob blob;' \
    '  l_raw raw(32767);' \
    'begin' \
    "  select source_blob into l_blob from doom_wasm2js_rank_source where source_kind='$source_kind' for update;"
  base64 <"$source_file" | tr -d '\r\n' | fold -w "$base64_fold_width" |
    while IFS= read -r piece || [[ -n "$piece" ]]; do
      printf "  l_raw:=utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));\n" \
        "$piece"
      printf '%s\n' \
        '  dbms_lob.writeappend(l_blob,utl_raw.length(l_raw),l_raw);'
    done
  printf '%s\n' 'end;' '/'
}

emit_sql() {
  printf '%s\n' \
    'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set define off echo off verify off feedback off heading off pages 0 lines 32767 trimspool on serveroutput on size unlimited' \
    "begin execute immediate 'drop procedure doom_wasm2js_rank_release'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_wasm2js_rank_memory'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_wasm2js_rank_lowering'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_wasm2js_rank_canonical_chunk'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_wasm2js_rank_canonical_length'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_wasm2js_rank_step'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_wasm2js_rank_init'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_wasm2js_rank_table_load'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_wasm2js_rank_table_allocate'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_wasm2js_rank_iwad_load'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop function doom_wasm2js_rank_iwad_allocate'; exception when others then if sqlcode<>-4043 then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop mle module doom_wasm2js_rank_bridge'; exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop mle env doom_wasm2js_rank_env'; exception when others then if sqlcode not in(-4080,-4103,-4104,-4105) then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop mle module doom_wasm2js_rank_engine'; exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;" \
    '/' \
    "begin execute immediate 'drop table doom_wasm2js_rank_source purge'; exception when others then if sqlcode<>-942 then raise;end if;end;" \
    '/' \
    'create table doom_wasm2js_rank_source(' \
    '  source_kind varchar2(16) primary key,' \
    '  source_blob blob not null,' \
    '  expected_bytes number not null,' \
    '  expected_sha256 varchar2(64) not null' \
    ');' \
    "insert into doom_wasm2js_rank_source values('ENGINE',empty_blob(),$artifact_bytes,'$artifact_sha');" \
    "insert into doom_wasm2js_rank_source values('BRIDGE',empty_blob(),$wrapper_bytes,'$wrapper_sha');"

  emit_blob_append ENGINE "$artifact"
  emit_blob_append BRIDGE "$wrapper"

  printf '%s\n' \
    'declare' \
    '  l_count pls_integer;' \
    'begin' \
    '  select count(*) into l_count' \
    '  from doom_wasm2js_rank_source' \
    '  where dbms_lob.getlength(source_blob)=expected_bytes' \
    '    and lower(rawtohex(dbms_crypto.hash(source_blob,dbms_crypto.hash_sh256)))=expected_sha256;' \
    '  if l_count<>2 then' \
    "    raise_application_error(-20796,'wasm2js Oracle staging hash mismatch');" \
    '  end if;' \
    "  dbms_output.put_line('PMLE_WASM2JS_MLE_STAGING|PASS|engine_bytes=$artifact_bytes|engine_sha256=$artifact_sha|bridge_bytes=$wrapper_bytes|bridge_sha256=$wrapper_sha');" \
    'end;' \
    '/' \
    "create mle module doom_wasm2js_rank_engine language javascript using blob (select source_blob from doom_wasm2js_rank_source where source_kind='ENGINE');" \
    '/' \
    "create mle env doom_wasm2js_rank_env imports('doom_wasm2js_engine' module doom_wasm2js_rank_engine);" \
    "create mle module doom_wasm2js_rank_bridge language javascript using blob (select source_blob from doom_wasm2js_rank_source where source_kind='BRIDGE');" \
    '/' \
    "create function doom_wasm2js_rank_iwad_allocate(p_length number) return number as mle module doom_wasm2js_rank_bridge env doom_wasm2js_rank_env signature 'allocateIwad(number)';" \
    '/' \
    "create function doom_wasm2js_rank_iwad_load(p_offset number,p_chunk raw) return number as mle module doom_wasm2js_rank_bridge env doom_wasm2js_rank_env signature 'loadIwadChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_wasm2js_rank_table_allocate(p_length number) return number as mle module doom_wasm2js_rank_bridge env doom_wasm2js_rank_env signature 'allocateTablePack(number)';" \
    '/' \
    "create function doom_wasm2js_rank_table_load(p_offset number,p_chunk raw) return number as mle module doom_wasm2js_rank_bridge env doom_wasm2js_rank_env signature 'loadTablePackChunk(number, Uint8Array)';" \
    '/' \
    "create function doom_wasm2js_rank_init(p_players number,p_deathmatch number,p_skill number,p_episode number,p_map number) return number as mle module doom_wasm2js_rank_bridge env doom_wasm2js_rank_env signature 'initializeMultiplayerGame(number, number, number, number, number)';" \
    '/' \
    "create function doom_wasm2js_rank_step(p_players number,p_membership number,p_commands raw) return number as mle module doom_wasm2js_rank_bridge env doom_wasm2js_rank_env signature 'stepMultiplayerAuthoritative(number, number, Uint8Array)';" \
    '/' \
    "create function doom_wasm2js_rank_canonical_length return number as mle module doom_wasm2js_rank_bridge env doom_wasm2js_rank_env signature 'canonicalStateLength()';" \
    '/' \
    "create function doom_wasm2js_rank_canonical_chunk(p_offset number,p_length number) return raw as mle module doom_wasm2js_rank_bridge env doom_wasm2js_rank_env signature 'canonicalStateChunk(number, number)';" \
    '/' \
    "create function doom_wasm2js_rank_lowering return varchar2 as mle module doom_wasm2js_rank_bridge env doom_wasm2js_rank_env signature 'loweringStatus()';" \
    '/' \
    "create function doom_wasm2js_rank_memory return varchar2 as mle module doom_wasm2js_rank_bridge env doom_wasm2js_rank_env signature 'memoryStatus()';" \
    '/' \
    "create procedure doom_wasm2js_rank_release as mle module doom_wasm2js_rank_bridge env doom_wasm2js_rank_env signature 'release()';" \
    '/' \
    'declare' \
    '  l_imports pls_integer;' \
    'begin' \
    '  select count(*) into l_imports from user_mle_env_imports' \
    "   where env_name='DOOM_WASM2JS_RANK_ENV'" \
    "     and import_name='doom_wasm2js_engine'" \
    "     and module_name='DOOM_WASM2JS_RANK_ENGINE';" \
    '  if l_imports<>1 then' \
    "    raise_application_error(-20796,'wasm2js MLE bridge import missing');" \
    '  end if;' \
    "  if doom_wasm2js_rank_lowering<>'i64=exact|values=15,15,23,7,15,15' then" \
    "    raise_application_error(-20796,'wasm2js MLE lowering smoke failed');" \
    '  end if;' \
    "  dbms_output.put_line('PMLE_WASM2JS_MLE_INSTALL|PASS|imports='||l_imports||'|lowering=exact');" \
    'end;' \
    '/' \
    'commit;'
}

if [[ "$self_test" == 1 ]]; then
  emitted="$(emit_sql)"
  printf '%s\n' "$emitted" |
    grep -Fq \
      "insert into doom_wasm2js_rank_source values('ENGINE',empty_blob(),$artifact_bytes,'$artifact_sha');"
  printf '%s\n' "$emitted" |
    grep -Fq \
      "insert into doom_wasm2js_rank_source values('BRIDGE',empty_blob(),$wrapper_bytes,'$wrapper_sha');"
  printf '%s\n' "$emitted" |
    grep -Fq 'PMLE_WASM2JS_MLE_STAGING|PASS'
  engine_line="$(printf '%s\n' "$emitted" |
    grep -n 'create mle module doom_wasm2js_rank_engine' |
    head -1 | cut -d: -f1)"
  env_line="$(printf '%s\n' "$emitted" |
    grep -n 'create mle env doom_wasm2js_rank_env' |
    head -1 | cut -d: -f1)"
  bridge_line="$(printf '%s\n' "$emitted" |
    grep -n 'create mle module doom_wasm2js_rank_bridge' |
    head -1 | cut -d: -f1)"
  lowering_line="$(printf '%s\n' "$emitted" |
    grep -n "doom_wasm2js_rank_lowering<>'i64=exact" |
    head -1 | cut -d: -f1)"
  terminal_line="$(printf '%s\n' "$emitted" |
    grep -n 'PMLE_WASM2JS_MLE_INSTALL|PASS' |
    head -1 | cut -d: -f1)"
  [[ "$engine_line" -lt "$env_line" &&
      "$env_line" -lt "$bridge_line" &&
      "$bridge_line" -lt "$lowering_line" &&
      "$lowering_line" -lt "$terminal_line" ]]
  printf 'PASS PMLE-WASM2JS-MLE-LOADER-SELF-TEST engine_bytes=%s engine_sha256=%s bridge_bytes=%s bridge_sha256=%s\n' \
    "$artifact_bytes" "$artifact_sha" "$wrapper_bytes" "$wrapper_sha"
  exit 0
fi

if [[ "$emit_only" == 1 ]]; then
  emit_sql
  exit 0
fi

competing_gate="$(ps ax -o command= | awk '
  /[r]un-ledger-differential|[r]un-decps-ledger|[b]uild-ledger-differential|[r]un-worker-soak|[r]un-decps-rank-mle|[r]un-presentation-decps-rank/ {print}
')"
[[ -z "$competing_gate" ]] || {
  printf 'wasm2js MLE loader refuses a competing evidence gate:\n%s\n' \
    "$competing_gate" >&2
  exit 1
}

output="$(mktemp "${TMPDIR:-/tmp}/doomdb-wasm2js-mle-load.XXXXXX")"
trap 'rm -f "$output"' EXIT HUP INT TERM
emit_sql | "$root/scripts/db_sql.sh" - >"$output"
cat "$output"
grep -Fqx \
  "PMLE_WASM2JS_MLE_STAGING|PASS|engine_bytes=$artifact_bytes|engine_sha256=$artifact_sha|bridge_bytes=$wrapper_bytes|bridge_sha256=$wrapper_sha" \
  "$output"
grep -Fqx \
  'PMLE_WASM2JS_MLE_INSTALL|PASS|imports=1|lowering=exact' "$output"
printf 'PASS PMLE-WASM2JS-MLE-INSTALL engine_bytes=%s engine_sha256=%s bridge_bytes=%s bridge_sha256=%s\n' \
  "$artifact_bytes" "$artifact_sha" "$wrapper_bytes" "$wrapper_sha"
