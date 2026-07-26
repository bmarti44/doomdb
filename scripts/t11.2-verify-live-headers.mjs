#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';

const [headersPath,expectedType,expectedCache,expectedSha]=process.argv.slice(2);
assert.ok(headersPath&&expectedType&&expectedCache&&expectedSha,
  'headers, content type, cache policy, and content digest are required');
assert.match(expectedSha,/^[0-9a-f]{64}$/);
const raw=fs.readFileSync(headersPath,'utf8').replaceAll('\r','');
const blocks=raw.trim().split(/\n\n+/);
assert.equal(blocks.length,1,'redirect or intermediate HTTP response');
const lines=blocks[0].split('\n');
assert.match(lines[0],/^HTTP\/\S+ 200(?: |$)/);
const headers=new Map();
const counts=new Map();
for(const line of lines.slice(1)){
  const separator=line.indexOf(':');
  if(separator>0){
    const name=line.slice(0,separator).toLowerCase();
    headers.set(name,line.slice(separator+1).trim());
    counts.set(name,(counts.get(name)??0)+1);
  }
}
const normalizeContentType=value=>value.toLowerCase().split(';')
  .map(part=>part.trim()).join(';');
assert.equal(normalizeContentType(headers.get('content-type')??''),
  normalizeContentType(expectedType));
assert.equal(headers.get('cache-control')?.toLowerCase(),
  expectedCache.toLowerCase());
assert.equal(headers.get('etag'),`"${expectedSha}"`,
  'strong ETag must be the stored SHA-256');
assert.equal(counts.get('etag'),1,'exactly one application-owned ETag');
assert.equal(headers.has('access-control-allow-origin'),false,
  'same-origin statics do not need CORS');
const retained={
  schema:1,status:200,contentType:expectedType,
  cacheControl:headers.get('cache-control'),
  etag:headers.get('etag'),
  observationSha256:crypto.createHash('sha256').update(raw).digest('hex')
};
process.stdout.write(`${JSON.stringify(retained)}\n`);
