import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {canonicalSha, decodeE1M1, pointSide} from './reference.mjs';

const root = path.resolve(import.meta.dirname, '../..');
const load = (name) => JSON.parse(fs.readFileSync(path.join(import.meta.dirname,name),'utf8'));
const expected=load('expectations.json'), manifest=load('test-ids.json'), mutations=load('mutation-specs.json');
let checks=0;
const check=(value,message)=>{assert.ok(value,message);checks++;};
const equal=(actual,wanted,message)=>{assert.equal(actual,wanted,message);checks++;};
const deep=(actual,wanted,message)=>{assert.deepEqual(actual,wanted,message);checks++;};
const sha=(file)=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

equal(manifest.tests.length,15,'stable test-id count');
equal(new Set(manifest.tests.map(t=>t.id)).size,15,'duplicate test id');
equal(manifest.tests.reduce((n,t)=>n+t.assertions,0),455,'declared assertion sum');
equal(manifest.declaredAssertions,455,'manifest assertion total');
check(manifest.tests.every(t=>/^T33-[A-Z0-9-]+$/.test(t.id)),'unstable test-id format');
check(manifest.tests.every(t=>t.intent.length>=50),'weak test intent');
equal(mutations.mutations.length,15,'mutation count');
equal(new Set(mutations.mutations.map(m=>m.id)).size,15,'duplicate mutation id');
check(mutations.mutations.every(m=>manifest.tests.some(t=>t.id===m.killedBy)),'mutation lacks named kill test');
check(mutations.mutations.every(m=>m.change.length>=55&&m.reason.length>=50),'underspecified mutation');

equal(expected.handSideCases.length,14,'hand side case count');
for(const test of expected.handSideCases) {
  const [x,y]=test.point,[nx,ny,dx,dy]=test.node;
  equal(pointSide(x,y,{x:nx,y:ny,dx,dy}),test.side,`hand case ${test.name}`);
}
check(expected.handSideCases.some(t=>t.name.includes('vertical-positive')),'positive vertical absent');
check(expected.handSideCases.some(t=>t.name.includes('vertical-negative')),'negative vertical absent');
check(expected.handSideCases.some(t=>t.name.includes('horizontal-positive')),'positive horizontal absent');
check(expected.handSideCases.some(t=>t.name.includes('horizontal-negative')),'negative horizontal absent');
equal(expected.handSideCases.filter(t=>t.name.includes('equality')).length,2,'non-axis equality count');

const scratch2=fs.mkdtempSync(path.join(os.tmpdir(),'doom-t33-wad-'));
try {
  const unzip=spawnSync('unzip',['-q',path.join(root,'vendor/freedoom/0.13.0/freedoom-0.13.0.zip'),'freedoom-0.13.0/freedoom1.wad','-d',scratch2]);
  equal(unzip.status,0,'second independent extraction');
  const map=decodeE1M1(fs.readFileSync(path.join(scratch2,'freedoom-0.13.0/freedoom1.wad'))), rootNode=map.nodes.at(-1);
  equal(map.things.length,expected.counts.things,'THING count');
  equal(map.nodes.length,expected.counts.nodes,'NODE count');
  equal(map.ssectors.length,expected.counts.ssectors,'SSECTOR count');
  deep({nodeId:rootNode.id,x:rootNode.x,y:rootNode.y,dx:rootNode.dx,dy:rootNode.dy},expected.root,'root fields');
  deep({x:expected.fractionalBindProbe.x,y:expected.fractionalBindProbe.y,...map.locate(expected.fractionalBindProbe.x,expected.fractionalBindProbe.y)},expected.fractionalBindProbe,'fractional bind probe');
  const spawn=map.things[expected.spawn.thingId], located=map.locate(spawn.x,spawn.y);
  deep({thingId:spawn.id,x:spawn.x,y:spawn.y,...located},expected.spawn,'spawn location');
  for(const probe of expected.boundaryProbes) deep({x:probe.x,y:probe.y,...map.locate(probe.x,probe.y)},probe,`boundary ${probe.x},${probe.y}`);
  const locations=map.things.map(t=>({thing:t,location:map.locate(t.x,t.y)}));
  const document=locations.map(({thing:t,location:l})=>`${t.id}:${t.x}:${t.y}:${l.ssector}:${l.sector}:${l.depth}:${l.pathSignature}\n`).join('');
  equal(Buffer.byteLength(document),expected.thingProbeDocument.bytes,'all-THING document bytes');
  equal(crypto.createHash('sha256').update(document).digest('hex'),expected.thingProbeDocument.sha256,'all-THING document hash');
  equal(Math.min(...locations.map(r=>r.location.depth)),expected.thingProbeDocument.minimumDepth,'minimum path depth');
  equal(Math.max(...locations.map(r=>r.location.depth)),expected.thingProbeDocument.maximumDepth,'maximum path depth');
  equal(canonicalSha(locations.map(r=>r.location)),canonicalSha(locations.map(r=>map.locate(r.thing.x,r.thing.y))),'repeat determinism');
} finally { fs.rmSync(scratch2,{recursive:true,force:true}); }

const oracle=fs.readFileSync(path.join(import.meta.dirname,'oracle-production.sql'),'utf8').toUpperCase();
const audit=fs.readFileSync(path.join(import.meta.dirname,'source-audit.mjs'),'utf8');
check(oracle.includes('TABLE(DOOM_BSP_LOCATE(P_X,P_Y))'),'live bind call absent');
check(oracle.includes('FOR T IN (SELECT THING_ID,X,Y FROM DOOM_MAP_THING ORDER BY THING_ID)'),'ordered all-THING loop absent');
check(oracle.includes('DBMS_CRYPTO.HASH_SH256'),'named SHA-256 constant absent');
check(oracle.includes(expected.thingProbeDocument.sha256.toUpperCase()),'independent all-THING hash absent');
check((oracle.match(/LOCATE\(/g)??[]).length>=8,'live boundary probes absent');
equal((oracle.match(/SIDE_CASE\(/g)??[]).length,15,'live hand-case procedure and calls');
check(audit.includes("'CONNECT BY'"),'CONNECT BY audit absent');
check(audit.includes('fixture coordinate embedded'),'fixture-source guard absent');
check(audit.includes('procedural BSP traversal'),'procedural traversal guard absent');

const baselines=[
  ['evaluator/integrity.json','2699e0e0f6e93593d8172ea19a048d2ad6ebabb57aef2604a81782c25f2882a3'],
  ['evaluator/integrity.pending-T2.2.json','23ca7de9b0a78fe6697350911ac0800f48c9fbd9b6851daed6d10cb982b1b04b'],
  ['evaluator/integrity.pending-T2.3.json','3f13e8dcc3294a0efa096365d3fcd7c70b043da3ff4734e912044878b140add9'],
  ['evaluator/integrity.pending-T2.4.json','7bf6d81695ff3b7085f70107b1925e3aaf72587ead46cd096cdbd6e79e0d9354'],
  ['evaluator/integrity.pending-T3.2.json','d617cdd9e5f8a36606d6606d6c61a514f46b3b5545f4526e48361a1c04208050']
];
for(const [file,hash] of baselines) equal(sha(path.join(root,file)),hash,`${file} changed`);
process.stdout.write(`PASS T3.3-EVAL-SELF-CHECK (${checks}/${checks} fixture-contract assertions)\n`);
