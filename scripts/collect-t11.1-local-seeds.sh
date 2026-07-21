#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${ADB_LOCAL_SEED_EVIDENCE:-/tmp/doomdb-t111-local-seed-observation.json}"
tmp="$(mktemp "${TMPDIR:-/tmp}/doomdb-t111-local-seeds.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

"$root/scripts/db_sql.sh" "$root/deploy/cloud/t11.1/seed-observation.sql" >"$tmp"
node - "$tmp" <<'NODE'
import fs from 'node:fs';
const text=fs.readFileSync(process.argv[2],'utf8');
const rows=[...text.matchAll(/^T111_SEED\|([^|]+)\|(\d+)\|([0-9a-f]{64})$/gm)];
if(rows.length!==24)throw new Error(`expected 24 seed domains, got ${rows.length}`);
if(new Set(rows.map(row=>row[1])).size!==24)throw new Error('seed domain ids are not unique');
if(rows.some(row=>Number(row[2])<1))throw new Error('seed domain is empty');
NODE
chmod 600 "$tmp"
mv "$tmp" "$output"
trap - EXIT
printf 'PASS T11.1-LOCAL-SEEDS (24/24 populated domains; evidence %s)\n' "$output"
