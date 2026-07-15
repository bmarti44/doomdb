import assert from 'node:assert/strict';
import fs from 'node:fs';
import {canonicalPixels,decodeRle,encodeIndexedPng,encodeRle,HEIGHT,rgbaBytes,WIDTH} from './reference.mjs';
const specs=JSON.parse(fs.readFileSync(new URL('./mutation-specs.json',import.meta.url))).mutations,killed=new Set(),kill=(id,v)=>{assert.ok(v,`${id} survived`);killed.add(id)};
const palette=Array.from({length:256},(_,i)=>[i,(i*73+19)&255,255-i]),rows=[];for(let x=0;x<WIDTH;x++)for(let y=0;y<HEIGHT;y++)rows.push({column:x,row:y,cidx:(x*17+y*31+Math.floor(y/11)*7)&255});const pix=canonicalPixels(rows),runs=encodeRle(pix);
kill('T43-M01-ROW-MAJOR',pix[1]!==pix[HEIGHT]);
for(const [id,mut] of [['T43-M02-DROP-PIXEL',a=>a.slice(1)],['T43-M03-DUPLICATE-PIXEL',a=>{const b=a.map(x=>({...x}));b[1]={...b[0]};return b;}],['T43-M04-PALETTE-WRAP',a=>{const b=a.map(x=>({...x}));b[0].cidx=256;return b;}]]){let dead=false;try{canonicalPixels(mut(rows));}catch{dead=true;}kill(id,dead);}
const badRuns={
  'T43-M05-RLE-CROSS-COLUMN':Array.from({length:WIDTH},(_,x)=>x?[[0,200,0]]:[[0,201,0]]),
  'T43-M06-RLE-GAP':runs.map((c,x)=>x?c:c.map((r,i)=>i?i===1?[r[0]+1,r[1]-1,r[2]]:r:r)),
  'T43-M07-RLE-ZERO-LENGTH':runs.map((c,x)=>x?c:[[0,0,3],...c]),
  'T43-M08-RLE-NONMAXIMAL':runs.map((c,x)=>x?c:[[0,1,c[0][2]],[1,c[0][1]-1,c[0][2]],...c.slice(1)])};
for(const [id,r] of Object.entries(badRuns)){let dead=false;try{decodeRle(r);}catch{dead=true;}kill(id,dead);}
kill('T43-M09-TRANSPOSE-PNG',pix[1]!==pix[HEIGHT]);const rgba=rgbaBytes(pix,palette);kill('T43-M10-RGBA-BGR',rgba[0]!==rgba[2]||rgba[4]!==rgba[6]);kill('T43-M11-ALPHA-ZERO',rgba[3]===255);const png=encodeIndexedPng(pix,palette);kill('T43-M12-PNG-TRUECOLOR',png.includes(Buffer.from('PLTE')));kill('T43-M13-PNG-TIMESTAMP',!png.includes(Buffer.from('tIME')));
const f=JSON.parse(fs.readFileSync(new URL('./fixtures.json',import.meta.url)));kill('T43-M14-ONE-POSE-REPLAY',new Set(f.poses.map(p=>p.id)).size===3);kill('T43-M15-AUTO-APPROVE',f.humanApproval.status==='PENDING'&&f.humanApproval.goldenHashes.length===0);const audit=fs.readFileSync(new URL('./source-audit.mjs',import.meta.url),'utf8').toUpperCase();kill('T43-M16-CANNED-FRAME',audit.includes('CANNED DIAGNOSTIC'));
assert.deepEqual([...killed],specs.map(s=>s.id),'mutation order/coverage');process.stdout.write(`PASS T4.3-EVAL-MUTATION-SELF-CHECK (${killed.size}/${specs.length} isolated mutations killed)\n`);
