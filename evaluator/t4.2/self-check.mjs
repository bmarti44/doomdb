import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {decodeWad,frameSha,miniMap,render,WIDTH,HEIGHT} from './reference.mjs';

const here=import.meta.dirname,root=path.resolve(here,'../..'),load=n=>JSON.parse(fs.readFileSync(path.join(here,n),'utf8'));
const fixtures=load('fixtures.json'),expected=load('expectations.json'),manifest=load('test-ids.json'),mutations=load('mutation-specs.json');
let checks=0;const ok=(v,m)=>{assert.ok(v,m);checks++},eq=(a,b,m)=>{assert.equal(a,b,m);checks++},deep=(a,b,m)=>{assert.deepEqual(a,b,m);checks++};
eq(manifest.tests.length,20,'stable test id count');eq(new Set(manifest.tests.map(x=>x.id)).size,20,'duplicate ids');
eq(manifest.tests.reduce((n,x)=>n+x.assertions,0),manifest.declaredAssertions,'declared assertion sum');eq(manifest.declaredAssertions,384426,'reviewed assertion total');
ok(manifest.tests.every(x=>/^T42-[A-Z0-9-]+$/.test(x.id)&&x.intent.length>=75),'weak or unstable test id');
eq(mutations.mutations.length,18,'mutation count');eq(new Set(mutations.mutations.map(x=>x.id)).size,18,'duplicate mutation');
ok(mutations.mutations.every(x=>manifest.tests.some(t=>t.id===x.killedBy)&&x.change.length>=70&&x.reason.length>=70),'weak mutation contract');
eq(WIDTH,fixtures.width,'oracle width');eq(HEIGHT,fixtures.height,'oracle height');eq(WIDTH*HEIGHT,expected.frameRows,'frame cardinality');

function verifyFrame(name,frame){const want=expected.frames.find(x=>x.name===name);eq(frame.pixels.length,64000,`${name} bytes`);eq(frame.layers.length,64000,`${name} layers`);ok([...frame.pixels].every(x=>x>=0&&x<=255),`${name} palette range`);eq(frameSha(frame.pixels),want.sha256,`${name} hash`);deep([0,1,10].map(x=>[...frame.layers].filter(y=>y===x).length),want.layerCounts,`${name} layers`);for(const [c,r,p,l] of want.probes){eq(frame.pixels[c*200+r],p,`${name} palette ${c}/${r}`);eq(frame.layers[c*200+r],l,`${name} layer ${c}/${r}`);}}
verifyFrame('mini',render(miniMap(),fixtures.mini.pose));
const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'doom-t42-wad-'));
try{const z=spawnSync('unzip',['-q',path.join(root,'vendor/freedoom/0.13.0/freedoom-0.13.0.zip'),'freedoom-0.13.0/freedoom1.wad','-d',scratch]);eq(z.status,0,'WAD extract');const map=decodeWad(fs.readFileSync(path.join(scratch,'freedoom-0.13.0/freedoom1.wad')));for(const pose of fixtures.e1m1Poses)verifyFrame(pose.name,render(map,pose));}finally{fs.rmSync(scratch,{recursive:true,force:true});}

eq(expected.frames.length,4,'frame count');eq(new Set(expected.frames.map(x=>x.sha256)).size,4,'hash distinction');
ok(expected.frames.every(x=>x.probes.some(p=>p[3]===0)&&x.probes.some(p=>p[3]===1)&&x.probes.some(p=>p[3]===10)),'each fixture lacks semantic layer probes');
const fileSha=f=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,f))).digest('hex');
const inherited=[
 ['evaluator/integrity.json','2699e0e0f6e93593d8172ea19a048d2ad6ebabb57aef2604a81782c25f2882a3'],
 ['evaluator/integrity.pending-T2.2.json','23ca7de9b0a78fe6697350911ac0800f48c9fbd9b6851daed6d10cb982b1b04b'],
 ['evaluator/integrity.pending-T2.3.json','3f13e8dcc3294a0efa096365d3fcd7c70b043da3ff4734e912044878b140add9'],
 ['evaluator/integrity.pending-T2.4.json','7bf6d81695ff3b7085f70107b1925e3aaf72587ead46cd096cdbd6e79e0d9354'],
 ['evaluator/integrity.pending-T3.2.json','d617cdd9e5f8a36606d6606d6c61a514f46b3b5545f4526e48361a1c04208050'],
 ['evaluator/integrity.pending-T3.3.json','8ccb54c64ed3e4e34ec3e1f84cda03a3b3ebe4a7ec8bf26c5688ab0b96260e37'],
 ['evaluator/integrity.pending-T3.4.json','6f1bd528776949ca4bc4b08f3fae80b810c38c11c7a9d556be134170400f5651'],
 ['evaluator/integrity.pending-T4.1.json','158c94e68220bbea4809f8688cb94549b07423655aaa4017b6fcaf3703c28ae6']
];for(const [f,h] of inherited)eq(fileSha(f),h,`${f} changed`);
process.stdout.write(`PASS T4.2-EVAL-SELF-CHECK (${checks}/${checks} fixture-contract assertions)\n`);
