whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  out0_ blob;out1_ blob;out2_ blob;out3_ blob;
  initial_ varchar2(4000);stepped_ varchar2(4000);
  state0_ varchar2(64);state1_ varchar2(64);frame0_ varchar2(64);frame1_ varchar2(64);
  tic_ number;

  function field_(status_ varchar2,name_ varchar2) return varchar2 is
    start_ number:=instr(status_,'|'||name_||'=');stop_ number;
  begin
    if start_=0 then raise_application_error(-20000,'missing '||name_);end if;
    start_:=start_+length(name_)+2;stop_:=instr(status_,'|',start_);
    return substr(status_,start_,case when stop_=0 then length(status_)+1 else stop_ end-start_);
  end;

  procedure blobs_ is
  begin
    dbms_lob.createtemporary(out0_,true);dbms_lob.createtemporary(out1_,true);
    dbms_lob.createtemporary(out2_,true);dbms_lob.createtemporary(out3_,true);
  end;
begin
  blobs_;
  initial_:=doom_mocha_multiplayer_new_game(2,0,3,1,1,out0_,out1_,out2_,out3_);
  if initial_ not like 'ok|%' then raise_application_error(-20000,initial_);end if;
  state0_:=field_(initial_,'stateSha256');
  frame0_:=field_(initial_,'pov0FrameSha');frame1_:=field_(initial_,'pov1FrameSha');
  if field_(initial_,'membership')<>'1100' or field_(initial_,'tic')<>'0' or
     dbms_lob.getlength(out0_)<64000 or
     dbms_lob.getlength(out1_)<64000 or dbms_lob.getlength(out2_)<>0 or
     dbms_lob.getlength(out3_)<>0 then
    raise_application_error(-20000,'invalid initial multiplayer payloads');
  end if;
  -- Vanilla tic zero intentionally contains only the shared border/back screen;
  -- distinct world POVs begin with the first advanced gameplay tic.

  stepped_:=doom_mocha_multiplayer_step(2,3,
    '08000000000000000008010000000000'||rpad('0',32,'0'),
    state0_,out0_,out1_,out2_,out3_);
  if stepped_ not like 'ok|%' then raise_application_error(-20000,stepped_);end if;
  state1_:=field_(stepped_,'stateSha256');tic_:=to_number(field_(stepped_,'tic'));
  if tic_<>1 or state1_=state0_ or
     field_(stepped_,'pov0FrameSha')=field_(stepped_,'pov1FrameSha') or
     length(field_(stepped_,'commandVector'))<>64 then
    raise_application_error(-20000,'invalid multiplayer step payloads');
  end if;
  if lower(rawtohex(dbms_crypto.hash(out0_,dbms_crypto.hash_sh256)))<>
       field_(stepped_,'pov0ResponseSha') or
     lower(rawtohex(dbms_crypto.hash(out1_,dbms_crypto.hash_sh256)))<>
       field_(stepped_,'pov1ResponseSha') then
    raise_application_error(-20000,'response SHA mismatch');
  end if;
  if doom_mocha_dispose not like 'ok|%' then
    raise_application_error(-20000,'dispose failed');
  end if;
  dbms_output.put_line('PASS P13.2-MULTIPLAYER-ADAPTER-LIVE tic=1 membership=1100 distinctPOVs=1');
exception when others then
  begin if doom_mocha_dispose is null then null;end if;exception when others then null;end;
  raise;
end;
/
