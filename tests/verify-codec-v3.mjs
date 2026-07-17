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
assert.equal(decoded.frameSha,frameSha);assert.deepEqual(decoded.audio,[[7,0,'DSPISTOL',127,128]]);
for(let x=0;x<320;x++)for(let y=0;y<200;y++)
  assert.equal(decoded.indices[y*320+x],transport[x*200+y]);

envelope[8]=2;
await assert.rejects(decodePayload(gzipSync(envelope).toString('base64')),
  /binary envelope is invalid/);
console.log('PASS codec v3 binary indexed frame');
