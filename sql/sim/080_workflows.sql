-- T8.2 database-owned presentation workflows. The owning STEP transaction
-- calls APPLY_CONTROL before gameplay and calls FINISH_TIC after gameplay.
-- This package never commits: rejection and every state change remain atomic
-- with the command/history row and frame authored by the STEP transaction.
create or replace package doom_workflow authid definer as
  procedure initialize_session(p_session in varchar2);

  procedure apply_control(
    p_session          in  varchar2,
    p_tic              in  number,
    p_pause_toggle     in  number,
    p_menu_action      in  varchar2,
    p_automap_toggle   in  number,
    p_cheat_code       in  varchar2,
    p_gameplay_enabled out number,
    p_branch_kind      out varchar2,
    p_branch_tic       out number);

  procedure finish_gameplay(p_session in varchar2,p_tic in number);
  procedure seal_terminal(
    p_session in varchar2,p_state_sha in varchar2,p_frame_sha in varchar2);
end doom_workflow;
/

create or replace package body doom_workflow as
  c_control_error constant pls_integer := -20881;

  procedure fail(p_message varchar2) is
  begin
    raise_application_error(c_control_error,p_message);
  end;

  procedure emit_control(
    p_session varchar2,p_tic number,p_type varchar2,p_value varchar2
  ) is
  begin
    insert into game_events(session_token,tic,event_ordinal,event_type,text_value)
    select p_session,p_tic,coalesce(max(event_ordinal)+1,0),p_type,p_value
      from game_events
     where session_token=p_session
       and lineage=(select save_lineage from game_sessions
                     where session_token=p_session)
       and tic=p_tic;
  end;

  function game_mode_for(p_automap varchar2) return varchar2 is
  begin
    return case when p_automap in ('NORMAL','FULL') then 'AUTOMAP' else 'GAME' end;
  end;

  procedure initialize_session(p_session in varchar2) is
  begin
    update game_sessions
       set menu_selection=0,god_mode=0,fullmap=0,workflow_generation=0,
           intermission_kills=null,intermission_items=null,
           intermission_secrets=null,intermission_time_tics=null,
           intermission_state_sha=null,intermission_frame_sha=null
     where session_token=p_session;
    if sql%rowcount<>1 then fail('unknown session');end if;
  end;

  procedure apply_control(
    p_session          in  varchar2,
    p_tic              in  number,
    p_pause_toggle     in  number,
    p_menu_action      in  varchar2,
    p_automap_toggle   in  number,
    p_cheat_code       in  varchar2,
    p_gameplay_enabled out number,
    p_branch_kind      out varchar2,
    p_branch_tic       out number
  ) is
    l_session game_sessions%rowtype;
    l_target number;
    l_weapon_mask number;
    l_bullet_cap number;l_shell_cap number;l_rocket_cap number;l_cell_cap number;
  begin
    p_gameplay_enabled:=0;p_branch_kind:=null;p_branch_tic:=null;
    begin
      select * into l_session from game_sessions
       where session_token=p_session for update;
    exception when no_data_found then fail('unknown session');end;

    if p_pause_toggle is null or p_pause_toggle not in (0,1)
       or p_automap_toggle is null or p_automap_toggle not in (0,1) then
      fail('invalid workflow toggle');
    end if;
    if p_menu_action is null
       or p_menu_action not in ('NONE','OPEN','DOWN','UP','SELECT','BACK','RESTART') then
      fail('unknown menu action');
    end if;
    if p_cheat_code is not null
       and p_cheat_code not in ('GOD','ALL','NOCLIP','FULLMAP')
       and not regexp_like(p_cheat_code,'^REWIND:(0|[1-9][0-9]*)$') then
      fail('unknown cheat');
    end if;
    if p_menu_action<>'NONE' and
       (p_pause_toggle=1 or p_automap_toggle=1 or p_cheat_code is not null) then
      fail('conflicting workflow controls');
    end if;

    if p_menu_action='RESTART' then
      if l_session.game_mode<>'DEAD' then fail('restart requires dead mode');end if;
      p_branch_kind:='RESTART';p_branch_tic:=0;
      emit_control(p_session,p_tic,'CONTROL_RESTART','0');
      return;
    elsif l_session.game_mode in ('DEAD','INTERMISSION') then
      -- Terminal modes append ordered commands/history but freeze gameplay.
      if p_pause_toggle<>0 or p_automap_toggle<>0
         or p_menu_action<>'NONE' or p_cheat_code is not null then
        fail('terminal workflow is frozen');
      end if;
      return;
    end if;

    if p_menu_action='OPEN' then
      if l_session.menu_state<>'NONE' then fail('menu already open');end if;
      update game_sessions set menu_state='MAIN:0',menu_selection=0,game_mode='MENU'
       where session_token=p_session;
      emit_control(p_session,p_tic,'CONTROL_MENU','MAIN:0');
    elsif p_menu_action in ('DOWN','UP') then
      if not regexp_like(l_session.menu_state,'^MAIN:[0-2]$') then
        fail('menu direction outside main menu');
      end if;
      l_session.menu_selection:=case p_menu_action when 'DOWN'
        then mod(l_session.menu_selection+1,3)
        else mod(l_session.menu_selection+2,3) end;
      update game_sessions set menu_selection=l_session.menu_selection,
        menu_state='MAIN:'||to_char(l_session.menu_selection,'TM9')
       where session_token=p_session;
      emit_control(p_session,p_tic,'CONTROL_MENU',
        'MAIN:'||to_char(l_session.menu_selection,'TM9'));
    elsif p_menu_action='SELECT' then
      if l_session.menu_state<>'MAIN:1' then fail('menu selection unavailable');end if;
      update game_sessions set menu_selection=0,menu_state='SKILL:0'
       where session_token=p_session;
      emit_control(p_session,p_tic,'CONTROL_MENU','SKILL:0');
    elsif p_menu_action='BACK' then
      if l_session.menu_state='NONE' then fail('menu is not open');end if;
      update game_sessions set menu_selection=0,menu_state='NONE',
        game_mode=game_mode_for(automap_state) where session_token=p_session;
      emit_control(p_session,p_tic,'CONTROL_MENU','NONE');
    end if;

    if p_pause_toggle=1 then
      update game_sessions set paused=1-paused where session_token=p_session;
      emit_control(p_session,p_tic,'CONTROL_PAUSE',to_char(1-l_session.paused,'TM9'));
      l_session.paused:=1-l_session.paused;
    end if;

    if p_automap_toggle=1 then
      if l_session.menu_state<>'NONE' then fail('automap unavailable in menu');end if;
      update game_sessions set fullmap=0,
        automap_state=case when automap_state='OFF' then 'NORMAL' else 'OFF' end,
        game_mode=case when automap_state='OFF' then 'AUTOMAP' else 'GAME' end
       where session_token=p_session;
      emit_control(p_session,p_tic,'CONTROL_AUTOMAP',
        case when l_session.automap_state='OFF' then 'NORMAL' else 'OFF' end);
      l_session.automap_state:=case when l_session.automap_state='OFF'
        then 'NORMAL' else 'OFF' end;
    end if;

    if p_cheat_code='GOD' then
      update game_sessions set god_mode=1-god_mode where session_token=p_session;
      emit_control(p_session,p_tic,'CONTROL_CHEAT','GOD');
    elsif p_cheat_code='NOCLIP' then
      update players set noclip=1-noclip where session_token=p_session
        and player_id=l_session.current_player_id;
      emit_control(p_session,p_tic,'CONTROL_CHEAT','NOCLIP');
    elsif p_cheat_code='FULLMAP' then
      if l_session.automap_state='OFF' then fail('full map requires automap');end if;
      update game_sessions set fullmap=1-fullmap,
        automap_state=case when fullmap=0 then 'FULL' else 'NORMAL' end,
        game_mode='AUTOMAP' where session_token=p_session;
      emit_control(p_session,p_tic,'CONTROL_CHEAT','FULLMAP');
    elsif p_cheat_code='ALL' then
      select coalesce(sum(power(2,slot_number-1)),0) into l_weapon_mask
        from doom_weapon_def where thing_type is null or thing_type in
          (select thing_type from doom_map_thing);
      select max(case ammo_type when 'BULLET' then normal_cap end),
             max(case ammo_type when 'SHELL' then normal_cap end),
             max(case ammo_type when 'ROCKET' then normal_cap end),
             max(case ammo_type when 'CELL' then normal_cap end)
        into l_bullet_cap,l_shell_cap,l_rocket_cap,l_cell_cap from doom_ammo_def;
      update players set blue_key=1,yellow_key=1,red_key=1,
        weapon_mask=l_weapon_mask,ammo_bullets=l_bullet_cap,
        ammo_shells=l_shell_cap,ammo_rockets=l_rocket_cap,ammo_cells=l_cell_cap
       where session_token=p_session and player_id=l_session.current_player_id;
      emit_control(p_session,p_tic,'CONTROL_CHEAT','ALL');
    elsif p_cheat_code like 'REWIND:%' then
      l_target:=to_number(substr(p_cheat_code,8));
      if l_target>=l_session.current_tic then fail('rewind target must be in history');end if;
      p_branch_kind:='REWIND';p_branch_tic:=l_target;
      emit_control(p_session,p_tic,'CONTROL_REWIND',to_char(l_target,'TM9'));
      return;
    end if;

    select * into l_session from game_sessions where session_token=p_session;
    p_gameplay_enabled:=case
      when l_session.paused=0 and l_session.menu_state='NONE'
       and p_menu_action='NONE'
       and l_session.game_mode not in ('DEAD','INTERMISSION') then 1 else 0 end;
  end;

  procedure finish_gameplay(p_session in varchar2,p_tic in number) is
    l_session game_sessions%rowtype;
    l_player players%rowtype;
  begin
    select * into l_session from game_sessions where session_token=p_session for update;
    select * into l_player from players where session_token=p_session
      and player_id=l_session.current_player_id;
    if l_player.alive=0 or l_player.health=0 then
      update game_sessions set game_mode='DEAD' where session_token=p_session;
    elsif l_session.map_status in ('COMPLETED','DONE') then
      update game_sessions set game_mode='INTERMISSION',map_status='DONE',
        intermission_kills=l_player.kill_count,
        intermission_items=l_player.item_count,
        intermission_secrets=l_player.secret_count,
        intermission_time_tics=p_tic,
        intermission_state_sha=null,intermission_frame_sha=null
       where session_token=p_session;
    end if;
  exception when no_data_found then fail('workflow state is incomplete');
  end;

  procedure seal_terminal(
    p_session in varchar2,p_state_sha in varchar2,p_frame_sha in varchar2
  ) is
  begin
    if not regexp_like(p_state_sha,'^[0-9a-f]{64}$')
       or not regexp_like(p_frame_sha,'^[0-9a-f]{64}$') then
      fail('terminal hashes are invalid');
    end if;
    update game_sessions set intermission_state_sha=p_state_sha,
      intermission_frame_sha=p_frame_sha
     where session_token=p_session and game_mode='INTERMISSION'
       and map_status='DONE';
    -- Nonterminal calls are deliberate no-ops; one integration hook can run
    -- after every rendered command without branching in the browser.
  end;
end doom_workflow;
/
