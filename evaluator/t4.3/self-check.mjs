import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import {canonicalPixels,decodeIndexedPng,decodeRle,diagnostics,encodeIndexedPng,encodeRle,HEIGHT,paletteBytes,rgbaBytes,sha256,WIDTH} from './reference.mjs';

const load=n=>JSON.parse(fs.readFileSync(new URL(n,import.meta.url),'utf8'));
const fixture=load('fixtures.json'),manifest=load('test-ids.json'),mutations=load('mutation-specs.json');let checks=0;
const eq=(a,b,m)=>{assert.equal(a,b,m);checks++},deep=(a,b,m)=>{assert.deepEqual(a,b,m);checks++},ok=(v,m)=>{assert.ok(v,m);checks++};
eq(manifest.tests.length,18,'test id count');eq(new Set(manifest.tests.map(t=>t.id)).size,18,'unique ids');eq(manifest.tests.reduce((n,t)=>n+t.assertions,0),manifest.declaredAssertions,'declared assertion sum');ok(manifest.tests.every(t=>/^T43-[A-Z0-9-]+$/.test(t.id)&&t.intent.length>=70),'weak stable test id');
eq(mutations.mutations.length,16,'mutation count');eq(new Set(mutations.mutations.map(m=>m.id)).size,16,'unique mutations');ok(mutations.mutations.every(m=>manifest.tests.some(t=>t.id===m.killedBy)&&m.change.length>=70&&m.reason.length>=70),'weak mutation contract');
eq(fixture.width,WIDTH,'width');eq(fixture.height,HEIGHT,'height');deep(fixture.poses.map(p=>p.id),['spawn-east','spawn-north','spawn-south'],'pose names');eq(fixture.humanApproval.status,'PENDING','human boundary');deep(fixture.humanApproval.goldenHashes,[],'no invented goldens');
const fileSha=u=>crypto.createHash('sha256').update(fs.readFileSync(new URL(u,import.meta.url))).digest('hex');
eq(fileSha('../integrity.pending-T4.1.json'),'158c94e68220bbea4809f8688cb94549b07423655aaa4017b6fcaf3703c28ae6','T4.1 inherited approved manifest changed');
eq(fileSha('../integrity.pending-T4.2.json'),'1cd2021266edea250fd11f9d285a5cdeb3d1fe826c5b557a3d95408d4cd70429','T4.2 inherited approved manifest changed');

const palette=Array.from({length:256},(_,i)=>[i,(i*73+19)&255,255-i]);
const rows=[];for(let x=0;x<WIDTH;x++)for(let y=0;y<HEIGHT;y++)rows.push({column:x,row:y,cidx:(x*17+y*31+Math.floor(y/11)*7)&255});
const pixels=canonicalPixels([...rows].reverse()),runs=encodeRle(pixels),decoded=decodeRle(runs);deep(decoded,pixels,'RLE round trip');eq(runs.length,320,'run columns');ok(runs.every(c=>c.reduce((n,r)=>n+r[1],0)===200),'run coverage');
const rgba=rgbaBytes(decoded,palette);eq(rgba.length,256000,'RGBA bytes');for(const [x,y] of fixture.diagnosticPixels){const p=x*HEIGHT+y,i=p*4,c=pixels[p];deep([...rgba.subarray(i,i+4)],[...palette[c],255],`RGBA ${x}/${y}`);}
const png1=encodeIndexedPng(decoded,palette),png2=encodeIndexedPng(decoded,palette);deep(png1,png2,'deterministic PNG');eq(sha256(png1),sha256(png2),'stable PNG hash');const parsed=decodeIndexedPng(png1);eq(parsed.width,WIDTH,'PNG width');eq(parsed.height,HEIGHT,'PNG height');deep(parsed.palette,paletteBytes(palette),'PNG palette');deep(parsed.pixels,pixels,'PNG pixels');
const runner=fs.readFileSync(new URL('./run-observation.mjs',import.meta.url),'utf8');
const diag=diagnostics(pixels,palette,fixture.diagnosticColumns,fixture.diagnosticPixels);eq(diag.columns.length,6,'diagnostic columns');ok(diag.pixels.length===8&&runner.includes('diagnostics(pixels,o.palette,fixture.diagnosticColumns,fixture.diagnosticPixels)'),'eight fixture pixels wired into observation diagnostics');ok(diag.columns.every(c=>c.runs.reduce((n,r)=>n+r[1],0)===200&&/^[0-9a-f]{64}$/.test(c.sha256)),'column diagnostics');

for(const mutate of [
  a=>a.slice(1),
  a=>{const b=a.map(x=>({...x}));b[1]={...b[0]};return b;},
  a=>{const b=a.map(x=>({...x}));b[0].cidx=256;return b;}
]){let failed=false;try{canonicalPixels(mutate(rows));}catch{failed=true;}ok(failed,'bad SQL frame rejected');}
for(const bad of [
  [[[1,199,4]]],
  [[[0,0,4],[0,200,5]]],
  [[[0,100,4],[101,99,5]]],
  [[[0,100,4],[100,100,4]]]
]){let failed=false;try{decodeRle([...bad,...Array.from({length:319},()=>[[0,200,0]])]);}catch{failed=true;}ok(failed,'bad RLE rejected');}
const damaged=Buffer.from(png1);damaged[damaged.length-1]^=1;let crcFailed=false;try{decodeIndexedPng(damaged);}catch{crcFailed=true;}ok(crcFailed,'damaged PNG rejected');
process.stdout.write(`PASS T4.3-EVAL-SELF-CHECK (${checks}/${checks} fixture-contract assertions)\n`);
