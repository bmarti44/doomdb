#!/usr/bin/env node
import assert from 'node:assert/strict';import crypto from 'node:crypto';import fs from 'node:fs';
const [ledgerPath,outPath,javaPath]=process.argv.slice(2);assert.ok(outPath&&javaPath);
const rows=fs.readFileSync(ledgerPath,'utf8').trim().split('\n').map(line=>{const [domain,path,sha256]=line.split('|');assert.match(domain,/^(schema|seed|engine|rest)$/);assert.match(path,/^(?:sql|deploy\/cloud\/t11\.1)\/[A-Za-z0-9._/-]+\.sql$/);assert.match(sha256,/^[0-9a-f]{64}$/);return {domain,path,sha256}});
assert.ok(rows.length>0);assert.equal(new Set(rows.map(x=>x.path)).size,rows.length);
const domains=['schema','seed','engine','rest'].map((domain,i)=>{const selected=rows.filter(x=>x.domain===domain);assert.ok(selected.length>0,domain);return {domain,order:i+1,sha256:crypto.createHash('sha256').update(selected.map(x=>`${x.path}\0${x.sha256}\n`).join('')).digest('hex'),files:selected.length}});
const javaArtifact=JSON.parse(fs.readFileSync(javaPath));assert.equal(javaArtifact.schema,1);assert.equal(javaArtifact.javaRelease,8);assert.equal(javaArtifact.classCount,830);assert.match(javaArtifact.revision,/^[0-9a-f]{40}$/);assert.match(javaArtifact.jarSha256,/^[0-9a-f]{64}$/);
fs.writeFileSync(outPath,`${JSON.stringify({schema:1,task:'T11.1',domains,files:rows,javaArtifact})}\n`,{mode:0o600,flag:'wx'});
