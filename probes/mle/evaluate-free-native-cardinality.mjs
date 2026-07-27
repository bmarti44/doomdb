#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const cells = [
  'translate_average', 'scatter_average', 'combined_average',
  'translate_peak', 'scatter_peak', 'combined_peak',
];

function evaluate(text) {
  const records = new Map();
  const recordPattern = new RegExp(
    String.raw`^PMLE_FREE_NATIVE_CARDINALITY\|PASS\|cell=([a-z_]+)`
    + String.raw`\|groups=([0-9]+)\|commands=([0-9]+)\|pixels=([0-9]+)`
    + String.raw`\|samples=30\|batch=5\|wall_p50_ms=([0-9.]+)`
    + String.raw`\|wall_p95_ms=([0-9.]+)\|clock_p50_ms=([0-9.]+)`
    + String.raw`\|clock_p95_ms=([0-9.]+)\|clock_suspects=([0-9]+)`
    + String.raw`\|checksum=([0-9]+)$`,
  );
  for (const line of text.split(/\r?\n/)) {
    const match = line.trim().match(recordPattern);
    if (match) records.set(match[1], {
      groups: Number(match[2]), commands: Number(match[3]),
      pixels: Number(match[4]), wallP50: Number(match[5]),
      wallP95: Number(match[6]), clockP50: Number(match[7]),
      clockP95: Number(match[8]), suspects: Number(match[9]),
    });
  }
  assert.deepEqual([...records.keys()].sort(), [...cells].sort());
  for (const record of records.values()) {
    assert.equal(record.suspects, 0);
    assert.ok(record.wallP95 >= record.wallP50 && record.wallP50 >= 0);
  }
  assert.deepEqual(
    [records.get('combined_average').groups,
      records.get('combined_average').commands,
      records.get('combined_average').pixels],
    [17, 1505, 56615],
  );
  assert.deepEqual(
    [records.get('combined_peak').groups,
      records.get('combined_peak').commands,
      records.get('combined_peak').pixels],
    [29, 2325, 77869],
  );
  const peak = records.get('combined_peak').wallP95;
  const classification = peak >= 11.330
    ? 'REJECT_COMMAND_SCATTER'
    : peak <= 6 ? 'PROMOTE_REAL_TAPE' : 'REQUIRE_TAPE_BUDGET';
  return {records, peak, classification};
}

if (process.argv[2] === '--self-test') {
  const line = (cell, groups, commands, pixels, p50, p95) =>
    `PMLE_FREE_NATIVE_CARDINALITY|PASS|cell=${cell}|groups=${groups}`
    + `|commands=${commands}|pixels=${pixels}|samples=30|batch=5`
    + `|wall_p50_ms=${p50}|wall_p95_ms=${p95}`
    + `|clock_p50_ms=${p50}|clock_p95_ms=${p95}`
    + '|clock_suspects=0|checksum=1';
  const text = [
    line('translate_average', 17, 1505, 56615, .1, .2),
    line('scatter_average', 17, 1505, 56615, 4, 5),
    line('combined_average', 17, 1505, 56615, 4, 5),
    line('translate_peak', 29, 2325, 77869, .1, .2),
    line('scatter_peak', 29, 2325, 77869, 9, 12),
    line('combined_peak', 29, 2325, 77869, 9, 12),
  ].join('\n');
  assert.equal(evaluate(text).classification, 'REJECT_COMMAND_SCATTER');
  assert.throws(() => evaluate(text.replace('clock_suspects=0',
    'clock_suspects=1')));
  process.stdout.write('PMLE_FREE_NATIVE_EVALUATOR|PASS|self_test=YES\n');
  process.exit(0);
}

const input = process.argv[2];
if (!input) throw new Error('usage: evaluate-free-native-cardinality.mjs LOG');
const result = evaluate(fs.readFileSync(input, 'utf8'));
process.stdout.write(
  `PMLE_FREE_NATIVE_VERDICT|PASS|classification=${result.classification}`
  + `|combined_peak_p95_ms=${result.peak.toFixed(3)}`
  + '|budget_ms=11.330|venue=OCI_ALWAYS_FREE\n',
);
