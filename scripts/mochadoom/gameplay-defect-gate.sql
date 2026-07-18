whenever sqlerror exit failure rollback
set serveroutput on feedback off heading off pages 0 lines 32767

declare
  l_status varchar2(4000);l_frame blob;l_previous_health number;
  l_health number;l_damage number;l_visible number;l_previous_visible number:=0;
  l_before_previous_visible number:=0;l_attacker varchar2(64);
  l_flash varchar2(64);l_weapon_state varchar2(64);l_audio varchar2(4000);
  l_damage_drops number:=0;l_unexplained_drops number:=0;
  l_sprite_dropouts number:=0;l_visible_tics number:=0;
  l_flash_tics number:=0;l_pistol_events number:=0;
  type state_set is table of boolean index by varchar2(64);
  l_weapon_states state_set;

  function field(p_status varchar2,p_name varchar2) return varchar2 is
    l_start pls_integer:=instr(p_status,'|'||p_name||'=');l_end pls_integer;
  begin
    if l_start=0 then raise_application_error(-20000,'missing '||p_name);end if;
    l_start:=l_start+length(p_name)+2;l_end:=instr(p_status,'|',l_start);
    return substr(p_status,l_start,
      case when l_end=0 then length(p_status)+1 else l_end end-l_start);
  end;
begin
  dbms_lob.createtemporary(l_frame,true,dbms_lob.call);
  l_status:=doom_mocha_new_game(2,1,1);
  for l_tic in 1..24 loop
    l_status:=doom_mocha_step_controls_frame(0,0,0,0,1,0,0,0,0,0,l_frame);
    l_weapon_state:=field(l_status,'weaponState');
    l_flash:=field(l_status,'flashState');
    l_audio:=field(l_status,'audioJson');
    l_weapon_states(l_weapon_state):=true;
    if l_flash<>'NONE' then l_flash_tics:=l_flash_tics+1;end if;
    if instr(l_audio,'"DSPISTOL"')>0 then l_pistol_events:=l_pistol_events+1;end if;
  end loop;
  if l_weapon_states.count<3 or l_flash_tics<1 or l_pistol_events<1 then
    raise_application_error(-20000,'weapon animation missing states='||
      l_weapon_states.count||' flashTics='||l_flash_tics||
      ' pistolEvents='||l_pistol_events);
  end if;

  l_status:=doom_mocha_new_game(2,1,1);
  l_previous_health:=null;
  for l_tic in 1..330 loop
    l_status:=doom_mocha_step_controls_frame(0,1,0,1,
      case when mod(l_tic-1,8)=0 then 1 else 0 end,0,0,0,0,0,l_frame);
    l_health:=to_number(field(l_status,'playerHealth'));
    l_damage:=to_number(field(l_status,'damageCount'));
    l_attacker:=field(l_status,'attacker');
    l_visible:=to_number(field(l_status,'visibleSprites'));
    if l_visible>0 then l_visible_tics:=l_visible_tics+1;end if;
    if l_before_previous_visible>0 and l_previous_visible=0 and l_visible>0 then
      l_sprite_dropouts:=l_sprite_dropouts+1;
    end if;
    if l_previous_health is not null and l_health<l_previous_health then
      l_damage_drops:=l_damage_drops+1;
      if l_damage<=0 or l_attacker='NONE' then
        l_unexplained_drops:=l_unexplained_drops+1;
      end if;
    end if;
    l_previous_health:=l_health;
    l_before_previous_visible:=l_previous_visible;
    l_previous_visible:=l_visible;
  end loop;
  if l_visible_tics<1 or l_sprite_dropouts<>0 then
    raise_application_error(-20000,'sprite continuity visibleTics='||
      l_visible_tics||' oneFrameDropouts='||l_sprite_dropouts);
  end if;
  if l_damage_drops<1 or l_unexplained_drops<>0 then
    raise_application_error(-20000,'damage causality drops='||l_damage_drops||
      ' unexplained='||l_unexplained_drops);
  end if;
  dbms_output.put_line('PASS MOCHADOOM-GAMEPLAY-DEFECTS weaponStates='||
    l_weapon_states.count||' flashTics='||l_flash_tics||
    ' pistolEventTics='||l_pistol_events||' visibleTics='||l_visible_tics||
    ' spriteDropouts='||l_sprite_dropouts||' damageDrops='||l_damage_drops||
    ' unexplainedDamage='||l_unexplained_drops||' finalHealth='||l_health);
  dbms_lob.freetemporary(l_frame);
  l_status:=doom_mocha_dispose;
exception when others then
  begin l_status:=doom_mocha_dispose;exception when others then null;end;
  raise;
end;
/
