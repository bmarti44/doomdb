import assert from 'node:assert/strict';
import fs from 'node:fs';

const [session, sequenceText, repeatText, commandText, capturePath = ''] = process.argv.slice(2);
if (!/^[0-9a-f]{32}$/.test(session ?? '')) throw Error('invalid session token');
let sequence = Number(sequenceText), repeat = Number(repeatText);
assert.ok(Number.isInteger(sequence) && sequence >= 0, 'starting sequence');
assert.ok(Number.isInteger(repeat) && repeat > 0, 'repeat');
const command = JSON.parse(commandText);
const expected = ['turn','forward','strafe','run','fire','use','weapon','pause',
  'automap','menu','cheat'];
assert.deepEqual(Object.keys(command).sort(), expected.sort(), 'command keys');
const base = process.env.DOOM_API_BASE ?? 'http://localhost:8080/ords/doom/doom_api/';
const value = (document, key) => document[key] ?? document[key.toUpperCase()]
  ?? document.items?.[0]?.[key] ?? document.items?.[0]?.[key.toUpperCase()];
async function post(body) {
  let response;
  for (const path of ['STEP', 'step/']) {
    response = await fetch(new URL(path, base), {method: 'POST',
      headers: {'content-type': 'application/json'}, body: JSON.stringify(body), redirect: 'error'});
    if (response.status !== 404) break;
  }
  if (!response?.ok) throw Error(`STEP: ${response?.status} ${await response?.text()}`);
  return Buffer.from(value(await response.json(), 'p_payload'), 'base64');
}

let payload;
for (let index = 0; index < repeat; index += 1) {
  payload = await post({p_session: session,
    p_commands: JSON.stringify({v: 2, commands: [{seq: ++sequence, ...command}]})});
  assert.equal(payload.subarray(0, 4).toString(), 'DMF3');
  if (payload[8] === 1 || payload[9] === 1) break;
}
if (capturePath) fs.writeFileSync(capturePath, payload);
process.stdout.write(`${JSON.stringify({session, sequence, tic: payload.readInt32BE(4),
  mode: payload[8] === 1 ? 'DEAD' : payload[9] === 1 ? 'INTERMISSION' : 'GAME',
  stateSha: payload.subarray(10, 74).toString(),
  frameSha: payload.subarray(74, 138).toString(), capturePath: capturePath || undefined})}\n`);
