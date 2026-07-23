import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {pathToFileURL} from 'node:url';

const [modulePath,iwadPath,tablePath]=process.argv.slice(2);
assert.ok(modulePath&&iwadPath&&tablePath,
  'usage: verify-pmle-checkpoint-reuse.mjs MODULE IWAD TABLE_PACK');
const engine=await import(pathToFileURL(path.resolve(modulePath)).href);
const iwad=fs.readFileSync(iwadPath);
const tables=fs.readFileSync(tablePath);
const load=(bytes,allocate,append)=>{
  assert.equal(allocate(bytes.length),bytes.length);
  for(let offset=0;offset<bytes.length;offset+=1024*1024) {
    const chunk=bytes.subarray(offset,Math.min(bytes.length,offset+1024*1024));
    assert.equal(append(offset,chunk),offset+chunk.length);
  }
};
const checkpoint=()=>{
  const length=engine.checkpointLength();
  const bytes=Buffer.alloc(length);
  for(let offset=0;offset<length;offset+=32767) {
    const chunk=engine.checkpointChunk(offset,Math.min(32767,length-offset));
    bytes.set(chunk,offset);
  }
  return `${length}:${crypto.createHash('sha256').update(bytes).digest('hex')}`;
};

load(iwad,engine.allocateIwad,engine.loadIwadChunk);
load(tables,engine.allocateTablePack,engine.loadTablePackChunk);
assert.match(engine.initializeMultiplayerGame(2,0,3,1,1),
  /^state=multiplayer-initialized\|gametic=0\|/);
const commands=new Uint8Array(32);
const checkpoints=[];
for(let tic=1;tic<=2048;tic+=1) {
  commands[0]=tic%5===0?25:0;
  commands[8]=tic%7===0?232:0;
  assert.equal(engine.stepMultiplayerAuthoritative(2,3,commands),tic);
  if(tic===32||tic===1024||tic===2048) {
    const first=checkpoint();
    const repeated=checkpoint();
    assert.equal(repeated,first,`checkpoint reuse changed bytes at tic ${tic}`);
    checkpoints.push(`${tic}:${first}`);
  }
}
engine.release();
console.log(`PMLE_CHECKPOINT_REUSE|PASS|${checkpoints.join('|')}`);
