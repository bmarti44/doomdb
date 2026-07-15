whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set serveroutput on size unlimited
set define off
alter session set nls_numeric_characters='.,';
alter session set nls_territory='AMERICA';
alter session set nls_language='AMERICAN';
alter session set time_zone='UTC';

declare
  l_count number;
  l_doc clob;
  l_line varchar2(32767);
  l_ss number; l_sector number; l_depth number; l_path varchar2(4000);
  procedure fail(p_message varchar2) is begin raise_application_error(-20933, p_message); end;
  procedure eq(p_actual number, p_expected number, p_name varchar2) is
  begin if p_actual is null or p_actual != p_expected then fail(p_name||' expected '||p_expected||' got '||nvl(to_char(p_actual),'NULL')); end if; end;
  procedure eqs(p_actual varchar2, p_expected varchar2, p_name varchar2) is
  begin if p_actual is null or p_actual != p_expected then fail(p_name||' mismatch'); end if; end;
  procedure locate(p_x number,p_y number,p_ss number,p_sector number,p_depth number,p_path varchar2,p_name varchar2) is
    a_ss number; a_sector number; a_depth number; a_path varchar2(4000);
  begin
    select ssector_id,sector_id,depth,path_signature into a_ss,a_sector,a_depth,a_path
      from table(doom_bsp_locate(p_x,p_y));
    eq(a_ss,p_ss,p_name||' subsector'); eq(a_sector,p_sector,p_name||' sector');
    eq(a_depth,p_depth,p_name||' depth'); eqs(a_path,p_path,p_name||' path');
  end;
  procedure side_case(p_x number,p_y number,p_nx number,p_ny number,p_dx number,p_dy number,p_expected number,p_name varchar2) is
    a_side number;
  begin
    select doom_bsp_side(p_x,p_y,p_nx,p_ny,p_dx,p_dy) into a_side from dual;
    eq(a_side,p_expected,p_name);
  end;
begin
  -- T33-MACRO-INTERFACE / T33-BIND-SAFETY
  select count(*) into l_count from user_objects where object_name='DOOM_BSP_LOCATE' and object_type='FUNCTION' and status='VALID';
  eq(l_count,1,'valid standalone macro');
  select count(*) into l_count from user_arguments where object_name='DOOM_BSP_LOCATE' and data_level=0 and argument_name in ('P_X','P_Y');
  eq(l_count,2,'bind arguments');
  locate(792,64.25,157,147,13,'680:0/453:0/187:1/186:1/185:1/184:1/183:0/176:0/168:0/167:0/166:0/155:0/154:0','fractional bind');

  -- T33-HAND-SIDE-CASES / T33-AXIS-TIE-SEMANTICS / T33-NONAXIS-CROSS
  side_case(10,0,10,4,0,8,1,'vertical positive tie');
  side_case(11,0,10,4,0,8,0,'vertical positive right');
  side_case(10,0,10,4,0,-8,0,'vertical negative tie');
  side_case(11,0,10,4,0,-8,1,'vertical negative right');
  side_case(0,4,3,4,8,0,0,'horizontal positive tie');
  side_case(0,5,3,4,8,0,1,'horizontal positive above');
  side_case(0,4,3,4,-8,0,1,'horizontal negative tie');
  side_case(0,5,3,4,-8,0,0,'horizontal negative above');
  side_case(2,0,0,0,4,4,0,'diagonal positive');
  side_case(0,2,0,0,4,4,1,'diagonal negative');
  side_case(0,0,0,0,4,4,1,'diagonal origin equality');
  side_case(7,7,0,0,4,4,1,'diagonal collinear equality');
  side_case(-2,0,0,0,-4,4,1,'mixed-sign negative');
  side_case(2,0,0,0,-4,4,0,'mixed-sign positive');

  -- T33-SPAWN-SECTOR-140
  locate(-416,256,115,140,8,'680:0/453:0/187:1/186:0/128:1/127:0/118:0/115:0','spawn');

  -- T33-BOUNDARY-PROBES / T33-OUTSIDE-COORDINATES
  locate(792,63,558,149,7,'680:1/679:0/590:0/564:1/563:0/558:0/555:1','root below');
  locate(792,64,558,149,7,'680:1/679:0/590:0/564:1/563:0/558:0/555:1','root equality');
  locate(792,65,157,147,13,'680:0/453:0/187:1/186:1/185:1/184:1/183:0/176:0/168:0/167:0/166:0/155:0/154:0','root above');
  locate(-10000,64,557,91,8,'680:1/679:0/590:0/564:1/563:0/558:0/555:0/554:1','far negative');
  locate(10000,64,647,134,8,'680:1/679:1/678:0/652:0/650:1/649:1/648:1/647:0','far positive');

  -- T33-ALL-THINGS-PROBES: compare every result, not a selected sample.
  dbms_lob.createtemporary(l_doc,true);
  l_count := 0;
  for t in (select thing_id,x,y from doom_map_thing order by thing_id) loop
    select ssector_id,sector_id,depth,path_signature into l_ss,l_sector,l_depth,l_path
      from table(doom_bsp_locate(t.x,t.y));
    l_line := to_char(t.thing_id,'FM9999990','NLS_NUMERIC_CHARACTERS=''.,''')||':'||
      to_char(t.x,'FM9999990','NLS_NUMERIC_CHARACTERS=''.,''')||':'||
      to_char(t.y,'FM9999990','NLS_NUMERIC_CHARACTERS=''.,''')||':'||
      to_char(l_ss,'FM9999990','NLS_NUMERIC_CHARACTERS=''.,''')||':'||
      to_char(l_sector,'FM9999990','NLS_NUMERIC_CHARACTERS=''.,''')||':'||
      to_char(l_depth,'FM9999990','NLS_NUMERIC_CHARACTERS=''.,''')||':'||l_path||chr(10);
    dbms_lob.writeappend(l_doc,length(l_line),l_line); l_count := l_count + 1;
  end loop;
  eq(l_count,292,'all THINGS discovered');
  eq(dbms_lob.getlength(l_doc),27158,'canonical probe document bytes');
  eqs(lower(rawtohex(dbms_crypto.hash(l_doc,dbms_crypto.hash_sh256))),
      '73d1f2d1c7cdc96737d4a9615ca0a8e43bdb67370a8ccce01e888e22c58c06ad','all THINGS digest');

  -- T33-DETERMINISTIC-PATH: the same bind must reproduce the same tuple.
  select ssector_id,sector_id,depth,path_signature into l_ss,l_sector,l_depth,l_path from table(doom_bsp_locate(-416,256));
  locate(-416,256,l_ss,l_sector,l_depth,l_path,'repeat spawn');
  dbms_lob.freetemporary(l_doc);
  dbms_output.put_line('PASS T3.3-ORACLE-PRODUCTION');
end;
/
