#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
evidence="$root/artifacts/performance/pmle-free-live-frames"
tag="${PMLE_PRESENTATION_COMMAND_TAG:-full-command-census-v1-2026-07-27}"
log="$evidence/node-$tag.log"
verdict="$evidence/node-$tag-verdict.log"
artifact="$project/target/javascript/doom-mle-presentation-engine-headless.js"
mocha="$project/target/mochadoom-mle-presentation.jar"
input="$project/target/mochadoom-mle-engine-slice-1.0.0.jar"
iwad="$project/target/iwad-smoke/freedoom1.wad"
tables="$project/target/canonical-runtime-v2.bin"
pack="${PMLE_PRESENTATION_COMMAND_PACK:-}"

[[ "${PMLE_PRESENTATION_COMMAND_EXECUTE:-NO}" == YES ]] || exit 2
for file in "$artifact" "$mocha" "$input" "$iwad" "$tables"; do
  [[ -s "$file" && ! -L "$file" ]] || {
    printf 'presentation command census input missing: %s\n' "$file" >&2
    exit 2
  }
done
for output in "$log" "$verdict"; do
  [[ ! -e "$output" ]] || {
    printf 'presentation command census evidence exists: %s\n' "$output" >&2
    exit 1
  }
done
if [[ -n "$pack" && -e "$pack" ]]; then
  printf 'presentation command pack exists: %s\n' "$pack" >&2
  exit 1
fi

PMLE_PRESENTATION_COMMAND_METRICS=YES \
  PMLE_PRESENTATION_COMMAND_PACK="$pack" \
  node "$project/run-presentation-node.mjs" "$iwad" "$tables" "$artifact" |
  tee "$log"

[[ "$(grep -c '^PMLE_PRESENTATION_COMMANDS|PASS|' "$log")" == 192 ]]
grep -Fq 'PMLE_TEAVM_PRESENTATION|PASS|tics=96|' "$log"
if [[ -n "$pack" ]]; then
  [[ -s "$pack" && ! -L "$pack" ]]
  grep -Fq 'PMLE_PRESENTATION_COMMAND_PACK|PASS|version=3|frames=192|' "$log"
fi

node - "$log" "$artifact" "$mocha" "$input" <<'NODE' | tee "$verdict"
import {createHash} from 'node:crypto';
import fs from 'node:fs';
const [logPath, artifactPath, mochaPath, inputPath] = process.argv.slice(2);
const lines = fs.readFileSync(logPath, 'utf8').split(/\r?\n/)
  .filter((line) => line.startsWith('PMLE_PRESENTATION_COMMANDS|PASS|'));
if (lines.length !== 192) throw new Error(`expected 192 metric rows, got ${lines.length}`);
const keys = ['wallCalls', 'wallPixels', 'maskedCalls', 'maskedPixels',
  'playerCalls', 'playerPixels', 'skyCalls', 'skyPixels', 'fuzzCalls',
  'fuzzPixels', 'translatedCalls', 'translatedPixels', 'spanCalls',
  'spanPixels'];
const values = Object.fromEntries(keys.map((key) => [key, []]));
const totals = {calls: [], pixels: []};
for (const line of lines) {
  const fields = Object.fromEntries(line.split('|').slice(2)
    .map((field) => field.split('=', 2)));
  let calls = 0;
  let pixels = 0;
  for (const key of keys) {
    const value = Number(fields[key]);
    if (!Number.isInteger(value) || value < 0) throw new Error(`invalid ${key}`);
    values[key].push(value);
    if (key.endsWith('Calls')) calls += value;
    if (key.endsWith('Pixels')) pixels += value;
  }
  totals.calls.push(calls);
  totals.pixels.push(pixels);
}
function percentile(samples, fraction) {
  const sorted = [...samples].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil(sorted.length * fraction) - 1)];
}
function sha(path) {
  return createHash('sha256').update(fs.readFileSync(path)).digest('hex');
}
const fields = [
  'PMLE_PRESENTATION_COMMAND_CENSUS|PASS',
  `frames=${lines.length}`,
  `calls_p50=${percentile(totals.calls, .5)}`,
  `calls_p95=${percentile(totals.calls, .95)}`,
  `calls_max=${Math.max(...totals.calls)}`,
  `pixels_p50=${percentile(totals.pixels, .5)}`,
  `pixels_p95=${percentile(totals.pixels, .95)}`,
  `pixels_max=${Math.max(...totals.pixels)}`,
];
for (const key of keys) fields.push(`${key}_p95=${percentile(values[key], .95)}`);
fields.push(`artifact_sha256=${sha(artifactPath)}`);
fields.push(`mocha_sha256=${sha(mochaPath)}`);
fields.push(`input_sha256=${sha(inputPath)}`);
fields.push('classification=DIAGNOSTIC_NOT_GATE');
process.stdout.write(`${fields.join('|')}\n`);
NODE
