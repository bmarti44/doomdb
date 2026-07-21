#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-t111-ojvm.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

"$root/scripts/mochadoom/build-ojvm-jar.sh" "$tmp/mochadoom.jar" "$tmp/metadata.json" >/dev/null
node - "$tmp/mochadoom.jar" "$tmp/metadata.json" <<'NODE'
import assert from 'node:assert/strict';import crypto from 'node:crypto';import fs from 'node:fs';
const [jar,path]=process.argv.slice(2),m=JSON.parse(fs.readFileSync(path));
assert.deepEqual(m,{schema:1,javaRelease:8,revision:'c0af1322ee5fd168b5cf8aaaf504cab2d1aabe93',classCount:830,jarSha256:'a27903f2dcd81aecb0292f605453969ad3d4389382bebdb8386dff3cb13f23ab'});
assert.equal(crypto.createHash('sha256').update(fs.readFileSync(jar)).digest('hex'),m.jarSha256);
NODE
unzip -p "$tmp/mochadoom.jar" doomdb/mocha/DoomDbMochaAdapter.class >"$tmp/adapter.class"
header="$(od -An -t u1 -N8 "$tmp/adapter.class" | xargs)"
[[ "$header" == '202 254 186 190 0 0 0 52' ]]
printf 'PASS T11.1-OJVM-ARTIFACT (830 deterministic Java 8 classes; client-loadable jar)\n'
