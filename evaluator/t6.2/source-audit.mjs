import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
const root=path.resolve(import.meta.dirname,'../..'),file=path.join(root,'sql/sim/020_movement_collision.sql');
assert.ok(fs.existsSync(file),'T6.2 production source missing: sql/sim/020_movement_collision.sql');
const source=fs.readFileSync(file,'utf8').toUpperCase();
for(const token of ['DOOM_PLAYER_MOVE','SQL_MACRO','P_SESSION','P_DELTA_X','P_DELTA_Y','GAME_SESSIONS','PLAYERS','NOCLIP','SECTOR_STATE','DOOM_MAP_LINEDEF','DOOM_MAP_SIDEDEF','DOOM_LINEDEF','DOOM_BSP_LOCATE','DOOM_CONFIG','PLAYER_RADIUS','PLAYER_HEIGHT','PLAYER_STEP_HEIGHT','PLAYER_VIEW_HEIGHT','PLAYER_MAX_CONTACTS','DEST_X','DEST_Y','DEST_Z','DESTINATION_SECTOR_ID','VIEW_HEIGHT','EYE_Z','CONTACT_COUNT','FIRST_BLOCKER_ID','FIRST_FRACTION','SECOND_BLOCKER_ID','SECOND_FRACTION','BITAND','ROW_NUMBER','ORDER BY'])assert.ok(source.includes(token),`required collision token absent: ${token}`);
assert.ok(source.includes('DOOM_BLOCK_LINE')||source.includes('SDO_FILTER'),'conservative BLOCKMAP or Spatial candidates absent'); // CONSERVATIVE CANDIDATE GUARD
assert.ok(/ORDER\s+BY[\s\S]{0,300}(FRACTION|CONTACT_T)[\s\S]{0,160}LINEDEF_ID/.test(source),'stable fraction then linedef ordering absent'); // STABLE CONTACT ORDER GUARD
assert.ok(source.includes('POWER')&&source.includes('SQRT'),'analytic segment/endcap contact math absent'); // EXACT SWEPT CIRCLE GUARD
assert.ok(/GREATEST[\s\S]{0,300}FLOOR_HEIGHT/.test(source)&&/LEAST[\s\S]{0,300}CEILING_HEIGHT/.test(source),'current portal intersection absent'); // DYNAMIC OPENING GUARD
assert.ok(/LEFT_SIDEDEF_ID\s+IS\s+NULL|LEFT_SIDED?EF[^\n]*NULL/.test(source),'one-sided blocker absent');
assert.ok(/BITAND\s*\([^,]+,\s*1\s*\)/.test(source),'blocking flag bit absent');
assert.ok(/(DIRECTION_X|END_X\s*-\s*START_X)[\s\S]{0,500}(DOT|DIRECTION_X|POWER)/.test(source),'blocking tangent projection absent'); // SLIDING TANGENT GUARD
assert.ok(/CONTACT_COUNT[\s\S]{0,500}(2|PLAYER_MAX_CONTACTS)/.test(source),'fixed two-contact result absent');
assert.ok(!/\b(WHILE|FOR\s+[^\n]+\s+LOOP|LOOP\s*;)/.test(source),'procedural collision loop forbidden'); // SET BASED COLLISION GUARD
assert.ok(!/EXECUTE\s+IMMEDIATE|DBMS_SQL/.test(source),'dynamic SQL forbidden');
assert.ok(!/P_NOCLIP|P_CLIENT|P_BROWSER|CLIENT_(X|Y)|BROWSER_(X|Y)/.test(source),'caller-authored collision or noclip state forbidden'); // DATABASE NOCLIP OWNERSHIP GUARD
for(const bad of ['EVALUATOR/','GOLDENS/','SNAPSHOTS/','REPORTS/','PLAYWRIGHT','CALL_STACK','FORMAT_CALL_STACK','V$PROCESS','TEST_NAME','EXPECTED','REFERENCE OUTPUT','346413660E2018','HEAD-ON','OBLIQUE-SLIDE','CORNER-TWO-CONTACT','TUNNELING'])assert.ok(!source.includes(bad),`embedded fixture answer or evaluator coupling: ${bad}`); // EMBEDDED COLLISION ANSWERS GUARD
process.stdout.write('PASS T6.2-SOURCE-AUDIT (session-bound relational swept collision, openings, sliding, stable contacts)\n');
