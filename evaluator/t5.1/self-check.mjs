import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {canonical,intersections,sha,timeline,transformScene} from './reference.mjs';

const here=import.meta.dirname,root=path.resolve(here,'../..'),load=n=>JSON.parse(fs.readFileSync(path.join(here,n),'utf8'));
const fixture=load('fixtures.json'),expected=load('expectations.json'),manifest=load('test-ids.json'),mutations=load('mutation-specs.json');
let checks=0;const ok=(v,m)=>{assert.ok(v,m);checks++},eq=(a,b,m)=>{assert.equal(a,b,m);checks++},deep=(a,b,m)=>{assert.deepEqual(a,b,m);checks++};
eq(manifest.tests.length,20,'stable id count');eq(new Set(manifest.tests.map(x=>x.id)).size,20,'duplicate id');
eq(manifest.tests.reduce((n,x)=>n+x.assertions,0),674,'assertion sum');eq(manifest.declaredAssertions,674,'declared total');
ok(manifest.tests.every(x=>/^T51-[A-Z0-9-]+$/.test(x.id)&&x.intent.length>=75),'weak test contract');
eq(mutations.mutations.length,18,'mutation count');eq(new Set(mutations.mutations.map(x=>x.id)).size,18,'duplicate mutant');
ok(mutations.mutations.every(x=>manifest.tests.some(t=>t.id===x.killedBy)&&x.change.length>=70&&x.reason.length>=70),'weak mutation contract');
eq(expected.scenes.length,fixture.scenes.length,'fixture expectation coverage');

const results=new Map();
for(const scene of fixture.scenes){
  const got=timeline(scene,fixture.pose),want=expected.scenes.find(x=>x.name===scene.name);results.set(scene.name,got);
  eq(got.hits.length,want.hitCount,`${scene.name} retained hits`);eq(got.hits.filter(x=>x.active).length,want.activeCount,`${scene.name} active hits`);
  eq(got.intervals.length,want.intervalCount,`${scene.name} intervals`);eq(got.hits.filter(x=>x.isTransition).length,want.transitionCount,`${scene.name} transitions`);
  eq(got.hits.filter(x=>x.isTermination).length,want.terminationCount,`${scene.name} terminations`);eq(sha(canonical(got)),want.sha256,`${scene.name} document`);
  deep(got.hits.map(x=>x.hitOrdinal),got.hits.map((_,i)=>i),`${scene.name} hit ordinals`);
  deep(got.intervals.map(x=>x.ordinal),got.intervals.map((_,i)=>i),`${scene.name} interval ordinals`);
}

const window=results.get('window');deep([window.hits[0].openingBottom,window.hits[0].openingTop],[32,96],'window opening');
deep([window.hits[0].lowerBottom,window.hits[0].lowerTop,window.hits[0].upperBottom,window.hits[0].upperTop],[0,32,96,128],'window pieces');
const steps=results.get('steps');deep(steps.hits.slice(0,2).map(x=>[x.lowerBottom,x.lowerTop]),[[0,16],[16,32]],'step pieces');
const closed=results.get('closed-door');eq(closed.hits[0].isClosed,1,'zero opening closed');eq(closed.hits[1].active,0,'after-solid retained inactive');
const opened=results.get('open-door');deep([opened.hits[0].isClosed,opened.hits[0].upperBottom,opened.hits[0].upperTop],[0,80,128],'open door');
const overlap=results.get('overlap');deep(overlap.hits.map(x=>[x.linedefId,x.active]),[[40,1],[41,0],[42,1]],'overlap compatibility');
const vertex=results.get('vertex-tie');deep(vertex.hits.slice(0,2).map(x=>[x.t,x.linedefId]),[[8,50],[8,51]],'vertex stable tie');eq(vertex.intervals[1].tStart,vertex.intervals[1].tEnd,'zero interval deliberate');
const nested=results.get('nested');deep(nested.intervals.map(x=>x.sectorId),[0,1,2,3],'nested sectors');
const range=results.get('open-range');deep(range.intervals.at(-1),{ordinal:1,tStart:8,tEnd:64,sectorId:1,terminatedBy:null,isFinal:1},'final far interval');

const nestedScene=fixture.scenes.find(x=>x.name==='nested'),base=canonical(nested);
const translated=timeline(transformScene(nestedScene,fixture.translation),{x:fixture.translation.dx,y:fixture.translation.dy,angle:0});eq(canonical(translated),base,'translation exact');
const mirrored=timeline(transformScene(nestedScene,{mirrorX:fixture.mirror.axisX}),{x:2*fixture.mirror.axisX,y:0,angle:180});
const semantics=r=>r.hits.map(x=>({...x,facingSide:0,t:Number(x.t.toFixed(9)),u:Number(x.u.toFixed(9))}));deep(semantics(mirrored),semantics(nested),'mirror semantic hits');deep(mirrored.intervals,nested.intervals,'mirror intervals');
ok(mirrored.hits.every((x,i)=>x.facingSide===1-nested.hits[i].facingSide),'mirror facing bits');
const threshold={startSector:0,sectors:[{id:0,floor:0,ceiling:128}],walls:[{id:1,x1:1e-9,y1:1,x2:1e-9,y2:-1,right:0,left:null},{id:2,x1:1.000001e-9,y1:1,x2:1.000001e-9,y2:-1,right:0,left:null}]};
eq(intersections(threshold,fixture.pose).length,1,'strict t threshold');

const fileSha=f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex');
const inherited=[
 ['evaluator/integrity.json','2699e0e0f6e93593d8172ea19a048d2ad6ebabb57aef2604a81782c25f2882a3'],
 ['evaluator/integrity.pending-T2.2.json','23ca7de9b0a78fe6697350911ac0800f48c9fbd9b6851daed6d10cb982b1b04b'],
 ['evaluator/integrity.pending-T2.3.json','3f13e8dcc3294a0efa096365d3fcd7c70b043da3ff4734e912044878b140add9'],
 ['evaluator/integrity.pending-T2.4.json','7bf6d81695ff3b7085f70107b1925e3aaf72587ead46cd096cdbd6e79e0d9354'],
 ['evaluator/integrity.pending-T3.2.json','d617cdd9e5f8a36606d6606d6c61a514f46b3b5545f4526e48361a1c04208050'],
 ['evaluator/integrity.pending-T3.3.json','8ccb54c64ed3e4e34ec3e1f84cda03a3b3ebe4a7ec8bf26c5688ab0b96260e37'],
 ['evaluator/integrity.pending-T3.4.json','6f1bd528776949ca4bc4b08f3fae80b810c38c11c7a9d556be134170400f5651']
];for(const [f,h] of inherited)eq(fileSha(f),h,`${f} changed`);
const rendererChain=[
 ['evaluator/integrity.pending-T4.1.json','158c94e68220bbea4809f8688cb94549b07423655aaa4017b6fcaf3703c28ae6'],
 ['evaluator/integrity.pending-T4.2.json','1cd2021266edea250fd11f9d285a5cdeb3d1fe826c5b557a3d95408d4cd70429'],
 ['evaluator/integrity.pending-T4.3.json','38927540dc430ff6d3476738f122577ec15bf4ab104628282a4f19a7e7c5977a'],
 ['goldens/integrity-T4.3.json','8b6ed7eca00188dff759b3ee2d8a15d7fc04d1b294bac4106e1d581139febc63']
];ok(rendererChain.every(([f,h])=>fileSha(f)===h),'approved T4 renderer and visible-golden integrity chain changed');
process.stdout.write(`PASS T5.1-EVAL-SELF-CHECK (${checks}/${checks} fixture-contract assertions)\n`);
