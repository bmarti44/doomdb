#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';

const output=process.argv[2];
const stream=process.argv[3];
const mode=process.argv[4]??'DEATHMATCH';
if(output===undefined||!/^[a-z0-9][a-z0-9-]{0,63}$/.test(stream??'')) {
  throw new Error('usage: capture-command-stream.mjs OUTPUT STREAM_NAME [COOP|DEATHMATCH]');
}
assert.match(mode,/^(COOP|DEATHMATCH)$/);
const rows=fs.readFileSync(0,'utf8').split(/\r?\n/)
  .map(value=>value.trim()).filter(value=>/^[0-9]+\|/.test(value))
  .map(value=>{
    const [ticText,membershipText,command]=value.split('|');
    assert.match(ticText??'',/^[1-9][0-9]*$/);
    assert.match(membershipText??'',/^[0-9]+$/);
    assert.match(command??'',/^[0-9a-f]{64}$/);
    return {tic:Number(ticText),membership:Number(membershipText),command};
  });
assert.ok(rows.length>=100,'command evidence requires at least 100 tics');
const runs=[];
const hash=crypto.createHash('sha256');
for(const [index,row] of rows.entries()) {
  assert.equal(row.tic,index+1,'command evidence has a tic gap');
  const bytes=Buffer.from(row.command,'hex');
  hash.update(Buffer.from([row.membership]));hash.update(bytes);
  const prior=runs.at(-1);
  if(prior!==undefined&&prior.membership===row.membership&&
      prior.command===row.command) {
    prior.repeat+=1;
  } else {
    runs.push({membership:row.membership,command:row.command,repeat:1});
  }
}
const document={
  schema:1,stream,mode,players:2,skill:3,episode:1,map:1,
  tics:rows.length,expandedSha256:hash.digest('hex'),runs
};
fs.writeFileSync(output,`${JSON.stringify(document)}\n`);
process.stdout.write(`PMLE_COMMAND_CAPTURE|PASS|stream=${stream}`+
  `|tics=${rows.length}|runs=${runs.length}`+
  `|sha256=${document.expandedSha256}|output=${output}\n`);
