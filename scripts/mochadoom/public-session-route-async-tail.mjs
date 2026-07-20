#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const [session, sequenceText, routePath] = process.argv.slice(2);
if (!/^[0-9a-f]{32}$/.test(session ?? '') || !/^\d+$/.test(sequenceText ?? '') ||
    !routePath) throw new Error('usage: public-session-route-async-tail.mjs session last-sequence route.json');
const route = JSON.parse(fs.readFileSync(routePath, 'utf8'));
const commands = route.runs.flatMap(run => Array.from({length: run.repeat}, () => run.command));
assert.equal(commands.length, route.commandCount);
let sequence = Number(sequenceText);
const start = route.startSequence ?? 0;
assert.ok(sequence >= start && sequence <= start + commands.length);
const root = (process.env.DOOM_ORDS_URL ?? 'http://localhost:8080/ords/doom').replace(/\/$/, '');
const sleep = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

async function post(procedure, body) {
  let failure;
  for (let attempt = 0; attempt < 8; attempt += 1) {
    try {
      const response = await fetch(`${root}/doom_api/${procedure}`, {method: 'POST',
        headers: {'content-type': 'application/json'}, body: JSON.stringify(body),
        signal: AbortSignal.timeout(30000)});
      if (!response.ok) throw new Error(`${procedure} ${response.status} ${(await response.text()).slice(0, 400)}`);
      return response.json();
    } catch (error) {
      failure = error;
      if (attempt < 7) await sleep(Math.min(25 * (2 ** attempt), 500));
    }
  }
  throw failure;
}

const submit = (seq, command) => post('SUBMIT_STEP', {p_session: session,
  p_commands: JSON.stringify({v: route.envelopeVersion ?? 2,
    commands: [{...command, cheat: command.cheat ?? '', seq}]})});
const poll = seq => post('POLL_FRAME', {p_session: session, p_seq: seq, p_wait_ms: 1000});
const value = (document, key) => document[key] ?? document[key.toUpperCase()]
  ?? document.items?.[0]?.[key] ?? document.items?.[0]?.[key.toUpperCase()];

let current;
let latestPayload;
while (sequence < start + commands.length) {
  const windowEnd = Math.min(start + commands.length, sequence + 24);
  for (let first = sequence + 1; first <= windowEnd; first += 4) {
    const last = Math.min(windowEnd, first + 3);
    await Promise.all(Array.from({length: last - first + 1}, (_, offset) => {
      const next = first + offset;
      return submit(next, commands[next - start - 1]);
    }));
  }
  sequence = windowEnd;
  let document;
  do document = await poll(sequence); while (Number(value(document, 'p_ready')) !== 1);
  const payload = Buffer.from(value(document, 'p_payload'), 'base64');
  latestPayload = payload;
  assert.equal(payload.subarray(0, 4).toString(), 'DMF3');
  current = {tic: payload.readInt32BE(4), mode: payload[8] === 1 ? 'DEAD'
    : payload[9] === 1 ? 'INTERMISSION' : 'GAME',
  stateSha: payload.subarray(10, 74).toString(),
  frameSha: payload.subarray(74, 138).toString()};
  if (sequence % 500 < 24) process.stderr.write(`sequence ${sequence} ${current.mode}\n`);
  if (current.mode !== 'GAME') break;
}
if (latestPayload === undefined) {
  let document;
  do document = await poll(sequence); while (Number(value(document, 'p_ready')) !== 1);
  latestPayload = Buffer.from(value(document, 'p_payload'), 'base64');
  assert.equal(latestPayload.subarray(0, 4).toString(), 'DMF3');
  current = {tic: latestPayload.readInt32BE(4),
    mode: latestPayload[8] === 1 ? 'DEAD' : latestPayload[9] === 1 ? 'INTERMISSION' : 'GAME',
    stateSha: latestPayload.subarray(10, 74).toString(),
    frameSha: latestPayload.subarray(74, 138).toString()};
}
if (process.env.DOOM_ROUTE_CAPTURE) fs.writeFileSync(process.env.DOOM_ROUTE_CAPTURE, latestPayload);
process.stdout.write(`${JSON.stringify({session, sequence, ...current})}\n`);
