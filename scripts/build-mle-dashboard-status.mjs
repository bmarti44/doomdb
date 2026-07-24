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
  'artifacts/performance/pmle-ledger-every-tic/run-checkpoint-map-2026-07-24.log';
const canonicalPath =
  'artifacts/performance/pmle-differentials/' +
  'canonical-warm-restore-e485-2026-07-24.log';
const coopPath =
  'artifacts/performance/pmle-differentials/' +
  'coop-warm-restore-e485-2026-07-24.log';
const membershipPath =
  'artifacts/performance/pmle-differentials/' +
  'membership-warm-restore-e485-2026-07-24.log';
const warmRestorePath =
  'artifacts/performance/pmle-warm-restore-ab/REPORT.md';
const highAwakeRecoveryPath =
  'artifacts/performance/pmle-worker-soak/' +
  'high-awake-recovery-fixed128-e485-v7-2026-07-24.log';
const warmSlotRecyclePath =
  'artifacts/performance/pmle-worker-soak/' +
  'warm-slot-recycle-state-e485-2026-07-24.log';
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
const livePerformancePath =
  'artifacts/performance/pmle-live-tic/matrix-parked-gate-2026-07-23.log';
const componentAbPath =
  'artifacts/performance/pmle-ledger-every-tic/component-ab-2026-07-24/REPORT.md';
const soak = read(soakPath);
const ledger = read(ledgerPath);
const canonical = read(canonicalPath);
const coop = read(coopPath);
const membership = read(membershipPath);
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
const livePerformance = read(livePerformancePath);
const componentAb = read(componentAbPath);
const warmRestore = read(warmRestorePath);
const highAwakeRecovery = read(highAwakeRecoveryPath);
const warmSlotRecycle = read(warmSlotRecyclePath);
const authority = versions.teaVM;
const presentation = authority.presentation;
const ledgerAuthority = {
  bytes: 1170639,
  sha256: '103e15e913b3a8f9a84497af601666fde5f47a720ac4b22fd7843db2559b665e'
};
const lastSoakedAuthority = {
  bytes: 1167197,
  sha256: 'a942cd2dcbdc8fa523a51af27aefc778ea9fbbebfe93f0a03fe4856c6df6c8e2'
};

contains(soak, 'PMLE_ARTIFACT|source_bytes=1163182|' +
  'source_sha256=06ac33331d9a9158d63fba2da4688ad5d3ff30c316b4c20c09e38d77d3fdebf0',
  'superseded soak artifact');
contains(soak, 'PASS P13.5-MULTIPLAYER-SOAK seconds=1800 warmupSeconds=300',
  'browser soak');
contains(soak, 'PMLE_WORKER_SOAK_MEMORY|PASS|role=AUTHORITY', 'authority memory');
contains(soak, 'PMLE_WORKER_SOAK_MEMORY|PASS|role=STANDBY', 'standby memory');
contains(soak, 'PMLE_WORKER_SOAK|PASS|duration_s=1800|warmup_s=300',
  'worker soak');
contains(ledger, `PMLE_PINNED_PAIR|authority_sha256=${ledgerAuthority.sha256}` +
  `|table_sha256=058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44` +
  `|ojvm_jar_sha256=${authority.canonicalOracleJarSha256}`, 'ledger pinned pair');
contains(ledger,
  `PMLE_ARTIFACT|source_bytes=${ledgerAuthority.bytes}` +
  `|source_sha256=${ledgerAuthority.sha256}`,
  'ledger authority artifact');
contains(ledger,
  'PMLE_TEAVM_LEDGER_DIFFERENTIAL|PASS|tics=13272|deep_every=1',
  'ledger every-tic');
contains(ledger,
  'PMLE_LEDGER_PROVENANCE|CONFIRMED|executions=1|terminal_markers=1',
  'ledger provenance');
contains(initDiet,
  `PMLE_INIT_DIET_ARTIFACT|authority_bytes=${lastSoakedAuthority.bytes}` +
  `|authority_sha256=${lastSoakedAuthority.sha256}`,
  'historical init-diet promoted artifact');
for (const [evidence, marker, label] of [
  [canonical, 'PMLE_TEAVM_MULTIPLAYER|PASS|players=4|tics=330',
    'candidate canonical 330'],
  [coop, 'PMLE_TEAVM_COOP_DIFFERENTIAL|PASS|players=2|skill=1|tics=762|deep_every=1',
    'candidate co-op 762'],
  [membership,
    'PMLE_TEAVM_MEMBERSHIP_RECOVERY_DIFFERENTIAL|PASS|players=2',
    'candidate membership recovery']
]) {
  contains(evidence,
    `PMLE_ARTIFACT|source_bytes=${authority.outputBytes}` +
    `|source_sha256=${authority.outputSha256}`,
    `${label} artifact`);
  contains(evidence, marker, label);
}
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
  `PMLE_ARTIFACT|source_bytes=${lastSoakedAuthority.bytes}` +
  `|source_sha256=${lastSoakedAuthority.sha256}` +
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
contains(livePerformance,
  'PMLE_LIVE_MATRIX|scenario=DM2_AUTHORITY_EXACT|tics=500|' +
  'p50_ms=244.672|p95_ms=374.710|p99_ms=443.837|max_ms=508.120|' +
  'throughput_tps=3.961|session_cpu_ms=126800|' +
  'session_cpu_ms_per_tic=253.600',
  'production-shaped MLE performance');
contains(componentAb,
  'Status: **PASS — `103e…` promoted under the five-percent ticker parity rule**',
  'current authority component A/B verdict');
contains(componentAb,
  'ae3c44e8937729a4fed42f4acb09c84121cdc964582d154cb3c978750bbaa22b',
  'current authority component A/B canonical digest');
contains(warmRestore,
  '18.377x', 'e485 direct MLE warm-restore A/B');
contains(highAwakeRecovery,
  'PMLE_HIGH_AWAKE_RECOVERY|PASS|probe_tic=512|checkpoint_tic=512|' +
  'frontier=639|distance=127|awake=20',
  'e485 maximum-distance recovery');
contains(highAwakeRecovery,
  'estimated_total_ms=57337|phase_budget_45s=PASS|sla_60s=PASS',
  'e485 recovery SLA');
contains(warmSlotRecycle,
  'PMLE_WARM_SLOT_RECYCLE|PASS|slot=1|status=READY|assigned=NONE|error=NONE',
  'e485 retained-slot recycle');

const status = {
  schema: 1,
  updated: '2026-07-24',
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
    presentationHud96Tics: 'PASS',
    canonical330: 'PASS',
    coopEveryTic762: 'PASS',
    membershipRecovery: 'PASS',
    ledgerEveryTic13272: 'HISTORICAL_PASS_103E',
    warmRestoreDirectMleAb: 'PASS',
    highAwakeMaximumDistanceRecovery: 'PASS',
    warmSlotRecycle: 'PASS',
    componentTickerParity500: 'PASS',
    finalWorkerSoak: 'PENDING_RERUN',
    lifecycleHardening: 'PENDING_RERUN',
    postHardeningCausalSoak: 'HISTORICAL_PASS',
    calibratedProcessMemory: 'PASS',
    browserConfirmedOnly: 'PASS',
    soloMleAuthority: 'PASS',
    warmPoolAdmissionP95: 'PENDING_RERUN',
    warmStandbyHealing: 'PENDING_RERUN',
    resourceCapDecision: 'PASS'
  },
  soak: {
    qualification: 'LAST_FULLY_SOAKED_SUPERSEDED_ARTIFACT',
    artifactSha256: lastSoakedAuthority.sha256,
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
    measuredFps: null,
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
  performance: {
    state: 'BELOW_30_FPS_ACCELERATION_IN_PROGRESS',
    evidenceArtifactSha256: lastSoakedAuthority.sha256,
    workload: 'two-player deathmatch authoritative exact command stream',
    tics: 500,
    throughputTicsPerSecond: 3.961,
    sessionCpuMillisecondsPerTic: 253.600,
    p50MillisecondsPerTic: 244.672,
    p95MillisecondsPerTic: 374.710,
    peakCombatMillisecondsPerTic: 290.124,
    requiredTicsPerSecond: 35,
    targetFps: 30,
    note: 'No current evidence supports an unqualified 30 FPS claim on 26ai Free'
  },
  remaining: [
    {id: 'LIFECYCLE', state: 'NEXT',
      label: 'Admission and full lifecycle battery on e485 fixed-128'},
    {id: 'SOAK', state: 'PENDING',
      label: '30-minute final e485 promoted-artifact soak'},
    {id: 'WAN', state: 'PAUSED', label: 'Injected-latency multiplayer matrix'},
    {id: 'JAVA-AUDIT', state: 'PENDING',
      label: 'Production-path Java removal audit'},
    {id: 'DVR', state: 'OPEN',
      label: 'HUD, automap, intermission, finale and audit/DVR presentation'},
    {id: 'ADB', state: 'DORMANT',
      label: 'Autonomous MLE performance probe; credentials required'}
  ],
  evidence: {
    soak: soakPath, ledger: ledgerPath, canonical: canonicalPath,
    coop: coopPath, membership: membershipPath, solo: soloPath,
    soloAdmission: soloAdmissionPath, warmPoolAdmission: warmPoolPath,
    initDietPromotion: initDietPath, voidedPromotedSoak: voidedSoakPath,
    voidedDiagnosticSmoke: voidedSmokePath, lifecycleHardening: lifecyclePath,
    causalSoak: causalSoakPath, finalPromotedSoak: finalPromotedSoakPath,
    browserReplicaProfile: browserProfilePath,
    livePerformance: livePerformancePath,
    componentTickerParity: componentAbPath,
    warmRestore: warmRestorePath,
    highAwakeRecovery: highAwakeRecoveryPath,
    warmSlotRecycle: warmSlotRecyclePath
  }
};

const serialized = `${JSON.stringify(status, null, 2)}\n`;
for (const relative of ['client/staging/mle-status.json', 'client/dist/mle-status.json']) {
  fs.writeFileSync(path.join(root, relative), serialized, {mode: 0o644});
}
process.stdout.write(`PASS MLE-DASHBOARD-STATUS authority=${authority.outputSha256}` +
  ` ledger=13272 soak=1800\n`);
