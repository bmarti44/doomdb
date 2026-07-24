#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
builder="$root/probes/mle/teavm-engine/build-tic0-checkpoint-bank.mjs"
table_pack="$root/client/dist/play/canonical-runtime-v2-058cd0df9444.bin"
iwad_zip="$root/vendor/freedoom/0.13.0/freedoom-0.13.0.zip"
authority="$root/client/dist/play/doom-mle-authority-e485b9418e58.js"
authority_sha256="$(shasum -a 256 "$authority" | awk '{print $1}')"
base64_fold_width=2000
emit_only=0
[[ "${1:-}" == "--emit-sql" ]] && emit_only=1
[[ $# -le 1 ]] || { printf 'usage: %s [--emit-sql]\n' "$0" >&2;exit 2; }

for tool in node unzip base64 fold shasum; do
  command -v "$tool" >/dev/null || { printf '%s is unavailable\n' "$tool" >&2;exit 2; }
done
test -s "$builder";test -s "$authority";test -s "$table_pack";test -s "$iwad_zip"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-tic0-bank.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
unzip -p "$iwad_zip" freedoom-0.13.0/freedoom1.wad >"$tmp/freedoom1.wad"
node "$builder" "$authority" "$tmp/freedoom1.wad" "$table_pack" "$tmp/bank" >&2

emit_sql() {
  printf '%s\n' \
    'whenever oserror exit failure rollback' \
    'whenever sqlerror exit sql.sqlcode rollback' \
    'set define off echo off verify off feedback off heading off pages 0 lines 32767 trimspool on serveroutput on size unlimited' \
    'delete from doom_mle_tic0_checkpoint;'
  local mode skill episode map players bytes sha state_sha filename file actual
  while IFS=$'\t' read -r mode skill episode map players bytes sha state_sha filename ||
      [[ -n "${mode:-}" ]]; do
    [[ "$mode" =~ ^(COOP|DEATHMATCH)$ ]]
    [[ "$skill" =~ ^[1-5]$ && "$episode" == 1 && "$map" == 1 && "$players" == 2 ]]
    [[ "$bytes" =~ ^[1-9][0-9]*$ ]]
    [[ "$sha" =~ ^[0-9a-f]{64}$ && "$state_sha" =~ ^[0-9a-f]{64}$ ]]
    [[ "$filename" =~ ^[a-z0-9-]+\.dmc1$ ]]
    file="$tmp/bank/$filename";test -s "$file"
    [[ "$(wc -c <"$file" | tr -d '[:space:]')" == "$bytes" ]]
    actual="$(shasum -a 256 "$file" | awk '{print $1}')";[[ "$actual" == "$sha" ]]
    printf "insert into doom_mle_tic0_checkpoint(game_mode,skill,episode,map,active_players,checkpoint_blob,checkpoint_bytes,checkpoint_sha256,state_sha256,authority_sha256) values('%s',%s,%s,%s,%s,empty_blob(),%s,'%s','%s','%s');\n" \
      "$mode" "$skill" "$episode" "$map" "$players" "$bytes" "$sha" \
      "$state_sha" "$authority_sha256"
    printf '%s\n' 'declare l_blob blob;l_raw raw(32767);begin'
    printf "select checkpoint_blob into l_blob from doom_mle_tic0_checkpoint where game_mode='%s' and skill=%s and episode=%s and map=%s and active_players=%s for update;\n" \
      "$mode" "$skill" "$episode" "$map" "$players"
    base64 <"$file" | tr -d '\r\n' | fold -w "$base64_fold_width" |
      while IFS= read -r piece || [[ -n "$piece" ]]; do
        printf "l_raw:=utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));\n" "$piece"
        printf '%s\n' 'dbms_lob.writeappend(l_blob,utl_raw.length(l_raw),l_raw);'
      done
    printf '%s\n' 'end;' '/'
  done <"$tmp/bank/manifest.tsv"
  printf '%s\n' \
    'declare l_bad number;begin' \
    'select count(*) into l_bad from doom_mle_tic0_checkpoint where' \
    '  dbms_lob.getlength(checkpoint_blob)<>checkpoint_bytes or' \
    '  lower(rawtohex(dbms_crypto.hash(checkpoint_blob,dbms_crypto.hash_sh256)))<>checkpoint_sha256 or' \
    "  authority_sha256<>'$authority_sha256';" \
    "if l_bad<>0 then raise_application_error(-20796,'tic-zero checkpoint staging mismatch rows='||l_bad);end if;" \
    'select count(*) into l_bad from doom_mle_tic0_checkpoint;' \
    "if l_bad<>10 then raise_application_error(-20796,'tic-zero checkpoint bank cardinality='||l_bad);end if;" \
    "dbms_output.put_line('PMLE_TIC0_BANK_STAGING|PASS|entries=10|authority_sha256=$authority_sha256');" \
    'commit;end;' '/'
}

if [[ "$emit_only" == 1 ]]; then emit_sql;exit 0;fi
output="$(mktemp "${TMPDIR:-/tmp}/doomdb-tic0-load.XXXXXX")"
trap 'rm -rf "$tmp";rm -f "$output"' EXIT HUP INT TERM
emit_sql | "$root/scripts/db_sql.sh" - >"$output"
cat "$output"
grep -q '^PMLE_TIC0_BANK_STAGING|PASS|entries=10|' "$output"
