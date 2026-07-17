whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off heading off timing on

declare
  type names_t is table of varchar2(128) index by pls_integer;
  names names_t;
  compiled number;
  missing number;
begin
  names(1):='DoomSimCatalogBench';
  names(2):='DoomPlayerMovementBench';
  names(3):='DoomCommonActorTickBench';
  names(4):='DoomCommonActorTickBench$Parser';
  names(5):='DoomActorWakeBench';
  names(6):='DoomActorWakeBench$Parser';
  names(7):='DoomRetainedLosBench';
  names(8):='DoomMonsterChaseBench';
  names(9):='DoomMonsterChaseBench$Parser';
  names(10):='DoomFreshDeathTickBench';
  names(11):='DoomFreshDeathTickBench$Parser';
  names(12):='DoomRetainedWorldStateBench';
  names(13):='DoomRetainedWorldStateBench$Cell';
  names(14):='DoomRetainedWorldStateBench$Column';
  names(15):='DoomRetainedWorldStateBench$State';
  names(16):='DoomRetainedWorldStateBench$TableState';
  names(17):='DoomRetainedRenderSceneBench';
  names(18):='DoomUnifiedActorStateBench';
  names(19):='DoomUnifiedActorStateBench$1';
  names(20):='DoomUnifiedActorStateBench$Owner';
  names(21):='DoomUnifiedActorStateBench$WorldMobjs';

  for i in 1..names.count loop
    compiled:=dbms_java.compile_class(names(i));
    dbms_output.put_line('OJVM_WORKER_COMPILED class='||names(i)||
      ' methods='||compiled);
  end loop;

  select count(*) into missing
    from user_java_methods m
   where m.name in(select column_value from table(sys.odcivarchar2list(
      'DoomSimCatalogBench','DoomPlayerMovementBench','DoomCommonActorTickBench',
      'DoomCommonActorTickBench$Parser','DoomActorWakeBench','DoomActorWakeBench$Parser',
      'DoomRetainedLosBench','DoomMonsterChaseBench','DoomMonsterChaseBench$Parser',
      'DoomFreshDeathTickBench','DoomFreshDeathTickBench$Parser',
      'DoomRetainedWorldStateBench','DoomRetainedWorldStateBench$Cell',
      'DoomRetainedWorldStateBench$Column','DoomRetainedWorldStateBench$State',
      'DoomRetainedWorldStateBench$TableState','DoomRetainedRenderSceneBench',
      'DoomUnifiedActorStateBench','DoomUnifiedActorStateBench$1',
      'DoomUnifiedActorStateBench$Owner','DoomUnifiedActorStateBench$WorldMobjs')))
     and m.is_compiled<>'YES' and m.method_name<>'<clinit>';
  if missing<>0 then raise_application_error(-20000,
    missing||' production OJVM worker methods are not compiled');end if;
end;
/

exit
