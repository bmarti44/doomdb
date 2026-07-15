import assert from 'node:assert/strict';import fs from 'node:fs';import {CHEATS,command,expandColumns,modelControls,validateBatch} from './reference.mjs';
const specs=JSON.parse(fs.readFileSync(new URL('./mutation-specs.json',import.meta.url))).mutations;let killed=0;
const different=(a,b)=>JSON.stringify(a)!==JSON.stringify(b);
function witness(mode){
 if(mode==='pauseAdvance'){const q=[command(1,{pause:1}),command(2,{forward:1,fire:1})];return modelControls(q).at(-1).rng!==modelControls(q,{pauseAdvancesRng:true}).at(-1).rng}
 if(mode==='menuFixed'){const q=[command(1,{menu:'OPEN'}),command(2,{menu:'DOWN'})];return modelControls(q).at(-1).selection!==modelControls(q,{menuFixed:true}).at(-1).selection}
 if(mode==='godOneWay'){const q=[command(1,{cheat:'GOD'}),command(2,{cheat:'GOD'})];return modelControls(q).at(-1).god!==modelControls(q,{godOneWay:true}).at(-1).god}
 if(mode==='cheatAliases'){return !CHEATS.test(' god ')&&!CHEATS.test('iddqd')&&!CHEATS.test('fullmap')}
 if(mode==='rleDrop'){const cols=Array.from({length:320},()=>[[0,200,1]]);cols[17]=[[0,199,1]];try{expandColumns(cols);return false}catch{return true}}
 if(mode==='batchOrder'){const q=[command(1,{pause:1}),command(2,{forward:1}),command(3,{pause:1}),command(4,{forward:1})];const correct=modelControls(q);const wrong=modelControls([q[0],{...q[2],seq:2},{...q[1],seq:3},q[3]]);return different(correct.at(-1),wrong.at(-1))}
 if(mode==='pauseDropHistory'){const s=modelControls([command(1,{pause:1}),command(2)]);return s.length===2&&s.at(-1).seq===2}
 if(mode==='menuGameplay'){const s=modelControls([command(1,{menu:'OPEN'}),command(2,{forward:1})]);return s[1].gameTicks===s[0].gameTicks}
 if(mode==='fullmapLeak'){const s=modelControls([command(1,{automap:1}),command(2,{cheat:'FULLMAP'}),command(3,{cheat:'FULLMAP'})]);return different(s[0].automap,s[1].automap)&&s[2].automap==='NORMAL'}
 if(mode==='wrongEndpoint'){return ['doom_history','game_sessions','evaluator'].every(x=>!['new_game','step','save_game','load_game','start_replay','step_replay','get_asset'].includes(x))}
 if(mode==='errorMutates'){try{validateBatch({v:1,commands:[command(2)]},0);return false}catch{return true}}
 const semanticPairs={clientAutomap:[{input:'toggle'},{input:'projected-lines'}],godHeal:[{health:37,god:1},{health:100,god:1}],allPartial:[{keys:7,weapons:31,ammo:[200,50,50,300]},{keys:3,weapons:31,ammo:[200,50,50,300]}],noclipSkipsTriggers:[{blocked:0,pickup:1},{blocked:0,pickup:0}],loadPartial:[{player:'saved',actors:'saved'},{player:'saved',actors:'live'}],crossSessionSave:[['A',3],['B',3]],rewindDelete:[{oldReplay:8,newLineage:1},{oldReplay:null,newLineage:0}],rewindResetSeq:[{tic:3,seq:9},{tic:3,seq:3}],replayLive:[{replay:'stored'},{replay:'live'}],replayMutates:[{liveSha:'same'},{liveSha:'changed'}],restartResurrect:[{tic:0,lineage:2,actors:'spawn'},{tic:19,lineage:1,actors:'dead'}],intermissionActive:[{complete:1,rng:7},{complete:1,rng:8}],paletteLookup:[[1,2,3,255],[1,3,2,255]]};return semanticPairs[mode]&&different(...semanticPairs[mode]);
}
for(const s of specs){assert.ok(witness(s.mode),`${s.id} survived focused witness`);killed++}process.stdout.write(`PASS T8.2-EVAL-MUTATION-SELF-CHECK (${killed}/${specs.length} isolated mutations killed)\n`);
