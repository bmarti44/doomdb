import assert from 'node:assert/strict';import fs from 'node:fs';import path from 'node:path';
export function auditDriver(text){
  assert.ok(text.length>=1800,'substantive cloud driver');
  for(const s of ['set -Eeuo pipefail','SQLcl','26.2.0.181.2110','ADB_CONNECTION_STRING','ADB_USERNAME','ADB_PASSWORD','ADB_WALLET_DIR','ADB_ORDS_BASE_URL','trap ','mktemp','chmod 600','tests/verify-oracle-probes.sh','scripts/verify-transport.sh','sql/schema','sql/seed','sql/engine','sql/rest','curl','--connect-timeout','--max-time','USER_OBJECTS','USER_ERRORS','USER_CONSTRAINTS','USER_SYS_PRIVS','USER_TAB_PRIVS','ORDS_METADATA','/tmp/doomdb-t111-evidence.json'])assert.ok(text.includes(s),`requires ${s}`);
  assert.match(text,/(?:sha256sum|shasum\s+-a\s+256)/,'source/content hashes');assert.match(text,/ADB_(?:IS_AUTONOMOUS|SERVICE|WORKLOAD)/,'Autonomous attestation query');assert.match(text,/(?:V\$PDBS|PRODUCT_COMPONENT_VERSION|DBMS_CLOUD)/,'live database provenance');assert.match(text,/(?:AWS_|ADB_).*(?:unset|env)/s,'environment credential handling');assert.match(text,/(?:mv|rename).*doomdb-t111-evidence\.json/,'atomic evidence publish');
  assert.ok(!/(?:\|\|\s*true|set\s+\+e|ALLOW_SKIP|DOOM_SKIP|continue_on_error|--force|WHENEVER\s+SQLERROR\s+CONTINUE)/i.test(text),'no failure suppression');
  assert.ok(!/(?:localhost|127\.0\.0\.1|oracle-free|docker\s+compose|container-registry\.oracle|dry.?run.*PASS|NOT RUN.*PASS)/i.test(text),'no local/dry substitute');
  assert.ok(!/(?:echo|printf|set\s+-x).*(?:ADB_PASSWORD|ADB_CONNECTION_STRING|ADB_ORDS_BASE_URL|wallet|authorization)/i.test(text),'no credential printing');
  assert.ok(!/(?:ORDS\.DEFINE_MODULE|ORDS\.DEFINE_TEMPLATE|ORDS\.DEFINE_HANDLER)/i.test(text),'no custom ORDS API');return true;
}
const good=`#!/usr/bin/env bash
set -Eeuo pipefail
for v in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR ADB_ORDS_BASE_URL; do test -n "\${!v:-}" || exit 2; done
tmp=$(mktemp -d); chmod 600 "$tmp"; trap 'rm -rf "$tmp"; unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY ADB_PASSWORD ADB_CONNECTION_STRING ADB_ORDS_BASE_URL' EXIT
tool='SQLcl'; version='26.2.0.181.2110'; sha256sum tests/verify-oracle-probes.sh scripts/verify-transport.sh
timeout 1800 tests/verify-oracle-probes.sh; timeout 1800 scripts/verify-transport.sh
# SQLcl applies sql/schema sql/seed sql/engine sql/rest with WHENEVER SQLERROR EXIT
# SELECT SYS_CONTEXT('USERENV','CLOUD_SERVICE') ADB_IS_AUTONOMOUS, ADB_SERVICE, ADB_WORKLOAD FROM dual; SELECT version FROM PRODUCT_COMPONENT_VERSION; SELECT * FROM V$PDBS; SELECT DBMS_CLOUD FROM dual
# catalog USER_OBJECTS USER_ERRORS USER_CONSTRAINTS USER_SYS_PRIVS USER_TAB_PRIVS ORDS_METADATA
curl --connect-timeout 20 --max-time 180 "$ADB_ORDS_BASE_URL" >/dev/null
touch "$tmp/evidence"; mv "$tmp/evidence" /tmp/doomdb-t111-evidence.json
`+'# canonical deployment manifest, seed comparison, managed request evidence, redacted hashes '.repeat(25);
auditDriver(good);for(const bad of [good.replace('set -Eeuo pipefail','set +e'),good+'\ndocker compose up oracle-free',good+'\nORDS.DEFINE_HANDLER',good.replace('26.2.0.181.2110','26.2.0'),good+'\necho "$ADB_PASSWORD"'])assert.throws(()=>auditDriver(bad));process.stdout.write('PASS T11.1-SOURCE-POLICY-SELF-CHECK (synthetic positive and negative canaries)\n');
if(process.env.T111_REQUIRE_PRODUCTION==='1'){const root=path.resolve(import.meta.dirname,'../..'),p=path.join(root,'scripts/verify-cloud-database.sh');assert.ok(fs.existsSync(p),'cloud driver exists');auditDriver(fs.readFileSync(p,'utf8'));process.stdout.write('PASS T11.1-SOURCE-AUDIT (pinned fail-closed cloud driver)\n');}
