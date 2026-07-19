import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = process.argv[2];
if (!source) throw Error('usage: node public-route-probe.mjs route.json');
const route = JSON.parse(fs.readFileSync(source, 'utf8'));
const base = process.env.DOOM_API_BASE ?? 'http://localhost:8080/ords/doom/doom_api/';
const skill = Number(process.env.DOOM_ROUTE_SKILL_OVERRIDE ?? route.skill);
const skipAccepted = process.env.DOOM_ROUTE_SKIP_ACCEPTED === '1';
const capturePath = process.env.DOOM_ROUTE_CAPTURE ?? '';
assert.ok(Number.isInteger(skill) && skill >= 1 && skill <= 5, 'route skill');
const value = (document, key) => document[key] ?? document[key.toUpperCase()]
  ?? document.items?.[0]?.[key] ?? document.items?.[0]?.[key.toUpperCase()];

async function post(name, body) {
  const stem = name.replace(/^\//, '').replace(/\/$/, '');
  let response;
  for (const path of [stem.toUpperCase(), `${stem.toLowerCase()}/`]) {
    response = await fetch(new URL(path, base), {
      method: 'POST', headers: {'content-type': 'application/json'},
      body: JSON.stringify(body), redirect: 'error'
    });
    if (response.status !== 404) break;
  }
  if (!response?.ok) throw Error(`${name}: ${response?.status} ${await response?.text()}`);
  return response.json();
}
let latestPayload;
function frame(document) {
  const payload = Buffer.from(value(document, 'p_payload'), 'base64');
  latestPayload = payload;
  assert.equal(payload.subarray(0, 4).toString(), 'DMF3');
  return {tic: payload.readInt32BE(4), mode: payload[8] === 1 ? 'DEAD'
    : payload[9] === 1 ? 'INTERMISSION' : 'GAME',
  stateSha: payload.subarray(10, 74).toString(),
  frameSha: payload.subarray(74, 138).toString()};
}

const commands = [];
for (const run of route.runs) {
  assert.ok(Number.isInteger(run.repeat) && run.repeat > 0);
  for (let index = 0; index < run.repeat; index += 1) commands.push(run.command);
}
assert.equal(commands.length, route.commandCount);
if (route.constraints?.noCheats) {
  assert.ok(commands.every(command => command.cheat === ''), 'route contains cheat');
}
const created = await post('new_game', {p_skill: skill});
const session = value(created, 'p_session');
let current = frame(created), sequence = 0;
const milestones = new Map((route.accepted?.milestones ?? [])
  .map(milestone => [milestone.tic, milestone]));
for (const sourceCommand of commands) {
  const command = {...sourceCommand, seq: ++sequence};
  current = frame(await post('step', {p_session: session,
    p_commands: JSON.stringify({v: route.envelopeVersion ?? 1, commands: [command]})}));
  const milestone = milestones.get(sequence);
  if (milestone && !skipAccepted) {
    assert.equal(current.stateSha, milestone.stateSha, `state milestone ${sequence}`);
    assert.equal(current.frameSha, milestone.frameSha, `frame milestone ${sequence}`);
  }
  if (sequence % 500 === 0) process.stderr.write(`tic ${sequence} ${current.mode}\n`);
  if (current.mode !== 'GAME') break;
}
if (route.accepted && !skipAccepted) {
  assert.equal(sequence, route.accepted.terminalTic);
  assert.equal(current.mode, route.accepted.mode);
  assert.equal(current.stateSha, route.accepted.stateSha);
  assert.equal(current.frameSha, route.accepted.frameSha);
}
if (capturePath) fs.writeFileSync(capturePath, latestPayload);
process.stdout.write(`${JSON.stringify({session, source, skill, sequence,
  capturePath: capturePath || undefined, ...current})}\n`);
