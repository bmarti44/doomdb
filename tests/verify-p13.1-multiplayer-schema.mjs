import assert from 'node:assert/strict';
import fs from 'node:fs';

const schema = fs.readFileSync(new URL(
  '../sql/schema/047_multiplayer.sql', import.meta.url), 'utf8');
const inputOverlay = fs.readFileSync(new URL(
  '../sql/schema/050_multiplayer_input_overlay.sql', import.meta.url), 'utf8');
const pacedInput = fs.readFileSync(new URL(
  '../sql/schema/051_multiplayer_paced_input.sql', import.meta.url), 'utf8');
const drop = fs.readFileSync(new URL(
  '../sql/schema/000_drop.sql', import.meta.url), 'utf8');
const order = fs.readFileSync(new URL(
  '../sql/bootstrap/order.txt', import.meta.url), 'utf8');

const tables = [
  'doom_match', 'doom_match_member', 'doom_match_command',
  'doom_match_tic', 'doom_match_frame', 'doom_match_checkpoint'
];
for (const table of tables) {
  assert.match(schema, new RegExp(`create table ${table} \\(`));
  assert.match(drop, new RegExp(`'${table.toUpperCase()}'`));
}
assert.match(inputOverlay, /create table doom_match_input_event \(/);
assert.match(inputOverlay, /primary key\(match_id,player_slot,input_seq\)/);
assert.match(inputOverlay, /effective_tic number\(12\) not null/);
assert.match(pacedInput, /worker_mode varchar2\(16\)/);
assert.match(pacedInput, /SAMPLED_INPUT/);
assert.match(drop, /'DOOM_MATCH_INPUT_EVENT'/);
assert.equal((schema.match(/create table doom_match(?: |\n|\()/g) ?? []).length, 1);
assert.match(schema, /host_capability_salt raw\(32\) not null/);
assert.match(schema, /host_capability_hash varchar2\(64\) not null/);
assert.match(schema, /join_capability_salt raw\(32\) not null/);
assert.match(schema, /join_capability_hash varchar2\(64\) not null/);
assert.match(schema, /capability_epoch number\(12\) not null/);
assert.match(schema, /membership_epoch number\(12\) not null/g);
assert.match(schema, /generation number\(12\) not null/g);
assert.match(schema, /command_vector raw\(32\) not null/);
assert.match(schema, /ticcmd_raw raw\(8\) not null/);
assert.match(schema, /membership_bitmap raw\(1\) not null/);
assert.match(schema, /references doom_match\(match_id\) on delete cascade/);
assert.match(schema, /references doom_match_member\(match_id,player_slot\) on delete cascade/);
assert.match(schema, /references doom_match_tic\(match_id,tic\) on delete cascade/);
assert.match(schema, /securefile\(cache logging retention none\)/g);
assert.doesNotMatch(schema, /capability_token|host_token|join_token|player_token/i);

const lines = order.trim().split('\n');
assert.equal(lines.filter(line => line === 'sql/schema/047_multiplayer.sql').length, 1);
assert.equal(lines.indexOf('sql/schema/047_multiplayer.sql'),
  lines.indexOf('sql/schema/046_mocha_frame_ledger.sql') + 1);
assert.ok(lines.indexOf('sql/schema/047_multiplayer.sql') <
  lines.indexOf('sql/schema/050_config.sql'));
assert.equal(lines.filter(line => line ===
  'sql/schema/050_multiplayer_input_overlay.sql').length, 1);
assert.equal(lines.filter(line => line ===
  'sql/schema/051_multiplayer_paced_input.sql').length, 1);

const dropPositions = [
  'DOOM_MATCH_CHECKPOINT', 'DOOM_MATCH_FRAME', 'DOOM_MATCH_COMMAND',
  'DOOM_MATCH_TIC', 'DOOM_MATCH_MEMBER', 'DOOM_MATCH'
].map(name => drop.indexOf(`'${name}'`));
assert.ok(dropPositions.every(position => position >= 0));
assert.deepEqual([...dropPositions].sort((a, b) => a - b), dropPositions);

process.stdout.write(
  'PASS P13.1-MULTIPLAYER-SCHEMA six tables, fences, hashed capabilities, bootstrap/drop order\n');
