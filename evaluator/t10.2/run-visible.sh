#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
node "$root/evaluator/t10.2/self-check.mjs"
node "$root/evaluator/t10.2/mutation-self-check.mjs"
T102_REQUIRE_PRODUCTION=1 node "$root/evaluator/t10.2/source-audit.mjs"
"$root/node_modules/.bin/tsc" -p "$root/client/tsconfig.json" --noEmit --pretty false
test -n "${DOOM_T102_BASE_URL:-}" || { printf 'FAIL T10.2: DOOM_T102_BASE_URL is required\n' >&2; exit 1; }
rm -f /tmp/t10.2-playwright-results.json /tmp/t10.2-desktop.png /tmp/t10.2-phone-portrait.png /tmp/t10.2-phone-landscape.png
DOOM_T102_BASE_URL="$DOOM_T102_BASE_URL" "$root/node_modules/.bin/playwright" test -c "$root/evaluator/t10.2/playwright.config.ts"
node "$root/evaluator/t10.2/validate-playwright.mjs"
for image in /tmp/t10.2-desktop.png /tmp/t10.2-phone-portrait.png /tmp/t10.2-phone-landscape.png; do test -s "$image" || { printf 'FAIL T10.2: missing responsive screenshot %s\n' "$image" >&2; exit 1; }; done
printf 'PASS T10.2 (912/912 assertions)\n'
