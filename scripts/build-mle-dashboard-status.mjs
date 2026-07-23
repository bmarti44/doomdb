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
  'artifacts/performance/pmle-ledger-every-tic/run-init-diet-a942cd2d-2026-07-23.log';
const initDietPath =
  'artifacts/performance/pmle-init-diet/promotion-a942cd2d-2026-07-23.log';
const soloPath =
  'artifacts/performance/pmle-browser-role-swap/solo-live-2026-07-23.log';
const soloAdmissionPath =
  'artifacts/performance/pmle-browser-role-swap/solo-admission-live-2026-07-23.log';
const warmPoolPath =
  'artifacts/performance/pmle-browser-role-swap/warm-pool-admission-live-2026-07-23.log';
const voidedSoakPath =
  'artifacts/performance/pmle-worker-soak/run-final-init-diet-a942-2026-07-23.log';
const voidedSmokePath =
  'artifacts/performance/pmle-worker-soak/run-smoke-init-diet-harness2-2026-07-23.log';
const lifecyclePath =
  'artifacts/performance/pmle-worker-lifecycle/run-2026-07-23.log';
const causalSoakPath =
  'artifacts/performance/pmle-worker-soak/' +
  'run-smoke-foreground-180-warm300-c664-2026-07-23.log';
const finalPromotedSoakPath =
  'artifacts/performance/pmle-worker-soak/' +
  'run-final-a942-lifecycle-0744-2026-07-23.log';
const browserProfilePath =
  'artifacts/performance/pmle-browser-replica/profile-2026-07-23.log';
const soak = read(soakPath);
const ledger = read(ledgerPath);
const initDiet = read(initDietPath);
const solo = read(soloPath);
const soloAdmission = read(soloAdmissionPath);
const warmPool = read(warmPoolPath);
const voidedSoak = read(voidedSoakPath);
const voidedSmoke = read(voidedSmokePath);
const lifecycle = read(lifecyclePath);
const causalSoak = read(causalSoakPath);
const finalPromotedSoak = read(finalPromotedSoakPath);
const browserProfile = read(browserProfilePath);
const authority = versions.teaVM;
const presentation = authority.presentation;

contains(soak, 'PMLE_ARTIFACT|source_bytes=1163182|' +
  'source_sha256=06ac33331d9a9158d63fba2da4688ad5d3ff30c316b4c20c09e38d77d3fdebf0',
  'superseded soak artifact');
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
contains(initDiet,
  `PMLE_INIT_DIET_ARTIFACT|authority_bytes=${authority.outputBytes}` +
  `|authority_sha256=${authority.outputSha256}` +
  `|presentation_bytes=${presentation.outputBytes}` +
  `|presentation_sha256=${presentation.outputSha256}`,
  'init-diet promoted artifact');
contains(initDiet,
  'PMLE_INIT_DIET_COLD|PASS|sample_1_ms=4541.733|sample_2_ms=4825.980',
  'init-diet cold gate');
contains(initDiet,
  'PMLE_INIT_DIET_PLAY_E2E|PASS|new_game_to_first_presented_ms=5223',
  'init-diet live play gate');
contains(solo, 'PMLE_SOLO_LIVE|PASS|elapsed_ms=248629', 'solo MLE browser');
contains(solo,
  'PMLE_SOLO_LEGACY_ENDPOINTS|NEW_GAME=0|SUBMIT_STEP=0|POLL_FRAME=0',
  'solo Java-free endpoint path');
contains(soloAdmission,
  'PMLE_SOLO_ADMISSION_LIVE|PASS|elapsed_ms=110458',
  'solo early authority admission');
contains(soloAdmission,
  'PMLE_SOLO_ORDS_POOL|PASS|status_poll=SINGLE_FLIGHT|' +
  'cold_match_row_lock=RELEASED|create_match_http=200',
  'solo ORDS pool correction');
contains(warmPool,
  'PMLE_WARM_POOL_ADMISSION|PASS|samples=10|min_ms=2985|p50_ms=3100|' +
  'p95_ms=3440|max_ms=3440|target_p95_ms=5000',
  'warm-pool admission');
contains(warmPool,
  'PMLE_WARM_STANDBY_HEAL|PASS|polls=8|poll_interval_ms=500|' +
  'sequence=WARMING>READY',
  'warm-pool standby healing');
contains(voidedSoak,
  'PMLE_WORKER_SOAK|VOIDED|reason=legacy_cleanup_stop_job_lifecycle_race',
  'promoted soak void classification');
contains(voidedSmoke,
  'PMLE_WORKER_SOAK|VOIDED|reason=pre_lifecycle_hardening_diagnostic',
  'pre-hardening smoke void classification');
contains(lifecycle,
  'PMLE_WARM_LIFECYCLE|PASS|scenarios=4|pool_restored=1',
  'warm lifecycle hardening');
contains(lifecycle,
  'PMLE_PREWARM_ORDER|PASS|order=RETIRE_BOTH_THEN_AUTHORITY_THEN_STANDBY',
  'sequential authority-first prewarm');
contains(causalSoak,
  'PASS P13.5-MULTIPLAYER-SOAK seconds=180 warmupSeconds=300',
  'post-hardening causal browser soak');
contains(causalSoak,
  'PMLE_WORKER_SOAK_MEMORY|PASS|role=AUTHORITY',
  'post-hardening authority memory');
contains(causalSoak,
  'PMLE_WORKER_SOAK|PASS|duration_s=180|warmup_s=300',
  'post-hardening causal soak');
contains(finalPromotedSoak,
  `PMLE_ARTIFACT|source_bytes=${authority.outputBytes}` +
  `|source_sha256=${authority.outputSha256}` +
  `|table_bytes=180272|table_sha256=` +
  '058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44',
  'final promoted soak artifact');
contains(finalPromotedSoak,
  'PASS P13.5-MULTIPLAYER-SOAK seconds=1800 warmupSeconds=300',
  'final promoted browser soak');
contains(finalPromotedSoak,
  'PMLE_WORKER_SOAK_MEMORY|PASS|role=AUTHORITY|samples=58|' +
  'warmup_excluded=1|spid_stable=1|margin=67108864',
  'final promoted authority memory');
contains(finalPromotedSoak,
  'PMLE_WORKER_SOAK_MEMORY|PASS|role=STANDBY|samples=58|' +
  'warmup_excluded=1|spid_stable=1|margin=67108864',
  'final promoted standby memory');
contains(finalPromotedSoak,
  'PMLE_WORKER_SOAK_RES_MGR|ash_samples=1457|cpu_quantum=0',
  'final promoted wait attribution');
contains(finalPromotedSoak,
  'PMLE_WORKER_SOAK|PASS|duration_s=1800|warmup_s=300|' +
  'memory_margin=67108864',
  'final promoted worker soak');
contains(browserProfile,
  'PMLE_BROWSER_REPLICA_PROFILE|VERDICT|compute_headroom=PASS',
  'browser confirmed-replica stage profile');

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
    soloPresentation: 'One browser player plus an uncredentialed neutral authority slot',
    clientPrediction: false,
    productionOjvm: false
  },
  playModes: {
    singlePlayer: {path: '/play/', authority: 'MLE', state: 'AVAILABLE'},
    coop: {
      path: '/play/multiplayer.html#mode=COOP',
      players: 2,
      authority: 'MLE',
      state: 'AVAILABLE'
    },
    multiplayer: {
      path: '/play/multiplayer.html#mode=DEATHMATCH',
      kind: 'DEATHMATCH',
      players: 2,
      authority: 'MLE',
      state: 'AVAILABLE'
    }
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
    lifecycleHardening: 'PASS',
    postHardeningCausalSoak: 'PASS',
    calibratedProcessMemory: 'PASS',
    browserConfirmedOnly: 'PASS',
    soloMleAuthority: 'PASS',
    warmPoolAdmissionP95: 'PASS',
    warmStandbyHealing: 'PASS',
    resourceCapDecision: 'PASS'
  },
  soak: {
    artifactSha256: authority.outputSha256,
    warmupSecondsExcluded: 300,
    scoredSeconds: 1800,
    maxConfirmedLagTics: 17,
    reconnects: 0,
    browserPresentations: [58875, 58858],
    browserAdvancedTics: [59255, 59256],
    browserResyncs: [20, 21],
    browserPaintP999MaximumMs: [2169.1, 2371.1],
    authorityPssBaselineBytes: 326010880,
    authorityPssMaximumBytes: 376375296,
    authorityPssEndBytes: 300486656,
    authorityPrivateBaselineBytes: 237096960,
    authorityPrivateMaximumBytes: 288854016,
    authorityPrivateEndBytes: 221904896,
    standbyPssBaselineBytes: 231512064,
    standbyPssMaximumBytes: 238575616,
    standbyPssEndBytes: 238160896,
    standbyPrivateBaselineBytes: 172462080,
    standbyPrivateMaximumBytes: 172544000,
    standbyPrivateEndBytes: 172335104,
    processMemoryMarginBytes: 67108864,
    ashSamples: 1457,
    resourceManagerCpuQuantumSamples: 0,
    promotedAttemptState: 'VOIDED',
    promotedAttemptReason: 'legacy cleanup stop/lifecycle ownership race',
    postDietPartialAuthorityPssMinimumBytes: 262067200,
    postDietPartialAuthorityPssMaximumBytes: 311932928,
    postDietPartialPlateauProven: false,
    causalSoakScoredSeconds: 180,
    causalSoakPresentations: [6286, 6287],
    causalSoakReconnects: 0,
    causalSoakStableSpids: true
  },
  capacity: {
    effectivePdbCpu: 1,
    runningSessions: 2,
    heldPollLeaseLimit: 4,
    guaranteedConcurrentPollReturns: 1,
    localLongPollingDefault: false
  },
  solo: {
    coldStartBaselineSeconds: 248.629,
    coldAuthorityAdmissionSeconds: 100.314,
    warmAdmissionP50Seconds: 3.100,
    warmAdmissionP95Seconds: 3.440,
    warmAdmissionMaximumSeconds: 3.440,
    warmAdmissionSamples: 10,
    warmAdmissionTargetSeconds: 5,
    warmCheckpointBankEntries: 10,
    warmCheckpointScope: 'E1M1; COOP/DEATHMATCH; skills 1-5',
    admissionReductionFromColdPercent: 96.57,
    measuredFps: 34.5,
    legacyEndpointCalls: 0,
    headlessAuthorityColdInitP50Seconds: 4.684,
    concurrentTwoSlotDeployReadySeconds: 34.669,
    sequentialAuthorityFirstAdmittableSeconds: 28,
    sequentialAuthorityThenStandbyReadySeconds: 55,
    promotedWarmAdmissionSeconds: 4.341,
    newGameToFirstConfirmedFrameSeconds: 5.223,
    startupOptimization:
      'deploy-time retained MLE pool, exact tic-zero restore, and headless init diet',
    recoveryStatusOutput: 'ABSENT/WARMING/READY/PROMOTING/DEGRADED',
    standbyHealing: 'WARMING to READY live gate PASS',
    ordsPoolFix: 'single outstanding status poll; cold initialization holds no match-row lock',
    note: 'cold work is paid at deployment; 100.314 seconds is the no-pool authority baseline'
  },
  remaining: [
    {id: 'SOAK', state: 'PASS',
      label: '30-minute final promoted-artifact soak'},
    {id: 'WAN', state: 'NEXT', label: 'Injected-latency multiplayer matrix'},
    {id: 'JAVA-AUDIT', state: 'NEXT',
      label: 'Production-path Java removal audit'},
    {id: 'DVR', state: 'OPEN',
      label: 'HUD, automap, intermission, finale and audit/DVR presentation'},
    {id: 'ADB', state: 'DORMANT',
      label: 'Autonomous MLE performance probe; credentials required'}
  ],
  evidence: {
    soak: soakPath, ledger: ledgerPath, solo: soloPath,
    soloAdmission: soloAdmissionPath, warmPoolAdmission: warmPoolPath,
    initDietPromotion: initDietPath, voidedPromotedSoak: voidedSoakPath,
    voidedDiagnosticSmoke: voidedSmokePath, lifecycleHardening: lifecyclePath,
    causalSoak: causalSoakPath, finalPromotedSoak: finalPromotedSoakPath,
    browserReplicaProfile: browserProfilePath
  }
};

const serialized = `${JSON.stringify(status, null, 2)}\n`;
for (const relative of ['client/staging/mle-status.json', 'client/dist/mle-status.json']) {
  fs.writeFileSync(path.join(root, relative), serialized, {mode: 0o644});
}
process.stdout.write(`PASS MLE-DASHBOARD-STATUS authority=${authority.outputSha256}` +
  ` ledger=13272 soak=1800\n`);
