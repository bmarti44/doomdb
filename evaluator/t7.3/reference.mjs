const clone=x=>structuredClone(x),clamp=(n,a,b)=>Math.max(a,Math.min(b,n));
export function emitTransitions(transitions,defs,opt={}){
  const byType=new Map(defs.map(d=>[d.eventType,d])),seen=new Set(),out=[];
  const ordered=[...transitions].sort((a,b)=>a.tic-b.tic||a.eventClass-b.eventClass||a.sourceId-b.sourceId||a.targetId-b.targetId||a.eventOrdinal-b.eventOrdinal);
  for(const e of ordered){const key=`${e.tic}:${e.eventOrdinal}`;if(seen.has(key))throw new Error(`duplicate transition ${key}`);seen.add(key);const d=byType.get(e.eventType);if(!d)continue;
    const volume=clamp(d.volume+(e.volumeDelta??0),0,255),separation=clamp(d.separation+(e.separationDelta??0),0,255);
    out.push({tic:e.tic,ordinal:0,asset:d.asset,kind:d.kind,volume,separation,sourceEventOrdinal:e.eventOrdinal});
  }
  const next=new Map();for(const e of out){const n=next.get(e.tic)??0;e.ordinal=opt.reverseOrdinals?999-n:n;next.set(e.tic,n+1)}return out;
}
export function acceptTimeline(state,tuples,opt={}){
  const s=clone(state),accepted=[];for(const raw of tuples){if(!Array.isArray(raw)||raw.length!==5)throw new Error('invalid audio tuple');const [tic,ordinal,asset,volume,separation]=raw;
    if(!Number.isInteger(tic)||!Number.isInteger(ordinal)||tic<0||ordinal<0||!/^DS[A-Z0-9]{1,30}$|^D_[A-Z0-9]{1,29}$/.test(asset)||!Number.isInteger(volume)||volume<0||volume>255||!Number.isInteger(separation)||separation<0||separation>255)throw new Error('invalid audio tuple');
    const key=[tic,ordinal];if(s.last&&(tic<s.last[0]||(tic===s.last[0]&&ordinal<=s.last[1])))throw new Error(tic===s.last[0]&&ordinal===s.last[1]?'duplicate audio event':'reordered audio event');
    s.last=key;if(!opt.dropAccepted)accepted.push({tic,ordinal,asset,volume,separation});
  }return {state:s,accepted};
}
export function makePresenter({getAsset,decode,context}){const cache=new Map(),queue=[];let last=null,enabled=false;
  const load=name=>{if(!cache.has(name))cache.set(name,Promise.resolve(getAsset(name)).then(x=>decode(x)));return cache.get(name)};
  return {cache,async consume(tuples){const r=acceptTimeline({last},tuples);last=r.state.last;for(const e of r.accepted){const buffer=await load(e.asset);queue.push({e,buffer});}if(enabled)this.flush();},async enable(){await context.resume();enabled=true;this.flush();},flush(){if(!enabled)return;while(queue.length){const {e,buffer}=queue.shift();context.schedule(buffer,{volume:e.volume/255,pan:(e.separation-128)/127,tic:e.tic,ordinal:e.ordinal});}},get last(){return last},get queued(){return queue.length}};
}

