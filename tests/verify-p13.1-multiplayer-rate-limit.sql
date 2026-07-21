whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  type id_list is table of varchar2(32) index by pls_integer;
  created_ id_list;
  initial_recent_ number;
  attempts_ number;
  match_ varchar2(32);host_ varchar2(64);join_ varchar2(64);player_ varchar2(64);
  rejected_code_ number:=0;

  procedure cleanup_ is
  begin
    for i in 1..created_.count loop
      delete from doom_match where match_id=created_(i);
    end loop;
    commit;
  end;
begin
  select count(*) into initial_recent_ from doom_match
    where created_at>(localtimestamp at time zone 'UTC')-interval '1' minute;
  attempts_:=greatest(0,16-initial_recent_);

  for i in 1..attempts_ loop
    doom_api.create_match('COOP',3,1,1,'RATE BOUNDARY',
      match_,host_,join_,player_);
    created_(i):=match_;
  end loop;

  begin
    doom_api.create_match('COOP',3,1,1,'RATE REJECT',
      match_,host_,join_,player_);
  exception when others then
    rejected_code_:=sqlcode;
  end;
  if rejected_code_<>-20702 then
    raise_application_error(-20000,
      'create burst boundary returned '||rejected_code_||' instead of -20702');
  end if;

  cleanup_;
  dbms_output.put_line('PASS P13.1-MULTIPLAYER-RATE-LIMIT live 16/minute create boundary; join bounded by two-slot capacity');
exception when others then
  rollback;
  cleanup_;
  raise;
end;
/
