import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

export function auditDriver(text){
  assert.ok(text.length>=5000,'substantive hosted-browser driver');
  for(const marker of ['set -Eeuo pipefail','DOOMDB_CLOUD_EXECUTE',
    'ADB_CONNECTION_STRING','ADB_ORDS_BASE_URL','T112_HOSTED_INDEX_URL',
    'install-hosted-statics.sql','load-hosted-statics.sh',
    'artifact-allowlist','loader-manifest.tsv','database_asset_load',
    't11.2-verify-database-inventory.mjs','t11.2-verify-live-headers.mjs',
    'DoomDB-T11.2-verifier','playwright','playwright.config.ts',
    'browser_30fps','/tmp/doomdb-t112-evidence.json','mktemp','chmod 600',
    'redact-cloud-output.mjs','trap cleanup']){
    assert.ok(text.includes(marker),`requires ${marker}`);
  }
  assert.match(text,/(?:sha256sum|shasum\s+-a\s+256)/,'byte hashes');
  assert.match(text,/mv "\$candidate" "\$evidence"/,'atomic evidence');
  assert.ok(!/(?:AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_S3_BUCKET|s3api|cloudfront)/i.test(text),
    'retired AWS transport absent');
  assert.ok(!/(?:route\.fulfill|page\.setContent|localhost|127\.0\.0\.1|http:\/\/|dry.?run.*PASS)/i.test(text),
    'no browser mock/local substitute');
  assert.ok(!/(?:set\s+\+e|\|\|\s*true|ALLOW_SKIP|continue_on_error)/i.test(text),
    'no failure suppression');
  assert.ok(!/(?:echo|printf|set\s+-x).*(?:ADB_PASSWORD|authorization|wallet)/i.test(text),
    'no secret printing');
  return true;
}

const good=`#!/usr/bin/env bash
set -Eeuo pipefail
tmp=$(mktemp -d); chmod 600 "$tmp"; trap cleanup EXIT
DOOMDB_CLOUD_EXECUTE=YES
ADB_CONNECTION_STRING=x ADB_ORDS_BASE_URL=https:x T112_HOSTED_INDEX_URL=x
install-hosted-statics.sql load-hosted-statics.sh artifact-allowlist
loader-manifest.tsv database_asset_load t11.2-verify-database-inventory.mjs
t11.2-verify-live-headers.mjs DoomDB-T11.2-verifier playwright playwright.config.ts browser_30fps
/tmp/doomdb-t112-evidence.json redact-cloud-output.mjs
sha256sum x
mv "$candidate" "$evidence"
`+'database hosted ORDS exact asset verification and browser evidence '.repeat(100);
auditDriver(good);
for(const bad of [good+' AWS_S3_BUCKET',good+' route.fulfill({})',
  good+' localhost',good.replace('set -Eeuo pipefail','set +e')])
  assert.throws(()=>auditDriver(bad));
process.stdout.write(
  'PASS T11.2-SOURCE-POLICY-SELF-CHECK (hosted positive and negative canaries)\n');

if(process.env.T112_REQUIRE_PRODUCTION==='1'){
  const root=path.resolve(import.meta.dirname,'../..');
  const driver=fs.readFileSync(path.join(root,'scripts/verify-cloud-browser.sh'),'utf8');
  auditDriver(driver);
  process.stdout.write(
    'PASS T11.2-SOURCE-AUDIT (pinned fail-closed database-hosted browser driver)\n');
}
