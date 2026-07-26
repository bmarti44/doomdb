#!/usr/bin/env node

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = fs.readFileSync(
  path.join(root, 'deploy/cloud/t11.1/schema-grants.sql'), 'utf8'
);
const grants = [...source.matchAll(/\bgrant\s+([\s\S]*?)\s+to\s+DOOM\s*;/gi)]
  .map(match => match[1].replace(/\s+/g, ' ').trim().toUpperCase())
  .sort();

const expected = [
  'CREATE SESSION, CREATE TABLE, CREATE VIEW, CREATE SEQUENCE, CREATE PROCEDURE, CREATE TRIGGER, CREATE TYPE, CREATE JOB, CREATE MLE, CREATE PROPERTY GRAPH',
  'EXECUTE ON SYS.DBMS_ALERT',
  'EXECUTE ON SYS.DBMS_AQ',
  'EXECUTE ON SYS.DBMS_AQADM',
  'EXECUTE ON SYS.DBMS_CRYPTO',
  'SELECT ON SYS.V_$PARAMETER',
  'SELECT ON SYS.V_$PROCESS',
  'SELECT ON SYS.V_$RSRCPDBMETRIC',
  'SELECT ON SYS.V_$SESSION'
].sort();

assert.deepEqual(grants, expected,
  'cloud production schema direct-grant inventory changed');
assert.match(source, /install-validation-only/);
assert.doesNotMatch(source, /V_\$TEMPORARY_LOBS/i);

console.log(`PASS cloud-schema-grants (${grants.length} pinned grants)`);
