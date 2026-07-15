import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {spawnSync} from 'node:child_process';
import {blockDocument,cellForPoint,decodeBlockmapBytes,decodeE1M1,decodeRejectBytes,encodeBlockmap,graphDocument,graphEdges,rejectDocument,sha} from './reference.mjs';

const root=path.resolve(import.meta.dirname,'../..');
const load=(name)=>JSON.parse(fs.readFileSync(path.join(import.meta.dirname,name),'utf8'));
const expected=load('expectations.json'), fixtures=load('fixtures.json'), manifest=load('test-ids.json'), mutations=load('mutation-specs.json');
let checks=0; const check=(v,m)=>{assert.ok(v,m);checks++;}; const equal=(a,b,m)=>{assert.equal(a,b,m);checks++;}; const deep=(a,b,m)=>{assert.deepEqual(a,b,m);checks++;};

equal(manifest.tests.length,17,'stable id count'); equal(new Set(manifest.tests.map(t=>t.id)).size,17,'duplicate id');
equal(manifest.tests.reduce((n,t)=>n+t.assertions,0),3300,'assertion sum'); equal(manifest.declaredAssertions,3300,'declared total');
check(manifest.tests.every(t=>/^T34-[A-Z0-9-]+$/.test(t.id)),'unstable id'); check(manifest.tests.every(t=>t.intent.length>=60),'weak test intent');
equal(mutations.mutations.length,17,'mutation count'); equal(new Set(mutations.mutations.map(m=>m.id)).size,17,'duplicate mutant');
check(mutations.mutations.every(m=>manifest.tests.some(t=>t.id===m.killedBy)),'unnamed mutation kill');
check(mutations.mutations.every(m=>m.change.length>=60&&m.reason.length>=60),'underspecified mutation');

const miniBytes=Buffer.from(fixtures.blockmapHex,'hex'), mini=decodeBlockmapBytes(miniBytes);
deep({originX:mini.originX,originY:mini.originY,columns:mini.columns,rows:mini.rows},Object.fromEntries(Object.entries(fixtures.blockmapExpected).filter(([k])=>['originX','originY','columns','rows'].includes(k))),'mini header');
deep(mini.cells.map(c=>c.listWordOffset),fixtures.blockmapExpected.offsets,'mini offsets');
deep(mini.cells.map(c=>c.lines),fixtures.blockmapExpected.lineLists,'mini line lists');
check(encodeBlockmap(mini).equals(miniBytes),'mini byte roundtrip');
for(const probe of fixtures.coordinateProbes) deep(cellForPoint(probe.x,probe.y,mini),{blockX:probe.blockX,blockY:probe.blockY},`coordinate ${probe.x},${probe.y}`);
deep(decodeRejectBytes(Buffer.from(fixtures.rejectHex,'hex'),fixtures.rejectSectorCount).map(b=>b.rejected),fixtures.rejectExpected,'mini reject bits');
const miniEdges=graphEdges(fixtures.graph.lines,fixtures.graph.sides,fixtures.graph.sectors);
deep(miniEdges,fixtures.graph.expectedEdges,'mini graph edges');
const miniReach=(start)=>{const seen=new Set([start]),q=[start];while(q.length){const x=q.shift();for(const e of miniEdges)if(e.sourceSectorId===x&&!seen.has(e.targetSectorId)){seen.add(e.targetSectorId);q.push(e.targetSectorId);}}return [...seen].sort((a,b)=>a-b);};
deep(miniReach(0),fixtures.graph.reachableFrom0,'mini reachable component');
deep(miniReach(3),fixtures.graph.reachableFrom3,'mini isolated vertex');
equal(miniEdges.filter(e=>e.soundBlock===1).length,2,'mini sound-block inverse pair');

const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'doom-t34-wad-'));
try {
  const unzip=spawnSync('unzip',['-q',path.join(root,'vendor/freedoom/0.13.0/freedoom-0.13.0.zip'),'freedoom-0.13.0/freedoom1.wad','-d',scratch]);
  equal(unzip.status,0,'independent WAD extraction');
  const map=decodeE1M1(fs.readFileSync(path.join(scratch,'freedoom-0.13.0/freedoom1.wad'))), b=map.blockmap;
  deep({bytes:map.blockBytes.length,originX:b.originX,originY:b.originY,columns:b.columns,rows:b.rows,cells:b.cells.length,memberships:b.memberships.length,uniqueLists:new Set(b.cells.map(c=>c.listWordOffset)).size,minimumListWordOffset:Math.min(...b.cells.map(c=>c.listWordOffset)),maximumListWordOffset:Math.max(...b.cells.map(c=>c.listWordOffset)),minimumLinesPerCell:Math.min(...b.cells.map(c=>c.lines.length)),maximumLinesPerCell:Math.max(...b.cells.map(c=>c.lines.length)),documentBytes:Buffer.byteLength(blockDocument(b.memberships)),documentSha256:sha(blockDocument(b.memberships))},Object.fromEntries(Object.entries(expected.blockmap).filter(([k])=>!['cellProbes'].includes(k))),'pinned block expectations');
  check(encodeBlockmap(b).equals(map.blockBytes),'pinned binary roundtrip');
  for(const probe of expected.blockmap.cellProbes) { const cell=b.cells[probe.blockY*b.columns+probe.blockX]; deep({blockX:cell.blockX,blockY:cell.blockY,listWordOffset:cell.listWordOffset,lines:cell.lines},probe,`cell ${probe.blockX},${probe.blockY}`); }
  deep({bytes:map.rejectBytes.length,sectorCount:map.sectors.length,bits:map.reject.length,setBits:map.reject.reduce((n,r)=>n+r.rejected,0),documentBytes:Buffer.byteLength(rejectDocument(map.reject)),documentSha256:sha(rejectDocument(map.reject))},Object.fromEntries(Object.entries(expected.reject).filter(([k])=>k!=='probes')),'pinned reject expectations');
  for(const p of expected.reject.probes) equal(map.reject[p.source*map.sectors.length+p.target].rejected,p.rejected,`reject ${p.source},${p.target}`);
  const graphDoc=graphDocument(map.edges), adj=Array.from({length:map.sectors.length},()=>new Set());
  for(const e of map.edges) adj[e.sourceSectorId].add(e.targetSectorId);
  const seen=new Set(), sizes=[]; for(let i=0;i<adj.length;i++) if(!seen.has(i)){const q=[i];seen.add(i);let n=0;while(q.length){const x=q.shift();n++;for(const y of adj[x])if(!seen.has(y)){seen.add(y);q.push(y);}}sizes.push(n);} sizes.sort((a,b)=>b-a);
  const reach=(start)=>{const s=new Set([start]),q=[start];while(q.length){for(const y of adj[q.shift()])if(!s.has(y)){s.add(y);q.push(y)}}return s.size;};
  deep({connections:map.edges.length/2,directedEdges:map.edges.length,soundBlockConnections:map.edges.filter(e=>e.soundBlock).length/2,minimumOpening:Math.min(...map.edges.map(e=>e.opening)),maximumOpening:Math.max(...map.edges.map(e=>e.opening)),documentBytes:Buffer.byteLength(graphDoc),documentSha256:sha(graphDoc),componentSizes:sizes,reachableFrom140:reach(140),isolatedSectors:adj.filter(s=>s.size===0).length},expected.graph,'pinned graph expectations');
} finally { fs.rmSync(scratch,{recursive:true,force:true}); }

const sourceAudit=fs.readFileSync(path.join(import.meta.dirname,'source-audit.mjs'),'utf8').toUpperCase();
for(const token of ['CREATE PROPERTY GRAPH','GRAPH_TABLE','BITAND','FLOOR','EVALUATOR/']) check(sourceAudit.includes(token),`source audit lacks ${token}`);
const oracle=fs.readFileSync(path.join(import.meta.dirname,'oracle-production.sql'),'utf8').toUpperCase();
for(const token of ['DOOM_BLOCK_CELL','DOOM_BLOCK_LINE','DOOM_SECTOR_REJECT','DOOM_SECTOR_EDGE','DOOM_SECTOR_GRAPH','GRAPH_TABLE','DBMS_CRYPTO.HASH_SH256']) check(oracle.includes(token),`oracle lacks ${token}`);

const fileSha=(file)=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex');
const baselines=[['evaluator/integrity.json','2699e0e0f6e93593d8172ea19a048d2ad6ebabb57aef2604a81782c25f2882a3'],['evaluator/integrity.pending-T2.2.json','23ca7de9b0a78fe6697350911ac0800f48c9fbd9b6851daed6d10cb982b1b04b'],['evaluator/integrity.pending-T2.3.json','3f13e8dcc3294a0efa096365d3fcd7c70b043da3ff4734e912044878b140add9'],['evaluator/integrity.pending-T2.4.json','7bf6d81695ff3b7085f70107b1925e3aaf72587ead46cd096cdbd6e79e0d9354'],['evaluator/integrity.pending-T3.2.json','d617cdd9e5f8a36606d6606d6c61a514f46b3b5545f4526e48361a1c04208050']];
for(const [file,hash] of baselines) equal(fileSha(file),hash,`${file} changed`);
process.stdout.write(`PASS T3.4-EVAL-SELF-CHECK (${checks}/${checks} fixture-contract assertions)\n`);
