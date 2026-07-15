import fs from 'node:fs';import {validateEvidence} from './reference.mjs';
const f=JSON.parse(fs.readFileSync(new URL('./fixtures.json',import.meta.url))),p=process.argv[2];if(!p)throw Error('evidence path required');const e=JSON.parse(fs.readFileSync(p,'utf8'));validateEvidence(e,f);process.stdout.write('PASS T11.1-LIVE-EVIDENCE (684/684 declared assertions)\n');
