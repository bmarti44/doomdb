#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import inspector from 'node:inspector';

const modulePath=process.env.DOOMDB_MLE_PROFILE_MODULE ??
  '../../../client/dist/play/doom-mle-authority-e485b9418e58.js';
const iwadPath=process.env.DOOMDB_MLE_PROFILE_IWAD ??
  '../../../client/dist/play/freedoom1-7323bcc168c5.bin';
const tablePath=process.env.DOOMDB_MLE_PROFILE_TABLES ??
  '../../../client/dist/play/canonical-runtime-v2-058cd0df9444.bin';
const deathmatch=Number(process.env.DOOMDB_MLE_PROFILE_DEATHMATCH??1);
const skill=Number(process.env.DOOMDB_MLE_PROFILE_SKILL??3);
const episode=Number(process.env.DOOMDB_MLE_PROFILE_EPISODE??1);
const map=Number(process.env.DOOMDB_MLE_PROFILE_MAP??1);
const profileOutput=process.env.DOOMDB_MLE_PROFILE_OUTPUT;
const here=new URL('./',import.meta.url);
const resolve=value=>new URL(value,here);
const engine=await import(resolve(modulePath));
const iwad=fs.readFileSync(resolve(iwadPath));
const tables=fs.readFileSync(resolve(tablePath));
const input=fs.readFileSync(0,'utf8').trim().split(/\r?\n/).filter(Boolean);
const rows=input.map(line=>{
  const [ticText,membershipText,hex]=line.trim().split('|');
  assert.match(ticText??'',/^[1-9][0-9]*$/);
  assert.match(membershipText??'',/^[0-9]+$/);
  assert.match(hex??'',/^[0-9a-f]{64}$/);
  return {tic:Number(ticText),membership:Number(membershipText),
    commands:Uint8Array.from(Buffer.from(hex,'hex'))};
});
assert.ok(rows.length>0,'command stream is empty');
assert.equal(rows[0].tic,1,'command stream must begin at tic one');

function load(bytes,allocate,write) {
  assert.equal(allocate(bytes.length),bytes.length);
  for(let offset=0;offset<bytes.length;offset+=1024*1024) {
    const chunk=bytes.subarray(offset,Math.min(bytes.length,offset+1024*1024));
    assert.equal(write(offset,chunk),offset+chunk.length);
  }
}
load(iwad,engine.allocateIwad,engine.loadIwadChunk);
load(tables,engine.allocateTablePack,engine.loadTablePackChunk);
const initialized=engine.initializeMultiplayerGame(
  2,deathmatch,skill,episode,map);
assert.match(initialized,/state=multiplayer-initialized\|gametic=0\|/);

const samples=[];
const windows=[];
let inspectorSession;
const post=(method,parameters={})=>new Promise((resolve,reject)=>
  inspectorSession.post(method,parameters,(error,result)=>
    error===null ? resolve(result) : reject(error)));
if(profileOutput!==undefined) {
  inspectorSession=new inspector.Session();
  inspectorSession.connect();
  await post('Profiler.enable');
  await post('Profiler.start');
}
let windowStarted=performance.now();
for(const [index,row] of rows.entries()) {
  assert.equal(row.tic,index+1,'command stream has a tic gap');
  const started=performance.now();
  assert.equal(engine.stepMultiplayerAuthoritative(
    2,row.membership,row.commands),row.tic);
  samples.push(performance.now()-started);
  if(row.tic%100===0||index===rows.length-1) {
    const ended=performance.now();
    const memory=engine.memoryDiagnostic();
    windows.push({throughTic:row.tic,tics:row.tic-(windows.at(-1)?.throughTic??0),
      wallMs:ended-windowStarted,memory});
    // Exclude diagnostic construction from the next timing window. The
    // diagnostic is Node-only evidence for the awake-population scaling law;
    // it is never part of the authoritative MLE tic path.
    windowStarted=performance.now();
  }
}
const percentile=(values,fraction)=>{
  const sorted=values.toSorted((left,right)=>left-right);
  return sorted[Math.max(0,Math.ceil(sorted.length*fraction)-1)];
};
if(profileOutput!==undefined) {
  const {profile}=await post('Profiler.stop');
  inspectorSession.disconnect();
  fs.writeFileSync(profileOutput,JSON.stringify(profile));
}
process.stdout.write('PMLE_NODE_COMMAND_STREAM|PASS'
  +`|mode=${deathmatch===0?'COOP':'DEATHMATCH'}|tics=${rows.length}`
  +`|p50_ms=${percentile(samples,.5).toFixed(3)}`
  +`|p95_ms=${percentile(samples,.95).toFixed(3)}`
  +`|p99_ms=${percentile(samples,.99).toFixed(3)}`
  +`|max_ms=${Math.max(...samples).toFixed(3)}`
  +`|throughput_tps=${(rows.length*1000/samples.reduce(
    (sum,value)=>sum+value,0)).toFixed(3)}`
  +`${profileOutput===undefined?'':`|profile=${profileOutput}`}\n`);
for(const window of windows) {
  process.stdout.write(`PMLE_NODE_COMMAND_WINDOW|through_tic=${window.throughTic}`
    +`|tics=${window.tics}|wall_ms=${window.wallMs.toFixed(3)}`
    +`|tps=${(window.tics*1000/window.wallMs).toFixed(3)}`
    +`|${window.memory}\n`);
}
process.stdout.write(`PMLE_NODE_COMMAND_MEMORY|${engine.memoryDiagnostic()}\n`);
engine.release();
