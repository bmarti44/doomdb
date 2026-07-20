#!/usr/bin/env node
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { parseWad } from './parser.mjs';

const WAD_SHA256 = '7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d';
const MAP = 'E1M1';
const sourceIds = ['plan-contract', 'doomwiki-behavior'];
const sources = [
  { id: 'plan-contract', title: 'DoomDB v2 implementation contract', url: 'https://github.com/doomdb/doomdb/blob/main/PLAN.md', license: 'MIT', usage: 'Project-specific behavior, determinism, scope, and independently authored implementation rules.', copiedCodeOrData: false },
  { id: 'doomwiki-behavior', title: 'DoomWiki gameplay and map-special documentation', url: 'https://doomwiki.org/wiki/Category:Doom_gameplay', license: 'CC BY-SA 4.0', usage: 'Public descriptions of observable gameplay behavior used as research for hand-authored registry rows.', copiedCodeOrData: false },
  { id: 'doomwiki-wad', title: 'DoomWiki WAD and map format documentation', url: 'https://doomwiki.org/wiki/WAD', license: 'CC BY-SA 4.0', usage: 'Public file-format descriptions used to interpret independently parsed WAD data.', copiedCodeOrData: false },
  { id: 'freedoom-data', title: 'Freedoom Phase 1 0.13.0 data and art', url: 'https://github.com/freedoom/freedoom/releases/tag/v0.13.0', license: 'BSD-3-Clause', usage: 'Pinned WAD asset names, bytes, map placements, and texture-to-patch provenance.', copiedCodeOrData: false }
];

const identities = {
  1:['PLAYER_1_START','spawn_marker'],2:['PLAYER_2_START','spawn_marker'],3:['PLAYER_3_START','spawn_marker'],4:['PLAYER_4_START','spawn_marker'],5:['BLUE_KEYCARD','pickup'],8:['BACKPACK','pickup'],9:['SHOTGUNNER','monster'],10:['GIBBED_PLAYER','decoration'],11:['DEATHMATCH_START','spawn_marker'],12:['DEAD_PLAYER','decoration'],15:['DEAD_CACODEMON','decoration'],17:['DEAD_DEMON','decoration'],18:['DEAD_ZOMBIEMAN','decoration'],19:['DEAD_SHOTGUNNER','decoration'],20:['DEAD_IMP','decoration'],21:['DEAD_LOST_SOUL','decoration'],24:['BLOOD_POOL','decoration'],26:['HANGING_LEG','decoration'],43:['HANGING_PAIR_LEGS','decoration'],47:['HANGING_VICTIM_ARMS_OUT','decoration'],48:['TALL_TECH_LAMP','decoration'],54:['LARGE_BROWN_TREE','decoration'],58:['SPECTRE','monster'],60:['HANGING_TORSO','decoration'],
  2001:['SHOTGUN','weapon_pickup'],2002:['CHAINGUN','weapon_pickup'],2003:['ROCKET_LAUNCHER','weapon_pickup'],2004:['PLASMA_RIFLE','weapon_pickup'],2005:['CHAINSAW','weapon_pickup'],2007:['AMMO_CLIP','pickup'],2008:['SHELL_BOX','pickup'],2010:['ROCKET_BOX','pickup'],2011:['STIMPACK','pickup'],2012:['MEDIKIT','pickup'],2013:['SOULSPHERE','pickup'],2014:['HEALTH_BONUS','pickup'],2015:['ARMOR_BONUS','pickup'],2018:['GREEN_ARMOR','pickup'],2019:['BLUE_ARMOR','pickup'],2023:['BERSERK','pickup'],2028:['FLOOR_LAMP','decoration'],2035:['EXPLOSIVE_BARREL','barrel'],2046:['ROCKET','pickup'],2047:['CELL_CHARGE','pickup'],2048:['BULLET_BOX','pickup'],2049:['CELL_PACK','pickup'],3001:['IMP','monster'],3002:['DEMON','monster'],3004:['ZOMBIEMAN','monster']
};
const sprite = {
  5:['BKEY','A'],8:['BPAK','A'],9:['SPOS','A'],10:['PLAY','W'],12:['PLAY','N'],15:['HEAD','L'],17:['SARG','N'],18:['POSS','L'],19:['SPOS','L'],20:['TROO','M'],21:['SKUL','K'],24:['POL5','A'],26:['POL6','A'],43:['GOR1','A'],47:['GOR4','A'],48:['ELEC','A'],54:['TRE2','A'],58:['SARG','A'],60:['GOR2','A'],2001:['SHOT','A'],2002:['MGUN','A'],2003:['LAUN','A'],2004:['PLAS','A'],2005:['CSAW','A'],2007:['CLIP','A'],2008:['SBOX','A'],2010:['BROK','A'],2011:['STIM','A'],2012:['MEDI','A'],2013:['SOUL','A'],2014:['BON1','A'],2015:['BON2','A'],2018:['ARM1','A'],2019:['ARM2','A'],2023:['PSTR','A'],2028:['COLU','A'],2035:['BAR1','A'],2046:['ROCK','A'],2047:['CELL','A'],2048:['AMMO','A'],2049:['CELP','A'],3001:['TROO','A'],3002:['SARG','A'],3004:['POSS','A']
};
const monsters = {
  9:{health:30,prefix:'SPOS',sound:'DSSGTSIT',deathSound:'DSSGTDTH',actions:['HITSCAN_ATTACK'],dropType:2001},
  58:{health:150,prefix:'SARG',sound:'DSBGSIT1',deathSound:'DSBGDTH1',actions:['MELEE_ATTACK'],dropType:null,flags:['SHADOW']},
  3001:{health:60,prefix:'TROO',sound:'DSBGSIT2',deathSound:'DSBGDTH2',actions:['MELEE_ATTACK','SPAWN_IMP_FIREBALL'],dropType:null},
  3002:{health:150,prefix:'SARG',sound:'DSBGSIT1',deathSound:'DSBGDTH1',actions:['MELEE_ATTACK'],dropType:null},
  3004:{health:20,prefix:'POSS',sound:'DSPOSIT1',deathSound:'DSPODTH1',actions:['HITSCAN_ATTACK'],dropType:2007}
};
const linedefSemantics = {1:['USE','REPEAT','DOOR_OPEN_WAIT_CLOSE'],2:['WALK','ONCE','DOOR_OPEN_STAY'],11:['USE','ONCE','EXIT'],23:['USE','ONCE','FLOOR_LOWER_LOWEST'],26:['USE','REPEAT','BLUE_KEY','DOOR_OPEN_WAIT_CLOSE'],62:['USE','REPEAT','LIFT_LOWER_WAIT_RAISE'],88:['WALK','REPEAT','LIFT_LOWER_WAIT_RAISE'],117:['USE','REPEAT','BLAZING_DOOR_OPEN_WAIT_CLOSE']};
const sectorSemantics = {1:['LIGHT_RANDOM_BLINK'],7:['DAMAGE_5','DAMAGE_EVERY_32_TICS'],9:['SECRET_ONCE'],12:['LIGHT_SYNC_SLOW_STROBE']};
const pickupEffects = {5:'GRANT_BLUE_KEYCARD',8:'GRANT_BACKPACK',2007:'ADD_BULLETS_SMALL',2008:'ADD_SHELLS_BOX',2010:'ADD_ROCKETS_BOX',2011:'HEAL_10_MAX_100',2012:'HEAL_25_MAX_100',2013:'HEAL_TO_200',2014:'HEAL_1_MAX_200',2015:'ADD_ARMOR_1_MAX_200',2018:'SET_GREEN_ARMOR_100',2019:'SET_BLUE_ARMOR_200',2023:'BERSERK_HEAL_AND_POWER',2046:'ADD_ROCKET_SINGLE',2047:'ADD_CELLS_SMALL',2048:'ADD_BULLETS_BOX',2049:'ADD_CELLS_LARGE'};
const weaponSpecs = [
  ['FIST',null,'NONE','PUNG','MELEE_ATTACK',['DSPUNCH']],['PISTOL',null,'BULLET','PISG','HITSCAN_ATTACK',['DSPISTOL']],['SHOTGUN',2001,'SHELL','SHTG','SHOTGUN_ATTACK',['DSSHOTGN','DSSGCOCK']],['CHAINGUN',2002,'BULLET','CHGG','HITSCAN_ATTACK',['DSPISTOL']],['ROCKET_LAUNCHER',2003,'ROCKET','MISG','SPAWN_ROCKET',['DSRLAUNC']],['PLASMA_RIFLE',2004,'CELL','PLSG','SPAWN_PLASMA',['DSPLASMA']],['CHAINSAW',2005,'NONE','SAWG','SAW_ATTACK',['DSSAWUP','DSSAWIDL','DSSAWFUL','DSSAWHIT']]
];
const requiredSounds = ['DSPISTOL','DSSHOTGN','DSSGCOCK','DSSAWUP','DSSAWIDL','DSSAWFUL','DSSAWHIT','DSRLAUNC','DSRXPLOD','DSFIRSHT','DSFIRXPL','DSPLASMA','DSDOROPN','DSDORCLS','DSSTNMOV','DSSWTCHN','DSSWTCHX','DSPLPAIN','DSPOPAIN','DSITEMUP','DSWPNUP','DSOOF','DSNOWAY','DSPOSIT1','DSPOSIT2','DSPOSIT3','DSSGTSIT','DSBGSIT1','DSBGSIT2','DSSGTATK','DSCLAW','DSPODTH1','DSPODTH2','DSPODTH3','DSSGTDTH','DSBGDTH1','DSBGDTH2','DSPOSACT','DSBGACT','DSBAREXP','DSPUNCH'];
const requiredMusic = ['D_E1M1','D_INTER','D_VICTOR'];
const requiredUi = ['TITLEPIC','M_DOOM','M_EPISOD','M_NGAME','M_SKILL','M_PAUSE','STBAR',...Array.from({length:10},(_,i)=>`STTNUM${i}`),'STTPRCNT',...Array.from({length:10},(_,i)=>`STYSNUM${i}`),...Array.from({length:6},(_,i)=>`STKEYS${i}`),'STARMS','STFB0','STFGOD0','STFDEAD0','WIMAP0','WILV00','WILV01','WIURH0','WIURH1','WISPLAT',...Array.from({length:10},(_,i)=>`WINUM${i}`),'WIPCNT','WICOLON','WIMINUS','WIF','WIENTER','WIOSTK','WIOSTS','WITIME','WIPAR','WIKILRS','WIVCTMS','WIMSTT','WISCRT2'];
const animationGroups = [
  {id:'FLAT_NUKAGE',kind:'flat',periodTics:8,frames:['NUKAGE1','NUKAGE2','NUKAGE3']},
  {id:'FLAT_FWATER',kind:'flat',periodTics:8,frames:['FWATER1','FWATER2','FWATER3','FWATER4']},
  {id:'WALL_SFALL',kind:'wall_texture',periodTics:8,frames:['SFALL1','SFALL2','SFALL3','SFALL4']}
];

function arg(name, fallback) { const at = process.argv.indexOf(name); return at < 0 ? fallback : process.argv[at + 1]; }
function canonical(file, value) { fs.mkdirSync(path.dirname(file), {recursive:true}); fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`); }
function state(id,tics,next,action,prefix,frame,rotations='0',sound) { return {id,tics,next,action,sourceIds,sprite:{prefix,frame,rotations},...(sound?{sound}:{})}; }

const wadPath = arg('--wad');
const output = path.resolve(arg('--output', 'tools/wad'));
if (!wadPath) throw new Error('usage: build-engine-defs.mjs --wad FILE [--output DIR]');
const bytes = fs.readFileSync(wadPath);
if (crypto.createHash('sha256').update(bytes).digest('hex') !== WAD_SHA256) throw new Error('pinned WAD SHA-256 mismatch');
const parsed = parseWad(bytes, MAP);
const lumpNames = new Set(parsed.directory.map((row)=>row.name));
const placed = [...new Set(parsed.things.map((row)=>row.type))].sort((a,b)=>a-b);
if (JSON.stringify(placed) !== JSON.stringify(Object.keys(identities).map(Number).sort((a,b)=>a-b))) throw new Error('placed E1M1 type closure differs from authored registry');

const states = [];
const thingTypes = [];
for (const id of placed) {
  const [name,category] = identities[id];
  if (category === 'spawn_marker') { thingTypes.push({id,name,category,spawnState:null,sourceIds}); continue; }
  const [prefix,frame] = sprite[id];
  const rotations = monsters[id] ? 'ALL' : '0';
  const spawnState = `THING_${id}_SPAWN`;
  states.push(state(spawnState, category === 'decoration' ? -1 : 8, category === 'decoration' ? null : spawnState, category === 'barrel' ? 'BARREL_IDLE' : category === 'monster' ? 'LOOK_FOR_TARGET' : 'PRESENT_PICKUP', prefix, frame, rotations));
  const row = {id,name,category,spawnState,sourceIds};
  if (monsters[id]) {
    const spec=monsters[id];
    row.health=spec.health; row.seeState=`THING_${id}_SEE`; row.attackState=`THING_${id}_ATTACK_1`; row.painState=`THING_${id}_PAIN`; row.deathState=`THING_${id}_DEATH`; row.dropType=spec.dropType; row.sounds=[spec.sound,spec.deathSound];
    if(spec.flags) row.flags=spec.flags;
    states.push(state(row.seeState,3,row.seeState,'CHASE_TARGET',prefix,'A','ALL',spec.sound));
    spec.actions.forEach((action,index)=>states.push(state(`THING_${id}_ATTACK_${index+1}`,8,index+1<spec.actions.length?`THING_${id}_ATTACK_${index+2}`:row.seeState,action,prefix,'B','ALL',action==='SPAWN_IMP_FIREBALL'?'DSFIRSHT':undefined)));
    states.push(state(row.painState,4,row.seeState,'APPLY_PAIN_REACTION',prefix,'G','ALL','DSPOPAIN'));
    states.push(state(row.deathState,-1,null,'CORPSE_TERMINAL',prefix,id===58||id===3002?'N':id===9?'L':id===3001?'M':'L','0',spec.deathSound));
  }
  if (id===2035) { row.radius=10; row.height=42; row.health=20; row.deathState='THING_2035_DEATH'; states.push(state(row.deathState,-1,null,'EXPLODE_AND_DAMAGE_RADIUS','BAR1','B','0','DSBAREXP')); }
  thingTypes.push(row);
}

const weapons=[];
for(const [id,thingType,ammoType,prefix,fireAction,sounds] of weaponSpecs){
  const base=`WEAPON_${id}`;
  states.push(state(`${base}_READY`,1,`${base}_READY`,'WEAPON_READY',prefix,'A'));
  states.push(state(`${base}_FIRE`,4,`${base}_REFIRE`,fireAction,prefix,'B','0',sounds[0]));
  states.push(state(`${base}_REFIRE`,4,`${base}_READY`,'CHECK_REFIRE',prefix,'A'));
  states.push(state(`${base}_FLASH`,2,`${base}_READY`,'EMIT_MUZZLE_FLASH',prefix,'B'));
  weapons.push({id,thingType,ammoType,readyState:`${base}_READY`,fireState:`${base}_FIRE`,refireState:`${base}_REFIRE`,flashState:`${base}_FLASH`,sounds,sourceIds});
}
const pickups=Object.entries(pickupEffects).map(([thingType,id])=>({thingType:Number(thingType),effect:{id},consume:true,sound:Number(thingType)>=2001&&Number(thingType)<=2005?'DSWPNUP':'DSITEMUP',sourceIds})).sort((a,b)=>a.thingType-b.thingType);
const defs={schema:1,wad:{sha256:WAD_SHA256,map:MAP},sources,thingTypes,linedefSpecials:Object.entries(linedefSemantics).map(([id,semantics])=>({id:Number(id),semantics,sourceIds})),sectorSpecials:Object.entries(sectorSemantics).map(([id,semantics])=>({id:Number(id),semantics,sourceIds})),weapons,pickups,states};

const assetMap=new Map();
const add=(kind,name,reasons,sourceLumps=[name])=>{
  for(const lump of sourceLumps) if(!lumpNames.has(lump)) throw new Error(`${kind}:${name} source lump ${lump} is absent`);
  const key=`${kind}:${name}`; const old=assetMap.get(key);
  if(old){old.reasons=[...new Set([...old.reasons,...reasons])].sort(); return;}
  assetMap.set(key,{kind,name,reasons:[...new Set(reasons)].sort(),sourceLumps});
};
const textureByName=new Map(parsed.textures.map((row)=>[row.name,row]));
const wallRoots=new Set();
for(const side of parsed.mapData.sidedefs) for(const name of [side.upper,side.lower,side.middle]) if(name!=='-') wallRoots.add(name);
for(const group of animationGroups.filter(g=>g.kind==='wall_texture')) for(const name of group.frames) wallRoots.add(name);
// A pressed Doom switch changes the sidedef's SW1* texture to its SW2* mate.
// Pull that mate into the immutable asset closure even though the map only
// names the unpressed texture.  This is naming/texture metadata, not a list of
// route-specific linedefs, and therefore works for every switch in the WAD.
for(const name of [...wallRoots]) if(name.startsWith('SW1')){
  const alternate=`SW2${name.slice(3)}`;
  if(!textureByName.has(alternate)) throw new Error(`switch wall mate ${alternate} for ${name} is absent`);
  wallRoots.add(alternate);
}
for(const name of [...wallRoots].sort()){
  const texture=textureByName.get(name); if(!texture) throw new Error(`wall texture ${name} is absent`);
  const patches=texture.patches.map(row=>parsed.pnames[row.patch]);
  add('wall_texture',name,[wallRoots.has(name)?'E1M1 wall or required animation frame':'required animation frame'],patches);
  for(const patch of patches) add('patch',patch,[`wall texture ${name}`]);
}
const flatRoots=new Set(parsed.mapData.sectors.flatMap(row=>[row.floorFlat,row.ceilingFlat]));
for(const group of animationGroups.filter(g=>g.kind==='flat')) for(const name of group.frames) flatRoots.add(name);
for(const name of [...flatRoots].sort()) add('flat',name,['E1M1 surface or required animation frame']);
const spriteLumps=(spec)=>{
  if(spec.rotations==='0') return [`${spec.prefix}${spec.frame}0`];
  return [...lumpNames].filter(name=>name.startsWith(spec.prefix)&&[...name.slice(4).matchAll(/([A-Z])([0-8])/g)].some(pair=>pair[1]===spec.frame)).sort();
};
for(const row of states){for(const lump of spriteLumps(row.sprite)) add('sprite_patch',lump,[`state ${row.id}`]); if(row.sound)add('sound',row.sound,[`state ${row.id}`]);}
for(const name of requiredSounds) add('sound',name,['required E1M1 gameplay audio']);
for(const name of requiredMusic) add('music',name,['E1M1 or intermission music']);
for(const name of requiredUi) add('ui_patch',name,['menu, HUD, pause, or intermission UI']);
const kindOrder=new Map(['wall_texture','flat','patch','sprite_patch','sound','music','ui_patch'].map((kind,index)=>[kind,index]));
const assets=[...assetMap.values()].sort((a,b)=>kindOrder.get(a.kind)-kindOrder.get(b.kind)||a.name.localeCompare(b.name));
const closure={schema:1,wadSha256:WAD_SHA256,map:MAP,assets};
const rngValues=[];
for(let counter=0;rngValues.length<256;counter++)rngValues.push(...crypto.createHash('sha256').update(`DoomDB project RNG v1|${String(counter).padStart(4,'0')}`,'ascii').digest());
const rng={schema:1,algorithm:'PROJECT_TABLE_V1',derivation:"concatenate SHA-256 ASCII bytes for 'DoomDB project RNG v1|' plus a zero-padded four-digit counter, counters starting at 0000; take first 256 bytes",cursorRule:'read values[cursor], then persist (cursor + 1) modulo 256 for every gameplay random read',values:rngValues.slice(0,256)};
canonical(path.join(output,'engine-defs.json'),defs);
canonical(path.join(output,'asset-closure.json'),closure);
canonical(path.join(output,'animation-groups.json'),{schema:1,groups:animationGroups});
canonical(path.join(output,'rng-table.json'),rng);
process.stdout.write(`generated ${thingTypes.length} thing types, ${states.length} states, and ${assets.length} asset rows\n`);
