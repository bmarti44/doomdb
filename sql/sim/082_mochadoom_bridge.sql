create or replace package doom_mocha_bridge authid definer as
  procedure create_lineage(
    p_session in varchar2,p_lineage in varchar2,p_skill in number,
    p_episode in number,p_map in number);

  procedure reconstruct(
    p_session in varchar2,p_lineage in varchar2,p_status out varchar2);

  procedure step(
    p_session in varchar2,p_lineage in varchar2,p_generation in number,
    p_expected_tic in number,p_command_seq in number,
    p_turn in number,p_forward in number,p_strafe in number,p_run in number,
    p_fire in number,p_use in number,p_weapon in number,p_pause in number,
    p_automap in number,p_menu in number,p_frame in blob,
    p_status out varchar2,p_ticcmd out raw,p_state_sha out varchar2,
    p_frame_sha out varchar2);
end doom_mocha_bridge;
/

create or replace package body doom_mocha_bridge as
  c_invalid constant pls_integer:=-20740;
  c_engine_revision constant varchar2(40):=
    'c0af1322ee5fd168b5cf8aaaf504cab2d1aabe93';

  function status_field(p_status varchar2,p_name varchar2) return varchar2 is
    l_start pls_integer:=instr(p_status,'|'||p_name||'=');
    l_end pls_integer;
  begin
    if l_start=0 then
      raise_application_error(c_invalid,'Mocha status missing '||p_name);
    end if;
    l_start:=l_start+length(p_name)+2;
    l_end:=instr(p_status,'|',l_start);
    return substr(p_status,l_start,
      case when l_end=0 then length(p_status)+1 else l_end end-l_start);
  end;

  procedure create_lineage(
    p_session in varchar2,p_lineage in varchar2,p_skill in number,
    p_episode in number,p_map in number
  ) is
    l_session_lineage varchar2(64);l_iwad_sha varchar2(64);
  begin
    select save_lineage into l_session_lineage from game_sessions
      where session_token=p_session for update;
    if l_session_lineage<>p_lineage or p_skill not between 1 and 5 or
       p_episode not between 1 and 9 or p_map not between 1 and 99 then
      raise_application_error(c_invalid,'invalid Mocha lineage root');
    end if;
    select payload_sha256 into l_iwad_sha from doom_engine_artifact
      where artifact_name='freedoom1.wad' and engine_revision=c_engine_revision;
    begin
      insert into doom_mocha_lineage(session_token,save_lineage,skill,episode,map,
        engine_revision,iwad_sha)
      values(p_session,p_lineage,p_skill,p_episode,p_map,c_engine_revision,l_iwad_sha);
    exception when dup_val_on_index then
      declare l_count number;begin
        select count(*) into l_count from doom_mocha_lineage
          where session_token=p_session and save_lineage=p_lineage
            and skill=p_skill and episode=p_episode and map=p_map
            and engine_revision=c_engine_revision and iwad_sha=l_iwad_sha;
        if l_count<>1 then
          raise_application_error(c_invalid,'conflicting Mocha lineage root');
        end if;
      end;
    end;
  exception when no_data_found then
    raise_application_error(c_invalid,'missing Mocha lineage dependency');
  end;

  procedure reconstruct(
    p_session in varchar2,p_lineage in varchar2,p_status out varchar2
  ) is
    l_skill number;l_episode number;l_map number;l_engine varchar2(40);
    l_iwad varchar2(64);l_live_iwad varchar2(64);l_expected_sha varchar2(64);
    l_commands blob;l_count number:=0;
  begin
    select skill,episode,map,engine_revision,iwad_sha
      into l_skill,l_episode,l_map,l_engine,l_iwad
      from doom_mocha_lineage where session_token=p_session
        and save_lineage=p_lineage;
    select payload_sha256 into l_live_iwad from doom_engine_artifact
      where artifact_name='freedoom1.wad' and engine_revision=c_engine_revision;
    if l_engine<>c_engine_revision or l_iwad<>l_live_iwad then
      raise_application_error(c_invalid,'Mocha replay dependency mismatch');
    end if;
    select count(*),max(frame_sha) keep(dense_rank last order by command_seq)
      into l_count,l_expected_sha from doom_mocha_command
      where session_token=p_session and save_lineage=p_lineage;
    if l_count=0 then
      p_status:=doom_mocha_new_game(l_skill-1,l_episode,l_map);
    else
      dbms_lob.createtemporary(l_commands,true,dbms_lob.call);
      for l_command in (
        select ticcmd_raw from doom_mocha_command
          where session_token=p_session and save_lineage=p_lineage
          order by command_seq
      ) loop
        dbms_lob.writeappend(l_commands,8,l_command.ticcmd_raw);
      end loop;
      p_status:=doom_mocha_reconstruct(
        l_skill-1,l_episode,l_map,l_commands,l_expected_sha);
      dbms_lob.freetemporary(l_commands);
    end if;
    if p_status not like 'ok|%' then
      raise_application_error(c_invalid,substr(p_status,1,1900));
    end if;
  exception when others then
    if l_commands is not null and dbms_lob.istemporary(l_commands)=1 then
      dbms_lob.freetemporary(l_commands);
    end if;
    raise;
  end;

  procedure step(
    p_session in varchar2,p_lineage in varchar2,p_generation in number,
    p_expected_tic in number,p_command_seq in number,
    p_turn in number,p_forward in number,p_strafe in number,p_run in number,
    p_fire in number,p_use in number,p_weapon in number,p_pause in number,
    p_automap in number,p_menu in number,p_frame in blob,
    p_status out varchar2,p_ticcmd out raw,p_state_sha out varchar2,
    p_frame_sha out varchar2
  ) is
    l_target varchar2(32);l_control_lineage varchar2(64);l_control_gen number;
    l_ready number;l_db_lineage varchar2(64);l_db_tic number;l_db_seq number;
    l_tic number;l_rng number;l_ticcmd_sha varchar2(64);
    l_previous_state_sha varchar2(64):=rpad('0',64,'0');
    l_audio_json varchar2(4000);l_audio_ordinal number:=0;
  begin
    if p_turn not between -1 and 1 or p_forward not between -1 and 1 or
       p_strafe not between -1 and 1 or p_run not in(0,1) or
       p_fire not in(0,1) or p_use not in(0,1) or p_weapon not between 0 and 9 or
       p_pause not in(0,1) or p_automap not in(0,1) or p_menu not in(0,1) or
       p_frame is null then
      raise_application_error(c_invalid,'invalid normalized Mocha command');
    end if;
    select target_session,target_lineage,generation,ready
      into l_target,l_control_lineage,l_control_gen,l_ready
      from doom_worker_control where target_session=p_session for update;
    if l_target<>p_session or l_control_lineage<>p_lineage or
       l_control_gen<>p_generation or l_ready<>1 then
      raise_application_error(c_invalid,'Mocha generation fence');
    end if;
    select save_lineage,current_tic,last_command_seq
      into l_db_lineage,l_db_tic,l_db_seq from game_sessions
      where session_token=p_session for update;
    if l_db_lineage<>p_lineage or l_db_tic<>p_expected_tic or
       p_command_seq<>l_db_seq+1 then
      raise_application_error(c_invalid,'Mocha frontier fence');
    end if;

    if l_db_seq>0 then
      -- The durable frontier already names the exact predecessor.  Scanning
      -- the full lineage for MAX(tic) on every step made a session
      -- progressively slower (quadratic work over a route).
      select state_sha
        into l_previous_state_sha from doom_mocha_command
        where session_token=p_session and save_lineage=p_lineage
          and command_seq=l_db_seq;
    end if;
    p_status:=doom_mocha_step_controls_payload(p_turn,p_forward,p_strafe,p_run,
      p_fire,p_use,p_weapon,p_pause,p_automap,p_menu,
      l_previous_state_sha,p_frame);
    if p_status not like 'ok|%' then
      raise_application_error(c_invalid,substr(p_status,1,1900));
    end if;
    p_ticcmd:=hextoraw(status_field(p_status,'commandHex'));
    p_state_sha:=status_field(p_status,'stateSha256');
    p_frame_sha:=status_field(p_status,'frameSha256');
    l_audio_json:=status_field(p_status,'audioJson');
    l_tic:=to_number(status_field(p_status,'tic'));
    l_rng:=to_number(status_field(p_status,'randomIndex'));
    if utl_raw.length(p_ticcmd)<>8 or l_tic<>p_expected_tic+1 or
       not regexp_like(p_state_sha,'^[0-9a-f]{64}$') or
       not regexp_like(p_frame_sha,'^[0-9a-f]{64}$') or l_rng not between 0 and 255 then
      raise_application_error(c_invalid,'Mocha result fence bytes='||
        utl_raw.length(p_ticcmd)||' tic='||l_tic||' expected='||
        (p_expected_tic+1)||' rng='||l_rng||' frame='||p_frame_sha);
    end if;
    select lower(rawtohex(standard_hash(p_ticcmd,'SHA256')))
      into l_ticcmd_sha from dual;
    insert into doom_mocha_command(session_token,save_lineage,command_seq,tic,
      generation,ticcmd_raw,ticcmd_sha,state_sha,frame_sha)
    values(p_session,p_lineage,p_command_seq,l_tic,p_generation,p_ticcmd,
      l_ticcmd_sha,p_state_sha,p_frame_sha);
    insert into tic_commands(session_token,lineage,command_seq,tic,command_ordinal,
      turn,forward_move,strafe,run,fire,use_action,weapon_slot,pause_toggle,
      automap_toggle,menu_action,cheat_code,command_sha)
    values(p_session,p_lineage,p_command_seq,l_tic,0,p_turn,p_forward,p_strafe,p_run,
      p_fire,p_use,p_weapon,p_pause,p_automap,
      case p_menu when 1 then 'OPTIONS' else 'NONE' end,null,l_ticcmd_sha);
    for l_audio in (
      select event_tic,event_ordinal,sound_id,volume,separation
        from json_table(l_audio_json,'$[*]' columns(
          event_tic number path '$[0]' error on error,
          event_ordinal number path '$[1]' error on error,
          sound_id varchar2(32) path '$[2]' error on error,
          volume number path '$[3]' error on error,
          separation number path '$[4]' error on error))
        order by event_ordinal
    ) loop
      if l_audio.event_tic<>l_tic or
         l_audio.event_ordinal<>l_audio_ordinal or
         l_audio.volume not between 0 and 255 or
         l_audio.separation not between 0 and 255 then
        raise_application_error(c_invalid,'Mocha audio event fence');
      end if;
      insert into audio_events(session_token,tic,event_ordinal,asset_kind,
        asset_name,volume,separation)
      values(p_session,l_tic,l_audio.event_ordinal,'sound',l_audio.sound_id,
        l_audio.volume,l_audio.separation);
      l_audio_ordinal:=l_audio_ordinal+1;
    end loop;
    update game_sessions set current_tic=l_tic,last_command_seq=p_command_seq,
      rng_cursor=l_rng where session_token=p_session
        and save_lineage=p_lineage and current_tic=p_expected_tic
        and last_command_seq=p_command_seq-1;
    if sql%rowcount<>1 then
      raise_application_error(c_invalid,'Mocha durable frontier race');
    end if;
  exception when no_data_found then
    raise_application_error(c_invalid,'Mocha worker ownership missing');
  end;
end doom_mocha_bridge;
/
