#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const original = fs.readFileSync(path.join(root,'tools/wad/generate-seed.mjs'),'utf8');
const mutations = [
  ['T2.4-M01','const MAX_ROWS = 500;','const MAX_ROWS = 501;'],
  ['T2.4-M02',"fs.writeFileSync(path.join(out, relative), file.text, 'ascii');","fs.writeFileSync(path.join(out, relative), file.text.replaceAll('\\n','\\r\\n'), 'ascii');"],
  ['T2.4-M03',"const manifest = { schema:1,","const manifest = { schema:1,generatedAt:new Date().toISOString(),"],
  ['T2.4-M04',"const files = writeOutput(args['--out'], generated);","const files = writeOutput(args['--out'], generated).reverse();"],
  ['T2.4-M05',"const mapLump = new Map(mapSources.map((source) => [source.name, source])), map = decodeMap(mapLump);","const mapLump = new Map(mapSources.map((source) => [source.name, source])), map = decodeMap(mapLump); map.things.pop();"],
  ['T2.4-M06','for (let i = start + 1; i < rows.length; i += 1) if (/^(?:E\\dM\\d|MAP\\d\\d)$/.test(rows[i].name))','for (let i = rows.length; i < rows.length; i += 1) if (/^(?:E\\dM\\d|MAP\\d\\d)$/.test(rows[i].name))'],
  ['T2.4-M07','size:source.size,sha256:source.sha256,selection','size:source.size+1,sha256:source.sha256,selection'],
  ['T2.4-M08',"selection:'last-occurrence'","selection:'first-occurrence'"],
  ['T2.4-M09','const assetKeys = new Set(assets.map((asset) => `${asset.kind}:${asset.name}`));',"{ const source=last(rows,'FLOOR4_8'); assets.push({assetId:assets.length,kind:'flat',name:'FLOOR4_8',sourceLumps:['FLOOR4_8'],sourceSha256:[source.sha256],rawSha256:source.sha256}); }\nconst assetKeys = new Set(assets.map((asset) => `${asset.kind}:${asset.name}`));"],
  ['T2.4-M10','for (const approved of [...closure.assets].sort','for (const approved of [...closure.assets].filter((a)=>a.name!==\'POSSA1\').sort'],
  ['T2.4-M11','const pixels = new Int16Array(width * height).fill(-1);','const pixels = new Int16Array(width * height).fill(0);'],
  ['T2.4-M12','for (const placement of definition.patches) {','for (const placement of [...definition.patches].reverse()) {'],
  ['T2.4-M13','sha256:fileHash','sha256:(relative===\'010_things.sql\'?\'0\'.repeat(64):fileHash)'],
  ['T2.4-M14',"assets.flatMap(a=>a.sourceLumps.map((name,i)=>[sqlString(a.kind),sqlString(a.name),sqlNumber(i),sqlString(name),sqlString(a.sourceSha256[i])]))","assets.flatMap(a=>a.sourceLumps.map((name,i)=>[sqlString(a.kind),sqlString(a.name),sqlNumber(i),sqlString(name),sqlString(a.sourceSha256[i])])).slice(1)"],
];

const selectedMutations = process.argv[2] ? mutations.slice(mutations.findIndex(([id])=>id===process.argv[2])) : mutations;
assert.ok(selectedMutations.length > 0 && (!process.argv[2] || selectedMutations[0][0]===process.argv[2]),'unknown starting mutation id');
for (const [id,find,replace] of selectedMutations) {
  assert.ok(original.includes(find),`${id}: source patch does not apply`);
  const scratch=fs.mkdtempSync(path.join(os.tmpdir(),`doomdb-${id}-`));
  try {
    fs.mkdirSync(path.join(scratch,'tools/wad'),{recursive:true});
    fs.mkdirSync(path.join(scratch,'evaluator'),{recursive:true});
    fs.cpSync(path.join(root,'evaluator/t2.4'),path.join(scratch,'evaluator/t2.4'),{recursive:true});
    fs.symlinkSync(path.join(root,'vendor'),path.join(scratch,'vendor'),'dir');
    for(const file of ['engine-defs.json','asset-closure.json','animation-groups.json','rng-table.json']) fs.copyFileSync(path.join(root,'tools/wad',file),path.join(scratch,'tools/wad',file));
    fs.writeFileSync(path.join(scratch,'tools/wad/generate-seed.mjs'),original.replace(find,replace));
    const run=spawnSync(process.execPath,['evaluator/t2.4/run-visible.mjs'],{cwd:scratch,encoding:'utf8',timeout:120000,maxBuffer:16*1024*1024});
    const output=`${run.stdout}\n${run.stderr}`;
    const infrastructureGreen=!/SyntaxError|ERR_MODULE_NOT_FOUND|timed out|heap out of memory/i.test(output) && run.error?.code!=='ETIMEDOUT';
    assert.ok(infrastructureGreen,`${id}: evaluator infrastructure failed: ${output.slice(-2000)}`);
    assert.notEqual(run.status,0,`${id}: semantic mutation survived`);
    assert.match(output,/AssertionError/,`${id}: did not die through an assertion`);
    process.stdout.write(`PASS ${id}\n`);
  } finally { fs.rmSync(scratch,{recursive:true,force:true}); }
}
process.stdout.write(`PASS T2.4-MUTATIONS (${selectedMutations.length}/${selectedMutations.length} isolated semantic mutations killed)\n`);
