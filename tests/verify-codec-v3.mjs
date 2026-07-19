import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {gzipSync} from 'node:zlib';
import {decodePayload} from '../client/staging/codec.js';

const transport=Buffer.alloc(320*200);
for(let index=0;index<transport.length;index++)transport[index]=(index*17+3)&255;
const frameSha=createHash('sha256').update(transport).digest('hex');
const audio=Buffer.from('[[7,0,"DSPISTOL",127,128]]');
const envelope=Buffer.alloc(140+audio.length+transport.length);
envelope.write('DMF3',0,'ascii');envelope.writeInt32BE(7,4);
envelope[8]=0;envelope[9]=0;envelope.write('0'.repeat(64),10,'ascii');
envelope.write(frameSha,74,'ascii');envelope.writeUInt16BE(audio.length,138);
audio.copy(envelope,140);transport.copy(envelope,140+audio.length);

const decoded=await decodePayload(gzipSync(envelope,{level:1}).toString('base64'));
assert.equal(decoded.tic,7);assert.equal(decoded.mode,'game');
assert.equal(decoded.complete,0);
assert.equal(decoded.frameSha,frameSha);assert.deepEqual(decoded.audio,[[7,0,'DSPISTOL',127,128]]);
for(let x=0;x<320;x++)for(let y=0;y<200;y++)
  assert.equal(decoded.indices[y*320+x],transport[x*200+y]);

// Each producer has one canonical frame_sha orientation: gzip-wrapped
// envelopes hash the column-major transport bytes (legacy SQL contract) and
// raw binary envelopes hash the row-major framebuffer (Mocha adapter). A raw
// envelope carrying the transport-orientation hash must now be rejected.
await assert.rejects(decodePayload(envelope.toString('base64')),
  /frame hash is invalid/);
const rowMajor=Buffer.alloc(320*200);
for(let x=0;x<320;x++)for(let y=0;y<200;y++)
  rowMajor[y*320+x]=transport[x*200+y];
const rowMajorSha=createHash('sha256').update(rowMajor).digest('hex');
const rawEnvelope=Buffer.from(envelope);
rawEnvelope.write(rowMajorSha,74,'ascii');
const rawDmf3=await decodePayload(rawEnvelope.toString('base64'));
assert.equal(rawDmf3.frameSha,rowMajorSha);
assert.deepEqual(rawDmf3.indices,decoded.indices);

const packBits=bytes=>{const chunks=[];let offset=0;while(offset<bytes.length){
  let run=1;while(run<128&&offset+run<bytes.length&&bytes[offset+run]===bytes[offset])run++;
  if(run>=3){chunks.push(Buffer.from([0x80|(run-1),bytes[offset]]));offset+=run;continue;}
  const start=offset;offset+=run;
  while(offset<bytes.length&&offset-start<128){run=1;
    while(run<128&&offset+run<bytes.length&&bytes[offset+run]===bytes[offset])run++;
    if(run>=3)break;offset+=Math.min(run,128-(offset-start));}
  chunks.push(Buffer.from([offset-start-1]),bytes.subarray(start,offset));
}return Buffer.concat(chunks);};
const encoded=packBits(transport),dmf4=Buffer.concat([
  Buffer.from(rawEnvelope.subarray(0,140+audio.length)),encoded]);
dmf4.write('DMF4',0,'ascii');dmf4[8]=0;
const rawDecoded=await decodePayload(dmf4.toString('base64'));
assert.equal(rawDecoded.frameSha,rowMajorSha);assert.deepEqual(rawDecoded.audio,decoded.audio);
assert.deepEqual(rawDecoded.indices,decoded.indices);

envelope[8]=2;
await assert.rejects(decodePayload(gzipSync(envelope).toString('base64')),
  /binary envelope is invalid/);
console.log(`PASS codec v3/v4 binary indexed frame dmf4Bytes=${dmf4.length}`);
