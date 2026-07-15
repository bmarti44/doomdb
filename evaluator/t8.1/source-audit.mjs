import assert from 'node:assert/strict';import fs from 'node:fs';import path from 'node:path';
const root=path.resolve(import.meta.dirname,'../..');
const candidates=['sql/sim/tic/010_tic_transaction.sql','sql/sim/050_combat_inventory.sql','sql/sim/060_monsters.sql','sql/sim/070_audio.sql','sql/rest/010_doom_api.sql'];
export function audit(text){const s=text.toUpperCase();for(const bad of ['EVALUATOR/T8.1','ROUTE-CANDIDATE.JSON','FIXTURES.JSON','GOLDENSTATEFRAMEHASHES','SCREENSHOTHASHES','T81-','APPROVEDSCRIPTSHA','REPORTS/','PLAYWRIGHT','CALL_STACK','FORMAT_CALL_STACK'])assert.ok(!s.includes(bad),`production coupling: ${bad}`);assert.ok(!/DBMS_RANDOM|SYSDATE|SYSTIMESTAMP|CURRENT_TIMESTAMP/.test(s),'host nondeterminism in replay path');assert.ok(!/EXECUTE\s+IMMEDIATE|DBMS_SQL/.test(s),'dynamic SQL in replay path');assert.ok(!/PRAGMA\s+AUTONOMOUS_TRANSACTION/.test(s),'autonomous transaction in replay path');}
for(const bad of ['evaluator/t8.1','route-candidate.json','T81-','dbms_random.value'])assert.throws(()=>audit(`normal source ${bad}`));
let present=0;for(const rel of candidates){const p=path.join(root,rel);if(fs.existsSync(p)){audit(fs.readFileSync(p,'utf8'));present++;}}
assert.ok(present>=1,'no production surfaces available for policy audit');
process.stdout.write(`PASS T8.1-SOURCE-POLICY-SELF-CHECK (${present} present production surfaces; T7 live acceptance remains upstream)\n`);
