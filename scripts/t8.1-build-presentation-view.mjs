#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root=path.resolve(import.meta.dirname,'..');
const source=fs.readFileSync(path.join(root,
  'sql/render/r2/040_presentation.sql'),'utf8');
const match=source.match(/return q'~\n([\s\S]*?)\n  ~';/);
assert.ok(match,'presentation SQL-macro body not found');
let query=match[1];
const predicate='where winner_ordinal=1 and session_token=p_session';
assert.equal(query.split(predicate).length,2,'unexpected presentation token predicate');
query=query.replace(predicate,'where winner_ordinal=1');
const sessionSource='from game_sessions session_row\n      join players player';
assert.equal(query.split(sessionSource).length,2,
  'unexpected presentation session source');
query=query.replace(sessionSource,`from game_sessions session_row
      join (select distinct session_token from frame_column) selected_session
        on selected_session.session_token=session_row.session_token
      join players player`);
assert.ok(!/\bp_session\b/i.test(query),'parameter survived view derivation');
const sql=`whenever sqlerror exit sql.sqlcode rollback
whenever oserror exit failure rollback
set define off
create or replace view doom_api_presentation_rows as
${query};
commit;
`;
const output=process.argv[2]?path.resolve(process.argv[2]):path.join(root,
  'artifacts/t8.1-live/010_api_presentation_rows.sql');
fs.mkdirSync(path.dirname(output),{recursive:true});
fs.writeFileSync(output,sql);
process.stdout.write(`PASS T8.1-API-PRESENTATION-VIEW (${query.split('\n').length} SQL lines)\n`);
