import assert from 'node:assert/strict';
import fs from 'node:fs';

const source = process.argv[2];
if (!source) throw Error('usage: node demo-route-probe.mjs demo.lmp');
const base = process.env.DOOM_API_BASE ?? 'http://localhost:8080/ords/doom/doom_api/';
const bytes = fs.readFileSync(source);
assert.equal(bytes[0], 109, 'only Doom 1.9 demos are supported');
assert.equal(bytes[2], 1, 'route must target episode 1');
assert.equal(bytes[3], 1, 'route must target map 1');

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
function frame(document) {
  const payload = Buffer.from(value(document, 'p_payload'), 'base64');
  assert.equal(payload.subarray(0, 4).toString(), 'DMF3');
  return {tic: payload.readInt32BE(4), mode: payload[8] === 1 ? 'DEAD'
    : payload[9] === 1 ? 'INTERMISSION' : 'GAME',
  stateSha: payload.subarray(10, 74).toString(),
  frameSha: payload.subarray(74, 138).toString()};
}
function signed(byte) { return byte > 127 ? byte - 256 : byte; }
function publicCommand(offset, seq, turn = -signed(bytes[offset + 2])) {
  const forward = signed(bytes[offset]);
  const strafe = signed(bytes[offset + 1]);
  const angle = signed(bytes[offset + 2]);
  const buttons = bytes[offset + 3];
  return {seq, turn, forward,
    strafe, run: Number(Math.abs(forward) >= 40 || Math.abs(strafe) >= 40),
    fire: Number((buttons & 1) !== 0), use: Number((buttons & 2) !== 0),
    weapon: (buttons & 4) === 0 ? 0 : ((buttons >> 3) & 7) + 1,
    pause: 0, automap: 0, menu: 'NONE', cheat: ''};
}

const skill = Number(process.env.DOOM_ROUTE_SKILL ?? bytes[1] + 1);
const created = await post('new_game', {p_skill: skill});
const session = value(created, 'p_session');
let current = frame(created), sequence = 0, sourceTics = 0, turnHeld = 0;
let turnResidual = 0;
for (let offset = 13; offset + 3 < bytes.length && bytes[offset] !== 0x80; offset += 4) {
  if (sourceTics >= Number(process.env.DOOM_ROUTE_LIMIT ?? Number.MAX_SAFE_INTEGER)) break;
  sourceTics += 1;
  const demoAngle = signed(bytes[offset + 2]) * 256;
  const commands = [];
  if (process.env.DOOM_ROUTE_EXPAND_TURN === '1' && demoAngle !== 0) {
    turnResidual += demoAngle;
    while (Math.abs(turnResidual) > 160) {
      const turn = -Math.sign(turnResidual);
      turnHeld += 1;
      const magnitude = turnHeld < 6 ? 320
        : (publicCommand(offset, 0).run === 1 ? 1280 : 640);
      if (Math.abs(turnResidual) < magnitude / 2) break;
      turnResidual -= -turn * magnitude;
      commands.push({...publicCommand(offset, 0, turn), forward: 0, strafe: 0,
        fire: 0, use: 0, weapon: 0});
    }
    commands.push({...publicCommand(offset, 0, 0)});
    turnHeld = 0;
  } else {
    const command = publicCommand(offset, 0);
    turnHeld = command.turn === 0 ? 0 : turnHeld + 1;
    commands.push(command);
  }
  for (const command of commands) {
    command.seq = ++sequence;
    current = frame(await post('step', {p_session: session,
      p_commands: JSON.stringify({v: 2, commands: [command]})}));
    if (current.mode !== 'GAME') break;
  }
  if (current.mode !== 'GAME') break;
}
for (const run of JSON.parse(process.env.DOOM_ROUTE_PATCH ?? '[]')) {
  for (let index = 0; index < run.repeat && current.mode === 'GAME'; index += 1) {
    const command = {seq: ++sequence, turn: 0, forward: 0, strafe: 0, run: 0,
      fire: 0, use: 0, weapon: 0, pause: 0, automap: 0, menu: 'NONE', cheat: '',
      ...run.command};
    current = frame(await post('step', {p_session: session,
      p_commands: JSON.stringify({v: 2, commands: [command]})}));
  }
}
process.stdout.write(`${JSON.stringify({session, skill, sourceTics, sequence, ...current})}\n`);
