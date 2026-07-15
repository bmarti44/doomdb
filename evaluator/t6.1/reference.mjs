import crypto from 'node:crypto';

export const LOGICAL_HZ=35,MAX_COMMANDS=4,MAX_BYTES=65536;
export const KEYS=['seq','turn','forward','strafe','run','fire','use','weapon','pause','automap','menu','cheat'];
export const ERR={MALFORMED:-20861,CONFLICT:-20862,OLD:-20863,GAP:-20864,SESSION:-20865};
export const sha256=value=>crypto.createHash('sha256').update(value).digest('hex');
export const canonical=value=>JSON.stringify(value);

function integer(v,lo,hi){return Number.isInteger(v)&&v>=lo&&v<=hi}
export function normalizeEnvelope(text){
  if(typeof text!=='string'||Buffer.byteLength(text)>MAX_BYTES)throw Object.assign(new Error('malformed'),{code:ERR.MALFORMED});
  let body;try{body=JSON.parse(text)}catch{throw Object.assign(new Error('malformed'),{code:ERR.MALFORMED})}
  if(!body||Array.isArray(body)||Object.keys(body).sort().join(',')!=='commands,v'||body.v!==1||!Array.isArray(body.commands)||!integer(body.commands.length,1,MAX_COMMANDS))throw Object.assign(new Error('malformed'),{code:ERR.MALFORMED});
  const commands=body.commands.map(c=>{
    if(!c||Array.isArray(c)||Object.keys(c).sort().join(',')!==[...KEYS].sort().join(','))throw Object.assign(new Error('malformed'),{code:ERR.MALFORMED});
    if(!integer(c.seq,1,999999999999)||!integer(c.turn,-1,1)||!integer(c.forward,-1,1)||!integer(c.strafe,-1,1)||
       !integer(c.run,0,1)||!integer(c.fire,0,1)||!integer(c.use,0,1)||!integer(c.weapon,0,9)||
       !integer(c.pause,0,1)||!integer(c.automap,0,1)||typeof c.menu!=='string'||typeof c.cheat!=='string'||c.menu.length>32||c.cheat.length>32)
      throw Object.assign(new Error('malformed'),{code:ERR.MALFORMED});
    return Object.fromEntries(KEYS.map(k=>[k,c[k]]));
  });
  if(commands.some((c,i)=>i&&c.seq!==commands[i-1].seq+1))throw Object.assign(new Error('malformed'),{code:ERR.MALFORMED});
  return {v:1,commands};
}

export function commandDocument(envelope){return canonical(envelope)}
export function stateDocument(s){
  return canonical({schema:1,skill:s.skill,current_player_id:s.current_player_id,tic:s.tic,rng_cursor:s.rng_cursor,game_mode:s.game_mode,map_status:s.map_status,paused:s.paused,
    menu_state:s.menu_state,automap_state:s.automap_state,last_command_seq:s.last_command_seq,save_lineage:s.save_lineage,
    player:{...s.player},mobjs:[...s.mobjs].sort((a,b)=>a.mobj_id-b.mobj_id),sectors:[...s.sectors].sort((a,b)=>a.sector_id-b.sector_id),
    lines:[...s.lines].sort((a,b)=>a.linedef_id-b.linedef_id),movers:[...s.movers].sort((a,b)=>a.mover_id-b.mover_id),
    switches:[...s.switches].sort((a,b)=>a.linedef_id-b.linedef_id),ordering_version:'APPENDIX-F-1'});
}
export const stateSha=s=>sha256(stateDocument(s));
export function cloneState(s){return structuredClone(s)}

export function applyBatch(input,text,mutation={}){
  const s=cloneState(input),env=normalizeEnvelope(text),first=env.commands[0].seq,last=env.commands.at(-1).seq,command_sha=sha256(commandDocument(env));
  const prior=s.responses.at(-1);const exactPrior=prior&&prior.first_seq===first&&prior.last_seq===last;
  if(exactPrior){if(prior.command_sha!==command_sha)throw Object.assign(new Error('conflict'),{code:ERR.CONFLICT});return {state:s,response:prior.response,retry:true,events:[]}}
  if(first<=s.last_command_seq)throw Object.assign(new Error('old'),{code:ERR.OLD});
  if(first!==s.last_command_seq+1)throw Object.assign(new Error('gap'),{code:ERR.GAP});
  const events=[];
  for(const c of env.commands){
    const tic=s.tic+1;let ordinal=0;
    const emit=(type,value)=>events.push({tic,event_ordinal:mutation.sameOrdinal?0:ordinal++,event_type:type,text_value:value});
    if(c.pause){s.paused=1-s.paused;emit('CONTROL_PAUSE',String(s.paused))}
    if(c.menu!=='NONE'){s.menu_state=c.menu;emit('CONTROL_MENU',c.menu)}
    if(c.automap){s.automap_state=s.automap_state==='OFF'?'ON':'OFF';s.game_mode=s.automap_state==='OFF'?'GAME':'AUTOMAP';emit('CONTROL_AUTOMAP',s.automap_state)}
    if(c.cheat!==''){emit('CONTROL_CHEAT',c.cheat)}
    if(mutation.wallClockTic)s.tic=Date.now();else s.tic=tic;
    s.last_command_seq=c.seq;
    s.commands.push({...c,tic:s.tic,command_ordinal:0,command_sha:sha256(canonical(c))});
    if(mutation.advanceRng)s.rng_cursor=(s.rng_cursor+1)&255;
  }
  if(mutation.reverseEvents)events.reverse();
  s.events.push(...events);const state_sha=stateSha(s);s.history.push({tic:s.tic,first_command_seq:first,last_command_seq:last,state_sha,snapshot_hex:Buffer.from(stateDocument(s)).toString('hex')});
  const payload={v:1,tic:s.tic,logical_hz:mutation.wrongHz?30:LOGICAL_HZ,first_seq:first,last_seq:last,command_sha,state_sha,event_count:events.length};
  const response=Buffer.from(canonical(payload));
  s.responses.push({first_seq:first,last_seq:last,command_sha,state_sha,response:response.toString('hex')});
  return {state:s,response:response.toString('hex'),retry:false,events};
}

export function snapshot(s){return {tic:s.tic,last_command_seq:s.last_command_seq,rng_cursor:s.rng_cursor,paused:s.paused,menu_state:s.menu_state,
  automap_state:s.automap_state,game_mode:s.game_mode,commands:s.commands,events:s.events,history:s.history,responses:s.responses,state_sha:stateSha(s)}}
