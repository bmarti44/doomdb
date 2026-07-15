import assert from 'node:assert/strict';import fs from 'node:fs';import {applyTic,digest} from './reference.mjs';
const fixture=JSON.parse(fs.readFileSync(new URL('./fixtures.json',import.meta.url))).initial,specs=JSON.parse(fs.readFileSync(new URL('./mutation-specs.json',import.meta.url))).mutations;
const base=()=>structuredClone(fixture),idle=(s,n,input={},mutation={})=>{for(let i=0;i<n;i++)s=applyTic(s,input,mutation);return s};
function witness(mode,mutation={}){let s=base(),steps=[];
  if(mode==='noUseRange')steps=[{useLine:101,useDistance:65,useFront:true}];
  else if(mode==='acceptBack')steps=[{useLine:101,useDistance:8,useFront:false}];
  else if(mode==='crossEither')steps=[{crossLine:102,crossDirection:'BACK_TO_FRONT'}];
  else if(mode==='repeatOnce'){s.lines[1].triggerCount=1;steps=[{crossLine:102,crossDirection:'FRONT_TO_BACK'}]}
  else if(mode==='disableRepeat'){s.lines[0].triggerCount=1;steps=[{useLine:101,useDistance:8,useFront:true}]}
  else if(mode==='noBlueDenial')steps=[{useLine:126,useDistance:8,useFront:true}];
  else if(['wrongDoorSpeed','noBlaze'].includes(mode))steps=[{useLine:mode==='noBlaze'?217:101,useDistance:8,useFront:true}];
  else if(mode==='wrongDoorWait'){steps=[{useLine:101,useDistance:8,useFront:true},...Array(100).fill({})]}
  else if(mode==='wrongFloorTarget'){steps=[{useLine:123,useDistance:8,useFront:true},...Array(20).fill({})]}
  else if(mode==='wrongLiftWait'){steps=[{useLine:162,useDistance:8,useFront:true},...Array(120).fill({})]}
  else if(['noButton','wrongButton'].includes(mode)){steps=[{useLine:162,useDistance:8,useFront:true},...Array(2).fill({})]}
  else if(mode==='ignoreOccupancy'){s.movers=[{sectorId:2,plane:'CEILING',kind:'DOOR_RAISE',direction:-1,speed:2,target:0,origin:124,timer:0,wait:150}];s.sectors[1].ceiling=100;steps=[{occupiedSector:2}]}
  else if(['wrongDamageCadence','noDamage'].includes(mode)){s.player.sectorId=7;steps=Array(32).fill({})}
  else if(mode==='repeatSecret'){s.player.sectorId=9;steps=Array(2).fill({})}
  else if(mode==='noExit')steps=[{useLine:111,useDistance:8,useFront:true}];
  else if(mode==='noStrobe')steps=Array(6).fill({});
  else if(mode==='noRandom')steps=[{}];
  let out=s;for(const x of steps)out=applyTic(out,x,mutation);return digest(out)}
let killed=0;for(const spec of specs){const normal=witness(spec.mode,{}),mutated=witness(spec.mode,{[spec.mode]:true});assert.notEqual(mutated,normal,`${spec.id} survived`);killed++}
process.stdout.write(`PASS T6.3-EVAL-MUTATION-SELF-CHECK (${killed}/${specs.length} isolated mutations killed)\n`);
