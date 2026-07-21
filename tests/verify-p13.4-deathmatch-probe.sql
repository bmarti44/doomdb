whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  first_ varchar2(4000);second_ varchar2(4000);
  function field_(document_ varchar2,name_ varchar2) return varchar2 is
    marker_ varchar2(256):='|'||name_||'=';start_ pls_integer;finish_ pls_integer;
  begin
    start_:=instr(document_,marker_);
    if start_=0 then raise_application_error(-20000,'missing field '||name_);end if;
    start_:=start_+length(marker_);finish_:=instr(document_,'|',start_);
    if finish_=0 then finish_:=length(document_)+1;end if;
    return substr(document_,start_,finish_-start_);
  end;
  procedure equal_(actual_ varchar2,expected_ varchar2,label_ varchar2) is
  begin
    if actual_<>expected_ then raise_application_error(-20000,
      label_||' actual='||actual_||' expected='||expected_);end if;
  end;
begin
  first_:=doom_mocha_deathmatch_probe;second_:=doom_mocha_deathmatch_probe;
  if substr(first_,1,3)<>'ok|' or substr(second_,1,3)<>'ok|' then
    raise_application_error(-20000,'deathmatch probe failed '||first_||' '||second_);
  end if;
  equal_(field_(first_,'deathmatch'),'1','deathmatch mode');
  equal_(field_(first_,'frag'),'1','frag');
  equal_(field_(first_,'respawn'),'1','respawn');
  equal_(field_(first_,'simultaneousTie'),'1','simultaneous tie');
  equal_(field_(first_,'suicideDelta'),'1','suicide attribution');
  equal_(field_(first_,'limitIntermission'),'1','frag-limit intermission');
  equal_(field_(first_,'timeLimitTics'),'21000','time-limit duration');
  equal_(field_(first_,'timeLimitIntermission'),'1','time-limit intermission');
  if field_(first_,'spawn0')=field_(first_,'spawn1') then
    raise_application_error(-20000,'deathmatch starts collapsed');
  end if;
  equal_(second_,first_,'deathmatch clean-run determinism');
  dbms_output.put_line('PASS P13.4-DEATHMATCH-PROBE spawn/frag/respawn/tie/suicide/full-time-limit exact');
end;
/
