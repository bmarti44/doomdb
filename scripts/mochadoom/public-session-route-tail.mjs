#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const [session, sequenceText, routePath, stopText = ''] = process.argv.slice(2);
if (!/^[0-9a-f]{32}$/.test(session ?? '') || !/^\d+$/.test(sequenceText ?? '') || !routePath) {
  throw Error('usage: public-session-route-tail.mjs session last-sequence route.json [stop-sequence]');
}
const route = JSON.parse(fs.readFileSync(routePath, 'utf8'));
const commands = route.runs.flatMap(run => Array.from({length: run.repeat}, () => run.command));
assert.equal(commands.length, route.commandCount);
let sequence = Number(sequenceText);
const startSequence = route.startSequence ?? 0;
assert.ok(Number.isInteger(startSequence) && startSequence >= 0);
const routeEnd = startSequence + commands.length;
const stop = stopText ? Number(stopText) : routeEnd;
assert.ok(Number.isInteger(stop) && stop >= sequence && stop <= routeEnd);
assert.ok(sequence >= startSequence,
  `last sequence ${sequence} precedes route start ${startSequence}`);
const base = process.env.DOOM_API_BASE ?? 'http://localhost:8080/ords/doom/doom_api/';
const value = (document, key) => document[key] ?? document[key.toUpperCase()]
  ?? document.items?.[0]?.[key] ?? document.items?.[0]?.[key.toUpperCase()];
async function post(body) {
  let lastError;
  for (let attempt = 1; attempt <= 5; attempt++) {
    try {
      for (const path of ['STEP', 'step/']) {
        const response = await fetch(new URL(path, base), {method: 'POST',
          headers: {'content-type': 'application/json'}, body: JSON.stringify(body),
          redirect: 'error', signal: AbortSignal.timeout(30000)});
        if (response.status === 404) continue;
        // A 555 is ambiguous: ORDS may have failed before or after the worker
        // commit. Never advance the local sequence without a correlated DMF3
        // response; the caller can inspect the durable frontier before retrying.
        if (response.status === 555) {
          const body = await response.text();
          const reason = response.headers.get('error-reason')
            ?? body.replace(/data:[^;"']+;base64,[A-Za-z0-9+/=]+/g, '[embedded data]')
              .replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, ' ')
              .replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim().slice(0, 2000);
          throw Error(`555 ${reason}`);
        }
        if (!response.ok) throw Error(`${response.status} ${await response.text()}`);
        return response.json();
      }
    } catch (error) {
      lastError = error;
      await new Promise(resolve => setTimeout(resolve, attempt * 250));
    }
  }
  throw lastError;
}
let current;
while (sequence < stop) {
  // The retained Mocha worker intentionally accepts one exact ticcmd per
  // request. Keep this helper aligned with that public contract.
  const command = commands[sequence - startSequence];
  const batch = [{seq: sequence + 1, ...command, cheat: command.cheat ?? ''}];
  const document = await post({p_session: session,
    p_commands: JSON.stringify({v: route.envelopeVersion ?? 2, commands: batch})});
  const payload = Buffer.from(value(document, 'p_payload'), 'base64');
  assert.equal(payload.subarray(0, 4).toString(), 'DMF3');
  sequence += batch.length;
  current = {tic: payload.readInt32BE(4), mode: payload[8] === 1 ? 'DEAD'
    : payload[9] === 1 ? 'INTERMISSION' : 'GAME',
  stateSha: payload.subarray(10, 74).toString(),
  frameSha: payload.subarray(74, 138).toString()};
  if (sequence % 500 < 4) process.stderr.write(`sequence ${sequence} ${current.mode}\n`);
  if (current.mode !== 'GAME') break;
}
process.stdout.write(`${JSON.stringify({session, sequence, ...current})}\n`);
