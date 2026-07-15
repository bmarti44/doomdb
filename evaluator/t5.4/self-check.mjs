import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {WIDTH,HEIGHT,HUD_Y,changedRegion,compose,drawText,frameRows,sha256} from './reference.mjs';
const here=import.meta.dirname,root=path.resolve(here,'../..'),load=n=>JSON.parse(fs.readFileSync(path.join(here,n),'utf8'));
const f=load('fixtures.json'),expected=load('expectations.json'),manifest=load('test-ids.json'),mutations=load('mutation-specs.json');
let checks=0;const ok=(v,m)=>{assert.ok(v,m);checks++},eq=(a,b,m)=>{assert.equal(a,b,m);checks++},deep=(a,b,m)=>{assert.deepEqual(a,b,m);checks++};
eq(WIDTH,320,'fixed width');eq(HEIGHT,200,'fixed height');eq(HUD_Y,168,'HUD boundary');
eq(manifest.tests.length,22,'stable id count');eq(new Set(manifest.tests.map(x=>x.id)).size,22,'unique ids');
eq(manifest.tests.reduce((n,x)=>n+x.assertions,0),manifest.declaredAssertions,'assertion sum');eq(manifest.declaredAssertions,448566,'declared assertions');
ok(manifest.tests.every(x=>/^T54-[A-Z0-9-]+$/.test(x.id)&&x.intent.length>=75),'weak test contracts');
eq(mutations.mutations.length,18,'mutation count');eq(new Set(mutations.mutations.map(x=>x.id)).size,18,'unique mutants');
ok(mutations.mutations.every(x=>manifest.tests.some(t=>t.id===x.killedBy)&&x.change.length>=75&&x.reason.length>=75),'weak mutation contracts');
eq(f.states.length,9,'mode/state coverage');eq(expected.frames.length,f.states.length,'expectation coverage');
const states=new Map(f.states.map(x=>[x.name,x])),frames=new Map();
for(const state of f.states){const a=compose(f,state),b=compose(f,{...state});frames.set(state.name,a);eq(a.length,64000,`${state.name} canvas`);eq(sha256(a),expected.frames.find(x=>x.name===state.name).sha256,`${state.name} hash`);deep(a,b,`${state.name} deterministic`);const rows=frameRows(a);eq(rows.length,64000,`${state.name} rows`);eq(new Set(rows.map(r=>`${r.column}:${r.row}`)).size,64000,`${state.name} unique coords`);ok(rows.every(r=>Number.isInteger(r.cidx)&&r.cidx>=0&&r.cidx<=255),`${state.name} palette`);}
const game=frames.get('game');
const weaponState={...states.get('game'),weapon:'SHOTGUN'};const weaponRegion=changedRegion(game,compose(f,weaponState));deep(weaponRegion,{count:3976,x0:114,x1:205,y0:122,y1:167},'weapon-only region');
deep(changedRegion(game,frames.get('paused')),{count:240,x0:132,x1:187,y0:76,y1:87},'pause region');
deep(changedRegion(frames.get('menu-0'),frames.get('menu-2')),{count:155,x0:126,x1:159,y0:66,y1:102},'menu selection regions');
deep(changedRegion(frames.get('automap'),frames.get('automap-full')),{count:239,x0:40,x1:280,y0:35,y1:140},'full map hidden line region');
const hv=changedRegion(game,frames.get('hud-variation'));eq(hv.y0,184,'HUD variation y0');eq(hv.y1,188,'HUD variation y1');ok(hv.x0>=0&&hv.x1<320,'HUD variation x bounds');
for(let x=0;x<320;x++)for(let y=168;y<200;y++)eq(frames.get('automap')[x*200+y],game[x*200+y],`automap HUD ${x},${y}`);
const text=Buffer.alloc(64000);const bounds=drawText(text,'SECRETS: 100%',200,194);ok(bounds.x0>=0&&bounds.x1<320&&bounds.y0>=0&&bounds.y1<200,'maximum text bounds');
const opaque=compose(f,states.get('paused'),{opaqueTransparency:true});ok(!opaque.equals(frames.get('paused')),'transparent hole witness');
const transformed={...f,geometry:f.geometry.map(g=>({...g,x1:g.x1+11,y1:g.y1+7,x2:g.x2+11,y2:g.y2+7}))};const shifted=compose(transformed,states.get('automap'));let matches=0;for(let x=0;x<309;x++)for(let y=0;y<161;y++)if(frames.get('automap')[x*200+y]===shifted[(x+11)*200+y+7])matches++;ok(matches>49000,'translated automap raster correspondence');
const fileSha=p=>crypto.createHash('sha256').update(fs.readFileSync(path.join(root,p))).digest('hex');
const inherited=[
  ['evaluator/integrity.json','2699e0e0f6e93593d8172ea19a048d2ad6ebabb57aef2604a81782c25f2882a3'],
  ['evaluator/integrity.pending-T2.2.json','23ca7de9b0a78fe6697350911ac0800f48c9fbd9b6851daed6d10cb982b1b04b'],
  ['evaluator/integrity.pending-T2.3.json','3f13e8dcc3294a0efa096365d3fcd7c70b043da3ff4734e912044878b140add9'],
  ['evaluator/integrity.pending-T2.4.json','7bf6d81695ff3b7085f70107b1925e3aaf72587ead46cd096cdbd6e79e0d9354'],
  ['evaluator/integrity.pending-T3.2.json','d617cdd9e5f8a36606d6606d6c61a514f46b3b5545f4526e48361a1c04208050'],
  ['evaluator/integrity.pending-T3.3.json','8ccb54c64ed3e4e34ec3e1f84cda03a3b3ebe4a7ec8bf26c5688ab0b96260e37'],
  ['evaluator/integrity.pending-T3.4.json','6f1bd528776949ca4bc4b08f3fae80b810c38c11c7a9d556be134170400f5651'],
  ['evaluator/integrity.pending-T4.1.json','158c94e68220bbea4809f8688cb94549b07423655aaa4017b6fcaf3703c28ae6'],
  ['evaluator/integrity.pending-T4.2.json','1cd2021266edea250fd11f9d285a5cdeb3d1fe826c5b557a3d95408d4cd70429'],
  ['evaluator/integrity.pending-T4.3.json','38927540dc430ff6d3476738f122577ec15bf4ab104628282a4f19a7e7c5977a'],
  ['evaluator/integrity.pending-T5.1.json','7b02f8ce55c7f67493134cae9c2bc928340fe39b5abfc5457a3dda4c0e5844f7']
];
for(const [p,h] of inherited)eq(fileSha(p),h,`${p} changed`);
assert.equal(fileSha('evaluator/integrity.pending-T5.2.json'),'b95895c22b3fb8cf5df42a314538ecdc2802abb744815196604070fab900d13c','final T5.2 evaluator chain changed');
assert.equal(fileSha('goldens/integrity-T5.2.json'),'e59b635cdda850ae092d940ac38fb62cbf8e8b2e1ea6812ad67b61a7ebcc4995','human-reviewed T5.2 visible chain changed');
assert.equal(fileSha('evaluator/integrity.pending-T5.3.json'),'8e5969b517dac26fa2143dfd6cbedee9cde1ec1a0e09eca775a4f72070aebc1b','final T5.3 evaluator chain changed');
assert.equal(fileSha('goldens/integrity-T5.3.json'),'24b543562a13c80db22edd376e93a7a5b3c30d28dc2e01db7d28a165210c0860','human-reviewed T5.3 visible chain changed');
const visibleManifest='goldens/integrity-T5.4.json',visible=JSON.parse(fs.readFileSync(path.join(root,visibleManifest),'utf8'));
assert.equal(fileSha(visibleManifest),'5f227adead95b36364b1d7bd06cd68a745ae4f55565885c21229bc7dc983c854','human-reviewed T5.4 visible chain changed');
assert.match(visible.approval,/^HUMAN_REVIEWED_APPROVED/,'T5.4 visible approval missing');
assert.equal(Object.keys(visible.files).length,20,'T5.4 reviewed visible artifact count changed');
process.stdout.write(`PASS T5.4-EVAL-SELF-CHECK (${checks}/${checks} fixture-contract assertions)\n`);
