import assert from 'node:assert/strict';
import {
  createColumnMajorIndexedBlitter,createColumnMajorIndexedPaletteBlitter
} from '../client/staging/canvas.js';

let painted=null;
let paints=0;
const image={data:new Uint8ClampedArray(320*200*4)};
const canvas={
  getContext(kind) {
    assert.equal(kind,'2d');
    return {
      imageSmoothingEnabled:true,
      createImageData(width,height) {
        assert.deepEqual([width,height],[320,200]);
        return image;
      },
      putImageData(value,x,y) {
        assert.equal(value,image);assert.deepEqual([x,y],[0,0]);
        painted=value;paints+=1;
      }
    };
  }
};
const palette=new Uint8Array(256*3);
palette.set([11,22,33],7*3);
palette.set([44,55,66],19*3);
const indices=new Uint8Array(320*200);
indices[0*200+0]=7;
indices[1*200+2]=19;

const blit=createColumnMajorIndexedBlitter(canvas,palette);
blit(indices);
assert.equal(painted,image);
assert.equal(paints,1);
assert.deepEqual([...image.data.subarray(0,4)],[11,22,33,255]);
const target=(2*320+1)*4;
assert.deepEqual([...image.data.subarray(target,target+4)],[44,55,66,255]);

indices[1*200+2]=7;
blit(indices);
assert.equal(paints,2);
assert.deepEqual([...image.data.subarray(target,target+4)],[11,22,33,255]);

const palettes=new Uint8Array(14*256*3);
palettes.set(palette,0);
palettes.set([77,88,99],14*256*3-256*3+7*3);
const paletteBlit=createColumnMajorIndexedPaletteBlitter(canvas,palettes);
paletteBlit(indices,13);
assert.equal(paints,3);
assert.deepEqual([...image.data.subarray(0,4)],[77,88,99,255]);
assert.throws(()=>paletteBlit(indices,14),/palette index is invalid/);
process.stdout.write(
  'PASS column-major database framebuffer canvas blitter with PLAYPAL variants\n');
