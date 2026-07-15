export const C=Object.freeze({USE_RANGE:64,BUTTON_TICS:35,DOOR_SPEED:2,BLAZE_SPEED:8,DOOR_WAIT:150,LIFT_SPEED:1,LIFT_WAIT:105,DAMAGE_PERIOD:32,DAMAGE_AMOUNT:5,STROBE_BRIGHT:5,STROBE_DARK:35});
export const LINE_SPECIALS=Object.freeze([1,2,11,23,26,62,88,117]);
export const SECTOR_SPECIALS=Object.freeze([1,7,9,12]);
export const clone=s=>structuredClone(s);

const event=(s,type,id,value=null)=>s.events.push({tic:s.tic,ordinal:s.events.filter(e=>e.tic===s.tic).length,type,id,value});
const sectorsFor=(s,line)=>line.tag===0?[line.backSector]:s.sectors.filter(x=>x.tag===line.tag).map(x=>x.id);
const addMover=(s,m)=>{if(!s.movers.some(x=>x.sectorId===m.sectorId&&x.plane===m.plane))s.movers.push(m)};
const accepted=(line,input,isUse,mutation)=>{
  if(isUse)return input.useLine===line.id&&(mutation.noUseRange||input.useDistance<=C.USE_RANGE)&&(mutation.acceptBack||input.useFront===true);
  return input.crossLine===line.id&&(mutation.crossEither||input.crossDirection==='FRONT_TO_BACK');
};
function trigger(s,line,input,mutation){
  const once=[2,11,23].includes(line.special),isUse=[1,11,23,26,62,117].includes(line.special);
  if(!accepted(line,input,isUse,mutation)||(!mutation.repeatOnce&&once&&line.triggerCount>0)||(mutation.disableRepeat&&!once&&line.triggerCount>0))return;
  if(line.special===26&&!s.player.blueKey&&!mutation.noBlueDenial){event(s,'KEY_DENIED',line.id,'BLUE');return}
  line.triggerCount++;event(s,'LINE_TRIGGER',line.id,line.special);
  if(line.special===11){s.mapStatus=mutation.noExit?'ACTIVE':'COMPLETED';event(s,'MAP_COMPLETE',line.id,'E1M1');return}
  if([1,2,26,117].includes(line.special))for(const sectorId of sectorsFor(s,line)){
    const sec=s.sectors.find(x=>x.id===sectorId),speed=line.special===117&&!mutation.noBlaze?C.BLAZE_SPEED:C.DOOR_SPEED;
    addMover(s,{sectorId,plane:'CEILING',kind:line.special===2?'DOOR_OPEN':'DOOR_RAISE',direction:1,speed:mutation.wrongDoorSpeed?1:speed,target:sec.doorTop,origin:sec.ceiling,timer:0,wait:C.DOOR_WAIT});
  }
  if(line.special===23)for(const sectorId of sectorsFor(s,line)){const sec=s.sectors.find(x=>x.id===sectorId);addMover(s,{sectorId,plane:'FLOOR',kind:'FLOOR_LOWER',direction:-1,speed:C.LIFT_SPEED,target:mutation.wrongFloorTarget?sec.floor-8:sec.lowestFloor,origin:sec.floor,timer:0,wait:0})}
  if([62,88].includes(line.special))for(const sectorId of sectorsFor(s,line)){const sec=s.sectors.find(x=>x.id===sectorId);addMover(s,{sectorId,plane:'FLOOR',kind:'LIFT',direction:-1,speed:C.LIFT_SPEED,target:sec.lowestFloor,origin:sec.floor,timer:0,wait:mutation.wrongLiftWait?35:C.LIFT_WAIT})}
  if(line.special===62&&!mutation.noButton){line.switchOn=1;s.switches.push({lineId:line.id,timer:mutation.wrongButton?1:C.BUTTON_TICS});event(s,'SWITCH_ON',line.id)}
}
function movePlanes(s,input,mutation){
  const keep=[];
  for(const m of s.movers){const sec=s.sectors.find(x=>x.id===m.sectorId),field=m.plane==='CEILING'?'ceiling':'floor';
    if(m.direction===0){if(--m.timer<=0){m.direction=m.kind==='LIFT'?1:-1;m.target=m.origin;event(s,'MOVER_RESUME',m.sectorId,m.direction)}keep.push(m);continue}
    if(m.kind==='LIFT'&&m.direction===1&&input.occupiedSector===m.sectorId&&!mutation.ignoreOccupancy){keep.push(m);event(s,'LIFT_BLOCKED',m.sectorId);continue}
    if(m.kind==='DOOR_RAISE'&&m.direction===-1&&input.occupiedSector===m.sectorId&&!mutation.ignoreOccupancy){m.direction=1;m.target=sec.doorTop;keep.push(m);event(s,'DOOR_REOPEN',m.sectorId);continue}
    const next=sec[field]+m.direction*m.speed,reached=m.direction>0?next>=m.target:next<=m.target;sec[field]=reached?m.target:next;
    if(!reached){keep.push(m);continue}
    event(s,'MOVER_REACHED',m.sectorId,sec[field]);
    if(m.kind==='DOOR_RAISE'&&m.direction===1){m.direction=0;m.timer=mutation.wrongDoorWait?35:m.wait;keep.push(m)}
    else if(m.kind==='LIFT'&&m.direction===-1){m.direction=0;m.timer=m.wait;keep.push(m)}
    else if((m.kind==='DOOR_RAISE'&&m.direction===-1)||(m.kind==='LIFT'&&m.direction===1)){}else if(m.kind==='DOOR_OPEN'||m.kind==='FLOOR_LOWER'){}
  }
  s.movers=keep;
}
function sectorEffects(s,mutation){
  for(const sec of s.sectors){
    if(sec.special===12&&!mutation.noStrobe){const cycle=C.STROBE_BRIGHT+C.STROBE_DARK,pos=(s.tic-1)%cycle;sec.light=pos<C.STROBE_BRIGHT?sec.maxLight:sec.minLight}
    if(sec.special===1&&!mutation.noRandom){if(--sec.lightTimer<=0){if(sec.light===sec.maxLight){sec.light=sec.minLight;sec.lightTimer=(s.rng[s.rngCursor++%s.rng.length]&7)+1}else{sec.light=sec.maxLight;sec.lightTimer=(s.rng[s.rngCursor++%s.rng.length]&64)+1}}}
  }
  const sec=s.sectors.find(x=>x.id===s.player.sectorId);if(!sec)return;
  if(sec.special===7){sec.damageClock++;if(sec.damageClock%(mutation.wrongDamageCadence?16:C.DAMAGE_PERIOD)===0&&!mutation.noDamage){s.player.health=Math.max(0,s.player.health-C.DAMAGE_AMOUNT);event(s,'SECTOR_DAMAGE',sec.id,C.DAMAGE_AMOUNT)}}
  if(sec.special===9&&!sec.secretFound){if(!mutation.repeatSecret)sec.secretFound=true;s.player.secretCount++;event(s,'SECRET_FOUND',sec.id,1)}
}
function switches(s){const keep=[];for(const sw of s.switches){if(--sw.timer<=0){const line=s.lines.find(x=>x.id===sw.lineId);line.switchOn=0;event(s,'SWITCH_RESET',line.id)}else keep.push(sw)}s.switches=keep}
export function applyTic(inputState,input={},mutation={}){
  const s=clone(inputState);s.tic++;for(const line of s.lines)trigger(s,line,input,mutation);movePlanes(s,input,mutation);switches(s);sectorEffects(s,mutation);return s;
}
export function run(state,steps){let s=clone(state);for(const step of steps)s=applyTic(s,step);return s}
export function digest(s){return JSON.stringify({tic:s.tic,mapStatus:s.mapStatus,player:s.player,sectors:s.sectors.map(({id,floor,ceiling,light,secretFound,damageClock})=>({id,floor,ceiling,light,secretFound,damageClock})),lines:s.lines.map(({id,triggerCount,switchOn})=>({id,triggerCount,switchOn})),movers:s.movers,switches:s.switches,events:s.events,rngCursor:s.rngCursor})}
