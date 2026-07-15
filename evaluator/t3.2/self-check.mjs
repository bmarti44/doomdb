import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = path.resolve(import.meta.dirname, '../..');
const load = (name) => JSON.parse(fs.readFileSync(path.join(import.meta.dirname, name), 'utf8'));
const expected = load('expectations.json');
const manifest = load('test-ids.json');
const mutations = load('mutation-specs.json');
let checks = 0;
const check = (condition, message) => { assert.ok(condition, message); checks++; };
const equal = (actual, wanted, message) => { assert.equal(actual, wanted, message); checks++; };
const deep = (actual, wanted, message) => { assert.deepEqual(actual, wanted, message); checks++; };
const sha = (file) => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

equal(manifest.tests.length, 14, 'stable test-id count');
equal(new Set(manifest.tests.map((row) => row.id)).size, 14, 'duplicate test id');
equal(manifest.tests.reduce((sum, row) => sum + row.assertions, 0), 136, 'declared assertion sum');
equal(manifest.declaredAssertions, 136, 'manifest assertion total');
check(manifest.tests.every((row) => /^T32-[A-Z0-9-]+$/.test(row.id)), 'unstable test-id format');
check(manifest.tests.every((row) => row.intent.length >= 40), 'test intent too weak');
equal(mutations.mutations.length, 14, 'mutation count');
equal(new Set(mutations.mutations.map((row) => row.id)).size, 14, 'duplicate mutation id');
check(mutations.mutations.every((row) => manifest.tests.some((test) => test.id === row.killedBy)), 'mutation without named kill test');
check(mutations.mutations.every((row) => row.change.length >= 50 && row.reason.length >= 40), 'underspecified mutation');

equal(expected.margin, expected.configuration.FAR_DISTANCE + expected.configuration.PLAYER_RADIUS, 'margin sum');
deep(expected.metadata.dimensions[0], {name:'X',lower:expected.vertexBounds.minX-expected.margin,upper:expected.vertexBounds.maxX+expected.margin}, 'derived X metadata');
deep(expected.metadata.dimensions[1], {name:'Y',lower:expected.vertexBounds.minY-expected.margin,upper:expected.vertexBounds.maxY+expected.margin}, 'derived Y metadata');
equal(expected.metadata.tolerance, 0.005, 'metadata tolerance');
deep(expected.geometry, {gtype:2002,elemInfo:[1,2,1],ordinateCount:4}, 'geometry representation');

const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'doom-t32-self-'));
try {
  const unzip = spawnSync('unzip', ['-q', path.join(root,'vendor/freedoom/0.13.0/freedoom-0.13.0.zip'), 'freedoom-0.13.0/freedoom1.wad', '-d', scratch]);
  equal(unzip.status, 0, `unable to read pinned WAD: ${unzip.stderr}`);
  const wad = fs.readFileSync(path.join(scratch,'freedoom-0.13.0/freedoom1.wad'));
  equal(crypto.createHash('sha256').update(wad).digest('hex'), '7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d', 'pinned WAD hash');
  const count = wad.readInt32LE(4), directoryAt = wad.readInt32LE(8), entries = [];
  for (let id=0; id<count; id++) {
    const at=directoryAt+id*16;
    entries.push({name:wad.subarray(at+8,at+16).toString('ascii').replace(/\0.*$/,''),offset:wad.readInt32LE(at),size:wad.readInt32LE(at+4)});
  }
  const marker=entries.findIndex((row)=>row.name==='E1M1');
  check(marker >= 0, 'E1M1 marker absent');
  const confined=new Map(entries.slice(marker+1,marker+11).map((row)=>[row.name,row]));
  const vertexLump=confined.get('VERTEXES'), lineLump=confined.get('LINEDEFS');
  equal(vertexLump.size/4, expected.counts.vertices, 'independent vertex count');
  equal(lineLump.size/14, expected.counts.linedefs, 'independent linedef count');
  const vertices=[];
  for (let id=0;id<vertexLump.size/4;id++) vertices.push([wad.readInt16LE(vertexLump.offset+id*4),wad.readInt16LE(vertexLump.offset+id*4+2)]);
  deep({minX:Math.min(...vertices.map(v=>v[0])),maxX:Math.max(...vertices.map(v=>v[0])),minY:Math.min(...vertices.map(v=>v[1])),maxY:Math.max(...vertices.map(v=>v[1]))}, expected.vertexBounds, 'independent vertex bounds');
  const lines=[];
  for (let id=0;id<lineLump.size/14;id++) {
    const at=lineLump.offset+id*14, start=vertices[wad.readUInt16LE(at)], end=vertices[wad.readUInt16LE(at+2)];
    const dx=end[0]-start[0],dy=end[1]-start[1],length=Math.hypot(dx,dy);
    lines.push({id,start,end,length,direction:[dx/length,dy/length]});
  }
  equal(lines.filter((line)=>line.length===0).length, 0, 'zero-length line count');
  for (const probe of expected.linedefProbes) {
    const actual=lines[probe.id];
    deep(actual.start,probe.start,`line ${probe.id} start`);
    deep(actual.end,probe.end,`line ${probe.id} end`);
    equal(Number(actual.length.toFixed(12)),probe.length,`line ${probe.id} length`);
    deep(actual.direction.map((value)=>Number(value.toFixed(12))),probe.direction,`line ${probe.id} direction`);
  }
} finally { fs.rmSync(scratch,{recursive:true,force:true}); }

const mini=fs.readFileSync(path.join(import.meta.dirname,'oracle-mini-map.sql'),'utf8').toUpperCase();
const production=fs.readFileSync(path.join(import.meta.dirname,'oracle-production.sql'),'utf8').toUpperCase();
const audit=fs.readFileSync(path.join(import.meta.dirname,'source-audit.mjs'),'utf8');
check(mini.includes("CURRENT_USER')") && mini.includes("LIKE 'DOOMDB_EVAL%'"), 'mini-map schema guard absent');
check((mini.match(/SDO_FILTER/g)??[]).length >= 6, 'mini-map lacks MBR probes');
check((mini.match(/SDO_RELATE/g)??[]).length >= 4, 'mini-map lacks exact probes');
check(mini.includes('ASSERT_EQ(L_FILTER,1') && mini.includes('ASSERT_EQ(L_EXACT,0'), 'false-positive oracle absent');
check(production.includes('VALIDATE_GEOMETRY_WITH_CONTEXT'), 'production geometry validity oracle absent');
check(production.includes('DOMIDX_STATUS') && production.includes('DOMIDX_OPSTATUS'), 'domain-index status oracle incomplete');
check(production.includes('ROUND(SQRT(') && production.includes("'MASK=ANYINTERACT'"), 'metric or exact production oracle absent');
check(audit.includes("filterStatements.length > 0"), 'source audit does not fail on missing filter queries');

const baselines = [
  ['evaluator/integrity.json','2699e0e0f6e93593d8172ea19a048d2ad6ebabb57aef2604a81782c25f2882a3'],
  ['evaluator/integrity.pending-T2.2.json','23ca7de9b0a78fe6697350911ac0800f48c9fbd9b6851daed6d10cb982b1b04b'],
  ['evaluator/integrity.pending-T2.3.json','3f13e8dcc3294a0efa096365d3fcd7c70b043da3ff4734e912044878b140add9'],
  ['evaluator/integrity.pending-T2.4.json','7bf6d81695ff3b7085f70107b1925e3aaf72587ead46cd096cdbd6e79e0d9354']
];
for (const [relative,hash] of baselines) equal(sha(path.join(root,relative)),hash,`${relative} changed`);
process.stdout.write(`PASS T3.2-EVAL-SELF-CHECK (${checks}/${checks} fixture-contract assertions)\n`);
