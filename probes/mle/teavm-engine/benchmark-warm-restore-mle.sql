whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off heading off pagesize 0 linesize 32767

declare
  c_samples constant pls_integer := 3;
  l_checkpoint blob;
  l_expected_sha varchar2(64);
  l_status varchar2(32767);
  l_actual_sha varchar2(64);
  l_started timestamp;
  l_elapsed number;
  l_general_total number := 0;
  l_warm_total number := 0;

  function elapsed_ms(p_started timestamp) return number is
    l_delta interval day to second := localtimestamp-p_started;
  begin
    return extract(day from l_delta)*86400000
      +extract(hour from l_delta)*3600000
      +extract(minute from l_delta)*60000
      +extract(second from l_delta)*1000;
  end;

  procedure transfer_blob(p_blob blob,p_kind varchar2) is
    l_length pls_integer := dbms_lob.getlength(p_blob);
    l_offset pls_integer := 0;
    l_loaded number;
    l_chunk raw(32767);
  begin
    if p_kind='IWAD' then
      l_loaded:=doom_restore_ab_allocate(l_length);
    elsif p_kind='TABLE' then
      l_loaded:=doom_restore_ab_table_allocate(l_length);
    else
      l_loaded:=doom_restore_ab_restore_allocate(l_length);
    end if;
    if l_loaded<>l_length then
      raise_application_error(-20796,'warm restore A/B allocation mismatch');
    end if;
    while l_offset<l_length loop
      l_chunk:=dbms_lob.substr(
        p_blob,least(32767,l_length-l_offset),l_offset+1);
      if p_kind='IWAD' then
        l_loaded:=doom_restore_ab_load(l_offset,l_chunk);
      elsif p_kind='TABLE' then
        l_loaded:=doom_restore_ab_table_load(l_offset,l_chunk);
      else
        l_loaded:=doom_restore_ab_restore_load(l_offset,l_chunk);
      end if;
      l_offset:=l_offset+utl_raw.length(l_chunk);
      if l_loaded<>l_offset then
        raise_application_error(-20796,'warm restore A/B transfer mismatch');
      end if;
    end loop;
  end;

  procedure initialize_origin is
    l_wad blob;
    l_tables blob;
  begin
    begin doom_restore_ab_release;exception when others then null;end;
    select payload_bytes into l_wad from doom_engine_artifact
      where artifact_name='freedoom1.wad';
    select table_pack_blob into l_tables from doom_restore_ab_source;
    transfer_blob(l_wad,'IWAD');
    transfer_blob(l_tables,'TABLE');
    l_status:=doom_restore_ab_multi_init_game(2,0,3,1,1);
    if l_status not like 'state=multiplayer-initialized|gametic=0|%' then
      raise_application_error(-20796,'warm restore A/B initialization failed');
    end if;
    transfer_blob(l_checkpoint,'CHECKPOINT');
  end;

  procedure verify_restored(p_mode varchar2,p_sample number) is
  begin
    if l_status not like 'state=restored|gametic=0|%' then
      raise_application_error(-20796,'warm restore A/B status mismatch');
    end if;
    select lower(standard_hash(doom_restore_ab_canonical_state,'SHA256'))
      into l_actual_sha from dual;
    if l_actual_sha<>l_expected_sha then
      raise_application_error(-20796,'warm restore A/B canonical mismatch');
    end if;
    dbms_output.put_line('PMLE_WARM_RESTORE_AB_CELL|PASS|mode='||p_mode
      ||'|sample='||p_sample||'|restore_ms='
      ||to_char(l_elapsed,'FM999999990D000','NLS_NUMERIC_CHARACTERS=''.,''')
      ||'|canonical_sha256='||l_actual_sha);
  end;
begin
  select checkpoint_blob,state_sha256
    into l_checkpoint,l_expected_sha
    from doom_mle_tic0_checkpoint
    where game_mode='COOP' and skill=3 and episode=1 and map=1
      and active_players=2
      and authority_sha256=
        'e485b9418e5845b78e9e1593918d8bbb6f3c441c41a43cb8f3faf046e595148b';

  for sample in 1..c_samples loop
    initialize_origin;
    l_started:=localtimestamp;
    l_status:=doom_restore_ab_restore(0);
    l_elapsed:=elapsed_ms(l_started);
    l_general_total:=l_general_total+l_elapsed;
    verify_restored('general',sample);
  end loop;

  for sample in 1..c_samples loop
    initialize_origin;
    l_started:=localtimestamp;
    l_status:=doom_restore_ab_restore_warm(0);
    l_elapsed:=elapsed_ms(l_started);
    l_warm_total:=l_warm_total+l_elapsed;
    verify_restored('warm',sample);
  end loop;
  doom_restore_ab_release;
  dbms_output.put_line('PMLE_WARM_RESTORE_AB|PASS|samples='||c_samples
    ||'|general_mean_ms='
    ||to_char(l_general_total/c_samples,'FM999999990D000',
      'NLS_NUMERIC_CHARACTERS=''.,''')
    ||'|warm_mean_ms='
    ||to_char(l_warm_total/c_samples,'FM999999990D000',
      'NLS_NUMERIC_CHARACTERS=''.,''')
    ||'|speedup='
    ||to_char(l_general_total/l_warm_total,'FM999999990D000',
      'NLS_NUMERIC_CHARACTERS=''.,'''));
exception when others then
  begin doom_restore_ab_release;exception when others then null;end;
  raise;
end;
/
