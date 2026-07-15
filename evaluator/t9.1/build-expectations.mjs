import fs from 'node:fs';import {animationHash,encode,frameHash,generate,stats} from './reference.mjs';
const f=JSON.parse(fs.readFileSync(new URL('./fixtures.json',import.meta.url))),frames=generate(f);
const out={schema:1,algorithm:'sha256 over exactly 15360 row-major intensity bytes',frameHashes:frames.map(frameHash),animationHash:animationHash(frames),stats:stats(frames),frameRunCounts:frames.map(x=>encode(x).length)};
process.stdout.write(JSON.stringify(out,null,2)+'\n');
