#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';

const [headersPath,bodyPath,expectedCache,expectedSha]=process.argv.slice(2);
assert.ok(headersPath&&bodyPath&&expectedCache&&expectedSha,
  'headers, body, cache policy, and content digest are required');
assert.match(expectedSha,/^[0-9a-f]{64}$/);
const raw=fs.readFileSync(headersPath,'utf8').replaceAll('\r','');
const blocks=raw.trim().split(/\n\n+/);
assert.equal(blocks.length,1,'redirect or intermediate HTTP response');
const lines=blocks[0].split('\n');
assert.match(lines[0],/^HTTP\/\S+ 304(?: |$)/);
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
const conditionalCache=headers.get('cache-control');
if(conditionalCache!==undefined)
  assert.equal(conditionalCache.toLowerCase(),expectedCache.toLowerCase(),
    'managed ORDS may omit representation cache metadata on 304');
assert.equal(headers.get('etag'),`"${expectedSha}"`,
  'strong ETag must be the stored SHA-256');
assert.equal(counts.get('etag'),1,'exactly one application-owned ETag');
assert.equal(fs.statSync(bodyPath).size,0,'304 response body must be empty');
assert.equal(headers.has('access-control-allow-origin'),false,
  'same-origin statics do not need CORS');
process.stdout.write(`${JSON.stringify({schema:1,status:304,
  representationCachePolicy:expectedCache,
  cacheControl:conditionalCache??null,etag:headers.get('etag'),
  emptyBody:true,
  observationSha256:crypto.createHash('sha256').update(raw).digest('hex')})}\n`);
