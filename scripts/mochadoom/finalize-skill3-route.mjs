#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const [source, output, stateSha, frameSha] = process.argv.slice(2);
if (!source || !output || !/^[0-9a-f]{64}$/.test(stateSha ?? '') ||
    !/^[0-9a-f]{64}$/.test(frameSha ?? '')) {
  throw new Error('usage: finalize-skill3-route.mjs export.json output.json state-sha frame-sha');
}

const route = JSON.parse(fs.readFileSync(source, 'utf8'));
assert.equal(route.envelopeVersion, 2, 'signed command envelope');
assert.equal(route.startSequence, 0, 'fresh replay starts at sequence zero');
assert.equal(route.commandCount, 13272, 'complete skill-3 tic count');
assert.equal(route.runs.reduce((sum, run) => sum + run.repeat, 0),
  route.commandCount, 'normalized run count');
const keys = ['automap', 'cheat', 'fire', 'forward', 'menu', 'pause', 'run',
  'strafe', 'turn', 'use', 'weapon'];
for (const run of route.runs) {
  assert.ok(Number.isInteger(run.repeat) && run.repeat > 0, 'positive run');
  run.command.cheat ??= '';
  assert.deepEqual(Object.keys(run.command).sort(), keys, 'strict command keys');
  assert.equal(run.command.cheat, '', 'route is cheat-free');
}
route.skill = 3;
route.purpose = 'T8.1 uninterrupted normal-skill-3 no-cheat E1M1 completion';
route.constraints = {generatedAutoRestOnly: true, noCheats: true,
  noSaveLoadDuringReplay: true};
route.accepted = {terminalTic: 13272, mode: 'INTERMISSION', stateSha, frameSha};
fs.writeFileSync(output, `${JSON.stringify(route, null, 2)}\n`);
process.stdout.write(`WROTE ${output} (${route.commandCount} commands, ${route.runs.length} runs)\n`);
