import assert from 'node:assert/strict';import fs from 'node:fs';import path from 'node:path';

export function auditHostDriver(text){
  assert.ok(text.length>=800,'substantive host driver');
  for(const needle of ['set -Eeuo pipefail','docker compose','--volumes','--remove-orphans','--wait-timeout','DOOMDB_ORACLE_PASSWORD_FILE','DOOMDB_APP_PASSWORD_FILE','trap ','evaluator'])assert.ok(text.includes(needle),`driver requires ${needle}`);
  assert.match(text,/(?:timeout|perl.*alarm)/,'whole-operation timeouts');
  assert.match(text,/mktemp/,'ephemeral credentials');
  assert.match(text,/chmod\s+600/,'credential permissions');
  assert.match(text,/NanoCpus/,'live cpu inspection');
  assert.match(text,/(?:HostConfig\.Memory|\.Memory)/,'live memory inspection');
  assert.match(text,/(?:read_only|ReadonlyRootfs)/i,'evaluator read-only inspection');
  assert.match(text,/(?:CapDrop|no-new-privileges)/,'evaluator confinement inspection');
  assert.match(text,/(?:for\s+[^;]*\b1\s+2\b|seq\s+1\s+2)/,'exactly two runs');
  assert.ok(!/(?:--privileged|\/var\/run\/docker\.sock|--network\s+host|pid:\s*host|--pid=host)/.test(text),'no evaluator privilege escape');
  assert.ok(!/(?:\|\|\s*true|set\s+\+e|--exit-zero-from|DOOM_SKIP|ALLOW_SKIP|continue_on_error)/i.test(text),'no failure suppression');
  assert.ok(!/(?:echo|printf).*(?:password|credential|secret)/i.test(text),'no credential printing');
  return true;
}

export function auditContainerRunner(text){
  assert.ok(text.length>=800,'substantive container runner');
  for(const needle of ['fixtures.json','suiteFamilies','spawnSync','timeout','parseSuiteOutput','compareRuns'])assert.ok(text.includes(needle),`runner requires ${needle}`);
  assert.ok(!/\bdocker(?:\s+compose)?\b|docker\.sock|child_process[^\n]*exec\s*\(/.test(text),'no Docker or shell-string execution in evaluator');
  assert.ok(!/(?:route\s*\(|page\.route|fetch\s*=|mock|fixtureServer|updateSnapshots\s*:\s*['"]all)/i.test(text),'no transport interception or snapshot updates');
  assert.ok(!/(?:canned|transcript|staticOnly|hash\s*\([^)]*(?:stdout|stderr|console|log))/i.test(text),'no static transcript or log-derived correctness');
  assert.ok(!/(?:SKIP|NOT RUN|TODO).*(?:pass|green|success)/i.test(text),'no skip-as-success');
  assert.match(text,/stdio\s*:/,'captured child evidence');
  assert.match(text,/shell\s*:\s*false/,'no shell command reinterpretation');
  assert.match(text,/PLAYWRIGHT_RETRIES\s*:\s*['"]0['"]/,'browser retries disabled');
  assert.match(text,/PLAYWRIGHT_UPDATE_SNAPSHOTS\s*:\s*['"]none['"]/,'snapshot updates disabled');
  return true;
}

const goodDriver=`#!/usr/bin/env bash
set -Eeuo pipefail
tmp=$(mktemp -d); chmod 600 "$tmp"; trap 'docker compose -p "$project" down --volumes --remove-orphans' EXIT
for run in 1 2; do project=doomdb-t103-$RANDOM; DOOMDB_ORACLE_PASSWORD_FILE="$tmp/oracle"; DOOMDB_APP_PASSWORD_FILE="$tmp/app"; export DOOMDB_ORACLE_PASSWORD_FILE DOOMDB_APP_PASSWORD_FILE; timeout 14400 docker compose -p "$project" up --wait --wait-timeout 1800; docker inspect --format '{{.HostConfig.NanoCpus}} {{.HostConfig.Memory}} {{.HostConfig.ReadonlyRootfs}} {{.HostConfig.CapDrop}} {{.HostConfig.SecurityOpt}}' "$project-db-1" "$project-evaluator-1"; timeout 14400 docker compose -p "$project" run --rm evaluator; docker compose -p "$project" down --volumes --remove-orphans; done
`+'# reviewed bounded orchestration evidence '.repeat(20);
const goodRunner=`import {spawnSync} from 'node:child_process'; import f from './fixtures.json' with {type:'json'}; import {parseSuiteOutput,compareRuns} from './reference.mjs'; const env={PLAYWRIGHT_RETRIES:'0',PLAYWRIGHT_UPDATE_SNAPSHOTS:'none'}; for(const suite of f.suiteFamilies){const [file,...args]=suite.command.split(' ');const r=spawnSync(file,args,{shell:false,stdio:'pipe',timeout:f.timeoutsSeconds.suite*1000,encoding:'utf8',env});parseSuiteOutput(r.stdout,suite)} compareRuns(globalThis.runA,globalThis.runB,f);`+'// timeout immutable evidence '.repeat(25);
auditHostDriver(goodDriver);auditContainerRunner(goodRunner);
for(const bad of [goodDriver.replaceAll('--volumes',''),goodDriver+'\ndocker run --privileged x',goodDriver.replace('set -Eeuo pipefail','set +e'),goodRunner.replace('shell:false','shell:true'),goodRunner+'\n// docker compose exec db',goodRunner+'\npage.route("**", mock)'])assert.throws(()=>bad.includes('suiteFamilies')?auditContainerRunner(bad):auditHostDriver(bad));
process.stdout.write('PASS T10.3-SOURCE-POLICY-SELF-CHECK (synthetic positive and negative canaries)\n');
if(process.env.T103_REQUIRE_PRODUCTION==='1'){
  const root=path.resolve(import.meta.dirname,'../..'),driver=path.join(root,'scripts/verify-local-e2e.sh'),runner=path.join(root,'evaluator/t10.3/run-container.mjs');
  assert.ok(fs.existsSync(driver),'production host driver exists');auditHostDriver(fs.readFileSync(driver,'utf8'));auditContainerRunner(fs.readFileSync(runner,'utf8'));process.stdout.write('PASS T10.3-SOURCE-AUDIT (bounded host orchestration and confined evaluator runner)\n');
}
