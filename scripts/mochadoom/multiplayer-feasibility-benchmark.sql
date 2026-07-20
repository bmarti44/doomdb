whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

-- Run only in an isolated SQL session after deploying the P13.0 adapter.
-- Each call constructs and disposes its own session-private engine.
declare
  output_ blob;
  result_ varchar2(4000);

  function field_(document_ varchar2,name_ varchar2) return number is
    marker_ varchar2(256):='|'||name_||'=';
    start_ pls_integer;
    finish_ pls_integer;
  begin
    start_:=instr(document_,marker_);
    if start_=0 then raise_application_error(-20000,'missing field '||name_);end if;
    start_:=start_+length(marker_);
    finish_:=instr(document_,'|',start_);
    if finish_=0 then finish_:=length(document_)+1;end if;
    return to_number(substr(document_,start_,finish_-start_));
  end;
begin
  dbms_lob.createtemporary(output_,true,dbms_lob.call);
  for players_ in 1..4 loop
    result_:=doom_mocha_multiplayer_benchmark(players_,300,35,output_);
    if substr(result_,1,3)<>'ok|' then
      raise_application_error(-20000,'multiplayer benchmark failed: '||result_);
    end if;
    if field_(result_,'players')<>players_ or
       field_(result_,'samples')<>300 or
       field_(result_,'tickerP95Micros')<0 or
       field_(result_,'totalP95Micros')<1 then
      raise_application_error(-20000,'invalid benchmark counters: '||result_);
    end if;
    for player_ in 0..players_-1 loop
      if field_(result_,'pov'||player_||'UniqueFrames')<2 or
         field_(result_,'pov'||player_||'RenderP95Micros')<0 or
         field_(result_,'pov'||player_||'CodecP95Micros')<0 or
         field_(result_,'pov'||player_||'BlobP95Micros')<0 then
        raise_application_error(-20000,'invalid POV counters: '||result_);
      end if;
    end loop;
    dbms_output.put_line('P13_0_MULTIPLAYER_BENCHMARK|'||result_);
  end loop;
  dbms_lob.freetemporary(output_);
  dbms_output.put_line('PASS P13.0-MULTIPLAYER-BENCHMARK 1/2/3/4 POV');
exception when others then
  if dbms_lob.istemporary(output_)=1 then dbms_lob.freetemporary(output_);end if;
  raise;
end;
/
