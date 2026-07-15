import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {canonical,decodeE1M1,intersect,rays,sha,traceMap,traceSegments} from './reference.mjs';

const root=path.resolve(import.meta.dirname,'../..'),load=n=>JSON.parse(fs.readFileSync(path.join(import.meta.dirname,n),'utf8'));
const fixture=load('fixtures.json'),expected=load('expectations.json'),manifest=load('test-ids.json'),mutations=load('mutation-specs.json');
let checks=0; const ok=(v,m)=>{assert.ok(v,m);checks++},eq=(a,b,m)=>{assert.equal(a,b,m);checks++},deep=(a,b,m)=>{assert.deepEqual(a,b,m);checks++};
eq(manifest.tests.length,18,'stable id count');eq(new Set(manifest.tests.map(t=>t.id)).size,18,'duplicate id');
eq(manifest.tests.reduce((n,t)=>n+t.assertions,0),1296,'assertion sum');eq(manifest.declaredAssertions,1296,'declared total');
ok(manifest.tests.every(t=>/^T41-[A-Z0-9-]+$/.test(t.id)&&t.intent.length>=70),'unstable or weak id');
eq(mutations.mutations.length,16,'mutation count');eq(new Set(mutations.mutations.map(m=>m.id)).size,16,'duplicate mutant');
ok(mutations.mutations.every(m=>manifest.tests.some(t=>t.id===m.killedBy)&&m.change.length>=70&&m.reason.length>=70),'weak mutation contract');

const camera=rays(fixture.handMap.pose,fixture.width,fixture.fovDegrees);
eq(camera.length,320,'ray count');deep(camera.map(r=>r.column),Array.from({length:320},(_,i)=>i),'column keys');
for(const c of [0,159,160,319]) ok(Math.abs(camera[c].dot-1)<1e-12,`unnormalized dot ${c}`);
ok(Math.abs(camera[159].camx+camera[160].camx)<1e-15,'center symmetry');ok(camera[0].camx===-0.996875&&camera[319].camx===0.996875,'edge pixel centers');

eq(intersect(fixture.parallelCase.pose,fixture.parallelCase.ray,fixture.parallelCase.v1,fixture.parallelCase.v2),null,'parallel reject');
eq(intersect(fixture.behindCase.pose,fixture.behindCase.ray,fixture.behindCase.v1,fixture.behindCase.v2),null,'behind reject');
const endpoint=intersect({x:0,y:0},{rayX:1,rayY:0},{x:8,y:0},{x:8,y:4});eq(endpoint.t,8,'endpoint t');eq(endpoint.u,0,'endpoint inclusive');
const end1=intersect({x:0,y:0},{rayX:1,rayY:0},{x:8,y:-4},{x:8,y:0});eq(end1.u,1,'other endpoint inclusive');
const tie=fixture.vertexTie.segments.map(s=>({...intersect(fixture.vertexTie.pose,fixture.vertexTie.ray,s.v1,s.v2),id:s.id})).sort((a,b)=>a.t-b.t||a.id-b.id);
deep(tie.map(h=>h.id),[4,9],'stable vertex tie');

const hm=fixture.handMap,base=traceSegments(hm.vertices,hm.segments,hm.pose,{width:320,fov:90});eq(base.length,320,'hand trace columns');
const movedVertices=hm.vertices.map(v=>({...v,x:v.x+hm.transform.translateX,y:v.y+hm.transform.translateY}));
const movedPose={...hm.pose,x:hm.pose.x+hm.transform.translateX,y:hm.pose.y+hm.transform.translateY};
const moved=traceSegments(movedVertices,hm.segments,movedPose,{width:320,fov:90});
for(const c of [0,40,159,160,279,319]){eq(base[c].hits.length,moved[c].hits.length,`translated count ${c}`);ok(Math.abs(base[c].nearestSolid.t-moved[c].nearestSolid.t)<1e-9,`translated t ${c}`);}
const axis=hm.transform.mirrorAxisX,mirroredVertices=hm.vertices.map(v=>({...v,x:2*axis-v.x})),mirroredPose={...hm.pose,x:2*axis-hm.pose.x,angle:180-hm.pose.angle};
const mirrored=traceSegments(mirroredVertices,hm.segments,mirroredPose,{width:320,fov:90});
for(const c of [0,40,159,160,279,319])ok(Math.abs(base[c].nearestSolid.t-mirrored[319-c].nearestSolid.t)<1e-9,`mirror t ${c}`);

const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'doom-t41-wad-'));
try{
  const z=spawnSync('unzip',['-q',path.join(root,'vendor/freedoom/0.13.0/freedoom-0.13.0.zip'),'freedoom-0.13.0/freedoom1.wad','-d',scratch]);eq(z.status,0,'WAD extraction');
  const map=decodeE1M1(fs.readFileSync(path.join(scratch,'freedoom-0.13.0/freedoom1.wad')));eq(map.segs.length,2057,'seg count');eq(map.lines.length,1175,'line count');
  for(const pose of fixture.e1m1Poses){
    const want=expected.poses.find(p=>p.name===pose.name),trace=traceMap(map,pose),doc=canonical(trace);
    eq(trace.reduce((n,c)=>n+c.hits.length,0),want.hitRows,`${pose.name} hits`);eq(trace.filter(c=>c.nearestSolid).length,want.solidColumns,`${pose.name} solids`);
    eq(Buffer.byteLength(doc),want.documentBytes,`${pose.name} doc bytes`);eq(sha(doc),want.sha256,`${pose.name} hash`);
    for(const p of want.probes){const h=trace[p.column].nearestSolid;ok(Math.abs(h.t-p.t)<=expected.tolerance.t,`${pose.name}/${p.column} t`);ok(Math.abs(h.u-p.u)<=expected.tolerance.u,`${pose.name}/${p.column} u`);deep({linedefId:h.linedefId,segId:h.segId,facingSide:h.facingSide},{linedefId:p.linedefId,segId:p.segId,facingSide:p.facingSide},`${pose.name}/${p.column} ids`);}
  }
}finally{fs.rmSync(scratch,{recursive:true,force:true});}

const fileSha=f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex');
const inherited=[['evaluator/integrity.json','2699e0e0f6e93593d8172ea19a048d2ad6ebabb57aef2604a81782c25f2882a3'],['evaluator/integrity.pending-T2.2.json','23ca7de9b0a78fe6697350911ac0800f48c9fbd9b6851daed6d10cb982b1b04b'],['evaluator/integrity.pending-T2.3.json','3f13e8dcc3294a0efa096365d3fcd7c70b043da3ff4734e912044878b140add9'],['evaluator/integrity.pending-T2.4.json','7bf6d81695ff3b7085f70107b1925e3aaf72587ead46cd096cdbd6e79e0d9354'],['evaluator/integrity.pending-T3.2.json','d617cdd9e5f8a36606d6606d6c61a514f46b3b5545f4526e48361a1c04208050'],['evaluator/integrity.pending-T3.3.json','8ccb54c64ed3e4e34ec3e1f84cda03a3b3ebe4a7ec8bf26c5688ab0b96260e37'],['evaluator/integrity.pending-T3.4.json','6f1bd528776949ca4bc4b08f3fae80b810c38c11c7a9d556be134170400f5651']];
for(const [f,h] of inherited)eq(fileSha(f),h,`${f} changed`);
process.stdout.write(`PASS T4.1-EVAL-SELF-CHECK (${checks}/${checks} fixture-contract assertions)\n`);
