#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';
import {captureRoute} from '../scripts/t8.1-capture-route.mjs';
import {candidateDocuments,partitionCommands,T81_MANIFEST_SHA256,
  writeCandidateArtifacts} from '../scripts/t8.1-route-tools.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
let checks=0;
const ok=(value,message)=>{assert.ok(value,message);checks++;};
const eq=(actual,expected,message)=>{assert.deepEqual(actual,expected,message);checks++;};
const docs=candidateDocuments(root);

eq(T81_MANIFEST_SHA256,
  '5d67fa78932123407f390208933cf18bd174604f91bbec73bd43d744d5b665c5',
  'frozen evaluator manifest');
eq(docs.rows.length,1393,'exact candidate command count');
eq(docs.milestones.map(row=>[row.name,row.seq]),[
  ['SPAWN',0],['FIRST_RESOURCE',137],['REPRESENTATIVE_FIGHT',165],
  ['KEY_ACQUIRED',376],['KEYED_DOOR_OPEN',544],['LIFT_OPERATED',831],
  ['SECRET_FOUND',1009],['EXIT_TRIGGERED',1323],['INTERMISSION',1393],
],'exact milestone plan');
eq(docs.script.commands.map(row=>row.seq),Array.from({length:1393},(_,i)=>i+1),
  'dense public sequence');
ok(docs.script.commands.every(command=>Object.keys(command).length===12),
  'strict command keyset');
ok(docs.script.commands.every(command=>command.cheat===''&&command.menu==='NONE'
  &&command.pause===0&&command.automap===0),'ordinary normal-game commands');
for(const mode of ['single','max4','varied']){
  const batches=partitionCommands(docs.rows,docs.milestones,mode);
  ok(batches.every(batch=>batch.commands.length>=1&&batch.commands.length<=4),
    `${mode} bounded batches`);
  eq(batches.flatMap(batch=>batch.commands),docs.script.commands,
    `${mode} exact stream`);
  ok(docs.milestones.slice(1).every(milestone=>
    batches.some(batch=>batch.lastSeq===milestone.seq)),`${mode} milestone boundary`);
}
eq(docs.ledger.review.approvedScriptSha,null,'no approved script hash');
eq(docs.ledger.review.approvedRouteSummarySha,null,'no approved summary hash');
eq(docs.ledger.review.goldenStateFrameHashes,[],'no state/frame goldens');
eq(docs.ledger.review.screenshotHashes,[],'no screenshot goldens');
ok(docs.ledger.milestones.every(row=>row.stateSha===null&&row.frameSha===null
  &&row.pngSha===null&&row.observationStatus==='NOT_CAPTURED'),
  'uncaptured milestone ledger fails closed');

const temp=fs.mkdtempSync(path.join(os.tmpdir(),'doomdb-t81-'));
try{
  const result=writeCandidateArtifacts(root,temp);
  eq(result.commandCount,1393,'materialized command count');
  eq(fs.readdirSync(temp).sort(),[
    'candidate-batch-plan.json','candidate-command-script.json',
    'candidate-milestone-ledger.json','candidate-route-summary.md',
  ],'materialized artifact set');
  const ledger=JSON.parse(fs.readFileSync(path.join(temp,
    'candidate-milestone-ledger.json'),'utf8'));
  eq(ledger.status,'CANDIDATE_UNPROVEN_NOT_APPROVED','candidate status');
  ok(!fs.readFileSync(path.join(temp,'candidate-route-summary.md'),'utf8')
    .includes('APPROVED'), 'summary does not claim approval');
}finally{fs.rmSync(temp,{recursive:true,force:true});}

const captureSource=fs.readFileSync(path.join(root,
  'scripts/t8.1-capture-route.mjs'),'utf8');
ok(captureSource.includes('inspectMilestone'),'authoritative inspection adapter required');
ok(captureSource.includes('START_REPLAY')===false,
  'runner does not embed database answers or SQL procedure bodies');
ok(!/approvedScriptSha:\s*['"][0-9a-f]/.test(captureSource),
  'runner cannot invent approved hashes');

// This in-memory adapter exercises orchestration only. Its deterministic unit
// hashes are deleted with the temporary directory and are never route goldens.
let nextSession=0;
const hash=text=>crypto.createHash('sha256').update(text).digest('hex');
const cols=Array.from({length:320},()=>[[0,200,0]]);
const payload=seq=>({v:1,tic:seq,w:320,h:200,state_sha:hash(`unit-state-${seq}`),
  frame_sha:hash(Buffer.alloc(64000)),cols,audio:[],complete:seq===1393?1:0});
const unitTransport={
  async getPalette(){return Array.from({length:256},(_,i)=>[i,i,i]);},
  async newGame(){return {session:(++nextSession).toString(16).padStart(32,'0'),
    payload:payload(0)};},
  async step({document}){return payload(document.commands.at(-1).seq);},
  async inspectMilestone({session,seq,payload:response}){return {schema:1,session,
    seq,tic:seq,stateSha:response.state_sha,frameSha:response.frame_sha,
    mapStatus:seq===1393?'INTERMISSION':'ACTIVE',complete:seq===1393?1:0,
    state:{unit:true},counters:{kills:seq===1393?3:0,items:seq===1393?2:0,
      secrets:seq===1393?1:0},inventory:{},machines:[],objects:[],rng:{},
    history:[],events:[],audio:[],pickups:[],combat:[]};},
};
const captureTemp=fs.mkdtempSync(path.join(os.tmpdir(),'doomdb-t81-capture-'));
try{
  const ledger=await captureRoute({root,transport:unitTransport,outDir:captureTemp,
    includeReplay:false});
  eq(ledger.runs.length,4,'fresh and partition execution count');
  ok(ledger.runs.every(run=>run.milestones.length===9),
    'all milestone ledgers complete');
  eq(ledger.review.approvedScriptSha,null,'capture remains unapproved');
  eq(fs.readdirSync(captureTemp).filter(name=>name.endsWith('.json')).sort(),[
    'authoritative-observations.json','png-ledger.json',
    'repeatability-ledger.json','state-frame-png-ledger.json',
  ],'capture ledger set');
  ok(fs.existsSync(path.join(captureTemp,'route-summary.md')),
    'captured review summary');
}finally{fs.rmSync(captureTemp,{recursive:true,force:true});}
process.stdout.write(`PASS T8.1-SOURCE-FIRST-UNIT (${checks}/${checks} assertions)\n`);
