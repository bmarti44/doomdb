import crypto from 'node:crypto';

export const C=Object.freeze({SNAPSHOT_INTERVAL:4,SCHEMA:1,REPLAY_SCHEMA:1});
const enc=v=>JSON.stringify(v);
export const sha=v=>crypto.createHash('sha256').update(typeof v==='string'?v:enc(v)).digest('hex');
export const clone=v=>structuredClone(v);

export function canonicalState(state){
  return {tic:state.tic,x:state.x,y:state.y,angle:state.angle,health:state.health,
    ammo:state.ammo,rng:state.rng,door:state.door,score:state.score};
}
export const stateSha=state=>sha(canonicalState(state));
export const frameSha=state=>sha({v:1,tic:state.tic,x:state.x,y:state.y,angle:state.angle,door:state.door,light:state.rng%32});

function commandBody(c){return {turn:c.turn,forward:c.forward,fire:c.fire,use:c.use};}
function evolve(prior,c){
  const s=clone(prior);s.tic++;
  s.angle=(s.angle+c.turn+360)%360;s.x+=Math.round(Math.cos(s.angle*Math.PI/180))*c.forward;s.y+=Math.round(Math.sin(s.angle*Math.PI/180))*c.forward;
  if(c.fire&&s.ammo>0){s.ammo--;s.rng=(s.rng*17+23)%256;s.score+=s.rng%7;}
  if(c.use)s.door=Math.min(128,s.door+8);
  return s;
}
function snapshot(session,state,reason,mutation={}){
  const document={schema:C.SCHEMA,lineage:session.lineage,state:canonicalState(state),
    frontier:session.frontier,commandSha:session.commandHead,eventSha:session.eventHead};
  if(mutation.shallowSnapshot)delete document.state.ammo;
  return {lineage:session.lineage,tic:state.tic,frontier:session.frontier,
    firstCommandSeq:session.lineageFirstSeq,lastCommandSeq:session.frontier,
    stateSha:stateSha(state),commandSha:session.commandHead,eventSha:session.eventHead,
    reason,blob:enc(document),blobSha:sha(document)};
}
function verifySnapshot(snap){
  const doc=JSON.parse(snap.blob);
  if(sha(doc)!==snap.blobSha||stateSha(doc.state)!==snap.stateSha||doc.lineage!==snap.lineage||
     doc.frontier!==snap.frontier||doc.commandSha!==snap.commandSha||doc.eventSha!==snap.eventSha)
    throw new Error('SNAPSHOT_CORRUPT');
  return doc;
}

export function newStore(initial={tic:0,x:0,y:0,angle:0,health:100,ammo:20,rng:7,door:0,score:0}){
  const lineage=sha('NEW-GAME|'+stateSha(initial));
  const store={nextSeq:1,commands:[],events:[],snapshots:[],saves:new Map(),replays:new Map(),nextReplay:1,
    session:{lineage,lineageFirstSeq:1,frontier:0,commandHead:'0'.repeat(64),eventHead:'0'.repeat(64),state:clone(initial)}};
  store.snapshots.push(snapshot(store.session,store.session.state,'NEW_GAME'));
  return store;
}

export function append(store,input,mutation={}){
  const s=store.session,seq=store.nextSeq++,body=commandBody(input);
  const rec={seq,lineage:s.lineage,tic:s.state.tic+1,ordinal:0,body,previousSha:s.commandHead};
  rec.commandSha=sha({seq:rec.seq,lineage:rec.lineage,tic:rec.tic,ordinal:0,body:rec.body,previousSha:rec.previousSha});
  const next=evolve(s.state,body);
  const events=[];
  if(body.fire&&s.state.ammo>0)events.push({type:'FIRE',value:next.rng});
  if(body.use)events.push({type:'DOOR',value:next.door});
  for(let ordinal=0;ordinal<events.length;ordinal++){
    const e={lineage:s.lineage,tic:next.tic,ordinal:mutation.duplicateEventOrdinal?0:ordinal,...events[ordinal],previousSha:s.eventHead};
    e.eventSha=sha(e);s.eventHead=e.eventSha;store.events.push(e);
  }
  rec.stateSha=mutation.badRecordedState?stateSha(s.state):stateSha(next);
  rec.frameSha=mutation.badRecordedFrame?frameSha(s.state):frameSha(next);
  s.state=next;s.frontier=seq;s.commandHead=rec.commandSha;
  if(mutation.overwriteCommand&&store.commands.length)store.commands[0]=rec;else store.commands.push(rec);
  if(!mutation.skipPeriodic&&(mutation.wallClockSnapshot?next.tic%3===0:next.tic%C.SNAPSHOT_INTERVAL===0))store.snapshots.push(snapshot(s,next,'INTERVAL',mutation));
  return {stateSha:stateSha(next),frameSha:frameSha(next),seq,tic:next.tic};
}

export function save(store,slot,mutation={}){
  if(!Number.isInteger(slot)||slot<0||slot>99)throw new Error('INVALID_SLOT');
  const snap=snapshot(store.session,store.session.state,'SAVE',mutation);
  if(!mutation.omitSaveSnapshot)store.snapshots.push(snap);
  store.saves.set(slot,{slot,lineage:snap.lineage,tic:snap.tic,stateSha:snap.stateSha,snapshot:clone(snap)});
  return snap.stateSha;
}

function lineageRecords(store,lineage,toTic=Infinity){return store.commands.filter(r=>r.lineage===lineage&&r.tic<=toTic).sort((a,b)=>a.tic-b.tic||a.ordinal-b.ordinal||a.seq-b.seq)}
export function reconstruct(store,lineage,targetTic,mutation={}){
  const choices=store.snapshots.filter(s=>s.lineage===lineage&&s.tic<=targetTic).sort((a,b)=>a.tic-b.tic);
  if(!choices.length)throw new Error('NO_SNAPSHOT');
  const snap=mutation.oldestSnapshot?choices[0]:choices.at(-1),doc=verifySnapshot(snap);
  let state=clone(doc.state),head=doc.commandSha,eventHead=doc.eventSha;
  const rows=lineageRecords(store,lineage,targetTic).filter(r=>r.tic>snap.tic);
  const ordered=mutation.acceptReorder?[...rows].reverse():rows;
  for(const r of ordered){
    const expected=sha({seq:r.seq,lineage:r.lineage,tic:r.tic,ordinal:r.ordinal,body:r.body,previousSha:r.previousSha});
    if(!mutation.ignoreCommandChain&&!mutation.acceptReorder&&(r.previousSha!==head||r.commandSha!==expected))throw new Error('COMMAND_CHAIN_CORRUPT');
    state=evolve(state,r.body);head=r.commandSha;
    if(!mutation.ignoreStateHash&&!mutation.acceptReorder&&stateSha(state)!==r.stateSha)throw new Error('STATE_HASH_MISMATCH');
    if(!mutation.ignoreFrameHash&&!mutation.acceptReorder&&frameSha(state)!==r.frameSha)throw new Error('FRAME_HASH_MISMATCH');
  }
  const ev=store.events.filter(e=>e.lineage===lineage&&e.tic>snap.tic&&e.tic<=targetTic).sort((a,b)=>a.tic-b.tic||a.ordinal-b.ordinal);
  for(let i=0;i<ev.length;i++){const e=ev[i],prior=ev[i-1];if(!mutation.ignoreEventChain&&((prior&&prior.tic===e.tic&&e.ordinal!==prior.ordinal+1)||(!prior||prior.tic!==e.tic)&&e.ordinal!==0||e.previousSha!==eventHead||sha({...e,eventSha:undefined})!==e.eventSha))throw new Error('EVENT_CHAIN_CORRUPT');eventHead=e.eventSha;}
  if(state.tic!==targetTic)throw new Error('COMMAND_RANGE_INCOMPLETE');
  return {state,commandHead:head,eventHead};
}

function branch(store,restored,label,mutation={}){
  const old=store.session;
  if(mutation.deleteFuture){store.commands=store.commands.filter(r=>r.lineage!==old.lineage||r.tic<=restored.state.tic);store.events=store.events.filter(e=>e.lineage!==old.lineage||e.tic<=restored.state.tic);}
  const lineage=mutation.reuseLineage?old.lineage:sha(`${label}|${old.lineage}|${store.nextSeq}|${stateSha(restored.state)}`);
  store.session={lineage,lineageFirstSeq:store.nextSeq,frontier:store.nextSeq-1,
    commandHead:restored.commandHead,eventHead:restored.eventHead,state:clone(mutation.keepCurrentState?old.state:restored.state)};
  store.snapshots.push(snapshot(store.session,store.session.state,label));
  return {lineage,stateSha:stateSha(store.session.state),frameSha:frameSha(store.session.state)};
}
export function load(store,slot,mutation={}){
  const saveRow=mutation.loadWrongSlot?[...store.saves.values()].at(-1):store.saves.get(slot);
  if(!saveRow)throw new Error('SAVE_NOT_FOUND');verifySnapshot(saveRow.snapshot);
  const doc=JSON.parse(saveRow.snapshot.blob);
  return branch(store,{state:doc.state,commandHead:doc.commandSha,eventHead:doc.eventSha},`LOAD:${slot}`,mutation);
}
export function rewind(store,lineage,tic,mutation={}){return branch(store,reconstruct(store,lineage,tic,mutation),`REWIND:${tic}`,mutation);}

export function startReplay(store,lineage,fromTic,toTic,mutation={}){
  if(!Number.isInteger(fromTic)||!Number.isInteger(toTic)||fromTic<0||toTic<fromTic)throw new Error('REPLAY_RANGE');
  const end=mutation.ignoreReplayRange?store.commands.filter(r=>r.lineage===lineage).at(-1)?.tic??toTic:toTic;
  const base=reconstruct(store,lineage,fromTic,mutation),id=sha(`REPLAY|${store.nextReplay++}|${lineage}|${fromTic}|${end}`).slice(0,32);
  store.replays.set(id,{id,lineage,currentTic:fromTic,toTic:end,state:base.state,commandHead:base.commandHead,eventHead:base.eventHead});return id;
}
export function stepReplay(store,id,mutation={}){
  const r=store.replays.get(id);if(!r)throw new Error('REPLAY_NOT_FOUND');if(r.currentTic>=r.toTic)return {done:true,tic:r.currentTic,stateSha:stateSha(r.state),frameSha:frameSha(r.state)};
  const rec=lineageRecords(store,r.lineage,r.currentTic+1).find(x=>x.tic===r.currentTic+1);if(!rec)throw new Error('COMMAND_RANGE_INCOMPLETE');
  if(!mutation.replayLiveState){const expected=sha({seq:rec.seq,lineage:rec.lineage,tic:rec.tic,ordinal:rec.ordinal,body:rec.body,previousSha:rec.previousSha});if(rec.previousSha!==r.commandHead||rec.commandSha!==expected)throw new Error('COMMAND_CHAIN_CORRUPT');r.state=evolve(r.state,rec.body);if(!mutation.ignoreStateHash&&stateSha(r.state)!==rec.stateSha)throw new Error('STATE_HASH_MISMATCH');if(!mutation.ignoreFrameHash&&frameSha(r.state)!==rec.frameSha)throw new Error('FRAME_HASH_MISMATCH');r.commandHead=rec.commandSha;}else r.state=clone(store.session.state);
  r.currentTic++;return {done:r.currentTic===r.toTic,tic:r.currentTic,stateSha:stateSha(r.state),frameSha:frameSha(r.state)};
}
export function run(store,commands,mutation={}){return commands.map(c=>append(store,c,mutation));}
