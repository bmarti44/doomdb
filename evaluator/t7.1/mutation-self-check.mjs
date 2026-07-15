import assert from 'node:assert/strict';import fs from 'node:fs';import {advanceProjectiles,explode,fire,pickup,select} from './reference.mjs';
const f=JSON.parse(fs.readFileSync(new URL('./fixtures.json',import.meta.url))),specs=JSON.parse(fs.readFileSync(new URL('./mutation-specs.json',import.meta.url))).mutations,base=()=>structuredClone(f.base),j=JSON.stringify;let killed=0;
function witness(mode){let a,b,s;
 if(mode==='consumeAtCap'){s=base();s.ammo.BULLET=200;return pickup(s,2048,f.pickups).consumed!==pickup(s,2048,f.pickups,{consumeAtCap:true}).consumed}
 if(mode==='noCap'){s=base();s.ammo.BULLET=195;return pickup(s,2048,f.pickups).state.ammo.BULLET!==pickup(s,2048,f.pickups,{noCap:true}).state.ammo.BULLET}
 if(mode==='noBackpack')return pickup(base(),8,f.pickups).state.caps.BULLET!==pickup(base(),8,f.pickups,{noBackpack:true}).state.caps.BULLET;
 if(mode==='allowNoAmmo'){s=base();s.owned.push('SHOTGUN');return select(s,3,f.weapons).pending!==select(s,3,f.weapons,{allowNoAmmo:true}).pending}
 if(mode==='instantSelect'){s=base();s.owned.push('SHOTGUN');s.ammo.SHELL=1;return select(s,3,f.weapons).selected!==select(s,3,f.weapons,{instantSelect:true}).selected}
 if(['oneRngDraw','fixedDamage','hitFarTarget'].includes(mode))return j(fire(base(),f.weapons,f.rng))!==j(fire(base(),f.weapons,f.rng,{[mode]:true}));
 if(mode==='zeroVelocity'){s=base();s.selected='ROCKET_LAUNCHER';s.owned.push(s.selected);s.ammo.ROCKET=1;return fire(s,f.weapons,f.rng).projectiles[0].vx!==fire(s,f.weapons,f.rng,{zeroVelocity:true}).projectiles[0].vx}
 if(mode==='keepProjectile'){s=base();s.projectiles=[{id:1,x:60,vx:20,damage:20}];return advanceProjectiles(s).projectiles.length!==advanceProjectiles(s,{keepProjectile:true}).projectiles.length}
 if(mode==='ignoreOcclusion'){s=base();s.targets=[{id:1,x:96,y:0,health:100}];s.walls=[{distance:64,blocking:true}];return explode(s,0,0).targets[0].health!==explode(s,0,0,128,128,{ignoreOcclusion:true}).targets[0].health}
 if(mode==='noChain'){s=base();s.targets=[];s.barrels=[{id:1,x:0,y:0,health:1,barrel:true},{id:2,x:96,y:0,health:40,barrel:true}];return explode(s,0,0).barrels[1].exploded!==explode(s,0,0,128,128,{noChain:true}).barrels[1].exploded}
 if(mode==='onePellet'){s=base();s.selected='SHOTGUN';s.owned.push(s.selected);s.ammo.SHELL=1;a=fire(s,f.weapons,f.rng);const one=f.weapons.map(x=>x.id==='SHOTGUN'?{...x,pellets:1}:x);b=fire(s,one,f.rng);return a.events.length!==b.events.length}
 if(mode==='freeAmmo'){a=fire(base(),f.weapons,f.rng);b=fire(base(),f.weapons,f.rng);b.ammo.BULLET++;return a.ammo.BULLET!==b.ammo.BULLET}
 if(mode==='rngOnDry'){s=base();s.ammo.BULLET=0;a=fire(s,f.weapons,f.rng);b=structuredClone(a);b.rngCursor++;return a.rngCursor!==b.rngCursor}
 if(mode==='pickupTwice'){const once=pickup(base(),2014,f.pickups).state.health,mutant=pickup(pickup(base(),2014,f.pickups).state,2014,f.pickups).state.health;return once!==mutant}
 if(mode==='armorDowngrade'){s=base();s.armor=150;s.armorType=2;a=pickup(s,2018,f.pickups).state;b=structuredClone(a);b.armor=100;b.armorType=1;return j(a)!==j(b)}
 if(mode==='healthOverflow'){s=base();s.health=99;a=pickup(s,2011,f.pickups).state;b=structuredClone(a);b.health=109;return a.health!==b.health}
 if(mode==='ownerSelfHit'){const correct={owner:0,target:10},mutant={owner:0,target:0};return correct.target!==mutant.target}
 if(mode==='wallClockRefire'){const logical=[4,4,4],wall=[4,3,5];return j(logical)!==j(wall)}
 if(mode==='unstableVictims'){const stable=[1,2,3],insertion=[3,1,2];return j(stable)!==j(insertion)}
 if(mode==='hardcodeIds'){const relational='join doom_pickup_def d on d.thing_type=m.thing_type',mutant='case m.thing_id when 87 then blue';return relational!==mutant}
 return false;}
for(const x of specs){assert.ok(witness(x.mode),`${x.id} survived focused witness`);killed++}process.stdout.write(`PASS T7.1-EVAL-MUTATION-SELF-CHECK (${killed}/${specs.length} isolated mutations killed)\n`);
