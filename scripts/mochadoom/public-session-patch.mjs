import fs from 'node:fs';

const [session, sequenceText, patchFile] = process.argv.slice(2);
if (!/^[0-9a-f]{32}$/.test(session ?? '') || !/^\d+$/.test(sequenceText ?? '')) {
  throw Error('usage: node public-session-patch.mjs session last-sequence [runs.json]');
}
const base = process.env.DOOM_API_BASE ?? 'http://localhost:8080/ords/doom/doom_api/';
const runs = JSON.parse(patchFile ? fs.readFileSync(patchFile, 'utf8')
  : process.env.DOOM_ROUTE_PATCH ?? '[]');
const value = (document, key) => document[key] ?? document[key.toUpperCase()]
  ?? document.items?.[0]?.[key] ?? document.items?.[0]?.[key.toUpperCase()];
async function post(body) {
  let response;
  for (const path of ['STEP', 'step/']) {
    response = await fetch(new URL(path, base), {method: 'POST',
      headers: {'content-type': 'application/json'}, body: JSON.stringify(body),
      redirect: 'error'});
    if (response.status !== 404) break;
  }
  if (!response?.ok) throw Error(`${response?.status} ${await response?.text()}`);
  return response.json();
}
function frame(document) {
  const payload = Buffer.from(value(document, 'p_payload'), 'base64');
  if (payload.subarray(0, 4).toString() !== 'DMF3') throw Error('DMF3 required');
  const audioLength = payload.readUInt16BE(138);
  return {tic: payload.readInt32BE(4), mode: payload[8] === 1 ? 'DEAD'
    : payload[9] === 1 ? 'INTERMISSION' : 'GAME',
  stateSha: payload.subarray(10, 74).toString(),
  frameSha: payload.subarray(74, 138).toString(),
  audio: JSON.parse(payload.subarray(140, 140 + audioLength).toString())};
}
let sequence = Number(sequenceText), current;
route: for (const run of runs) for (let index = 0; index < run.repeat; index += 1) {
  const command = {seq: ++sequence, turn: 0, forward: 0, strafe: 0, run: 0,
    fire: 0, use: 0, weapon: 0, pause: 0, automap: 0, menu: 'NONE', cheat: '',
    ...run.command};
  current = frame(await post({p_session: session,
    p_commands: JSON.stringify({v: 2, commands: [command]})}));
  if (current.mode !== 'GAME') break route;
}
process.stdout.write(`${JSON.stringify({session, sequence, ...current})}\n`);
