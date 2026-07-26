#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';

const fixturePath = process.argv[2];
if (fixturePath === undefined) {
  throw new Error('usage: emit-command-stream-sql.mjs FIXTURE.json');
}

const fixture = JSON.parse(fs.readFileSync(fixturePath, 'utf8'));
assert.equal(fixture.schema, 1);
assert.match(fixture.stream, /^[a-z0-9][a-z0-9-]{0,63}$/);
assert.equal(fixture.tics, 5250);
assert.match(fixture.expandedSha256, /^[0-9a-f]{64}$/);
assert.ok(Array.isArray(fixture.runs) && fixture.runs.length > 0);

const rows = [];
const digest = crypto.createHash('sha256');
for (const run of fixture.runs) {
  assert.ok(Number.isInteger(run.membership) &&
    run.membership >= 0 && run.membership <= 255);
  assert.match(run.command, /^[0-9a-f]{64}$/);
  assert.ok(Number.isInteger(run.repeat) && run.repeat > 0);
  const command = Buffer.from(run.command, 'hex');
  for (let index = 0; index < run.repeat; index += 1) {
    rows.push({membership: run.membership, command: run.command});
    digest.update(Buffer.from([run.membership]));
    digest.update(command);
  }
}
assert.equal(rows.length, fixture.tics);
assert.equal(digest.digest('hex'), fixture.expandedSha256);

const quotedStream = fixture.stream.replaceAll("'", "''");
process.stdout.write(`whenever sqlerror exit sql.sqlcode rollback
set define off
set echo off
set verify off
set feedback off
set heading off
set pagesize 0
set linesize 32767
set trimout on
set trimspool on
set tab off
set serveroutput on size unlimited
begin
  execute immediate 'drop table doom_mle_perf_vector purge';
exception when others then
  if sqlcode <> -942 then raise; end if;
end;
/
create table doom_mle_perf_vector (
  stream_name varchar2(64) not null,
  tic number(10) not null,
  membership_bitmap raw(1) not null,
  command_vector raw(32) not null,
  constraint doom_mle_perf_vector_pk primary key(stream_name,tic)
);
`);

for (let offset = 0; offset < rows.length; offset += 100) {
  const batch = rows.slice(offset, offset + 100);
  process.stdout.write('insert all\n');
  for (const [index, row] of batch.entries()) {
    const tic = offset + index + 1;
    const membership = row.membership.toString(16).padStart(2, '0');
    process.stdout.write(
      ` into doom_mle_perf_vector values('${quotedStream}',${tic},` +
      `hextoraw('${membership}'),hextoraw('${row.command}'))\n`);
  }
  process.stdout.write('select 1 from dual;\n');
}

process.stdout.write(`declare
  l_payload blob;
  l_sha varchar2(64);
begin
  dbms_lob.createtemporary(l_payload,true,dbms_lob.call);
  for row_ in (
    select membership_bitmap,command_vector
    from doom_mle_perf_vector
    where stream_name='${quotedStream}'
    order by tic
  ) loop
    dbms_lob.writeappend(
      l_payload,utl_raw.length(row_.membership_bitmap),
      row_.membership_bitmap);
    dbms_lob.writeappend(
      l_payload,utl_raw.length(row_.command_vector),
      row_.command_vector);
  end loop;
  l_sha:=lower(rawtohex(
    dbms_crypto.hash(l_payload,dbms_crypto.hash_sh256)));
  if dbms_lob.getlength(l_payload)<>${rows.length * 33}
      or l_sha<>'${fixture.expandedSha256}' then
    raise_application_error(
      -20796,
      'command stream staging mismatch bytes='||
      dbms_lob.getlength(l_payload)||' sha='||l_sha);
  end if;
  dbms_output.put_line(
    'PMLE_OCI_COMMAND_STREAM|PASS|stream=${quotedStream}'||
    '|tics=${rows.length}|bytes=${rows.length * 33}'||
    '|sha256=${fixture.expandedSha256}');
  dbms_lob.freetemporary(l_payload);
end;
/
commit;
`);
