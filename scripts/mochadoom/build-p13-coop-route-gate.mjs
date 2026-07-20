#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const routeArg = process.argv.find(value => value.startsWith('--route='));
const routePath = routeArg?.slice(8) ??
  new URL('../../artifacts/t8.1-live/mocha-e1m1-skill3-route.json', import.meta.url);
const route = JSON.parse(fs.readFileSync(routePath));
assert.ok(Number.isInteger(route.commandCount) && route.commandCount > 0);
assert.ok(Number.isInteger(route.skill) && route.skill >= 1 && route.skill <= 5);
assert.equal(route.accepted?.mode, 'INTERMISSION');
const limitArg = process.argv.find(value => value.startsWith('--limit='));
const limit = limitArg ? Number(limitArg.slice(8)) : route.commandCount;
const guestLeaves = process.argv.includes('--guest-leaves');
assert.ok(Number.isInteger(limit) && limit > 0 && limit <= route.commandCount);

const byte = value => ((value % 256) + 256) % 256;
function ticcmd(command) {
  const forward = Math.abs(command.forward) > 1 ? command.forward :
    command.forward * (command.run ? 50 : 25);
  const side = Math.abs(command.strafe) > 1 ? command.strafe :
    command.strafe * (command.run ? 40 : 24);
  const turn = command.turn === 0 ? 0 : -Math.sign(command.turn) *
    (Math.abs(command.turn) > 1 ? Math.abs(command.turn) * 256 :
      (command.run ? 1280 : 320));
  const buttons = (command.fire ? 1 : 0) | (command.use ? 2 : 0) |
    (command.weapon > 0 ? 4 | ((command.weapon - 1) << 3) : 0);
  return [byte(forward), byte(side), (turn >> 8) & 255, turn & 255,
    0, 0, 0, buttons].map(value => value.toString(16).padStart(2, '0'))
    .join('').toUpperCase();
}

process.stdout.write(`whenever sqlerror exit failure rollback
set serveroutput on size unlimited feedback off verify off
declare
  m varchar2(32);h varchar2(64);j varchar2(64);p0 varchar2(64);p1 varchar2(64);
  s varchar2(32);slot number;gm varchar2(16);sk number;ep number;mp number;
  mx number;mc number;rc number;rq number;epoch number;gen number;tic number;
  accepted number;ready number;payload blob;job varchar2(64);seq number:=0;
  complete varchar2(2);err varchar2(2000);diag varchar2(4000);
  state_sha varchar2(64);frame_sha varchar2(64);
  procedure status_ is begin
    doom_api.match_status(m,h,s,gm,sk,ep,mp,mx,mc,rc,rq,epoch,gen,tic);end;
  procedure cleanup_ is begin
    if m is null then return;end if;
    begin select job_name,generation into job,gen from doom_match_worker_control where match_id=m;
      doom_match_worker.stop_match(m,gen);dbms_session.sleep(.2);
      begin dbms_scheduler.drop_job(job,true);exception when others then null;end;
    exception when no_data_found then null;end;
    delete from doom_match where match_id=m;commit;
  end;
begin
  doom_api.create_match('COOP',${route.skill},1,1,'ROUTE0',m,h,j,p0);p1:=null;
  doom_api.join_match(m,j,'ROUTE1',p1,slot);doom_api.ready_match(m,p0,1,s);
  doom_api.ready_match(m,p1,1,s);
  if s='STARTING' then for i in 1..1800 loop status_;exit when s='ACTIVE';
    dbms_session.sleep(.1);end loop;end if;status_;
  if s<>'ACTIVE' then raise_application_error(-20000,'co-op route start');end if;
  update doom_match_worker_control set route_diagnostics=1 where match_id=m;
  commit;
${guestLeaves ? "  doom_api.leave_match(m,p1,s);if s<>'ACTIVE' then raise_application_error(-20000,'guest leave');end if;\n" : ''}
`);
let remaining = limit;
for (const run of route.runs) {
  if (remaining === 0) break;
  const repeat = Math.min(run.repeat, remaining);
  remaining -= repeat;
  process.stdout.write(`  for z in 1..${repeat} loop seq:=seq+1;
    doom_match_worker.submit_command(m,0,epoch,gen,seq,seq,hextoraw('${ticcmd(run.command)}'),accepted);
    ${guestLeaves ? '' : "doom_match_worker.submit_command(m,1,epoch,gen,seq,seq,hextoraw('0000000000000000'),accepted);"}
    for q in 1..5000 loop doom_match_worker.poll_frame(m,0,epoch,gen,seq,ready,payload);
      exit when ready=1;dbms_session.sleep(.002);end loop;
    if ready<>1 then select last_error into err from doom_match_worker_control where match_id=m;
      raise_application_error(-20000,'co-op route timeout '||seq||' '||err);end if;
  end loop;
`);
}
process.stdout.write(`  status_;
  if tic<>${limit} then raise_application_error(-20000,'co-op route frontier');end if;
  select rawtohex(dbms_lob.substr(f.response_blob,1,10)),t.state_sha,f.frame_sha
    into complete,state_sha,frame_sha from doom_match_frame f join doom_match_tic t
      on t.match_id=f.match_id and t.tic=f.tic
    where f.match_id=m and f.tic=seq and f.player_slot=0;
`);
  if (limit === route.commandCount) {
  process.stdout.write(`  if complete<>'01' then
    raise_application_error(-20000,'co-op route did not reach intermission');end if;
  select job_name into job from doom_match_worker_control where match_id=m;
  begin dbms_scheduler.stop_job(job,true);exception when others then null;end;
  begin dbms_scheduler.drop_job(job,true);exception when others then null;end;
  doom_match_worker.recover_match(m,180000,s);status_;
  if s<>'ACTIVE' or tic<>seq then raise_application_error(-20000,'co-op route recovery');end if;
`);
}
process.stdout.write(`  select route_status into diag from doom_match_worker_control where match_id=m;
  dbms_output.put_line('PASS P13.3-COOP-ROUTE tic='||tic||
    ' complete='||complete||' stateSha='||state_sha||' frameSha='||frame_sha||
    ' diag='||diag);
  cleanup_;
exception when others then
  begin select route_status into diag from doom_match_worker_control where match_id=m;
    dbms_output.put_line('P13.3 diag='||diag);exception when others then null;end;
  begin select last_error into err from doom_match_worker_control where match_id=m;
    dbms_output.put_line('P13.3 worker='||err);exception when others then null;end;
  rollback;cleanup_;raise;
end;
/
`);
