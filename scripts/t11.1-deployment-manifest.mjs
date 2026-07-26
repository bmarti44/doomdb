#!/usr/bin/env node
import assert from 'node:assert/strict';import crypto from 'node:crypto';import fs from 'node:fs';
const [ledgerPath,outPath,mlePath]=process.argv.slice(2);assert.ok(outPath&&mlePath);
const rows=fs.readFileSync(ledgerPath,'utf8').trim().split('\n').map(line=>{const [domain,path,sha256]=line.split('|');assert.match(domain,/^(schema|seed|engine|rest)$/);assert.match(path,/^(?:(?:sql|deploy\/cloud\/t11\.1)\/[A-Za-z0-9._/-]+\.sql|probes\/mle\/teavm-engine\/load-tic0-checkpoint-bank\.sh)$/);assert.match(sha256,/^[0-9a-f]{64}$/);return {domain,path,sha256}});
assert.ok(rows.length>0);assert.equal(new Set(rows.map(x=>x.path)).size,rows.length);
const domains=['schema','seed','engine','rest'].map((domain,i)=>{const selected=rows.filter(x=>x.domain===domain);assert.ok(selected.length>0,domain);return {domain,order:i+1,sha256:crypto.createHash('sha256').update(selected.map(x=>`${x.path}\0${x.sha256}\n`).join('')).digest('hex'),files:selected.length}});
const mleArtifact=JSON.parse(fs.readFileSync(mlePath));assert.equal(mleArtifact.schema,1);
assert.equal(mleArtifact.runtime,'MLE_JAVASCRIPT');
assert.equal(mleArtifact.teaVMVersion,'0.15.0');
assert.equal(mleArtifact.targetType,'JAVASCRIPT');
assert.equal(mleArtifact.moduleType,'ES2015');
assert.match(mleArtifact.inputBytecodeSha256,/^[0-9a-f]{64}$/);
assert.match(mleArtifact.mochaBytecodeSha256,/^[0-9a-f]{64}$/);
assert.equal(mleArtifact.authority.bytes,1081335);
assert.equal(mleArtifact.authority.sha256,
  '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3');
assert.equal(mleArtifact.tablePack.bytes,180272);
assert.equal(mleArtifact.tablePack.sha256,
  '058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44');
assert.match(mleArtifact.iwadSha256,/^[0-9a-f]{64}$/);
assert.equal('canonicalOracleJarSha256' in mleArtifact,false);
fs.writeFileSync(outPath,
  `${JSON.stringify({schema:1,task:'T11.1',domains,files:rows,mleArtifact})}\n`,
  {mode:0o600,flag:'wx'});
