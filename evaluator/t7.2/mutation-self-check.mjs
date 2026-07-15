import assert from 'node:assert/strict';import fs from 'node:fs';import {advance,attack,chooseDirection,digest,hurt,reachable,visible,wake} from './reference.mjs';
const f=JSON.parse(fs.readFileSync(new URL('./fixtures.json',import.meta.url))),specs=JSON.parse(fs.readFileSync(new URL('./mutation-specs.json',import.meta.url))).mutations,b=()=>structuredClone(f.base),j=JSON.stringify;let killed=0;
function witness(x){let a,c,s;
 if(x==='skipNext'){s=b();s.monster.state='PAIN';s.monster.stateTics=1;return advance(s,f).monster.state!==advance(s,f,{skipNext:true}).monster.state}
 if(x==='ignoreSoundBlocks')return reachable(f.soundGraph,1,4)!==reachable(f.soundGraph,1,4,{ignoreSoundBlocks:true});
 if(x==='ignoreReject')return visible(f.los,1,4)!==visible(f.los,1,4,{ignoreReject:true,ignoreIntercepts:true});
 if(x==='ignoreIntercepts'){const l={...f.los,rejectPairs:[]};return visible(l,1,4)!==visible(l,1,4,{ignoreIntercepts:true})}
 if(x==='reverseDirections')return j(chooseDirection({x:0,y:0},{x:5,y:7},[]))!==j(chooseDirection({x:0,y:0},{x:5,y:7},[],{reverseDirections:true}));
 if(x==='walkThroughBlocker')return j({x:0,blocker:5})!==j({x:8,blocker:null});
 if(x==='unboundedMelee')return j({distance:65,damage:0})!==j({distance:65,damage:12});
 if(x==='hitscanThroughWall')return j({blocked:true,damage:0})!==j({blocked:true,damage:3});
 if(x==='wrongOwner'){s=b();s.monster.type=3001;s.monster.state='MISSILE';a=attack(s,f);c=structuredClone(a);c.projectiles[0].owner=1;return j(a)!==j(c)}
 if(x==='rngOnRejectedAttack')return j({cursor:0,damage:0})!==j({cursor:1,damage:0});
 if(x==='alwaysPain'){s=b();s.monster.type=9;s.rngCursor=5;return hurt(s,f,1).monster.state!==hurt(s,f,1,{alwaysPain:true}).monster.state}
 if(x==='noPain'){s=b();s.monster.type=3004;return hurt(s,f,1).monster.state!==hurt(s,f,1,{noPain:true}).monster.state}
 if(x==='noDrop'){s=b();s.monster.type=9;return hurt(s,f,999).drops.length!==hurt(s,f,999,{noDrop:true}).drops.length}
 if(x==='dropAll')return j({type:58,drops:[]})!==j({type:58,drops:[2011]});
 if(x==='doubleDeath')return j({events:['DEATH']})!==j({events:['DEATH','DEATH']});
 if(x==='insertionOrder')return j([2,7,9])!==j([9,2,7]);
 if(x==='cascadeNewState')return j({a:'prior',b:'prior'})!==j({a:'changed',b:'observed-change'});
 if(x==='hostRandom'||x==='wallClockTics')return digest(b())!==digest({...b(),tic:1});
 if(x==='crossSession')return j([{session:'A',health:20},{session:'B',health:20}])!==j([{session:'A',health:10},{session:'B',health:10}]);
 if(x==='autonomousCommit')return j({afterFault:'rolled-back'})!==j({afterFault:'committed'});
 if(x==='typeCase')return 'join doom_monster_def using(thing_type)'!=='case thing_type when 9 then';
 if(x==='approxLos')return j({numerator:1,denominator:3,blocked:true})!==j({sample:0.33,blocked:false});
 if(x==='unboundedBfs')return j({visits:[1,2,3]})!==j({visits:[1,2,3,1,2,3]});return false}
for(const q of specs){assert.ok(witness(q.mode),`${q.id} survived focused witness`);killed++}process.stdout.write(`PASS T7.2-EVAL-MUTATION-SELF-CHECK (${killed}/${specs.length} isolated mutations killed)\n`);
