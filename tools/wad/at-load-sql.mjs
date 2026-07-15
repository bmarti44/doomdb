#!/usr/bin/env node
import fs from 'node:fs';

if (process.argv.length !== 3) throw new Error('usage: at-load-sql.mjs <generated-at-sql>');
const source = fs.readFileSync(process.argv[2], 'ascii');
const rowPattern = /^  INTO AT \(A, X, Y, C\) VALUES \((-?\d+), (-?\d+), (-?\d+), (-?\d+)\)$/gm;
const rows = [];
for (const match of source.matchAll(rowPattern)) rows.push(match.slice(1).map(Number));
const declared = [...source.matchAll(/^  INTO AT \(/gm)].length;
if (rows.length === 0 || rows.length !== declared) throw new Error(`AT row decode mismatch: ${rows.length}/${declared}`);
const json = JSON.stringify(rows);
const chunks = [];
for (let i = 0; i < json.length; i += 3000) chunks.push(`to_clob('${json.slice(i, i + 3000)}')`);
process.stdout.write(`INSERT INTO AT (A,X,Y,C)\n`);
process.stdout.write(`SELECT A,X,Y,C FROM JSON_TABLE(\n  ${chunks.join(' ||\n  ')}\n`);
process.stdout.write(`  , '$[*]' COLUMNS (\n`);
process.stdout.write(`      A NUMBER PATH '$[0]', X NUMBER PATH '$[1]',\n`);
process.stdout.write(`      Y NUMBER PATH '$[2]', C NUMBER PATH '$[3]')) JT;\n`);

