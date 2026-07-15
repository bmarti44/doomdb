#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const mutations = [
  ['T2.3-MUT-DROP-THING','defs',d=>{d.thingTypes=d.thingTypes.filter(x=>x.id!==3001);},/thing type id closure mismatch/],
  ['T2.3-MUT-UNKNOWN','defs',d=>{d.thingTypes.find(x=>x.id===58).category='unknown';},/thing 58 category is a placeholder/],
  ['T2.3-MUT-BREAK-STATE','defs',d=>{d.states.find(x=>x.id==='THING_3001_ATTACK_1').next='MISSING_STATE';},/unresolved next MISSING_STATE/],
  ['T2.3-MUT-DROP-SPRITE','closure',d=>{d.assets=d.assets.filter(x=>!(x.kind==='sprite_patch'&&x.name==='TROOA1'));},/sprite closure missing TROOA1/],
  ['T2.3-MUT-DROP-SOUND','closure',d=>{d.assets=d.assets.filter(x=>!(x.kind==='sound'&&x.name==='DSFIRSHT'));},/sound closure missing DSFIRSHT|required sound absent: DSFIRSHT/],
  ['T2.3-MUT-DROP-UI','closure',d=>{d.assets=d.assets.filter(x=>!(x.kind==='ui_patch'&&x.name==='WISPLAT'));},/required UI patch absent: WISPLAT/],
  ['T2.3-MUT-BREAK-TEXTURE','closure',d=>{d.assets.find(x=>x.kind==='wall_texture'&&x.name==='SFALL1').sourceLumps.pop();},/wall_texture:SFALL1: sourceLumps required|SFALL1: exact patch dependency mismatch/],
  ['T2.3-MUT-ANIM-ORDER','animations',d=>{[d.groups[1].frames[1],d.groups[1].frames[2]]=[d.groups[1].frames[2],d.groups[1].frames[1]];},/animation|Expected values to be strictly deep-equal/],
  ['T2.3-MUT-SPECIAL','defs',d=>{const x=d.linedefSpecials.find(x=>x.id===26);x.semantics=x.semantics.filter(v=>v!=='BLUE_KEY');},/linedef special 26: semantics mismatch/],
  ['T2.3-MUT-PICKUP','defs',d=>{d.pickups.find(x=>x.thingType===5).consume=false;},/pickup 5: must consume/],
  ['T2.3-MUT-RNG','rng',d=>{d.values[173]^=1;},/Expected values to be strictly deep-equal|rng\.values/],
  ['T2.3-MUT-GPL-SOURCE','defs',d=>{d.sources.find(x=>x.id==='doomwiki-behavior').copiedCodeOrData=true;},/copied code\/data is forbidden/]
];
const names = {defs:'engine-defs.json',closure:'asset-closure.json',animations:'animation-groups.json',rng:'rng-table.json'};

for (const [id,document,mutate,expectedFailure] of mutations) {
  const temp=fs.mkdtempSync(path.join(os.tmpdir(),'doomdb-t2.3-mutation-'));
  try {
    fs.cpSync(path.join(root,'evaluator'),path.join(temp,'evaluator'),{recursive:true});
    fs.mkdirSync(path.join(temp,'tools/wad'),{recursive:true});
    fs.mkdirSync(path.join(temp,'reports'),{recursive:true});
    fs.symlinkSync(path.join(root,'vendor'),path.join(temp,'vendor'),'dir');
    for(const file of Object.values(names)) fs.copyFileSync(path.join(root,'tools/wad',file),path.join(temp,'tools/wad',file));
    fs.copyFileSync(path.join(root,'reports/t2.3-behavior-sources.md'),path.join(temp,'reports/t2.3-behavior-sources.md'));
    const target=path.join(temp,'tools/wad',names[document]);
    const value=JSON.parse(fs.readFileSync(target,'utf8'));
    mutate(value);
    fs.writeFileSync(target,`${JSON.stringify(value,null,2)}\n`);
    const run=spawnSync(process.execPath,['evaluator/t2.3/run-visible.mjs'],{cwd:temp,encoding:'utf8',timeout:30000});
    assert.notEqual(run.status,0,`${id}: mutation survived`);
    assert.match(`${run.stdout}\n${run.stderr}`,expectedFailure,`${id}: failed outside its intended semantic assertion`);
    process.stdout.write(`PASS ${id}\n`);
  } finally { fs.rmSync(temp,{recursive:true,force:true}); }
}
process.stdout.write('PASS T2.3-MUTATIONS (12/12 isolated semantic mutations killed)\n');
