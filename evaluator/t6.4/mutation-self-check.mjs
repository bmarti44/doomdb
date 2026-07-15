import assert from 'node:assert/strict';import fs from 'node:fs';import {append,clone,load,newStore,reconstruct,rewind,run,save,startReplay,stepReplay} from './reference.mjs';
const f=JSON.parse(fs.readFileSync(new URL('./fixtures.json',import.meta.url))),specs=JSON.parse(fs.readFileSync(new URL('./mutation-specs.json',import.meta.url))).mutations;
const rejects=fn=>{try{fn();return false}catch{return true}},base=()=>newStore(f.initial);let killed=0;
function witness(mode){
  if(mode==='overwriteCommand'){const a=base(),b=base();run(a,f.commands.slice(0,2));run(b,f.commands.slice(0,2),{overwriteCommand:true});return a.commands.length!==b.commands.length;}
  if(mode==='skipPeriodic'){const a=base(),b=base();run(a,f.commands.slice(0,4));run(b,f.commands.slice(0,4),{skipPeriodic:true});return a.snapshots.length!==b.snapshots.length;}
  if(mode==='shallowSnapshot'){const s=base();run(s,f.commands.slice(0,4),{shallowSnapshot:true});return rejects(()=>reconstruct(s,s.session.lineage,4));}
  if(mode==='oldestSnapshot'){const s=base();run(s,f.commands.slice(0,8));s.snapshots[0].blob='{}';return !rejects(()=>reconstruct(s,s.session.lineage,8))&&rejects(()=>reconstruct(s,s.session.lineage,8,{oldestSnapshot:true}));}
  if(mode==='ignoreCommandChain'){const s=base();run(s,f.commands.slice(0,6));s.commands[5].previousSha='f'.repeat(64);return rejects(()=>reconstruct(s,s.session.lineage,6))&&!rejects(()=>reconstruct(s,s.session.lineage,6,{ignoreCommandChain:true}));}
  if(mode==='acceptReorder'){const s=base();run(s,f.commands.slice(0,3));const normal=reconstruct(s,s.session.lineage,3).state;const changed=reconstruct(s,s.session.lineage,3,{acceptReorder:true}).state;return JSON.stringify(normal)!==JSON.stringify(changed);}
  if(mode==='ignoreStateHash'){const s=base();run(s,f.commands.slice(0,6));s.commands[5].stateSha='0'.repeat(64);return rejects(()=>reconstruct(s,s.session.lineage,6))&&!rejects(()=>reconstruct(s,s.session.lineage,6,{ignoreStateHash:true}));}
  if(mode==='ignoreFrameHash'){const s=base();run(s,f.commands.slice(0,6));s.commands[5].frameSha='0'.repeat(64);return rejects(()=>reconstruct(s,s.session.lineage,6))&&!rejects(()=>reconstruct(s,s.session.lineage,6,{ignoreFrameHash:true}));}
  if(mode==='ignoreEventChain'){const s=base();run(s,f.commands.slice(0,6));s.events.at(-1).value++;return rejects(()=>reconstruct(s,s.session.lineage,6))&&!rejects(()=>reconstruct(s,s.session.lineage,6,{ignoreEventChain:true}));}
  if(mode==='duplicateEventOrdinal'){const s=base();append(s,{turn:0,forward:0,fire:1,use:1},{duplicateEventOrdinal:true});return s.events.length===2&&s.events[0].ordinal===s.events[1].ordinal&&rejects(()=>reconstruct(s,s.session.lineage,1));}
  if(mode==='omitSaveSnapshot'){const a=base(),b=base();run(a,f.commands.slice(0,3));run(b,f.commands.slice(0,3));save(a,7);save(b,7,{omitSaveSnapshot:true});return a.snapshots.length===b.snapshots.length+1;}
  if(mode==='loadWrongSlot'){const s=base();run(s,f.commands.slice(0,2));save(s,1);run(s,f.commands.slice(2,4));save(s,2);return load(cloneStore(s),1).stateSha!==load(cloneStore(s),1,{loadWrongSlot:true}).stateSha;}
  if(mode==='keepCurrentState'){const s=base();run(s,f.commands.slice(0,2));save(s,1);run(s,f.commands.slice(2,5));return load(s,1,{keepCurrentState:true}).stateSha!==s.saves.get(1).stateSha;}
  if(mode==='reuseLineage'){const s=base();run(s,f.commands.slice(0,2));save(s,1);const old=s.session.lineage;load(s,1,{reuseLineage:true});return s.session.lineage===old;}
  if(mode==='deleteFuture'){const s=base();run(s,f.commands.slice(0,8));const n=s.commands.length;rewind(s,s.session.lineage,3,{deleteFuture:true});return s.commands.length<n;}
  if(mode==='ignoreReplayRange'){const s=base();run(s,f.commands.slice(0,8));const id=startReplay(s,s.session.lineage,0,4,{ignoreReplayRange:true});let x;do{x=stepReplay(s,id)}while(!x.done);return x.tic===8;}
  if(mode==='replayLiveState'){const s=base();run(s,f.commands.slice(0,8));const id=startReplay(s,s.session.lineage,0,2);const x=stepReplay(s,id,{replayLiveState:true});return x.stateSha!==s.commands[0].stateSha;}
  if(mode==='badRecordedState'){const s=base();run(s,f.commands.slice(0,6),{badRecordedState:true});return rejects(()=>reconstruct(s,s.session.lineage,6));}
  if(mode==='badRecordedFrame'){const s=base();run(s,f.commands.slice(0,6),{badRecordedFrame:true});return rejects(()=>reconstruct(s,s.session.lineage,6));}
  if(mode==='wallClockSnapshot'){const a=base(),b=base();run(a,f.commands.slice(0,4));run(b,f.commands.slice(0,4),{wallClockSnapshot:true});return JSON.stringify(a.snapshots.map(x=>x.tic))!==JSON.stringify(b.snapshots.map(x=>x.tic));}
  return false;
}
function cloneStore(s){const x=structuredClone({...s,saves:undefined,replays:undefined});x.saves=new Map([...s.saves].map(([k,v])=>[k,clone(v)]));x.replays=new Map();return x;}
for(const spec of specs){assert.ok(witness(spec.mode),`${spec.id} survived its focused witness`);killed++;}
process.stdout.write(`PASS T6.4-EVAL-MUTATION-SELF-CHECK (${killed}/${specs.length} isolated mutations killed)\n`);
