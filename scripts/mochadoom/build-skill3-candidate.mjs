import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = 'artifacts/t8.1-live/mocha-e1m1-no-cheat-route.json';
const output = 'artifacts/t8.1-live/mocha-e1m1-skill3-candidate.json';
const route = JSON.parse(fs.readFileSync(source, 'utf8'));
assert.equal(route.commandCount, 762);
const defaults = {turn: 0, forward: 0, strafe: 0, run: 0, fire: 0,
  use: 0, weapon: 0, pause: 0, automap: 0, menu: 'NONE', cheat: ''};
const suffix = [
  [34, {turn: 1, run: 1}],
  [50, {forward: 50, run: 1, use: 1}],
  [8, {turn: -1, run: 1}],
  [20, {forward: -50, run: 1, fire: 1}],
  [80, {forward: 50, run: 1, use: 1}],
  [67, {turn: 1, run: 1}],
  [100, {forward: 50, run: 1, use: 1}],
  [17, {turn: -1, run: 1}],
  [1, {automap: 1}],
  [20, {forward: 50, run: 1, use: 1}],
  [10, {fire: 1}],
  [8, {turn: 1, run: 1}],
  [50, {forward: 50, run: 1, use: 1}],
];
route.skill = 3;
route.purpose = 'T8.1 normal-skill-3 no-cheat route authoring candidate';
route.source = {...route.source, extension:
  'DoomDB-authored normalized suffix recovered from the durable Oracle request ledger'};
route.runs.push(...suffix.map(([repeat, command]) =>
  ({repeat, command: {...defaults, ...command}})));
route.commandCount = route.runs.reduce((total, run) => total + run.repeat, 0);
delete route.accepted;
fs.writeFileSync(output, `${JSON.stringify(route, null, 2)}\n`);
process.stdout.write(`WROTE ${output} (${route.commandCount} no-cheat commands)\n`);
