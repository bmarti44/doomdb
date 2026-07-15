import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import {canonicalPixels,decodeIndexedPng,decodeRle,rgbaBytes,sha256} from '../evaluator/t4.3/reference.mjs';

const dir=path.resolve(process.argv[2]??'artifacts/t4.3-review');
const ids=['spawn-east','spawn-north','spawn-south'],observed=[];
for(const id of ids){
  const observation=JSON.parse(fs.readFileSync(path.join(dir,`${id}.observation.json`),'utf8'));
  const diagnostics=JSON.parse(fs.readFileSync(path.join(dir,`${id}.diagnostics.json`),'utf8'));
  const png=fs.readFileSync(path.join(dir,`${id}.png`)),rgba=fs.readFileSync(path.join(dir,`${id}.rgba`));
  assert.equal(observation.pose.id,id);assert.equal(observation.pose.eyeZ,41);
  const pixels=canonicalPixels(observation.rows),expanded=decodeRle(observation.cols),parsed=decodeIndexedPng(png);
  assert.deepEqual(expanded,pixels);assert.deepEqual(parsed.pixels,pixels);assert.deepEqual(rgba,rgbaBytes(pixels,observation.palette));
  assert.equal(diagnostics.frameSha256,sha256(pixels));assert.equal(diagnostics.rgbaSha256,sha256(rgba));assert.equal(diagnostics.pngSha256,sha256(png));
  assert.equal(diagnostics.columns.length,6);assert.equal(diagnostics.pixels.length,8);
  observed.push({id,pose:observation.pose,frameSha256:sha256(pixels),rgbaSha256:sha256(rgba),pngSha256:sha256(png),pngBytes:png.length});
}
assert.equal(new Set(observed.map(x=>x.frameSha256)).size,3,'poses must produce distinct frames');
assert.equal(new Set(observed.map(x=>x.pngSha256)).size,3,'poses must produce distinct PNGs');
const summary={schema:1,kind:'doomdb-t4.3-review-observations',generatedFrom:'DOOM_R1_PIXELS and DOOM_PALETTE_TEXEL',observed};
fs.writeFileSync(path.join(dir,'review-summary.json'),`${JSON.stringify(summary,null,2)}\n`);
process.stdout.write('PASS T4.3-CAPTURE (3/3 database poses; SQL RLE, RGBA, indexed PNG and diagnostics agree)\n');
