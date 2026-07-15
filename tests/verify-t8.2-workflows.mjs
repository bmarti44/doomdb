import assert from 'node:assert/strict';
import {WorkflowClient,command} from '../client/staged/t8.2/workflows.mjs';

function evolve(sequence) {
  let state={paused:0,menu:'NONE',selection:0,automap:'OFF',god:0,noclip:0,
    fullmap:0,tic:0,gameTics:0,rng:7,frontier:0,generation:0};
  const history=[];
  for (const patch of sequence) {
    const value=command(++state.frontier,patch);
    state={...state,tic:state.tic+1};
    if(value.pause)state.paused=1-state.paused;
    if(value.menu==='OPEN'){state.menu='MAIN';state.selection=0}
    else if(value.menu==='DOWN'&&state.menu==='MAIN')state.selection=(state.selection+1)%3;
    else if(value.menu==='UP'&&state.menu==='MAIN')state.selection=(state.selection+2)%3;
    else if(value.menu==='SELECT'&&state.menu==='MAIN'&&state.selection===1){state.menu='SKILL';state.selection=0}
    else if(value.menu==='BACK')state.menu='NONE';
    else if(value.menu==='RESTART'){state={...state,paused:0,menu:'NONE',selection:0,
      automap:'OFF',fullmap:0,god:0,noclip:0,tic:0,gameTics:0,rng:7,
      generation:state.generation+1}}
    if(value.automap){state.automap=state.automap==='OFF'?'NORMAL':'OFF';state.fullmap=0}
    if(value.cheat==='GOD')state.god=1-state.god;
    if(value.cheat==='NOCLIP')state.noclip=1-state.noclip;
    if(value.cheat==='FULLMAP'){state.fullmap=1-state.fullmap;state.automap=state.fullmap?'FULL':'NORMAL'}
    if(value.cheat.startsWith('REWIND:')){state.tic=Number(value.cheat.slice(7));state.generation++}
    if(!state.paused&&state.menu==='NONE'&&value.menu==='NONE'){
      state.gameTics++;state.rng=(state.rng*17+3)%256;
    }
    history.push({...state});
  }
  return history;
}

const menu=evolve([{menu:'OPEN'},{menu:'DOWN'},{menu:'DOWN'},{menu:'UP'},
  {menu:'SELECT'},{menu:'BACK'}]);
assert.deepEqual(menu.map(x=>x.menu==='MAIN'?`MAIN:${x.selection}`:x.menu),
  ['MAIN:0','MAIN:1','MAIN:2','MAIN:1','SKILL','NONE']);
assert.equal(menu.at(-1).gameTics,0,'menu commands freeze gameplay through BACK command');

const pause=evolve([{pause:1},{forward:1,strafe:1,run:1,fire:1,use:1},{pause:1}]);
assert.deepEqual(pause.map(x=>x.gameTics),[0,0,1]);
assert.deepEqual(pause.map(x=>x.rng),[7,7,122]);
assert.deepEqual(pause.map(x=>x.tic),[1,2,3]);

const toggles=evolve([{automap:1},{cheat:'FULLMAP'},{cheat:'FULLMAP'},
  {cheat:'GOD'},{cheat:'GOD'},{cheat:'NOCLIP'},{cheat:'NOCLIP'}]);
assert.deepEqual(toggles.map(x=>x.automap).slice(0,3),['NORMAL','FULL','NORMAL']);
assert.deepEqual(toggles.map(x=>x.god).slice(3,5),[1,0]);
assert.deepEqual(toggles.map(x=>x.noclip).slice(5),[1,0]);

const branched=evolve([{}, {}, {}, {cheat:'REWIND:1'}, {}, {menu:'RESTART'}]);
assert.equal(branched[3].tic,1);assert.equal(branched[3].frontier,4);
assert.equal(branched[5].tic,0);assert.equal(branched[5].frontier,6);
assert.equal(branched[5].generation,2);

const calls=[];let failStep=false;
const post=async(path,body)=>{calls.push([path,structuredClone(body)]);if(failStep&&path==='step/')throw Error('rejected');
  if(path==='new_game/')return {p_session:'a'.repeat(32),p_payload:'spawn'};
  if(path==='step/'||path==='load_game/'||path==='step_replay/')return {p_payload:'frame'};
  if(path==='save_game/')return {p_state_sha:'b'.repeat(64)};
  if(path==='start_replay/')return {p_replay_id:'c'.repeat(32)};
  throw Error(path)};
const client=new WorkflowClient(post);
assert.equal(await client.newGame(3),'spawn');
await client.pause();
let sent=JSON.parse(calls.at(-1)[1].p_commands);assert.equal(sent.commands[0].seq,1);
await client.step([{automap:1},{cheat:'FULLMAP'}]);
sent=JSON.parse(calls.at(-1)[1].p_commands);assert.deepEqual(sent.commands.map(x=>x.seq),[2,3]);
assert.equal(client.frontier,3);
await client.retryLastStep();assert.equal(client.frontier,3);
assert.deepEqual(calls.at(-1),calls.at(-2),'retry preserves exact request bytes');
failStep=true;await assert.rejects(()=>client.cheat('GOD'));assert.equal(client.frontier,3);
failStep=false;await client.cheat('GOD');sent=JSON.parse(calls.at(-1)[1].p_commands);
assert.equal(sent.commands[0].seq,4,'atomic rejection preserves sequence frontier');
assert.equal(await client.save(3),'b'.repeat(64));assert.equal(await client.load(3),'frame');
const replay=await client.startReplay(1,4);assert.equal(await client.stepReplay(replay),'frame');
assert.throws(()=>command(5,{cheat:'god'}));assert.throws(()=>command(5,{menu:'OPTIONS'}));
assert.throws(()=>command(5,{projectedGeometry:[]}));
assert.ok(calls.every(([path])=>['new_game/','step/','save_game/','load_game/',
  'start_replay/','step_replay/'].includes(path)));

process.stdout.write('PASS T8.2-WORKFLOW-UNIT (menu, pause, automap, cheats, branches, persistence, retry atomicity)\n');
