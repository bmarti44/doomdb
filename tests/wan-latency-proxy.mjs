#!/usr/bin/env node
import assert from 'node:assert/strict';
import http from 'node:http';

const value = name => process.argv.find(argument => argument.startsWith(`--${name}=`))
  ?.slice(name.length + 3);
const listenPort = Number(value('port'));
const rttMs = Number(value('rtt-ms'));
const jitterMs = Number(value('jitter-ms'));
const seedValue = Number(value('seed'));
const upstream = new URL(value('upstream') ?? 'http://127.0.0.1:8080');
assert.ok(Number.isInteger(listenPort) && listenPort > 1024 && listenPort < 65536);
assert.ok(Number.isFinite(rttMs) && rttMs >= 0 && rttMs <= 2000);
assert.ok(Number.isFinite(jitterMs) && jitterMs >= 0 && jitterMs <= rttMs);
assert.ok(Number.isInteger(seedValue) && seedValue > 0);
assert.equal(upstream.protocol, 'http:');

let randomState = seedValue | 0;
const random = () => {
  randomState = (Math.imul(randomState, 1664525) + 1013904223) | 0;
  return (randomState >>> 0) / 0x1_0000_0000;
};
const wait = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
const requestDelay = () => {
  const total = Math.max(0, rttMs + (random() * 2 - 1) * jitterMs);
  return {request: total / 2, response: total / 2, total};
};

const server = http.createServer(async (incoming, outgoing) => {
  const chunks = [];
  for await (const chunk of incoming) chunks.push(chunk);
  const body = Buffer.concat(chunks);
  const delay = requestDelay();
  await wait(delay.request);
  const headers = {...incoming.headers, host: upstream.host};
  delete headers['content-length'];
  const target = new URL(incoming.url ?? '/', upstream);
  const proxied = http.request(target, {
    method: incoming.method,
    headers: {...headers, 'content-length': String(body.length)}
  }, response => {
    const responseChunks = [];
    response.on('data', chunk => responseChunks.push(chunk));
    response.on('end', async () => {
      await wait(delay.response);
      const responseHeaders = {...response.headers};
      const location = responseHeaders.location;
      if (typeof location === 'string') {
        responseHeaders.location = location.replace(
          upstream.origin, `http://127.0.0.1:${listenPort}`);
      }
      responseHeaders['x-doomdb-injected-rtt-ms'] = delay.total.toFixed(3);
      outgoing.writeHead(response.statusCode ?? 502, responseHeaders);
      outgoing.end(Buffer.concat(responseChunks));
    });
  });
  proxied.on('error', error => {
    if (!outgoing.headersSent) outgoing.writeHead(502, {'content-type': 'text/plain'});
    outgoing.end(`WAN proxy upstream error: ${error.message}\n`);
  });
  proxied.end(body);
});

server.listen(listenPort, '127.0.0.1', () => {
  process.stdout.write(`PMLE_WAN_PROXY|READY|port=${listenPort}|upstream=${upstream.origin}` +
    `|rtt_ms=${rttMs}|jitter_ms=${jitterMs}|seed=${seedValue}\n`);
});

const shutdown = () => server.close(() => process.exit(0));
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);
