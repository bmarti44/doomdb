#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {normalizeDbOutput} from './lib/db-output.mjs';

const prefix='PMLE_OCI_TWO_POV_ARTIFACT|';
const fieldsFrom=(text)=>{
  const markers=normalizeDbOutput(text).filter(line=>line.startsWith(prefix));
  assert.equal(markers.length,1,'exactly one deployed-artifact marker is required');
  const fields=Object.fromEntries(markers[0].split('|').slice(1).map(field=>{
    const split=field.indexOf('=');
    assert.ok(split>0,`malformed artifact field: ${field}`);
    return [field.slice(0,split),field.slice(split+1)];
  }));
  assert.deepEqual(Object.keys(fields).sort(),[
    'authority_sha256','coordinator_sha256','renderer_sha256']);
  for(const name of Object.keys(fields))
    assert.match(fields[name],/^[0-9a-f]{64}$/,name);
  return fields;
};

const verify=(text,authority,renderer,coordinator)=>{
  for(const value of [authority,renderer,coordinator])
    assert.match(value??'',/^[0-9a-f]{64}$/);
  const fields=fieldsFrom(text);
  assert.equal(fields.authority_sha256,authority);
  assert.equal(fields.renderer_sha256,renderer);
  assert.equal(fields.coordinator_sha256,coordinator);
  return `${prefix}authority_sha256=${authority}`
    +`|renderer_sha256=${renderer}|coordinator_sha256=${coordinator}`;
};

if(process.argv[2]==='--self-test') {
  const a='a'.repeat(64),r='b'.repeat(64),c='c'.repeat(64);
  const marker=`${prefix}authority_sha256=${a}`
    +`|renderer_sha256=${r}|coordinator_sha256=${c}`;
  assert.equal(verify(`${marker}\n`,a,r,c),marker);
  // SQLcl can wrap a marker at arbitrary columns. The shared parser must join
  // that output before field validation.
  assert.equal(verify(`${marker.slice(0,73)}\n${marker.slice(73)}\n`,a,r,c),
    marker);
  assert.throws(()=>verify(`${marker}\n${marker}\n`,a,r,c));
  assert.throws(()=>verify(marker.replace(a,'d'.repeat(64)),a,r,c));
  assert.throws(()=>verify(`${marker}|extra=1`,a,r,c));
  process.stdout.write(
    'PMLE_LIVE_FRAME_ARTIFACT_MARKER_SELFTEST|PASS|mutations=4\n');
} else {
  const [path,authority,renderer,coordinator]=process.argv.slice(2);
  assert.ok(coordinator,
    'usage: verify-live-frame-artifact-marker.mjs LOG AUTHORITY RENDERER COORDINATOR');
  process.stdout.write(
    `${verify(fs.readFileSync(path,'utf8'),authority,renderer,coordinator)}\n`);
}
