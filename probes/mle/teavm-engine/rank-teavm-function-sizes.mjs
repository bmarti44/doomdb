#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';

const selfTest = process.argv[2] === '--self-test';

function matchingBrace(source, open) {
  let depth = 0;
  let state = 'code';
  let quote = '';
  for (let index = open; index < source.length; index++) {
    const char = source[index];
    const next = source[index + 1];
    if (state === 'line') {
      if (char === '\n') state = 'code';
      continue;
    }
    if (state === 'block') {
      if (char === '*' && next === '/') {
        state = 'code';
        index++;
      }
      continue;
    }
    if (state === 'string') {
      if (char === '\\') {
        index++;
      } else if (char === quote) {
        state = 'code';
      }
      continue;
    }
    if (char === '/' && next === '/') {
      state = 'line';
      index++;
    } else if (char === '/' && next === '*') {
      state = 'block';
      index++;
    } else if (char === '"' || char === '\'' || char === '`') {
      state = 'string';
      quote = char;
    } else if (char === '{') {
      depth++;
    } else if (char === '}') {
      depth--;
      if (depth === 0) return index;
      assert.ok(depth >= 0);
    }
  }
  throw new Error(`unterminated function body at byte ${open}`);
}

function rank(source) {
  const patterns = [
    /\b([A-Za-z_$][\w$]*)\s*=\s*(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>\s*\{/g,
    /\bfunction\s+([A-Za-z_$][\w$]*)\s*\([^)]*\)\s*\{/g,
  ];
  const functions = [];
  const seen = new Set();
  for (const pattern of patterns) {
    for (const match of source.matchAll(pattern)) {
      const open = match.index + match[0].lastIndexOf('{');
      if (seen.has(open)) continue;
      seen.add(open);
      const end = matchingBrace(source, open);
      functions.push({
        name: match[1],
        start: match.index,
        end,
        bytes: Buffer.byteLength(source.slice(match.index, end + 1)),
      });
    }
  }
  return functions.toSorted((left, right) =>
    right.bytes - left.bytes || left.name.localeCompare(right.name));
}

if (selfTest) {
  const source = `
let one = x => { return {x}; },
two = (x, y) => { /* } */ if (x) { return "{"; } return y; };
function three() { return \`}\`; }
`;
  const result = rank(source);
  assert.equal(result.length, 3);
  assert.deepEqual(new Set(result.map(row => row.name)),
    new Set(['one', 'two', 'three']));
  assert.ok(result.every(row => row.bytes > 0 && row.end > row.start));
  console.log('PASS PMLE-TEAVM-FUNCTION-SIZE-CENSUS-SELF-TEST');
} else {
  const file = process.argv[2];
  const limit = Number(process.argv[3] ?? 100);
  assert.ok(file && Number.isInteger(limit) && limit >= 10 && limit <= 1000);
  const bytes = fs.readFileSync(file);
  const source = bytes.toString('utf8');
  const functions = rank(source);
  assert.ok(functions.length >= 3000,
    `function census coverage too small: ${functions.length}`);
  const sha = crypto.createHash('sha256').update(bytes).digest('hex');
  console.log(`PMLE_TEAVM_FUNCTION_SIZE_CENSUS|PASS|artifact_sha256=${sha}`
    + `|artifact_bytes=${bytes.length}|functions=${functions.length}`
    + `|reported=${Math.min(limit, functions.length)}`);
  for (const [index, row] of functions.slice(0, limit).entries()) {
    console.log(`PMLE_TEAVM_FUNCTION_SIZE|rank=${index + 1}`
      + `|name=${row.name}|bytes=${row.bytes}|start=${row.start}|end=${row.end}`);
  }
}
