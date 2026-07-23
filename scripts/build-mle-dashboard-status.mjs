#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(new URL('..', import.meta.url).pathname);
const versions = JSON.parse(fs.readFileSync(path.join(root, 'versions.lock'), 'utf8'));
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const contains = (text, marker, label) =>
  assert.ok(text.includes(marker), `${label} marker missing: ${marker}`);

const soakPath =
  'artifacts/performance/pmle-worker-soak/run-final-checkpoint-reuse-v3.log';
const ledgerPath =
  'artifacts/performance/pmle-ledger-every-tic/run-final-06ac3333-2026-07-23.log';
const soak = read(soakPath);
const ledger = read(ledgerPath);
const authority = versions.teaVM;
const presentation = authority.presentation;

contains(soak, `PMLE_ARTIFACT|source_bytes=${authority.outputBytes}` +
  `|source_sha256=${authority.outputSha256}`, 'soak final artifact');
contains(soak, 'PASS P13.5-MULTIPLAYER-SOAK seconds=1800 warmupSeconds=300',
  'browser soak');
contains(soak, 'PMLE_WORKER_SOAK_MEMORY|PASS|role=AUTHORITY', 'authority memory');
contains(soak, 'PMLE_WORKER_SOAK_MEMORY|PASS|role=STANDBY', 'standby memory');
contains(soak, 'PMLE_WORKER_SOAK|PASS|duration_s=1800|warmup_s=300',
  'worker soak');
contains(ledger, `PMLE_PINNED_PAIR|authority_sha256=${authority.outputSha256}` +
  `|table_sha256=058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44` +
  `|ojvm_jar_sha256=${authority.canonicalOracleJarSha256}`, 'ledger pinned pair');
contains(ledger,
  'PMLE_TEAVM_LEDGER_DIFFERENTIAL|PASS|tics=13272|deep_every=1',
  'ledger every-tic');
contains(ledger,
  'PMLE_LEDGER_PROVENANCE|CONFIRMED|executions=1|terminal_markers=1',
  'ledger provenance');

const status = {
  schema: 1,
  updated: '2026-07-23',
  database: {
    product: 'Oracle AI Database 26ai Free',
    imageVersion: '23.26.2',
    cpuCount: 2,
    pdbUtilizationLimitPercent: 50,
    runningSessionsLimit: 2,
    resourceCapModifiable: false
  },
  architecture: {
    authority: 'TeaVM-generated MLE JavaScript in retained database sessions',
    livePresentation: 'Browser rendering from confirmed DMD1 transitions',
    clientPrediction: false,
    productionOjvm: false
  },
  artifacts: {
    authority: {
      bytes: authority.outputBytes,
      sha256: authority.outputSha256,
      profile: authority.profile
    },
    presentation: {
      bytes: presentation.outputBytes,
      sha256: presentation.outputSha256,
      profile: presentation.profile
    },
    inputBytecodeSha256: authority.inputBytecodeSha256,
    mochaBytecodeSha256: authority.mochaBytecodeSha256,
    tablePackSha256:
      '058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44',
    ojvmDifferentialOracleSha256: authority.canonicalOracleJarSha256,
    ojvmScope: 'repository/dev differential oracle only'
  },
  gates: {
    canonical330: 'PASS',
    coopEveryTic762: 'PASS',
    membershipRecovery: 'PASS',
    ledgerEveryTic13272: 'PASS',
    finalWorkerSoak: 'PASS',
    calibratedProcessMemory: 'PASS',
    browserConfirmedOnly: 'PASS',
    resourceCapDecision: 'PASS'
  },
  soak: {
    warmupSecondsExcluded: 300,
    scoredSeconds: 1800,
    maxConfirmedLagTics: 18,
    reconnects: 0,
    authorityPssBaselineBytes: 464108544,
    authorityPssMaximumBytes: 518277120,
    authorityPssEndBytes: 434509824,
    standbyPssBaselineBytes: 442265600,
    standbyPssMaximumBytes: 483700736,
    standbyPssEndBytes: 413642752,
    processMemoryMarginBytes: 67108864,
    ashSamples: 1486,
    resourceManagerCpuQuantumSamples: 0
  },
  capacity: {
    effectivePdbCpu: 1,
    runningSessions: 2,
    heldPollLeaseLimit: 4,
    guaranteedConcurrentPollReturns: 1,
    localLongPollingDefault: false
  },
  remaining: [
    {id: 'WAN', state: 'NEXT', label: 'Injected-latency multiplayer matrix'},
    {id: 'JAVA-AUDIT', state: 'NEXT',
      label: 'Production-path Java removal audit'},
    {id: 'DVR', state: 'OPEN',
      label: 'HUD, automap, intermission, finale and audit/DVR presentation'},
    {id: 'ADB', state: 'DORMANT',
      label: 'Autonomous MLE performance probe; credentials required'}
  ],
  evidence: {soak: soakPath, ledger: ledgerPath}
};

const serialized = `${JSON.stringify(status, null, 2)}\n`;
for (const relative of ['client/staging/mle-status.json', 'client/dist/mle-status.json']) {
  fs.writeFileSync(path.join(root, relative), serialized, {mode: 0o644});
}
process.stdout.write(`PASS MLE-DASHBOARD-STATUS authority=${authority.outputSha256}` +
  ` ledger=13272 soak=1800\n`);
