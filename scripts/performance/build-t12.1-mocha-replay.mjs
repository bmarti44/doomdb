#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const root=path.resolve(import.meta.dirname,'../..');
const sourceRelative='artifacts/t8.1-live/mocha-e1m1-skill3-route.json';
const outputRelative='artifacts/performance/t12.1/mocha-replay-300.json';
const sourcePath=path.join(root,sourceRelative);
const outputPath=path.join(root,outputRelative);
const sourceBytes=fs.readFileSync(sourcePath);
const source=JSON.parse(sourceBytes);
assert.equal(source.envelopeVersion,2);
assert.ok(source.commandCount>=299);

const commands=[];
for (const run of source.runs) {
  assert.ok(Number.isInteger(run.repeat)&&run.repeat>0);
  for (let index=0;index<run.repeat&&commands.length<299;index+=1)
    commands.push(structuredClone(run.command));
  if (commands.length===299) break;
}
assert.equal(commands.length,299);

const commandClass=command=>command.fire===1?'FIRE':command.use===1?'USE':
  command.forward!==0||command.strafe!==0?'MOVE':command.turn!==0?'TURN':'IDLE';
const pose=frame=>frame<30?'spawn':frame<120?'corridor':frame<200?'door':'combat';
const frames=[{
  frame:0,pose:'spawn',command:'IDLE',request:{p_skill:3}
},...commands.map((command,index)=>({
  frame:index+1,pose:pose(index+1),command:commandClass(command),request:command
}))];
const replay={
  schema:2,
  task:'T12.1',
  engine:'MOCHA_OJVM_RETAINED',
  resolution:[320,200],
  source:{path:sourceRelative,
    sha256:crypto.createHash('sha256').update(sourceBytes).digest('hex'),
    firstCommands:299},
  frames
};
const body=`${JSON.stringify(replay,null,2)}\n`;
fs.mkdirSync(path.dirname(outputPath),{recursive:true,mode:0o700});
fs.writeFileSync(outputPath,body,{encoding:'utf8',mode:0o600});
process.stdout.write(`T12_1_REPLAY_SHA256=${crypto.createHash('sha256').update(body).digest('hex')}\n`);
