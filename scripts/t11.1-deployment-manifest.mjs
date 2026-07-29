#!/usr/bin/env node
import assert from 'node:assert/strict';import crypto from 'node:crypto';import fs from 'node:fs';
const [ledgerPath,outPath,mlePath]=process.argv.slice(2);assert.ok(outPath&&mlePath);
const rows=fs.readFileSync(ledgerPath,'utf8').trim().split('\n').map(line=>{const [domain,path,sha256]=line.split('|');assert.match(domain,/^(schema|seed|engine|rest)$/);assert.match(path,/^(?:(?:sql|deploy\/cloud\/t11\.1)\/[A-Za-z0-9._/-]+\.sql|probes\/mle\/(?:teavm-engine\/load-tic0-checkpoint-bank|load-live-frame-module)\.sh)$/);assert.match(sha256,/^[0-9a-f]{64}$/);return {domain,path,sha256}});
assert.ok(rows.length>0);assert.equal(new Set(rows.map(x=>x.path)).size,rows.length);
const domains=['schema','seed','engine','rest'].map((domain,i)=>{const selected=rows.filter(x=>x.domain===domain);assert.ok(selected.length>0,domain);return {domain,order:i+1,sha256:crypto.createHash('sha256').update(selected.map(x=>`${x.path}\0${x.sha256}\n`).join('')).digest('hex'),files:selected.length}});
const mleArtifact=JSON.parse(fs.readFileSync(mlePath));assert.equal(mleArtifact.schema,1);
assert.equal(mleArtifact.runtime,'MLE_JAVASCRIPT');
assert.equal(mleArtifact.teaVMVersion,'0.15.0');
assert.equal(mleArtifact.targetType,'JAVASCRIPT');
assert.equal(mleArtifact.moduleType,'ES2015');
assert.match(mleArtifact.inputBytecodeSha256,/^[0-9a-f]{64}$/);
assert.match(mleArtifact.mochaBytecodeSha256,/^[0-9a-f]{64}$/);
assert.equal(mleArtifact.authority.bytes,1090790);
assert.equal(mleArtifact.authority.sha256,
  '66dd235cde82a8b8fbcac88bb905912bacfd6ea40671d2808e5951ce290ce873');
assert.equal(mleArtifact.tablePack.bytes,180272);
assert.equal(mleArtifact.tablePack.sha256,
  '058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44');
assert.equal(mleArtifact.liveFrameRenderer.requiredAuthoritySha256,
  mleArtifact.authority.sha256);
assert.equal(mleArtifact.liveFrameRenderer.bytes,48097);
assert.equal(mleArtifact.liveFrameRenderer.sha256,
  '61163171b77421fc01a96359903fc1bc5fbbc17c639177c77e48f4973b4a0f12');
assert.equal(mleArtifact.liveFrameRenderer.coordinatorBytes,46231);
assert.equal(mleArtifact.liveFrameRenderer.coordinatorSha256,
  '59acb671e6e0a03ee89735806c8f0178a53dc792d22b87fb2c22db5f226fdd85');
assert.match(mleArtifact.iwadSha256,/^[0-9a-f]{64}$/);
assert.equal('canonicalOracleJarSha256' in mleArtifact,false);
fs.writeFileSync(outPath,
  `${JSON.stringify({schema:1,task:'T11.1',domains,files:rows,mleArtifact})}\n`,
  {mode:0o600,flag:'wx'});
