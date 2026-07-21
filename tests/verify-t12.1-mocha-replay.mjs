import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';

const replayUrl=new URL('../artifacts/performance/t12.1/mocha-replay-300.json',import.meta.url);
const routeUrl=new URL('../artifacts/t8.1-live/mocha-e1m1-skill3-route.json',import.meta.url);
const replayBytes=fs.readFileSync(replayUrl);
const replay=JSON.parse(replayBytes);
const routeBytes=fs.readFileSync(routeUrl);
const route=JSON.parse(routeBytes);
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');

assert.equal(sha(replayBytes),'1ad47bc8e2a5b7518d68b937a333492d66d7d539f827980086d4b4fdad327fe3');
assert.equal(replay.schema,2);
assert.equal(replay.task,'T12.1');
assert.equal(replay.engine,'MOCHA_OJVM_RETAINED');
assert.deepEqual(replay.resolution,[320,200]);
assert.equal(replay.source.path,'artifacts/t8.1-live/mocha-e1m1-skill3-route.json');
assert.equal(replay.source.sha256,sha(routeBytes));
assert.equal(replay.frames.length,300);
assert.deepEqual(replay.frames[0],{
  frame:0,pose:'spawn',command:'IDLE',request:{p_skill:3}
});

const expanded=[];
for (const run of route.runs) {
  for (let count=0;count<run.repeat&&expanded.length<299;count+=1)
    expanded.push(run.command);
  if (expanded.length===299) break;
}
assert.deepEqual(replay.frames.slice(1).map(frame=>frame.request),expanded);
assert.deepEqual([...new Set(replay.frames.map(frame=>frame.pose))].sort(),
  ['combat','corridor','door','spawn']);
assert.deepEqual([...new Set(replay.frames.map(frame=>frame.command))].sort(),
  ['FIRE','IDLE','MOVE','TURN','USE']);
for (const [index,frame] of replay.frames.entries()) assert.equal(frame.frame,index);

process.stdout.write('PASS T12.1-MOCHA-REPLAY content-addressed 300-frame selected-engine fixture\n');
