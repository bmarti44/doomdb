whenever sqlerror exit failure rollback
set serveroutput on

declare
  l_session varchar2(32);l_payload blob;l_pack raw(32767);l_line number;
  l_count pls_integer;l_pos pls_integer;l_id pls_integer;l_on pls_integer;
  l_timer pls_integer;l_name_length pls_integer;l_name varchar2(32);
  l_expected_on pls_integer;l_expected_timer pls_integer;l_expected_name varchar2(32);
  l_seen pls_integer;
  function u8(p raw,n pls_integer)return pls_integer is
  begin return to_number(rawtohex(utl_raw.substr(p,n,1)),'XX');end;
  function u16(p raw,n pls_integer)return pls_integer is
  begin return to_number(rawtohex(utl_raw.substr(p,n,2)),'XXXX');end;
  function i32(p raw,n pls_integer)return pls_integer is
    v number;
  begin
    v:=to_number(rawtohex(utl_raw.substr(p,n,4)),'XXXXXXXX');
    return case when v>=2147483648 then v-4294967296 else v end;
  end;
  procedure assert_(p boolean,m varchar2) is
  begin if not p then raise_application_error(-20000,m);end if;end;
  procedure verify_(label varchar2) is
  begin
    doom_retained_switch_presentation.build(l_session,l_pack);
    assert_(rawtohex(utl_raw.substr(l_pack,1,6))='444D53560101',label||' header');
    l_count:=u16(l_pack,7);l_pos:=9;l_seen:=0;
    for i in 1..l_count loop
      l_id:=i32(l_pack,l_pos);l_on:=u8(l_pack,l_pos+4);l_timer:=i32(l_pack,l_pos+5);
      l_name_length:=u8(l_pack,l_pos+9);
      l_name:=utl_i18n.raw_to_char(utl_raw.substr(l_pack,l_pos+10,l_name_length),'AL32UTF8');
      select ls.switch_on,case when ls.switch_on=1 then sw.timer_tics else -1 end,
             coalesce(nullif(sd.middle_texture,'-'),nullif(sd.upper_texture,'-'),
                      nullif(sd.lower_texture,'-'),'NONE')
        into l_expected_on,l_expected_timer,l_expected_name
        from line_state ls join doom_map_linedef ml on ml.linedef_id=ls.linedef_id
        join doom_map_sidedef sd on sd.sidedef_id=ml.right_sidedef_id
        left join active_switches sw on sw.session_token=ls.session_token
          and sw.linedef_id=ls.linedef_id
       where ls.session_token=l_session and ls.linedef_id=l_id;
      assert_(l_on=l_expected_on and l_timer=l_expected_timer and l_name=l_expected_name,
        label||' relational byte parity line '||l_id);
      l_seen:=l_seen+1;l_pos:=l_pos+10+l_name_length;
    end loop;
    assert_(l_seen=l_count and l_pos=utl_raw.length(l_pack)+1,label||' exact length');
  end;
begin
  doom_api.new_game(3,l_session,l_payload);
  verify_('off');
  select min(ml.linedef_id) into l_line from doom_map_linedef ml
    join doom_map_sidedef sd on sd.sidedef_id=ml.right_sidedef_id
   where coalesce(nullif(sd.middle_texture,'-'),nullif(sd.upper_texture,'-'),
                  nullif(sd.lower_texture,'-'),'NONE') like 'SW1%';
  assert_(l_line is not null,'map has no metadata-derived switch line');
  update line_state set switch_on=1 where session_token=l_session and linedef_id=l_line;
  insert into active_switches(session_token,linedef_id,timer_tics,restore_texture)
    select l_session,l_line,35,
      coalesce(nullif(sd.middle_texture,'-'),nullif(sd.upper_texture,'-'),
               nullif(sd.lower_texture,'-'),'NONE')
      from doom_map_linedef ml join doom_map_sidedef sd
        on sd.sidedef_id=ml.right_sidedef_id where ml.linedef_id=l_line;
  verify_('on');
  update line_state set switch_on=0 where session_token=l_session and linedef_id=l_line;
  delete from active_switches where session_token=l_session and linedef_id=l_line;
  verify_('reset');
  delete from game_sessions where session_token=l_session;commit;
  dbms_output.put_line('RETAINED_SWITCH_PRESENTATION_CONTRACT_OK line='||l_line||
    ' rows='||l_count||' bytes='||utl_raw.length(l_pack));
exception when others then
  if l_session is not null then delete from game_sessions where session_token=l_session;commit;end if;
  raise;
end;
/
