import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';import {spawnSync} from 'node:child_process';
import {WIDTH,HEIGHT,canonical,chooseRotation,compose,rotationFor,sha} from './reference.mjs';
import {decodeE1M1,traceMap} from '../t4.1/reference.mjs';
const here=import.meta.dirname,root=path.resolve(here,'../..'),load=n=>JSON.parse(fs.readFileSync(path.join(here,n),'utf8'));
const fileSha=p=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,p))).digest('hex');
assert.equal(fileSha('evaluator/integrity.pending-T5.1.json'),'7b02f8ce55c7f67493134cae9c2bc928340fe39b5abfc5457a3dda4c0e5844f7','final T5.1 evaluator chain changed');
assert.equal(fileSha('evaluator/integrity.pending-T5.2.json'),'b95895c22b3fb8cf5df42a314538ecdc2802abb744815196604070fab900d13c','final T5.2 evaluator chain changed');
assert.equal(fileSha('goldens/integrity-T5.2.json'),'e59b635cdda850ae092d940ac38fb62cbf8e8b2e1ea6812ad67b61a7ebcc4995','human-reviewed T5.2 visible chain changed');
const visibleManifest='goldens/integrity-T5.3.json',visible=JSON.parse(fs.readFileSync(path.join(root,visibleManifest),'utf8'));
assert.equal(fileSha(visibleManifest),'24b543562a13c80db22edd376e93a7a5b3c30d28dc2e01db7d28a165210c0860','human-reviewed T5.3 visible chain changed');
assert.match(visible.approval,/^HUMAN_REVIEWED_APPROVED/,'T5.3 visible approval missing');
assert.equal(Object.keys(visible.files).length,7,'T5.3 reviewed visible artifact count changed');
const oracleSource=fs.readFileSync(path.join(here,'oracle-production.sql'),'utf8').replace(/\s+/g,' ').toUpperCase();
assert.match(oracleSource,/INSERT INTO SECTOR_STATE\s*\(\s*SESSION_TOKEN\s*,\s*SECTOR_ID\s*,\s*FLOOR_HEIGHT\s*,\s*CEILING_HEIGHT\s*,\s*LIGHT_LEVEL\s*,\s*SECRET_FOUND\s*,\s*DAMAGE_CLOCK\s*\)/,'SECTOR_STATE insert must name every evaluator-owned value in the final schema');
assert.match(oracleSource,/SELECT K_TOKEN\s*,\s*SECTOR_ID\s*,\s*FLOOR_HEIGHT\s*,\s*CEILING_HEIGHT\s*,\s*LIGHT_LEVEL\s*,\s*0\s*,\s*0 FROM DOOM_MAP_SECTOR/,'SECTOR_STATE evaluator defaults changed');
const f=load('fixtures.json'),e=load('expectations.json'),ids=load('test-ids.json'),mut=load('mutation-specs.json');
let checks=0;const ok=(v,m)=>{assert.ok(v,m);checks++},eq=(a,b,m)=>{assert.equal(a,b,m);checks++},deep=(a,b,m)=>{assert.deepEqual(a,b,m);checks++};
eq(ids.tests.length,17,'id count');eq(new Set(ids.tests.map(x=>x.id)).size,17,'unique ids');eq(ids.tests.reduce((n,x)=>n+x.assertions,0),988,'manifest sum');eq(ids.declaredAssertions,988,'declared');
ok(ids.tests.every(x=>/^T53-[A-Z0-9-]+$/.test(x.id)&&x.intent.length>=80),'stable meaningful ids');
eq(mut.mutations.length,18,'mutation count');eq(new Set(mut.mutations.map(x=>x.id)).size,18,'unique mutations');ok(mut.mutations.every(x=>ids.tests.some(t=>t.id===x.killedBy)&&x.change.length>=70&&x.reason.length>=70),'mutation contracts');

const results=new Map();
for(const s of f.scenes){const got=compose({...s,pose:f.pose,patches:f.patches}),want=e.scenes.find(x=>x.name===s.name);results.set(s.name,got);eq(got.candidates.length,want.candidates,`${s.name} candidates`);eq(got.winners.length,want.winners,`${s.name} winners`);eq(sha(canonical(got)),want.sha256,`${s.name} hash`);ok(got.winners.every(x=>x.column>=0&&x.column<WIDTH&&x.row>=0&&x.row<HEIGHT),`${s.name} bounds`);}
deep(results.get('transparent-mask').winners.map(x=>[x.row,x.palette]),[[4,90],[6,91]],'transparent middle hole');
eq(results.get('wall-occlusion').winners.length,0,'wall hides sprite');
ok(results.get('sprite-depth').winners.every(x=>x.sourceId===30),'near sprite wins');
deep(results.get('equal-depth').winners.at(-1),results.get('equal-depth').winners.find(x=>x.row===5),'tie spot exists');
eq(results.get('equal-depth').winners.find(x=>x.row===5).sourceKind,'MASKED','class tie');eq(results.get('sector-clip').winners[0].row,5,'sector row');

const rotations=[];for(let i=0;i<8;i++){const a=i*45;rotations.push(rotationFor({x:10*Math.cos(a*Math.PI/180),y:10*Math.sin(a*Math.PI/180)},{x:0,y:0,angle:0}));}deep(rotations,e.rotations,'eight rotations');
eq(rotationFor({x:10*Math.cos(22.499*Math.PI/180),y:10*Math.sin(22.499*Math.PI/180)},{x:0,y:0,angle:0}),1,'lower half boundary');
eq(rotationFor({x:10*Math.cos(22.501*Math.PI/180),y:10*Math.sin(22.501*Math.PI/180)},{x:0,y:0,angle:0}),2,'upper half boundary');
deep(chooseRotation(2,f.baseFrames),{asset:'MIRR2',flip:1},'dual lump mirror');deep(chooseRotation(1,{0:{asset:'ITEM0',flip:0}}),{asset:'ITEM0',flip:0},'declared zero fallback');

const moved={...f.scenes[2],pose:{...f.pose,x:37,y:-19},patches:f.patches,sprites:f.scenes[2].sprites.map(s=>({...s,x:s.x+37,y:s.y-19}))};
eq(canonical(compose(moved)),canonical(results.get('sprite-depth')),'joint translation');
const outside={pose:f.pose,patches:f.patches,sprites:[],masked:[{id:1,depth:1,asset:'X',sectorId:1,pixels:[{column:-1,row:2,assetX:0,assetY:0,palette:1},{column:16,row:2,assetX:0,assetY:0,palette:2}]}]};
eq(compose(outside).winners.length,0,'screen clipping');eq(compose(outside,{ignoreScreen:true}).winners.length,2,'screen witness');
const equalWall={pose:f.pose,patches:f.patches,wallDepth:{4:3},masked:[{id:1,depth:3,asset:'X',sectorId:1,pixels:[{column:4,row:4,assetX:0,assetY:0,palette:1}]}],sprites:[]};
eq(compose(equalWall).winners.length,0,'equal wall hidden');eq(compose(equalWall,{wallBehindSprite:true}).winners.length,1,'equal wall witness');

const defs=JSON.parse(fs.readFileSync(path.join(root,'tools/wad/engine-defs.json'),'utf8')),manifest=JSON.parse(fs.readFileSync(path.join(root,'sql/seed/seed-manifest.json'),'utf8'));
const assets=new Set(manifest.assets.filter(x=>x.kind==='sprite_patch').map(x=>x.name)),states=defs.states.filter(x=>!x.id.startsWith('WEAPON_'));
const hasRotation=(p,fr,r)=>[...assets].some(n=>n.startsWith(p)&&Array.from({length:Math.floor((n.length-4)/2)},(_,i)=>n.slice(4+i*2,6+i*2)).includes(fr+r));
eq(states.length,e.closure.worldStates,'world state count');eq(defs.thingTypes.filter(x=>x.spawnState).length,e.closure.renderableThingTypes,'renderable types');eq(assets.size,e.closure.spriteAssets,'sprite asset count');
for(const [category,count] of Object.entries(e.closure.requiredCategories))eq(defs.thingTypes.filter(x=>x.category===category).length,count,`${category} count`);
for(const s of states){ok(s.sprite&&s.sprite.prefix&&s.sprite.frame,`${s.id} sprite`);if(s.sprite.rotations==='0')ok(assets.has(`${s.sprite.prefix}${s.sprite.frame}0`),`${s.id} rotation zero`);else for(let r=1;r<=8;r++)ok(hasRotation(s.sprite.prefix,s.sprite.frame,r),`${s.id} rotation ${r}`);}
eq(f.diagnosticPoses.length,e.closure.diagnosticPoses,'diagnostic poses');deep(f.diagnosticPoses[0],{x:-416,y:256,angle:0},'pinned spawn pose');
const scratch=fs.mkdtempSync(path.join(os.tmpdir(),'t53-wad-'));try{
  const z=spawnSync('unzip',['-q',path.join(root,'vendor/freedoom/0.13.0/freedoom-0.13.0.zip'),'freedoom-0.13.0/freedoom1.wad','-d',scratch]);eq(z.status,0,'WAD extraction');
  const map=decodeE1M1(fs.readFileSync(path.join(scratch,'freedoom-0.13.0/freedoom1.wad'))),types=new Map(defs.thingTypes.map(x=>[x.id,x]));
  for(let pi=0;pi<f.diagnosticPoses.length;pi++){const pose=f.diagnosticPoses[pi],traces=traceMap(map,pose),a=pose.angle*Math.PI/180,rows=[];
    for(const t of map.things){const depth=(t.x-pose.x)*Math.cos(a)+(t.y-pose.y)*Math.sin(a),side=-(t.x-pose.x)*Math.sin(a)+(t.y-pose.y)*Math.cos(a);if(depth<=1e-9||Math.abs(side/depth)>1||!types.get(t.type)?.spawnState)continue;const column=Math.max(0,Math.min(319,Math.floor(160+160*side/depth))),wall=traces[column].nearestSolid?.t??4096;if(depth<wall-1e-6)rows.push([t.id,t.type,Number(depth.toFixed(6)),column,rotationFor(pose,{x:t.x,y:t.y,angle:t.angle})]);}
    rows.sort((x,y)=>x[3]-y[3]||x[2]-y[2]||x[0]-y[0]);const doc=rows.map(x=>x.join(':')).join('\n')+'\n',want=e.diagnostics[pi];eq(rows.length,want.count,`diagnostic ${pi} count`);eq(sha(doc),want.sha256,`diagnostic ${pi} identity hash`);deep(rows[0],want.first,`diagnostic ${pi} first spot`);deep(rows.at(-1),want.last,`diagnostic ${pi} last spot`);}
}finally{fs.rmSync(scratch,{recursive:true,force:true});}
process.stdout.write(`PASS T5.3-EVAL-SELF-CHECK (${checks}/${checks} fixture-contract assertions)\n`);
