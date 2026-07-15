#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

export const T81_MANIFEST_SHA256='5d67fa78932123407f390208933cf18bd174604f91bbec73bd43d744d5b665c5';
export const MILESTONES=[
  'SPAWN','FIRST_RESOURCE','REPRESENTATIVE_FIGHT','KEY_ACQUIRED',
  'KEYED_DOOR_OPEN','LIFT_OPERATED','SECRET_FOUND','EXIT_TRIGGERED',
  'INTERMISSION',
];
export const COMMAND_KEYS=[
  'seq','turn','forward','strafe','run','fire','use','weapon','pause',
  'automap','menu','cheat',
];

export const sha256=value=>crypto.createHash('sha256').update(value).digest('hex');

function readJson(file){return JSON.parse(fs.readFileSync(file,'utf8'));}

export function loadFrozenCandidate(root){
  const manifestPath=path.join(root,'evaluator/integrity.pending-T8.1.json');
  assert.equal(sha256(fs.readFileSync(manifestPath)),T81_MANIFEST_SHA256,
    'T8.1 frozen manifest changed');
  const manifest=readJson(manifestPath);
  assert.equal(manifest.task,'T8.1-EVAL');
  for(const [relative,expected] of Object.entries(manifest.files)){
    assert.equal(sha256(fs.readFileSync(path.join(root,relative))),expected,
      `frozen evaluator file changed: ${relative}`);
  }
  const route=readJson(path.join(root,'evaluator/t8.1/route-candidate.json'));
  const fixture=readJson(path.join(root,'evaluator/t8.1/fixtures.json'));
  assert.equal(route.reviewStatus,'CANDIDATE_NOT_YET_PROVEN_OR_APPROVED');
  assert.equal(fixture.review.status,'PENDING');
  assert.equal(fixture.review.approvedScriptSha,null);
  assert.deepEqual(fixture.review.approvedMilestones,[]);
  assert.deepEqual(fixture.review.goldenStateFrameHashes,[]);
  assert.deepEqual(fixture.review.screenshotHashes,[]);
  return {manifest,route,fixture};
}

export function expandCandidate(route){
  let seq=1;
  const rows=[];
  route.runs.forEach((run,runIndex)=>{
    assert.ok(Number.isInteger(run.repeat)&&run.repeat>0,`run ${runIndex} repeat`);
    for(let offset=0;offset<run.repeat;offset++){
      const command={...route.defaults,...run.command,seq:seq++};
      assert.deepEqual(Object.keys(command).sort(),[...COMMAND_KEYS].sort(),
        `run ${runIndex} command keyset`);
      for(const key of ['turn','forward','strafe'])
        assert.ok([-1,0,1].includes(command[key]),`${key} range`);
      for(const key of ['run','fire','use','pause','automap'])
        assert.ok([0,1].includes(command[key]),`${key} boolean`);
      assert.ok(Number.isInteger(command.weapon)&&command.weapon>=0,'weapon range');
      assert.equal(command.menu,'NONE');
      assert.equal(command.cheat,'');
      rows.push({runIndex,label:run.label,offset,command});
    }
  });
  assert.equal(rows[0].command.seq,1);
  assert.equal(rows.at(-1).command.seq,rows.length);
  return rows;
}

export function milestonePlan(route,rows){
  const result=[];
  for(const name of MILESTONES){
    const runIndex=route.milestoneRuns[name];
    const inRun=rows.filter(row=>row.runIndex===runIndex);
    assert.ok(inRun.length,`milestone ${name} has no run`);
    result.push({name,seq:name==='SPAWN'?0:inRun.at(-1).command.seq,runIndex,
      runLabel:route.runs[runIndex].label});
  }
  assert.deepEqual(result.map(row=>row.name),MILESTONES);
  assert.ok(result.every((row,index)=>index===0||row.seq>result[index-1].seq));
  assert.equal(result.at(-1).seq,rows.length);
  return result;
}

export function routeRuns(route){
  let firstSeq=1;
  return route.runs.map((run,runIndex)=>{
    const lastSeq=firstSeq+run.repeat-1;
    const row={runIndex,label:run.label,firstSeq,lastSeq,repeat:run.repeat,
      command:{...route.defaults,...run.command}};
    firstSeq=lastSeq+1;
    return row;
  });
}

export function partitionCommands(rows,milestones,mode='max4'){
  const widths={single:[1],max4:[4],varied:[3,1,4,2]}[mode];
  assert.ok(widths,`unknown partition mode ${mode}`);
  const boundaries=new Set(milestones.map(row=>row.seq).filter(Boolean));
  const batches=[];
  let at=0,widthIndex=0;
  while(at<rows.length){
    let width=widths[widthIndex++%widths.length];
    const seq=rows[at].command.seq;
    for(const boundary of boundaries)
      if(boundary>=seq&&boundary<seq+width)width=boundary-seq+1;
    width=Math.min(width,4,rows.length-at);
    const commands=rows.slice(at,at+width).map(row=>row.command);
    assert.ok(commands.length>=1&&commands.length<=4);
    batches.push({firstSeq:commands[0].seq,lastSeq:commands.at(-1).seq,commands});
    at+=width;
  }
  assert.deepEqual(batches.flatMap(batch=>batch.commands),rows.map(row=>row.command));
  return batches;
}

export function candidateDocuments(root){
  const {route,fixture}=loadFrozenCandidate(root);
  const rows=expandCandidate(route);
  const milestones=milestonePlan(route,rows);
  const commands=rows.map(row=>row.command);
  const script={v:1,commands};
  const batches=Object.fromEntries(['single','max4','varied'].map(mode=>
    [mode,partitionCommands(rows,milestones,mode)]));
  const ledger={schema:1,task:'T8.1',status:'CANDIDATE_UNPROVEN_NOT_APPROVED',
    map:fixture.map,skill:fixture.skill,width:fixture.width,height:fixture.height,
    commandCount:commands.length,runs:routeRuns(route),milestones:milestones.map(
      milestone=>({...milestone,stateSha:null,frameSha:null,pngSha:null,
        observationStatus:'NOT_CAPTURED'})),
    final:{mapStatus:null,complete:null,kills:null,items:null,secrets:null},
    review:{status:'PENDING_ACTUAL_ROUTE_AND_IMAGE_REVIEW',approvedScriptSha:null,
      approvedRouteSummarySha:null,goldenStateFrameHashes:[],screenshotHashes:[]}};
  return {route,fixture,rows,milestones,script,batches,ledger,
    canonicalScriptText:JSON.stringify(script)};
}

export function writeCandidateArtifacts(root,outDir){
  const docs=candidateDocuments(root);
  fs.mkdirSync(outDir,{recursive:true});
  const write=(name,value)=>fs.writeFileSync(path.join(outDir,name),
    `${JSON.stringify(value,null,2)}\n`);
  write('candidate-command-script.json',docs.script);
  write('candidate-batch-plan.json',{schema:1,maxStepBatch:4,
    partitions:docs.batches});
  write('candidate-milestone-ledger.json',docs.ledger);
  const lines=['# T8.1 candidate route','',
    'Status: CANDIDATE — unproven, unapproved, and without goldens.','',
    `Commands: ${docs.rows.length}`,'','| Run | Label | Sequence span | Repeats |',
    '|---:|---|---:|---:|',...docs.ledger.runs.map(row=>
      `| ${row.runIndex} | ${row.label} | ${row.firstSeq}-${row.lastSeq} | ${row.repeat} |`),
    '','| Milestone | Sequence | Capture |','|---|---:|---|',
    ...docs.milestones.map(row=>`| ${row.name} | ${row.seq} | NOT CAPTURED |`),
    '','No state, frame, PNG, route-summary, or approval hash has been recorded.',''];
  fs.writeFileSync(path.join(outDir,'candidate-route-summary.md'),lines.join('\n'));
  return {commandCount:docs.rows.length,milestoneCount:docs.milestones.length,
    canonicalBytes:Buffer.byteLength(docs.canonicalScriptText)};
}

if(process.argv[1]===fileURLToPath(import.meta.url)){
  const root=path.resolve(import.meta.dirname,'..');
  const outArg=process.argv[2];
  const outDir=outArg?path.resolve(outArg):path.join(root,'artifacts/t8.1-candidate');
  const result=writeCandidateArtifacts(root,outDir);
  process.stdout.write(`PASS T8.1-CANDIDATE-MATERIALIZED (${result.commandCount} commands; `+
    `${result.milestoneCount} milestones; no approved goldens)\n`);
}
