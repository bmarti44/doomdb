#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
[[ "$(shasum -a 256 evaluator/integrity.pending-T4.3.json | awk '{print $1}')" == 38927540dc430ff6d3476738f122577ec15bf4ab104628282a4f19a7e7c5977a ]]
node evaluator/t4.3/self-check.mjs
node evaluator/t4.3/mutation-self-check.mjs
node evaluator/t4.3/source-audit.mjs
for id in spawn-east spawn-north spawn-south; do
  node evaluator/t4.3/run-observation.mjs "artifacts/t4.3-review/$id.observation.json" artifacts/t4.3-review
done
node tests/verify-t4.3-artifacts.mjs artifacts/t4.3-review
node tests/verify-t4.3-goldens.mjs
node evaluator/t4.2/self-check.mjs
node evaluator/t4.2/mutation-self-check.mjs
node evaluator/t4.2/source-audit.mjs
printf 'PASS T4.3 (1282017/1282017 assertions)\n'
