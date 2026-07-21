whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off

declare
  first_ varchar2(4000);
  second_ varchar2(4000);

  function field_(document_ varchar2,name_ varchar2) return varchar2 is
    marker_ varchar2(256):='|'||name_||'=';
    start_ pls_integer;
    finish_ pls_integer;
  begin
    start_:=instr(document_,marker_);
    if start_=0 then raise_application_error(-20000,'missing field '||name_);end if;
    start_:=start_+length(marker_);
    finish_:=instr(document_,'|',start_);
    if finish_=0 then finish_:=length(document_)+1;end if;
    return substr(document_,start_,finish_-start_);
  end;

  procedure equal_(actual_ varchar2,expected_ varchar2,label_ varchar2) is
  begin
    if actual_<>expected_ then
      raise_application_error(-20000,label_||' actual='||actual_||
        ' expected='||expected_);
    end if;
  end;
begin
  first_:=doom_mocha_multiplayer_probe;
  if substr(first_,1,3)<>'ok|' then
    raise_application_error(-20000,'first multiplayer probe failed: '||first_);
  end if;
  second_:=doom_mocha_multiplayer_probe;
  if substr(second_,1,3)<>'ok|' then
    raise_application_error(-20000,'second multiplayer probe failed: '||second_);
  end if;

  equal_(field_(first_,'membership'),'1100','membership bitmap');
  equal_(field_(first_,'netgame'),'1','netgame');
  equal_(field_(first_,'deathmatch'),'0','co-op mode');
  equal_(field_(first_,'playerMobjs'),'2','player mobj count');
  equal_(field_(first_,'ticDelta'),'1','one world tic');
  equal_(field_(first_,'levelTimeDelta'),'1','one level tic');
  equal_(field_(first_,'dead'),'1','shared damage/death');
  equal_(field_(first_,'fragDelta'),'1','frag attribution');
  equal_(field_(first_,'reborn'),'1','co-op reborn');
  equal_(field_(first_,'pickupWinner'),'0','pickup contention order');
  equal_(field_(first_,'sharedKey'),'1','netgame shared key');
  equal_(field_(first_,'simultaneousActions'),'1','simultaneous fire/use');
  equal_(field_(first_,'spatialAudio'),'1','per-listener spatial audio');
  if field_(first_,'command0')=field_(first_,'command1') then
    raise_application_error(-20000,'distinct slot commands collapsed');
  end if;
  if field_(first_,'pov0Sha')=field_(first_,'pov1Sha') then
    raise_application_error(-20000,'distinct POV hashes collapsed');
  end if;
  if not regexp_like(field_(first_,'pov0Sha'),'^[0-9a-f]{64}$') or
     not regexp_like(field_(first_,'pov1Sha'),'^[0-9a-f]{64}$') or
     not regexp_like(field_(first_,'renderStateSha'),'^[0-9a-f]{64}$') then
    raise_application_error(-20000,'malformed multiplayer hash');
  end if;
  if to_number(field_(first_,'pov0VisibleSprites'))<1 or
     to_number(field_(first_,'pov1VisibleSprites'))<1 then
    raise_application_error(-20000,'mutual sprite projection absent');
  end if;

  -- The probe is disposable and begins from the same pinned IWAD every time;
  -- exact output equality locks command order, state, POVs, combat, and reborn.
  equal_(second_,first_,'clean-run determinism');
  dbms_output.put_line('PASS P13.0-MULTIPLAYER-PROBE '||
    'pov0='||field_(first_,'pov0Sha')||' pov1='||field_(first_,'pov1Sha'));
end;
/
