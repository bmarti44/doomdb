import assert from 'node:assert/strict';import fs from 'node:fs';import path from 'node:path';
const root=path.resolve(import.meta.dirname,'../..'),history=path.join(root,'sql/sim/040_history_replay.sql'),tic=path.join(root,'sql/sim/tic/010_tic_transaction.sql');
function audit(h,t){const s=h.toUpperCase(),tx=t.toUpperCase();
  for(const x of ['CREATE OR REPLACE PACKAGE DOOM_HISTORY','AUTHID DEFINER','CAPTURE_TIC','SAVE_GAME','LOAD_GAME','REWIND_TO_TIC','START_REPLAY','STEP_REPLAY','GAME_SESSIONS','PLAYERS','MOBJS','SECTOR_STATE','LINE_STATE','ACTIVE_MOVERS','ACTIVE_SWITCHES','TIC_COMMANDS','GAME_EVENTS','AUDIO_EVENTS','STATE_HISTORY','SAVE_SLOTS','REPLAY_CURSORS','HISTORY_SNAPSHOT_INTERVAL','DBMS_CRYPTO.HASH','JSON_OBJECT','JSON_TABLE','ORDER BY','FOR UPDATE'])assert.ok(s.includes(x),`required history token absent: ${x}`);
  assert.ok(tx.includes('DOOM_HISTORY.CAPTURE_TIC'),'tic transaction does not delegate history capture');
  assert.ok(/MOD\s*\([^,]+,\s*(?:[A-Z0-9_.]*HISTORY_SNAPSHOT_INTERVAL|4)\s*\)\s*=\s*0/.test(s),'fixed logical-tic snapshot predicate absent');
  assert.ok(/STATE_HISTORY[\s\S]{0,1600}(MAX\s*\(\s*TIC\s*\)|ORDER\s+BY\s+TIC\s+DESC)[\s\S]{0,500}(ROWNUM|FETCH\s+FIRST)/.test(s),'nearest snapshot selection absent');
  assert.ok(/PREVIOUS_COMMAND_SHA[\s\S]{0,1400}(COMMAND_SHA|DBMS_CRYPTO.HASH)/.test(s),'command chain validation absent');
  assert.ok(/PREVIOUS_EVENT_SHA[\s\S]{0,1400}(EVENT_SHA|DBMS_CRYPTO.HASH)/.test(s),'event chain validation absent');
  assert.ok(/STATE_SHA[\s\S]{0,1600}RAISE_APPLICATION_ERROR/.test(s)&&/FRAME_SHA[\s\S]{0,1600}RAISE_APPLICATION_ERROR/.test(s),'state/frame fail-closed validation absent');
  assert.ok(/SAVE_SLOTS[\s\S]{0,1200}(MERGE|UPDATE)[\s\S]{0,1200}STATE_HISTORY/.test(s)||/STATE_HISTORY[\s\S]{0,1200}SAVE_SLOTS/.test(s),'save-point history and slot pointer path absent');
  assert.ok(/STANDARD_HASH|DBMS_CRYPTO.HASH/.test(s)&&/SAVE_LINEAGE/.test(s),'deterministic lineage derivation absent');
  for(const table of ['TIC_COMMANDS','GAME_EVENTS','AUDIO_EVENTS','STATE_HISTORY']){assert.ok(!new RegExp(`DELETE\\s+FROM\\s+${table}|UPDATE\\s+${table}\\s+SET`).test(s),`${table} is not append-only`);}
  assert.ok(!/\b(COMMIT|ROLLBACK|PRAGMA\s+AUTONOMOUS_TRANSACTION)\b/.test(s),'history package owns transaction boundary');
  assert.ok(!/EXECUTE\s+IMMEDIATE|DBMS_SQL/.test(s),'dynamic SQL forbidden');
  assert.ok(!/SYSDATE|SYSTIMESTAMP|CURRENT_TIMESTAMP|DBMS_RANDOM/.test(s),'wall-clock or host random history decision forbidden');
  for(const bad of ['EVALUATOR/','GOLDENS/','REPORTS/','FIXTURES.JSON','EXPECTATIONS.JSON','MUTATION-SPECS','PLAYWRIGHT','CALL_STACK','FORMAT_CALL_STACK','V$PROCESS','TEST_NAME','EXPECTED OUTPUT','T64-','7D20298C','2801C2BC','485EFDAF'])assert.ok(!s.includes(bad),`embedded evaluator answer or coupling: ${bad}`);
}
const good=`create or replace package doom_history authid definer as procedure capture_tic; procedure save_game; procedure load_game; procedure rewind_to_tic; procedure start_replay; procedure step_replay; end; game_sessions players mobjs sector_state line_state active_movers active_switches tic_commands game_events audio_events state_history save_slots replay_cursors history_snapshot_interval dbms_crypto.hash json_object json_table order by for update save_lineage previous_command_sha command_sha previous_event_sha event_sha state_sha raise_application_error frame_sha raise_application_error standard_hash mod(x,history_snapshot_interval)=0 state_history order by tic desc fetch first save_slots merge state_history`;
audit(good,'doom_history.capture_tic');
for(const bad of ['commit;','execute immediate x;','delete from tic_commands;','update game_events set event_sha=x;','systimestamp'])assert.throws(()=>audit(`${good} ${bad}`,'doom_history.capture_tic'));
if(fs.existsSync(history)){assert.ok(fs.existsSync(tic),'tic transaction source absent');audit(fs.readFileSync(history,'utf8'),fs.readFileSync(tic,'utf8'));process.stdout.write('PASS T6.4-SOURCE-AUDIT (production lineage history, nearest reconstruction, save/load, rewind, replay)\n');}
else {assert.notEqual(process.env.T64_REQUIRE_PRODUCTION,'1','T6.4 production source missing: sql/sim/040_history_replay.sql');process.stdout.write('PASS T6.4-SOURCE-POLICY-SELF-CHECK (production source not yet present)\n');}
