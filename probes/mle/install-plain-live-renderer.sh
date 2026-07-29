#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_file="$root/probes/mle/free-live-renderer.mjs"
pack_file="$root/probes/mle/target/free-live-renderer/free-live-render.pack"
asset_dir="$root/probes/mle/target/free-live-renderer/assets-v1"
wall_file="$asset_dir/wall_texture.bin"
flat_file="$asset_dir/flat.bin"
[[ "${1:-}" == --emit-sql && "$#" == 1 ]] || {
  printf 'usage: %s --emit-sql\n' "$0" >&2;exit 2; }
for file in "$source_file" "$pack_file" "$wall_file" "$flat_file"; do
  [[ -s "$file" && ! -L "$file" ]] || exit 2
done

sha() { shasum -a 256 "$1" | awk '{print $1}'; }
bytes() { wc -c <"$1" | tr -d '[:space:]'; }
source_sha="$(sha "$source_file")"; source_bytes="$(bytes "$source_file")"
pack_sha="$(sha "$pack_file")"; pack_bytes="$(bytes "$pack_file")"
wall_sha="$(sha "$wall_file")"; wall_bytes="$(bytes "$wall_file")"
flat_sha="$(sha "$flat_file")"; flat_bytes="$(bytes "$flat_file")"

emit_blob() {
  local file="$1" target="$2"
  base64 <"$file" | tr -d '\r\n' | fold -w 2000 |
    while IFS= read -r piece || [[ -n "$piece" ]]; do
      printf "l_raw:=utl_encode.base64_decode(utl_raw.cast_to_raw('%s'));\n" \
        "$piece"
      printf 'dbms_lob.writeappend(%s,utl_raw.length(l_raw),l_raw);\n' "$target"
    done
}

cat <<'SQL'
whenever oserror exit failure rollback
whenever sqlerror exit sql.sqlcode rollback
set define off echo off verify off feedback off heading off pages 0 lines 32767
set serveroutput on size unlimited
begin execute immediate 'drop mle module doom_plain_live_renderer';exception when others then if sqlcode not in(-4080,-4103) then raise;end if;end;
/
begin execute immediate 'drop table doom_plain_renderer_source purge';exception when others then if sqlcode<>-942 then raise;end if;end;
/
SQL
cat <<SQL
create table doom_plain_renderer_source(
  source_blob blob not null,pack_blob blob not null,
  wall_blob blob not null,flat_blob blob not null,
  source_bytes number not null,source_sha varchar2(64) not null,
  pack_bytes number not null,pack_sha varchar2(64) not null,
  wall_bytes number not null,wall_sha varchar2(64) not null,
  flat_bytes number not null,flat_sha varchar2(64) not null);
insert into doom_plain_renderer_source values(
  empty_blob(),empty_blob(),empty_blob(),empty_blob(),
  $source_bytes,'$source_sha',$pack_bytes,'$pack_sha',
  $wall_bytes,'$wall_sha',$flat_bytes,'$flat_sha');
declare l_source blob;l_pack blob;l_wall blob;l_flat blob;
  l_raw raw(32767);
begin
  select source_blob,pack_blob,wall_blob,flat_blob
    into l_source,l_pack,l_wall,l_flat
    from doom_plain_renderer_source for update;
SQL
emit_blob "$source_file" l_source
emit_blob "$pack_file" l_pack
emit_blob "$wall_file" l_wall
emit_blob "$flat_file" l_flat
cat <<SQL
end;
/
declare l_count number;begin
  select count(*) into l_count from doom_plain_renderer_source
   where dbms_lob.getlength(source_blob)=source_bytes
     and lower(rawtohex(dbms_crypto.hash(
       source_blob,dbms_crypto.hash_sh256)))=source_sha
     and dbms_lob.getlength(pack_blob)=pack_bytes
     and lower(rawtohex(dbms_crypto.hash(
       pack_blob,dbms_crypto.hash_sh256)))=pack_sha
     and dbms_lob.getlength(wall_blob)=wall_bytes
     and lower(rawtohex(dbms_crypto.hash(
       wall_blob,dbms_crypto.hash_sh256)))=wall_sha
     and dbms_lob.getlength(flat_blob)=flat_bytes
     and lower(rawtohex(dbms_crypto.hash(
       flat_blob,dbms_crypto.hash_sh256)))=flat_sha;
  if l_count<>1 then
    raise_application_error(-20796,'plain renderer staging mismatch');
  end if;
  dbms_output.put_line(
    'PMLE_PLAIN_RENDERER_STAGING|PASS'||
    '|source_bytes=$source_bytes|source_sha256=$source_sha'||
    '|pack_bytes=$pack_bytes|pack_sha256=$pack_sha'||
    '|wall_bytes=$wall_bytes|wall_sha256=$wall_sha'||
    '|flat_bytes=$flat_bytes|flat_sha256=$flat_sha');
end;
/
create mle module doom_plain_live_renderer language javascript using blob
  (select source_blob from doom_plain_renderer_source);
/
commit;
SQL
