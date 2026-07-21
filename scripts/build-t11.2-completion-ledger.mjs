#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';

const root=new URL('../',import.meta.url);
const source=new URL('artifacts/t8.1-live/mocha-e1m1-skill3-route.json',root);
const output=process.argv[2] ?? '/tmp/doomdb-t112-completion-ledger.json';
const sourceBytes=fs.readFileSync(source);
const sourceSha256=crypto.createHash('sha256').update(sourceBytes).digest('hex');
assert.equal(sourceSha256,'cc4ad42d7f6663cf3197d67c5a8ba8a73da69e239d1536cbe71fb8633e4364c9','accepted completion route drift');
const route=JSON.parse(sourceBytes);
assert.equal(route.envelopeVersion,2);
assert.equal(route.startSequence,0);
assert.equal(route.commandCount,13272);
assert.deepEqual(route.constraints,{generatedAutoRestOnly:true,noCheats:true,noSaveLoadDuringReplay:true});
assert.deepEqual(route.accepted,{
  terminalTic:13272,
  mode:'INTERMISSION',
  stateSha:'2dee7fcc7d54586bd91714341186299ac19c5c70cd9c1b53f55dbf4ae9172369',
  frameSha:'7ad3d6e57913d2f2cca837b54a37d74bceeb5b56a52885735b2c5e8718b3f2fe'
});
const keys=['automap','cheat','fire','forward','menu','pause','run','strafe','turn','use','weapon'];
const commands=[];
for(const run of route.runs){
  assert.ok(Number.isInteger(run.repeat)&&run.repeat>0);
  assert.deepEqual(Object.keys(run.command).sort(),keys);
  assert.equal(run.command.cheat,'');
  for(let i=0;i<run.repeat;i++)commands.push({seq:commands.length+1,...run.command});
}
assert.equal(commands.length,route.commandCount);
const scriptSha256=crypto.createHash('sha256').update(JSON.stringify(commands)).digest('hex');
const ledger={schema:1,approved:true,sourceSha256,scriptSha256,terminal:route.accepted,commands};
fs.writeFileSync(output,`${JSON.stringify(ledger)}\n`,{mode:0o600});
process.stdout.write(`PASS T11.2-COMPLETION-LEDGER (${commands.length} approved no-cheat commands; ${output})\n`);
