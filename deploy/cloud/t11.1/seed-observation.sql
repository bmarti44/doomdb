whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off echo off feedback off heading off pagesize 0 linesize 32767 trimspool on serveroutput on size unlimited

-- The reviewed row signature is a SHA-256 chain over sorted canonical JSON rows.
-- It is intentionally identical for the fresh local measurement and cloud run.
declare
  procedure observe(p_id varchar2,p_query varchar2) is
    c integer; ignored integer; value clob; n number:=0;
    digest raw(32):=hextoraw(rpad('00',64,'0'));
  begin
    c:=dbms_sql.open_cursor; dbms_sql.parse(c,p_query,dbms_sql.native);
    dbms_sql.define_column(c,1,value); ignored:=dbms_sql.execute(c);
    while dbms_sql.fetch_rows(c)>0 loop
      dbms_sql.column_value(c,1,value); n:=n+1;
      digest:=dbms_crypto.hash(digest||dbms_crypto.hash(utl_raw.cast_to_raw(dbms_lob.substr(value,16000,1)),dbms_crypto.hash_sh256),dbms_crypto.hash_sh256);
    end loop;
    dbms_sql.close_cursor(c);
    if n=0 then raise_application_error(-20811,'empty seed domain '||p_id); end if;
    dbms_output.put_line('T111_SEED|'||p_id||'|'||n||'|'||lower(rawtohex(digest)));
  exception when others then if dbms_sql.is_open(c) then dbms_sql.close_cursor(c); end if; raise;
  end;
begin
  observe('wad_lumps',q'[select json_object(*) returning clob from doom_wad_source order by directory_index]');
  observe('vertexes',q'[select json_object(*) returning clob from doom_map_vertex order by vertex_id]');
  observe('linedefs',q'[select json_object(*) returning clob from doom_map_linedef order by linedef_id]');
  observe('sidedefs',q'[select json_object(*) returning clob from doom_map_sidedef order by sidedef_id]');
  observe('sectors',q'[select json_object(*) returning clob from doom_map_sector order by sector_id]');
  observe('things',q'[select json_object(*) returning clob from doom_map_thing order by thing_id]');
  observe('segs',q'[select json_object(*) returning clob from doom_map_seg order by seg_id]');
  observe('subsectors',q'[select json_object(*) returning clob from doom_map_ssector order by ssector_id]');
  observe('nodes',q'[select json_object(*) returning clob from doom_map_node order by node_id]');
  observe('reject_bytes',q'[select json_object(*) returning clob from doom_reject_byte order by byte_offset]');
  observe('blockmap_words',q'[select json_object(*) returning clob from doom_blockmap_byte order by byte_offset]');
  observe('playpal',q'[select json_object(*) returning clob from doom_palette_texel order by palette_index]');
  observe('colormap',q'[select json_object(*) returning clob from doom_colormap_texel order by map_index,palette_index]');
  observe('textures',q'[select json_object(*) returning clob from doom_asset where asset_kind in ('texture','flat') order by asset_kind,asset_name]');
  observe('patches',q'[select json_object(*) returning clob from doom_asset where asset_kind='patch' order by asset_name]');
  observe('sprites',q'[select json_object(*) returning clob from doom_sprite_rotation order by state_id,rotation]');
  observe('sounds',q'[select json_object('sound_id' value s.sound_id,'asset_id' value s.asset_id,'sample_rate' value s.sample_rate,'sample_count' value s.sample_count,'raw_sha256' value a.raw_sha256 returning clob) from doom_sound s join doom_asset a on a.asset_id=s.asset_id order by s.sound_id]');
  observe('music',q'[select json_object('music_id' value m.music_id,'asset_id' value m.asset_id,'media_type' value m.media_type,'raw_sha256' value a.raw_sha256 returning clob) from doom_music m join doom_asset a on a.asset_id=m.asset_id order by m.music_id]');
  observe('engine_states',q'[select json_object(*) returning clob from doom_state_def order by state_id]');
  observe('engine_actions',q'[select json_object('action_name' value action_name returning clob) from (select distinct action_name from doom_state_def where action_name is not null) order by action_name]');
  observe('engine_objects',q'[select json_object(*) returning clob from doom_thing_type_def order by thing_type]');
  observe('engine_weapons',q'[select json_object(*) returning clob from doom_weapon_def order by weapon_id]');
  observe('engine_specials',q'[select json_object(*) returning clob from doom_linedef_special_def order by special_id]');
  observe('engine_rng',q'[select json_object(*) returning clob from doom_rng_value order by rng_index]');
end;
/
exit success commit
