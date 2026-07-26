#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const install=fs.readFileSync(
  new URL('../deploy/cloud/t11.2/install-hosted-statics.sql',import.meta.url),
  'utf8').toUpperCase();
const uninstall=fs.readFileSync(
  new URL('../deploy/cloud/t11.2/uninstall-hosted-statics.sql',import.meta.url),
  'utf8').toUpperCase();
const created=[...install.matchAll(/\bCREATE\s+TABLE\s+([A-Z][A-Z0-9_$#]*)/g)]
  .map(match=>match[1]).sort();
const dropped=[...uninstall.matchAll(/\bDROP\s+TABLE\s+([A-Z][A-Z0-9_$#]*)/g)]
  .map(match=>match[1]).sort();
assert.ok(created.length>0,'hosted installer must declare its tables');
assert.deepEqual(dropped,created,
  'hosted-static teardown must cover every installer CREATE TABLE');
assert.match(install,/P_MODULE_NAME\s*=>\s*'DOOM\.HOSTED\.APP'/);
assert.match(uninstall,/DELETE_MODULE\s*\(\s*P_MODULE_NAME\s*=>\s*'DOOM\.HOSTED\.APP'/);
process.stdout.write(
  `PASS T11.2-DROP-INVENTORY (${created.length} hosted table and module covered)\n`);
