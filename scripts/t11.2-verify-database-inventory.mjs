#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import {normalizeDbOutput} from './lib/db-output.mjs';

const [manifestPath,catalogPath]=process.argv.slice(2);
assert.ok(manifestPath&&catalogPath,'build manifest and catalog are required');
const manifest=JSON.parse(fs.readFileSync(manifestPath));
const catalogRaw=fs.readFileSync(catalogPath,'utf8');
const catalog=normalizeDbOutput(catalogRaw).join('\n');
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const rows=[...catalog.matchAll(
  /^T112_ASSET\|([^|]+)\|([^|]+)\|([^|]+)\|([0-9a-f]{64})\|(\d+)\|(\d+)\|([0-9a-f]{64})$/gm)]
  .map(match=>({key:match[1],contentType:match[2],cacheControl:match[3],
    sha256:match[4],bytes:Number(match[5]),lobBytes:Number(match[6]),
    databaseSha256:match[7]}));
assert.equal(rows.length,manifest.objects.length,'database asset count');
assert.deepEqual(rows.map(row=>row.key),
  manifest.objects.map(object=>object.key).sort(),'database asset keys');
for(const object of manifest.objects){
  const row=rows.find(candidate=>candidate.key===object.key);
  assert.ok(row,`missing database asset ${object.key}`);
  assert.equal(row.contentType,object.contentType);
  assert.equal(row.cacheControl,object.cacheControl);
  assert.equal(row.sha256,object.sha256);
  assert.equal(row.bytes,object.bytes);
  assert.equal(row.lobBytes,object.bytes);
  assert.equal(row.databaseSha256,object.sha256);
}
const ords=catalog.match(/^T112_ORDS\|(\d+)\|(\d+)\|(\d+)\|(\d+)$/m);
assert.ok(ords,'ORDS inventory marker');
assert.deepEqual(ords.slice(1).map(Number),[1,2,2,2],
  'dedicated module and AutoREST inventory');
const enabled=[...catalog.matchAll(
  /^T112_ENABLED\|([^|]+)\|([^|]+)\|([^\n]+)$/gm)]
  .map(match=>({object:match[1],type:match[2],status:match[3]}));
assert.deepEqual(enabled.map(row=>row.object).sort(),
  ['DOOM_API','PUBLIC_HEALTH']);
assert.ok(enabled.every(row=>row.status==='ENABLED'));
process.stdout.write(`${JSON.stringify({schema:1,objects:rows.map(row=>({
  key:row.key,sha256:row.sha256,bytes:row.bytes,
  contentType:row.contentType,cacheControl:row.cacheControl,
  databaseSha256:row.databaseSha256})),ords:{
  modules:Number(ords[1]),templates:Number(ords[2]),
  handlers:Number(ords[3]),enabledObjects:Number(ords[4]),
  enabled:enabled.map(row=>({object:row.object,type:row.type,status:row.status}))
},catalogSha256:sha(catalogRaw)})}\n`);
