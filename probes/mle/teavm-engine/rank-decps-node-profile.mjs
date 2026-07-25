import fs from 'node:fs';

const profilePath = process.argv[2];
if (!profilePath) {
  throw new Error('usage: rank-decps-node-profile.mjs PROFILE.cpuprofile');
}
const selfTest = profilePath === '--self-test';
const profile = selfTest ? {
  nodes: [
    {id: 1, callFrame: {functionName: 'P_CheckSight'}},
    {id: 2, callFrame: {functionName: 'P_MobjThinker'}},
    {id: 3, callFrame: {functionName: 'Long_compare'}},
    {id: 4, callFrame: {functionName: '(garbage collector)'}},
  ],
  samples: [1, 2, 3, 4],
  timeDeltas: [250, 250, 250, 250],
} : JSON.parse(fs.readFileSync(profilePath, 'utf8'));
if (!Array.isArray(profile.nodes) || !Array.isArray(profile.samples)
    || !Array.isArray(profile.timeDeltas)
    || profile.samples.length !== profile.timeDeltas.length) {
  throw new Error('malformed V8 CPU profile');
}

const nodes = new Map(profile.nodes.map(node => [node.id, node]));
const selfMicros = new Map();
let totalMicros = 0;
for (let index = 0; index < profile.samples.length; index += 1) {
  const node = nodes.get(profile.samples[index]);
  const micros = Number(profile.timeDeltas[index]);
  if (node === undefined || !Number.isFinite(micros) || micros < 0) {
    throw new Error(`invalid CPU sample at index ${index}`);
  }
  const name = node.callFrame?.functionName || '(anonymous)';
  selfMicros.set(name, (selfMicros.get(name) ?? 0) + micros);
  totalMicros += micros;
}
if (totalMicros <= 0) {
  throw new Error('empty V8 CPU profile');
}

const categories = [
  ['sight_bsp',
    /Sight|CheckSight|CrossBSP|CrossSubsector|Divline|InterceptVector|AimLine|AimTraverse/i],
  ['movement_ai',
    /MobjThinker|TryMove|CheckPosition|NewChaseDir|Move|Chase|Look|PIT_|PathTraverse|BlockThingsIterator/i],
  ['mobj_flag_long',
    /Long_|Long(?!itude)|longBits|longFrom|longTo|compareLong/i],
  ['garbage_collection', /garbage collector/i],
];
const categoryMicros = new Map(categories.map(([name]) => [name, 0]));
categoryMicros.set('other', 0);

for (const [functionName, micros] of selfMicros) {
  const category = categories.find(([, pattern]) => pattern.test(functionName));
  const name = category?.[0] ?? 'other';
  categoryMicros.set(name, categoryMicros.get(name) + micros);
}
if (selfTest && [...categoryMicros.values()].join(',') !==
    '250,250,250,250,0') {
  throw new Error('de-CPS CPU category self-test failed');
}

const percent = micros => (micros * 100 / totalMicros).toFixed(3);
for (const [name, micros] of categoryMicros) {
  console.log(
    `PMLE_DECPS_NODE_PROFILE_CATEGORY|name=${name}`
    + `|self_ms=${(micros / 1000).toFixed(3)}`
    + `|self_pct=${percent(micros)}`,
  );
}

const top = [...selfMicros].sort((left, right) => right[1] - left[1])
  .slice(0, 30);
for (const [functionName, micros] of top) {
  const safeName = functionName.replaceAll('|', '/').replaceAll(/\s+/g, ' ');
  console.log(
    `PMLE_DECPS_NODE_PROFILE_TOP|function=${safeName}`
    + `|self_ms=${(micros / 1000).toFixed(3)}`
    + `|self_pct=${percent(micros)}`,
  );
}
console.log(
  `PMLE_DECPS_NODE_PROFILE_RANK|PASS|samples=${profile.samples.length}`
  + `|sampled_ms=${(totalMicros / 1000).toFixed(3)}`
  + `|sight_bsp_pct=${percent(categoryMicros.get('sight_bsp'))}`
  + `|sight_bsp_eligible=${
    categoryMicros.get('sight_bsp') * 100 / totalMicros >= 25 ? 'YES' : 'NO'}`
  + `|movement_ai_pct=${percent(categoryMicros.get('movement_ai'))}`
  + `|mobj_flag_long_pct=${percent(categoryMicros.get('mobj_flag_long'))}`,
);
if (selfTest) {
  console.log('PASS PMLE-DECPS-NODE-PROFILE-RANK-SELF-TEST');
}
