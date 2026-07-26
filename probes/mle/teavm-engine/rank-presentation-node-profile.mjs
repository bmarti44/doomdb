#!/usr/bin/env node
import fs from 'node:fs';

const profilePath = process.argv[2];
if (!profilePath) {
  throw new Error('usage: rank-presentation-node-profile.mjs PROFILE.cpuprofile');
}
const profile = JSON.parse(fs.readFileSync(profilePath, 'utf8'));
if (!Array.isArray(profile.nodes) || !Array.isArray(profile.samples)
    || !Array.isArray(profile.timeDeltas)
    || profile.samples.length !== profile.timeDeltas.length) {
  throw new Error('malformed V8 CPU profile');
}

const nodes = new Map(profile.nodes.map(node => [node.id, node]));
const selfMicros = new Map();
let totalMicros = 0, excluded = 0;
for (let index = 0; index < profile.samples.length; index += 1) {
  const node = nodes.get(profile.samples[index]);
  const micros = Number(profile.timeDeltas[index]);
  if (node === undefined || !Number.isFinite(micros)) {
    throw new Error(`invalid CPU sample at index ${index}`);
  }
  // Node/V8 profiles occasionally contain a negative clock-correction
  // delta. Preserve the source profile and count the excluded record instead
  // of attributing negative CPU to whichever function happened to be sampled.
  if (micros < 0) {
    excluded += 1;
    continue;
  }
  const name = node.callFrame?.functionName || '(anonymous)';
  selfMicros.set(name, (selfMicros.get(name) ?? 0) + micros);
  totalMicros += micros;
}
if (totalMicros <= 0 || excluded / profile.samples.length > 0.005) {
  throw new Error(`presentation profile exclusion cap exceeded: ${excluded}`);
}

const percent = micros => (micros * 100 / totalMicros).toFixed(3);
for (const [functionName, micros] of [...selfMicros]
    .sort((left, right) => right[1] - left[1]).slice(0, 50)) {
  const safeName = functionName.replaceAll('|', '/').replaceAll(/\s+/g, ' ');
  console.log(
    `PMLE_PRESENTATION_NODE_PROFILE_TOP|function=${safeName}`
    + `|self_ms=${(micros / 1000).toFixed(3)}`
    + `|self_pct=${percent(micros)}`,
  );
}
console.log(
  `PMLE_PRESENTATION_NODE_PROFILE_RANK|PASS|samples=${profile.samples.length}`
  + `|excluded_negative=${excluded}`
  + `|exclusion_pct=${(excluded * 100 / profile.samples.length).toFixed(3)}`
  + `|sampled_ms=${(totalMicros / 1000).toFixed(3)}`,
);
