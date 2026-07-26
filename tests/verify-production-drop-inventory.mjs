#!/usr/bin/env node

import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const orderPath = path.join(root, 'sql/bootstrap/production-order.txt');
const dropPath = path.join(root, 'sql/schema/000_drop.sql');

const productionSql = fs.readFileSync(orderPath, 'utf8')
  .split(/\r?\n/)
  .map(line => line.trim())
  .filter(line => line.startsWith('sql/') && line.endsWith('.sql'));

assert.ok(!productionSql.includes(
  'sql/schema/039_retained_render_overlap.sql'
), 'legacy retained-render overlap schema entered the production manifest');

const createdTables = new Map();
for (const relativePath of productionSql) {
  const source = fs.readFileSync(path.join(root, relativePath), 'utf8');
  for (const match of source.matchAll(
    /\bcreate\s+table\s+([a-z][a-z0-9_$#]*)/ig
  )) {
    const table = match[1].toUpperCase();
    const owners = createdTables.get(table) ?? [];
    owners.push(relativePath);
    createdTables.set(table, owners);
  }
}

const dropSource = fs.readFileSync(dropPath, 'utf8');
const dropInventory = new Set(
  [...dropSource.matchAll(/'([A-Z][A-Z0-9_$#]*)'/g)]
    .map(match => match[1])
);

// This bootstrap-version table intentionally survives application teardown.
// Its initializer is conditional and its MERGE is the migration-version gate.
const persistentTables = new Set(['DOOM_BOOTSTRAP_STATE']);
const missing = [...createdTables]
  .filter(([table]) => !persistentTables.has(table) &&
    !dropInventory.has(table))
  .map(([table, owners]) => `${table} (${owners.join(', ')})`)
  .sort();

assert.deepEqual(
  missing,
  [],
  `production tables missing from 000_drop.sql:\n${missing.join('\n')}`
);
assert.ok(createdTables.size >= 90,
  `unexpected production table inventory size: ${createdTables.size}`);

console.log(
  `PASS production-drop-inventory ` +
  `(${createdTables.size - persistentTables.size} manifest tables covered)`
);
