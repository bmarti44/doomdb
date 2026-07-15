#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {decodeRle,encodeIndexedPng,decodeIndexedPng} from '../evaluator/t4.3/reference.mjs';
import {candidateDocuments,partitionCommands,sha256} from './t8.1-route-tools.mjs';

const HEX64=/^[0-9a-f]{64}$/;
const REQUIRED_EVIDENCE=[
  'state','counters','inventory','machines','objects','rng','history','events',
  'audio','pickups','combat',
];

function validatePayload(payload){
  assert.equal(payload.v,1,'response version');
  assert.ok(Number.isInteger(payload.tic)&&payload.tic>=0,'response tic');
  assert.equal(payload.w,320);assert.equal(payload.h,200);
  assert.match(payload.state_sha,HEX64,'state hash');
  assert.match(payload.frame_sha,HEX64,'frame hash');
  assert.ok(Array.isArray(payload.cols),'RLE columns');
  const pixels=decodeRle(payload.cols,320,200);
  assert.equal(sha256(pixels),payload.frame_sha,'frame hash must bind decoded pixels');
  assert.ok([0,1].includes(payload.complete),'completion flag');
  return pixels;
}

function validateEvidence(evidence,session,seq,payload){
  assert.equal(evidence.schema,1,'evidence schema');
  assert.equal(evidence.session,session,'evidence session');
  assert.equal(evidence.seq,seq,'evidence sequence');
  assert.equal(evidence.tic,payload.tic,'evidence tic');
  assert.equal(evidence.stateSha,payload.state_sha,'evidence state hash');
  assert.equal(evidence.frameSha,payload.frame_sha,'evidence frame hash');
  for(const key of REQUIRED_EVIDENCE)
    assert.ok(Object.hasOwn(evidence,key),`authoritative evidence missing ${key}`);
  assert.ok(Number.isInteger(evidence.counters.kills)&&evidence.counters.kills>=0);
  assert.ok(Number.isInteger(evidence.counters.items)&&evidence.counters.items>=0);
  assert.ok(Number.isInteger(evidence.counters.secrets)&&evidence.counters.secrets>=0);
  assert.equal(typeof evidence.mapStatus,'string');
  assert.ok([0,1].includes(evidence.complete));
}

async function captureMilestone({transport,palette,outDir,runId,milestone,session,payload}){
  const pixels=validatePayload(payload);
  const evidence=await transport.inspectMilestone({session,seq:milestone.seq,
    name:milestone.name,payload});
  validateEvidence(evidence,session,milestone.seq,payload);
  const png=encodeIndexedPng(pixels,palette,320,200);
  const decoded=decodeIndexedPng(png);
  assert.ok(decoded.pixels.equals(pixels),'PNG round trip');
  const pngSha=sha256(png);
  const milestoneDir=path.join(outDir,'runs',runId,'milestones');
  fs.mkdirSync(milestoneDir,{recursive:true});
  fs.writeFileSync(path.join(milestoneDir,`${milestone.name}.png`),png);
  return {name:milestone.name,seq:milestone.seq,tic:payload.tic,
    stateSha:payload.state_sha,frameSha:payload.frame_sha,pngSha,
    width:320,height:200,mapStatus:evidence.mapStatus,
    complete:evidence.complete,kills:evidence.counters.kills,
    items:evidence.counters.items,secrets:evidence.counters.secrets,evidence};
}

async function executeFresh({transport,docs,palette,outDir,runId,mode}){
  const started=await transport.newGame({skill:docs.fixture.skill,map:docs.fixture.map});
  assert.match(started.session,/^[0-9a-f]{32}$/,'opaque session token');
  const milestones=new Map(docs.milestones.map(row=>[row.seq,row]));
  const observations=[];
  observations.push(await captureMilestone({transport,palette,outDir,runId,
    milestone:milestones.get(0),session:started.session,payload:started.payload}));
  for(const batch of partitionCommands(docs.rows,docs.milestones,mode)){
    const payload=await transport.step({session:started.session,
      document:{v:1,commands:batch.commands}});
    if(milestones.has(batch.lastSeq))observations.push(await captureMilestone({
      transport,palette,outDir,runId,milestone:milestones.get(batch.lastSeq),
      session:started.session,payload}));
  }
  assert.deepEqual(observations.map(row=>row.name),docs.milestones.map(row=>row.name));
  return {runId,mode,session:started.session,milestones:observations,
    final:observations.at(-1)};
}

function comparable(run){return run.milestones.map(row=>({name:row.name,seq:row.seq,
  tic:row.tic,stateSha:row.stateSha,frameSha:row.frameSha,pngSha:row.pngSha,
  mapStatus:row.mapStatus,complete:row.complete,kills:row.kills,items:row.items,
  secrets:row.secrets}));}

async function executeReplay({transport,source,docs,palette,outDir}){
  const replayId=await transport.startReplay({session:source.session,fromTic:0,
    toTic:source.final.tic});
  assert.match(replayId,/^[0-9a-f]{32}$/,'opaque replay identifier');
  assert.equal(typeof transport.inspectReplayStart,'function',
    'adapter must inspect replay reconstruction at tic zero');
  const replayStart=await transport.inspectReplayStart({replayId,
    session:source.session,fromTic:0});
  assert.equal(replayStart.tic,source.milestones[0].tic,'replay start tic');
  assert.equal(replayStart.stateSha,source.milestones[0].stateSha,
    'replay start state');
  assert.equal(replayStart.frameSha,source.milestones[0].frameSha,
    'replay start frame');
  const byTic=new Map(source.milestones.map(row=>[row.tic,row]));
  const milestones=[{...source.milestones[0],evidence:{
    ...source.milestones[0].evidence,replayCursor:replayStart}}];
  for(let tic=1;tic<=source.final.tic;tic++){
    const payload=await transport.stepReplay({replayId});
    validatePayload(payload);
    if(byTic.has(tic)){
      const expected=byTic.get(tic);
      const row=await captureMilestone({transport,palette,outDir,runId:'replay',
        milestone:{name:expected.name,seq:expected.seq},session:source.session,payload});
      milestones.push(row);
    }
  }
  assert.deepEqual(comparable({...source,milestones}),comparable(source),
    'database replay milestone identity');
  return {runId:'replay',mode:'database-replay',session:source.session,milestones,
    final:milestones.at(-1)};
}

export async function captureRoute({root,transport,outDir,includeReplay=true}){
  const docs=candidateDocuments(root);
  const palette=await transport.getPalette();
  assert.equal(palette.length,256,'PLAYPAL entry count');
  const runs=[];
  for(const [runId,mode] of [['primary','max4'],['fresh-rerun','max4'],
    ['single','single'],['varied','varied']])
    runs.push(await executeFresh({transport,docs,palette,outDir,runId,mode}));
  for(const run of runs.slice(1))assert.deepEqual(comparable(run),comparable(runs[0]),
    `${run.runId} differs from primary`);
  if(includeReplay)runs.push(await executeReplay({transport,source:runs[0],docs,
    palette,outDir}));
  const final=runs[0].final;
  assert.equal(final.mapStatus,docs.fixture.completion.mapStatus);
  assert.equal(final.complete,docs.fixture.completion.complete);
  assert.ok(final.kills>=docs.fixture.completion.minimumKills);
  assert.ok(final.items>=docs.fixture.completion.minimumItems);
  assert.ok(final.secrets>=docs.fixture.completion.minimumSecrets);
  const ledger={schema:1,task:'T8.1',status:'CAPTURED_PENDING_INDEPENDENT_REVIEW',
    routeStatus:'CANDIDATE_NOT_APPROVED',map:docs.fixture.map,
    skill:docs.fixture.skill,commandCount:docs.rows.length,
    runs:runs.map(run=>({runId:run.runId,mode:run.mode,
      milestones:comparable(run)})),final:{mapStatus:final.mapStatus,
      complete:final.complete,kills:final.kills,items:final.items,
      secrets:final.secrets},review:{status:'PENDING_ACTUAL_ROUTE_AND_IMAGE_REVIEW',
      approvedScriptSha:null,approvedRouteSummarySha:null,
      goldenStateFrameHashes:[],screenshotHashes:[]}};
  fs.mkdirSync(outDir,{recursive:true});
  fs.writeFileSync(path.join(outDir,'state-frame-png-ledger.json'),
    `${JSON.stringify(ledger,null,2)}\n`);
  fs.writeFileSync(path.join(outDir,'authoritative-observations.json'),
    `${JSON.stringify({schema:1,status:'CAPTURED_PENDING_REVIEW',
      milestones:runs[0].milestones.map(row=>row.evidence)},null,2)}\n`);
  fs.writeFileSync(path.join(outDir,'png-ledger.json'),
    `${JSON.stringify({schema:1,status:'PENDING_ACTUAL_VISUAL_REVIEW',
      approvedScreenshotHashes:[],milestones:runs[0].milestones.map(row=>({
        name:row.name,seq:row.seq,width:row.width,height:row.height,
        frameSha:row.frameSha,pngSha:row.pngSha,
        relativePath:`runs/primary/milestones/${row.name}.png`,
        reviewStatus:'PENDING'}))},null,2)}\n`);
  fs.writeFileSync(path.join(outDir,'repeatability-ledger.json'),
    `${JSON.stringify({schema:1,status:'CAPTURED_PENDING_REVIEW',
      referenceRun:'primary',comparisons:runs.slice(1).map(run=>({
        runId:run.runId,mode:run.mode,milestoneCount:run.milestones.length,
        exactStateFramePngAndCounterMatch:true}))},null,2)}\n`);
  const summary=['# T8.1 captured candidate route','',
    'Status: CAPTURED — pending independent route and image review.','',
    `Commands: ${docs.rows.length}`,'',
    '| Milestone | Seq | Tic | Kills | Items | Secrets | Map status | Complete | State | Frame | PNG |',
    '|---|---:|---:|---:|---:|---:|---|---:|---|---|---|',
    ...runs[0].milestones.map(row=>`| ${row.name} | ${row.seq} | ${row.tic} | `+
      `${row.kills} | ${row.items} | ${row.secrets} | ${row.mapStatus} | `+
      `${row.complete} | ${row.stateSha} | ${row.frameSha} | ${row.pngSha} |`),
    '','All approval and golden fields remain empty until independent review.',''];
  fs.writeFileSync(path.join(outDir,'route-summary.md'),summary.join('\n'));
  return ledger;
}

if(process.argv[1]===fileURLToPath(import.meta.url)){
  const root=path.resolve(import.meta.dirname,'..');
  const adapterArg=process.argv[2];
  if(!adapterArg)throw new Error('usage: t8.1-capture-route.mjs <adapter.mjs> [output-dir]');
  const adapterPath=path.resolve(adapterArg);
  const module=await import(`${pathToFileURL(adapterPath).href}?v=${Date.now()}`);
  assert.equal(typeof module.createTransport,'function','adapter createTransport export');
  const transport=await module.createTransport({root});
  const outDir=process.argv[3]?path.resolve(process.argv[3]):
    path.join(root,'artifacts/t8.1-live-candidate');
  const ledger=await captureRoute({root,transport,outDir});
  process.stdout.write(`PASS T8.1-CANDIDATE-CAPTURE (${ledger.runs.length} `+
    `executions; ${ledger.commandCount} commands; review still pending)\n`);
}
