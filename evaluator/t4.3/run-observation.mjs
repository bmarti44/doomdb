import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {canonicalPixels,decodeIndexedPng,decodeRle,diagnostics,encodeIndexedPng,paletteBytes,rgbaBytes,sha256} from './reference.mjs';
const fixture=JSON.parse(fs.readFileSync(new URL('./fixtures.json',import.meta.url),'utf8'));
const [input,outdir]=process.argv.slice(2);assert.ok(input&&outdir,'usage: node run-observation.mjs observation.json artifact-dir');const o=JSON.parse(fs.readFileSync(input,'utf8'));assert.equal(o.schema,1);assert.ok(['spawn-east','spawn-north','spawn-south'].includes(o.pose.id));
const pixels=canonicalPixels(o.rows),expanded=decodeRle(o.cols);assert.deepEqual(expanded,pixels,'independent RLE does not equal SQL frame');const rgba=rgbaBytes(expanded,o.palette),png=encodeIndexedPng(expanded,o.palette),parsed=decodeIndexedPng(png);assert.deepEqual(parsed.pixels,pixels);assert.deepEqual(parsed.palette,paletteBytes(o.palette));
fs.mkdirSync(outdir,{recursive:true});fs.writeFileSync(path.join(outdir,`${o.pose.id}.png`),png);fs.writeFileSync(path.join(outdir,`${o.pose.id}.rgba`),rgba);fs.writeFileSync(path.join(outdir,`${o.pose.id}.diagnostics.json`),JSON.stringify({schema:1,pose:o.pose,frameSha256:sha256(pixels),rgbaSha256:sha256(rgba),pngSha256:sha256(png),...diagnostics(pixels,o.palette,fixture.diagnosticColumns,fixture.diagnosticPixels)},null,2)+'\n');
process.stdout.write(`PASS T4.3-OBSERVATION ${o.pose.id} frame=${sha256(pixels)} png=${sha256(png)}\n`);
