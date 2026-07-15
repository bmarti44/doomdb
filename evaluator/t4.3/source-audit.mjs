import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'../..'),decoder=fs.readFileSync(path.join(import.meta.dirname,'reference.mjs'),'utf8').toUpperCase();
for(const bad of ['../T4.2','SQL/RENDER','DOOM_R1_PIXELS','CHILD_PROCESS','EXEC(','SPAWN(','FETCH(','HTTP:','HTTPS:','NET.','EVALUATOR/GOLDENS'])assert.ok(!decoder.includes(bad),`independent decoder dependency/escape: ${bad}`);
for(const bad of ['-416','SPAWN-EAST','SPAWN-NORTH','SPAWN-SOUTH','GOLDENHASH','EXPECTEDHASH'])assert.ok(!decoder.includes(bad),`canned diagnostic answer in decoder: ${bad}`);
const roots=['sql','scripts','client'],files=[];for(const d of roots){const at=path.join(root,d);if(!fs.existsSync(at))continue;const walk=p=>{for(const e of fs.readdirSync(p,{withFileTypes:true})){const q=path.join(p,e.name);e.isDirectory()?walk(q):files.push(q);}};walk(at);}
const production=files.filter(f=>/\.(sql|mjs|js|ts|sh|html|css)$/i.test(f)).map(f=>fs.readFileSync(f,'utf8')).join('\n').toUpperCase();
for(const bad of ['EVALUATOR/T4.3','EVALUATOR/GOLDENS','T4.3-EVAL','PASS T4.3','REPORTS/T4.3','GOLDENHASH','EXPECTED_VISIBLE_HASH'])assert.ok(!production.includes(bad),`production/evaluator coupling: ${bad}`);
assert.ok(!production.includes('41414141414141414141414141414141'),'evaluator session token embedded in production');
process.stdout.write(`PASS T4.3-SOURCE-AUDIT (${files.length} production files, independent decoder)\n`);
