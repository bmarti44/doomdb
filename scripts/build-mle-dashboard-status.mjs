#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(new URL('..', import.meta.url).pathname);
const versions = JSON.parse(fs.readFileSync(path.join(root, 'versions.lock'), 'utf8'));
const authority = versions.teaVM;
const presentation = authority.presentation;
const deCpsAuthority = {
  bytes: 1081335,
  sha256: '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3'
};
const liveFrameAuthority = {
  bytes: 1181281,
  sha256: 'c613bb5106d6572d1023ae6caf9045f52d493005bc1be001326acd3826d8eae1'
};
const hudLiveFrameAuthority = {
  bytes: 1090790,
  sha256: '66dd235cde82a8b8fbcac88bb905912bacfd6ea40671d2808e5951ce290ce873'
};
const adbVenueEvidencePath =
  'artifacts/performance/pmle-adb-venue/adb-tier-probe-2026-07-25.log';
const ociReleaseVenueEvidencePath =
  'artifacts/performance/pmle-decps-rank/' +
  'oci-adb-release-venue-verdict-2026-07-26.md';
const ociHostedBrowserEvidencePath =
  'artifacts/performance/pmle-cloud/' +
  'oci-hosted-browser-verdict-2026-07-26.log';
const ociHostedBrowserFullEvidencePath =
  'artifacts/performance/pmle-cloud/' +
  't11.2-oci-hosted-post-push-reverify-2026-07-26.json';
const ociHostedBrowserScoringIncidentPath =
  'artifacts/performance/pmle-cloud/' +
  't11.2-moving-input-scoring-incident-2026-07-26.md';
const ociWaitFreeWanEvidencePath =
  'artifacts/performance/pmle-wan/' +
  'oci-wait-free-setpoint-depth6-qualification-v2-pass-2026-07-26.md';
const ociJavaRemovalEvidencePath =
  'artifacts/performance/pmle-cloud/' +
  'oci-exact-release-java-removal-2026-07-26.log';
const ociDeCpsPresentationEvidencePath =
  'artifacts/performance/pmle-presentation-decps/REPORT.md';
const ociDatabaseFrameEvidencePath =
  'artifacts/performance/pmle-database-frames/REPORT.md';
const ociWasm2jsPresentationCostEvidencePath =
  'artifacts/performance/pmle-database-frames/' +
  'wasm2js-presentation-cost-verdict-2026-07-26.md';
const ociPlainMleRasterFloorEvidencePath =
  'artifacts/performance/pmle-database-frames/' +
  'plain-mle-raster-floor-verdict-2026-07-26.md';
const ociDatabasePixelReleaseEvidencePath =
  'artifacts/performance/pmle-live-frame-authority/' +
  'oci-two-pov-native35-input20-standby5-terminal-2026-07-29-v37.log';
const ociHudDatabasePixelEvidencePath =
  'artifacts/performance/pmle-live-frame-hud-fix/' +
  'OCI-160X84-DEPLOYMENT.md';
const ociHudSoloPrimaryEvidencePath =
  'artifacts/performance/pmle-live-frame-hud-fix/' +
  'oci-160x84-phase-stagger-solo-browser-repeat-2026-07-29.json';
const ociHudSoloRepeatEvidencePath =
  'artifacts/performance/pmle-live-frame-hud-fix/' +
  'oci-160x84-phase-stagger-solo-browser-2026-07-29.json';
const ociHudSoloPostflightEvidencePath =
  'artifacts/performance/pmle-live-frame-hud-fix/' +
  'oci-160x84-phase-stagger-db-postflight-2026-07-29.log';
const ociFrameStageEvidencePath =
  'artifacts/performance/pmle-live-frame-stage-split/' +
  'oci-static-copy-observe-2026-07-29.log';
const ociBrowserCleanupEvidencePath =
  'artifacts/performance/pmle-live-frame-authority/' +
  'oci-session-cleanup-browser-native35-2026-07-29.log';
const ociDatabaseCleanupEvidencePath =
  'artifacts/performance/pmle-live-frame-authority/' +
  'oci-session-cleanup-live-native35-2026-07-29.log';
const ociActiveLeaveEvidencePath =
  'artifacts/performance/pmle-live-frame-authority/' +
  'oci-active-leave-native35-2026-07-29.log';
const deCpsPromoted = authority.outputSha256 === deCpsAuthority.sha256;
const hudLiveFramePromoted =
  authority.outputSha256 === hudLiveFrameAuthority.sha256;
const liveFramePromoted =
  authority.outputSha256 === liveFrameAuthority.sha256 ||
  hudLiveFramePromoted;
const deCpsPromotionPath =
  'artifacts/performance/pmle-decps-rank/' +
  'promotion-5ec18cbe-2026-07-25.log';
const deCpsPrePromotionPath =
  'artifacts/performance/pmle-decps-rank/REPORT.md';
const deCpsStatePath =
  'artifacts/performance/pmle-decps-rank/database-deployment-state.json';
const deCpsState = deCpsPromoted &&
    fs.existsSync(path.join(root, deCpsStatePath))
  ? JSON.parse(fs.readFileSync(path.join(root, deCpsStatePath), 'utf8'))
  : null;
if (deCpsState !== null) {
  assert.equal(deCpsState.schema, 1);
  assert.equal(deCpsState.authoritySha256, deCpsAuthority.sha256);
}
const deCpsDeploymentState = deCpsPromoted
  ? (deCpsState?.state ?? 'SOURCE_PINNED_DATABASE_DEPLOYMENT_PENDING')
  : 'DATABASE_DEPLOYED_LIFECYCLE_RERUN_PENDING';
const deCpsInterventionRequired =
  deCpsDeploymentState.startsWith('INTERVENTION_REQUIRED_');
const deCpsSourceEvidencePath = deCpsPromoted
  ? deCpsPromotionPath
  : deCpsPrePromotionPath;
const deCpsStateEvidencePath =
  deCpsState?.evidence ?? deCpsSourceEvidencePath;
if (deCpsPromoted && deCpsState === null) {
  const promotionEvidence = fs.readFileSync(
    path.join(root, deCpsSourceEvidencePath),
    'utf8',
  );
  const promotionBegin =
    'PMLE_DECPS_SOURCE_PROMOTION|BEGIN|bytes=1081335'
    + `|sha256=${deCpsAuthority.sha256}`;
  const promotionPass =
    'PMLE_DECPS_SOURCE_PROMOTION|PASS|bytes=1081335'
    + `|sha256=${deCpsAuthority.sha256}`;
  assert.equal(
    promotionEvidence.split(/\r?\n/).filter(
      line => line === promotionBegin,
    ).length,
    1,
    'source-pinned dashboard lacks exactly one promotion BEGIN',
  );
  if (process.env.PMLE_DECPS_SOURCE_PROMOTION_IN_PROGRESS !== 'YES') {
    assert.equal(
      promotionEvidence.split(/\r?\n/).filter(
        line => line === promotionPass,
      ).length,
      1,
      'source-pinned dashboard lacks exactly one completed promotion PASS',
    );
  }
}
const finalCapacityEvidence = () => {
  const lines = fs.readFileSync(
    path.join(root, deCpsStateEvidencePath),
    'utf8',
  ).split(/\r?\n/).filter(
    line => line.startsWith('PMLE_DECPS_DEPLOY_CAPACITY|'),
  );
  assert.ok(lines.length > 0, 'intervention state lacks capacity evidence');
  const line = lines.at(-1);
  const match = line.match(
    /^PMLE_DECPS_DEPLOY_CAPACITY\|(HELD_CLOSED|UNPROVEN)\|reason=([a-z0-9_]+)$/,
  );
  assert.ok(match, 'final intervention capacity evidence is malformed');
  assert.equal(deCpsState?.interventionReason, match[2],
    'dashboard intervention reason does not match final capacity evidence');
  return {kind: match[1], reason: match[2]};
};
if (deCpsPromoted && deCpsDeploymentState ===
    'DATABASE_DEPLOYED_LIFECYCLE_RERUN_PENDING') {
  const stateEvidence = fs.readFileSync(
    path.join(root, deCpsStateEvidencePath),
    'utf8',
  );
  assert.ok(stateEvidence.includes(
    `PMLE_DECPS_DEPLOY_DATABASE|READY|sha256=${deCpsAuthority.sha256}`),
  'database-deployed state lacks the database-ready marker');
} else if (deCpsPromoted && deCpsDeploymentState ===
    'INTERVENTION_REQUIRED_CAPACITY_HELD_CLOSED') {
  assert.equal(finalCapacityEvidence().kind, 'HELD_CLOSED',
    'intervention state lacks a final held-closed marker');
} else if (deCpsPromoted && deCpsDeploymentState ===
    'INTERVENTION_REQUIRED_CAPACITY_UNPROVEN') {
  assert.equal(finalCapacityEvidence().kind, 'UNPROVEN',
    'unproven-capacity intervention lacks a final uncertainty marker');
} else if (deCpsState !== null && deCpsDeploymentState ===
    'SOURCE_PINNED_DATABASE_DEPLOYMENT_PENDING') {
  assert.ok(fs.readFileSync(
    path.join(root, deCpsStateEvidencePath),
    'utf8',
  ).includes('PMLE_DECPS_DEPLOY_ROLLBACK|PASS|'),
  'source-pinned deployment state lacks a verified rollback');
} else if (deCpsPromoted && deCpsDeploymentState ===
    'DATABASE_DEPLOYED_LIFECYCLE_QUALIFIED') {
  assert.match(deCpsState?.evidenceCommit ?? '', /^[0-9a-f]{40}$/);
} else if (deCpsPromoted && deCpsState !== null) {
  throw new Error(`unsupported de-CPS deployment state: ${
    deCpsDeploymentState}`);
}
const deCpsDatabaseDeployed = [
  'DATABASE_DEPLOYED_LIFECYCLE_RERUN_PENDING',
  'DATABASE_DEPLOYED_LIFECYCLE_QUALIFIED',
].includes(deCpsDeploymentState);
const deCpsLifecycleQualified =
  deCpsDeploymentState === 'DATABASE_DEPLOYED_LIFECYCLE_QUALIFIED';
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8');
const contains = (text, marker, label) =>
  assert.ok(text.includes(marker), `${label} marker missing: ${marker}`);

const soakPath =
  'artifacts/performance/pmle-worker-soak/run-final-checkpoint-reuse-v3.log';
const ledgerPath = liveFramePromoted
  ? 'artifacts/performance/pmle-ledger-every-tic/' +
    'run-live-frame-c613-2026-07-28.log'
  : deCpsPromoted
  ? 'artifacts/performance/pmle-ledger-every-tic/' +
    'run-decps-reproducible-5ec18cbe-2026-07-25.log'
  : 'artifacts/performance/pmle-ledger-every-tic/' +
    'run-checkpoint-map-2026-07-24.log';
const canonicalPath = 'artifacts/performance/pmle-differentials/' +
  (deCpsPromoted || liveFramePromoted
    ? 'canonical-decps-reproducible-5ec18cbe-2026-07-25.log'
    : 'canonical-warm-restore-e485-2026-07-24.log');
const coopPath = 'artifacts/performance/pmle-differentials/' +
  (liveFramePromoted
    ? 'coop-live-frame-c613-final-2026-07-28.log'
    : deCpsPromoted
    ? 'coop-decps-reproducible-5ec18cbe-2026-07-25.log'
    : 'coop-warm-restore-e485-2026-07-24.log');
const membershipPath = 'artifacts/performance/pmle-differentials/' +
  (liveFramePromoted
    ? 'membership-live-frame-c613-final-2026-07-28.log'
    : deCpsPromoted
    ? 'membership-decps-reproducible-5ec18cbe-2026-07-25.log'
    : 'membership-warm-restore-e485-2026-07-24.log');
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
const currentAdmissionPath =
  'artifacts/performance/pmle-browser-role-swap/' +
  'warm-pool-admission-decps-5ec18cbe-bank-yield100ms-2026-07-25.log';
const asyncAdmissionRacePath =
  'artifacts/performance/pmle-worker-lifecycle/' +
  'async-admission-races-decps-5ec18cbe-oci-ticker-pass-cleanup-v2-2026-07-25.log';
const currentWarmLifecyclePath =
  'artifacts/performance/pmle-worker-lifecycle/' +
  'run-decps-5ec18cbe-2026-07-25-v2.log';
const nodeProfilePath =
  'artifacts/performance/pmle-decps-rank/' +
  'node-decps-peak-5ec18cbe4cff-v3.log';
const mobjLowWordDecisionPath =
  'artifacts/performance/pmle-decps-rank/' +
  'mobj-low-word-decision-2026-07-25.md';
const asyncJitDecisionPath =
  'artifacts/performance/pmle-decps-rank/' +
  'async-jit-decision-2026-07-25.md';
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
const hiddenJitPath =
  'artifacts/performance/pmle-hidden-jit/REPORT.md';
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
const currentAdmission = read(currentAdmissionPath);
const asyncAdmissionRace = read(asyncAdmissionRacePath);
const currentWarmLifecycle = read(currentWarmLifecyclePath);
const nodeProfile = read(nodeProfilePath);
const causalSoak = read(causalSoakPath);
const finalPromotedSoak = read(finalPromotedSoakPath);
const browserProfile = read(browserProfilePath);
const livePerformance = read(livePerformancePath);
const componentAb = read(componentAbPath);
const hiddenJit = read(hiddenJitPath);
const ociReleaseVenue = read(ociReleaseVenueEvidencePath);
const ociHostedBrowser = read(ociHostedBrowserEvidencePath);
const ociWaitFreeWan = read(ociWaitFreeWanEvidencePath);
const ociJavaRemoval = read(ociJavaRemovalEvidencePath);
const ociHostedBrowserFull = JSON.parse(read(ociHostedBrowserFullEvidencePath));
const warmRestore = read(warmRestorePath);
const highAwakeRecovery = read(highAwakeRecoveryPath);
const warmSlotRecycle = read(warmSlotRecyclePath);
const ociDatabasePixelRelease = read(ociDatabasePixelReleaseEvidencePath);
const ociHudDatabasePixel = hudLiveFramePromoted
  ? read(ociHudDatabasePixelEvidencePath)
  : null;
const ociHudSoloPrimary = hudLiveFramePromoted
  ? JSON.parse(read(ociHudSoloPrimaryEvidencePath))
  : null;
const ociHudSoloRepeat = hudLiveFramePromoted
  ? JSON.parse(read(ociHudSoloRepeatEvidencePath))
  : null;
const ociHudSoloPostflight = hudLiveFramePromoted
  ? read(ociHudSoloPostflightEvidencePath)
  : null;
const ociFrameStage = hudLiveFramePromoted
  ? read(ociFrameStageEvidencePath)
  : null;
const ociBrowserCleanup = read(ociBrowserCleanupEvidencePath);
const ociDatabaseCleanup = read(ociDatabaseCleanupEvidencePath);
const ociActiveLeave = read(ociActiveLeaveEvidencePath);
const ledgerAuthority = liveFramePromoted
  ? liveFrameAuthority
  : deCpsPromoted ? deCpsAuthority : {
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
contains(ledger, `${deCpsPromoted || liveFramePromoted
  ? 'PMLE_CANDIDATE_PAIR|classification=UNPROMOTED_CANDIDATE'
  : 'PMLE_PINNED_PAIR'}|authority_sha256=${ledgerAuthority.sha256}` +
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
for (const [evidence, marker, label, expectedAuthority] of [
  [canonical, 'PMLE_TEAVM_MULTIPLAYER|PASS|players=4|tics=330',
    'candidate canonical 330',
    liveFramePromoted ? deCpsAuthority : authority],
  [coop, 'PMLE_TEAVM_COOP_DIFFERENTIAL|PASS|players=2|skill=1|tics=762|deep_every=1',
    'candidate co-op 762',
    hudLiveFramePromoted ? liveFrameAuthority : authority],
  [membership,
    'PMLE_TEAVM_MEMBERSHIP_RECOVERY_DIFFERENTIAL|PASS|players=2',
    'candidate membership recovery',
    hudLiveFramePromoted ? liveFrameAuthority : authority]
]) {
  contains(evidence,
    `PMLE_ARTIFACT|source_bytes=${expectedAuthority.bytes ??
      expectedAuthority.outputBytes}` +
    `|source_sha256=${expectedAuthority.sha256 ??
      expectedAuthority.outputSha256}`,
    `${label} artifact`);
  contains(evidence, marker, label);
}
contains(ociDatabasePixelRelease,
  'PMLE_OCI_TWO_POV|PASS|frames_per_player=300|minimum_fps=30|' +
  'renderer=DATABASE_PIXELS',
  'OCI database-pixel release gate');
contains(ociDatabasePixelRelease,
  'PMLE_OCI_TWO_POV_EVALUATOR|PASS|p0_fps=34.182|' +
  'p0_p95_ms=33.000',
  'OCI database-pixel player zero cadence');
contains(ociDatabasePixelRelease,
  '|p1_fps=34.133|p1_p95_ms=32.800|',
  'OCI database-pixel player one cadence');
contains(ociDatabasePixelRelease,
  'PMLE_OCI_CHECKPOINT_CROSSING|PASS|checkpoint_tic=512|' +
  'windows=301-600/301-600',
  'OCI database-pixel checkpoint crossing');
if (hudLiveFramePromoted) {
  contains(ociHudDatabasePixel,
    'PMLE_OCI_SOLO_160X84_ARTIFACT|' +
    `authority_sha256=${hudLiveFrameAuthority.sha256}|` +
    `renderer_sha256=${authority.liveFrameRenderer.deployedOutputSha256}|` +
    `coordinator_sha256=${authority.liveFrameRenderer.deployedCoordinatorSha256}`,
    'OCI HUD database-pixel artifact attestation');
  contains(ociHudDatabasePixel,
    'PMLE_OCI_SOLO_160X84|PERFORMANCE_PASS|frames=300|' +
    'unique_frames=300|sequential_tics=true|fps=34.691|' +
    'p50_ms=28.200|p95_ms=32.100',
    'OCI HUD database-pixel solo performance pass');
  contains(ociHudDatabasePixel,
    'PMLE_OCI_SOLO_160X84_REPEAT|DIAGNOSTIC_NOT_GATE|' +
    'frames=300|unique_frames=300|sequential_tics=true|fps=34.752|' +
    'p50_ms=28.200|p95_ms=32.100|p99_ms=33.100|max_ms=63.400',
    'OCI HUD database-pixel repeat venue tail');
  assert.deepEqual(
    {
      frames: ociHudSoloPrimary.performance.frames,
      uniqueFrames: ociHudSoloPrimary.performance.uniqueFrames,
      sequentialTics: ociHudSoloPrimary.performance.sequentialTics,
      fps: Number(ociHudSoloPrimary.performance.fps.toFixed(3)),
      p95: Number(ociHudSoloPrimary.performance.p95IntervalMs.toFixed(3)),
      drops: ociHudSoloPrimary.performance.confirmedDropCount,
      starvations: ociHudSoloPrimary.performance.scoredPixelStarvations,
      resyncs: ociHudSoloPrimary.performance.scoredPixelResyncs,
      cleanup: ociHudSoloPrimary.cleanup.status,
    },
    {
      frames: 300, uniqueFrames: 300, sequentialTics: true,
      fps: 34.691, p95: 32.1, drops: 0, starvations: 0, resyncs: 0,
      cleanup: 200,
    },
    'OCI solo primary raw ledger drifted',
  );
  assert.deepEqual(
    {
      frames: ociHudSoloRepeat.performance.frames,
      uniqueFrames: ociHudSoloRepeat.performance.uniqueFrames,
      sequentialTics: ociHudSoloRepeat.performance.sequentialTics,
      fps: Number(ociHudSoloRepeat.performance.fps.toFixed(3)),
      p95: Number(ociHudSoloRepeat.performance.p95IntervalMs.toFixed(3)),
      maximum: Number(ociHudSoloRepeat.performance.maxIntervalMs.toFixed(3)),
      starvations: ociHudSoloRepeat.performance.scoredPixelStarvations,
      cleanup: ociHudSoloRepeat.cleanup.status,
    },
    {
      frames: 300, uniqueFrames: 300, sequentialTics: true,
      fps: 34.752, p95: 32.1, maximum: 63.4, starvations: 1,
      cleanup: 200,
    },
    'OCI solo repeat raw ledger drifted',
  );
  contains(ociHudSoloPostflight,
    `PMLE_160X84_SOURCE|authority_sha256=${hudLiveFrameAuthority.sha256}` +
    `|renderer_sha256=${authority.liveFrameRenderer.deployedOutputSha256}` +
    `|coordinator_sha256=${authority.liveFrameRenderer.deployedCoordinatorSha256}`,
    'OCI solo database source postflight');
  contains(ociHudSoloPostflight,
    'PMLE_160X84_ACTIVE_MATCHES|0', 'OCI solo active-match postflight');
  contains(ociHudSoloPostflight,
    'PMLE_160X84_READY_SLOTS|2', 'OCI solo ready-slot postflight');
  contains(ociHudSoloPostflight,
    'PMLE_160X84_NONREADY_SLOTS|0', 'OCI solo nonready-slot postflight');
  contains(ociFrameStage,
    'PMLE_TWO_POV_PRODUCER|DIAGNOSTIC_NOT_GATE|mode=OBSERVE_ONLY|' +
    'first_tic=264|last_tic=912|elapsed_ms=25213.249|fps=25.701',
    'OCI sustained two-POV producer');
  contains(ociFrameStage,
    'FRAME_STAGE_WINDOW|546|645|render_avg_ms=28.387|' +
    'render_max_ms=66.763|publish_avg_ms=1.996|publish_max_ms=2.625',
    'OCI render/publish stage split');
}
contains(ociBrowserCleanup,
  'PASS SESSION-CLEANUP-BROWSER',
  'browser refresh/close cleanup');
contains(ociDatabaseCleanup,
  'PASS SESSION-CLEANUP-LIVE abandoned active browser releases retained slot',
  'database abandoned-session cleanup');
contains(ociActiveLeave,
  'PASS P13.2-ACTIVE-LEAVE',
  'active leave and host release');
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
contains(currentAdmission,
  'PMLE_WARM_POOL_ADMISSION|PASS|metric=browser_ready_click_to_first_active|' +
  'poll_cadence_ms=100|samples=10|min_ms=4418|p50_ms=4599|' +
  'p95_ms=4906|max_ms=4906|target_p95_ms=5000',
  'current async admission');
contains(asyncAdmissionRace,
  'PMLE_ASYNC_ADMISSION_RACES|PASS|scenario_set=ALL|scenarios=4|' +
  'db_output_helper=self_tested',
  'current async-admission race battery');
contains(asyncAdmissionRace,
  'PMLE_ASYNC_ADMISSION_CLEANUP|PASS|ready_slots=2|busy_slots=0|' +
  'third_session_avoided=1',
  'current async-admission cleanup');
contains(asyncAdmissionRace,
  'PMLE_ALERT_WINDOW|PASS|label=DECPS_ASYNC_ADMISSION_RACES|' +
  'new_ora_incidents=0',
  'current async-admission alert window');
contains(ociReleaseVenue,
  'PMLE_OCI_RELEASE_VENUE|PASS|' +
  `authority_sha256=${deCpsAuthority.sha256}|route_tps_min=302.419|` +
  'slowest_peak_tps=140.845|digest_binding=FULL_CHAIN_PASS|' +
  'client_unique_fps=PENDING',
  'OCI release venue');
contains(ociReleaseVenue,
  'PMLE_OCI_PRESENTATION_PERSIST|DIAGNOSTIC_NOT_GATE|samples=300|' +
  'unique=300|locator_p95_ms=212.095|direct_p95_ms=214.009|' +
  'exact_30fps=FAIL',
  'OCI exact-frame persistence diagnostic');
contains(ociHostedBrowser,
  'T112_HOSTED_BROWSER_VERDICT|PASS|objects=24|frames=300|unique=300|' +
  'sequential=YES|fps=34.08028814518894|p50_ms=31|' +
  'p95_ms=32.80000019073486|p99_ms=33.5|max_ms=70.30000019073486|' +
  'frame_chain_sha256=cc2fed9d14adbbac3add9d8056030bfb573a99f05d9b3e55970774a06348de78|' +
  'evidence_sha256=12dd37b5aa32f83276010f8cb39d51d24341dee9ea356ffc87fc14d705b6d0e5',
  'OCI hosted browser release gate');
contains(ociWaitFreeWan,
  'Classification: `QUALIFICATION_PASS`',
  'OCI wait-free WAN classification');
contains(ociWaitFreeWan,
  'PMLE_WAN_MATRIX|PASS|profiles=3|duration=600|warmup=90|' +
  'classification=QUALIFICATION|transport_legs=2|' +
  'approval_sha256=c0257840d5ec12ea730e8da11d08589c85eef03d989fde6b0533b6da53b2463c',
  'OCI wait-free WAN terminal marker');
contains(ociJavaRemoval,
  'PMLE_OCI_JAVA_REMOVAL|PASS|java_objects=0|java_specs=0|' +
  'java_dependencies=0|legacy_objects=0|legacy_api=0|mle_modules=1|' +
  'mle_environments=1|mle_call_specs=25',
  'OCI production Java-removal audit');
assert.equal(ociHostedBrowserFull.result, 'PASS',
  'latest OCI hosted-browser evidence is not a PASS');
assert.equal(ociHostedBrowserFull.browser.performance.frames, 300);
assert.equal(ociHostedBrowserFull.browser.performance.uniqueFrames, 300);
assert.equal(ociHostedBrowserFull.browser.performance.sequentialTics, true);
assert.ok(ociHostedBrowserFull.browser.performance.fps >= 30,
  'latest OCI hosted-browser evidence missed 30 FPS');
contains(currentWarmLifecycle,
  'PMLE_WARM_LIFECYCLE|PASS|scenarios=5|pool_restored=1',
  'current warm-slot lifecycle battery');
contains(nodeProfile,
  `PMLE_DECPS_NODE_PROFILE|PASS|authority_sha256=${deCpsAuthority.sha256}`,
  'current de-CPS Node profile');
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
contains(hiddenJit,
  '373.169 ns/iteration', 'default interpreted arithmetic');
contains(hiddenJit,
  '2.792', 'synchronous compiled arithmetic');
contains(hiddenJit,
  'compilation hang', 'full-artifact JIT disposition');
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
  updated: '2026-07-29',
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
    livePresentation:
      'Complete 320x200 indexed frames generated by MLE and delivered through ORDS',
    browserRole:
      'Decompress database pixel batches, apply palette, and copy to canvas',
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
      profile: authority.profile,
      deploymentQualification: deCpsDeploymentState,
      deploymentInterventionReason:
        deCpsInterventionRequired ? deCpsState?.interventionReason : null
    },
    presentation: {
      bytes: presentation.outputBytes,
      sha256: presentation.outputSha256,
      profile: presentation.profile
    },
    liveFrameRenderer: {
      bytes: authority.liveFrameRenderer.outputBytes,
      sha256: authority.liveFrameRenderer.deployedOutputSha256,
      profile: authority.liveFrameRenderer.profile,
      coordinatorBytes: authority.liveFrameRenderer.coordinatorBytes,
      coordinatorSha256:
        authority.liveFrameRenderer.deployedCoordinatorSha256
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
    canonical330: liveFramePromoted
      ? 'HISTORICAL_PASS_5EC'
      : 'PASS',
    coopEveryTic762: hudLiveFramePromoted
      ? 'HISTORICAL_PASS_C613'
      : 'PASS',
    membershipRecovery: hudLiveFramePromoted
      ? 'HISTORICAL_PASS_C613'
      : 'PASS',
    ledgerEveryTic13272: hudLiveFramePromoted
      ? 'HISTORICAL_PASS_C613_NODE_5250_PARITY_CURRENT'
      : deCpsPromoted || liveFramePromoted
      ? 'PASS_CURRENT_AUTHORITY'
      : 'HISTORICAL_PASS_103E',
    databasePixelTwoPov300: hudLiveFramePromoted
      ? 'SOLO_160X84_PERFORMANCE_PASS_TWO_POV_30FPS_AVERAGE_P95_OPEN'
      : 'PASS',
    databasePixelCheckpointCrossing: hudLiveFramePromoted
      ? 'HISTORICAL_PASS_C613'
      : 'PASS',
    abandonedSessionCleanup: 'PASS',
    warmRestoreDirectMleAb: deCpsPromoted
      ? (deCpsLifecycleQualified
        ? 'PASS_CURRENT_AUTHORITY'
        : 'HISTORICAL_PASS_E485_PENDING_RERUN')
      : 'PASS',
    highAwakeMaximumDistanceRecovery: deCpsPromoted
      ? (deCpsLifecycleQualified
        ? 'PASS_CURRENT_AUTHORITY'
        : 'HISTORICAL_PASS_E485_PENDING_RERUN')
      : 'PASS',
    warmSlotRecycle: deCpsPromoted
      ? (deCpsLifecycleQualified
        ? 'PASS_CURRENT_AUTHORITY'
        : 'HISTORICAL_PASS_E485_PENDING_RERUN')
      : 'PASS',
    componentTickerParity500: 'PASS',
    finalWorkerSoak: deCpsLifecycleQualified
      ? 'PASS_CURRENT_AUTHORITY'
      : 'PENDING_RERUN',
    lifecycleHardening: deCpsLifecycleQualified
      ? 'PASS_CURRENT_AUTHORITY'
      : 'PENDING_RERUN',
    asyncAdmissionRaces: hudLiveFramePromoted
      ? 'HISTORICAL_PASS_5EC'
      : 'PASS_CURRENT_AUTHORITY',
    warmSlotLifecycle: hudLiveFramePromoted
      ? 'HISTORICAL_PASS_5EC'
      : 'PASS_CURRENT_AUTHORITY',
    postHardeningCausalSoak: 'HISTORICAL_PASS',
    calibratedProcessMemory: 'PASS',
    browserConfirmedOnly: 'PASS',
    soloMleAuthority: 'PASS',
    warmPoolAdmissionP95: deCpsLifecycleQualified
      ? 'PASS_CURRENT_AUTHORITY'
      : 'PENDING_RERUN',
    warmStandbyHealing: deCpsLifecycleQualified
      ? 'PASS_CURRENT_AUTHORITY'
      : 'PENDING_RERUN',
    resourceCapDecision: 'PASS',
    databaseAuthorityDeployment: deCpsPromoted
      ? (deCpsInterventionRequired
        ? 'INTERVENTION_REQUIRED'
        : (deCpsDatabaseDeployed ? 'PASS' : 'PENDING'))
      : 'PASS'
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
  sessionCleanup: {
    browserRefreshReleaseMilliseconds: 1557,
    browserCloseReleaseMilliseconds: 321,
    terminalState: 'FINISHED',
    capacityReuse: 'PASS',
    abandonedLobby: 'PASS',
    abandonedActiveMatch: 'PASS',
    expiredCascadePurge: 'PASS',
    activeGuestLeaveNeutralSubstitution: 'PASS',
    hostFinishSlotRelease: 'PASS',
    evidence: [
      ociBrowserCleanupEvidencePath,
      ociDatabaseCleanupEvidencePath,
      ociActiveLeaveEvidencePath
    ]
  },
  solo: {
    coldStartBaselineSeconds: 248.629,
    coldAuthorityAdmissionSeconds: 100.314,
    warmAdmissionP50Seconds: 4.599,
    warmAdmissionP95Seconds: 4.906,
    warmAdmissionMaximumSeconds: 4.906,
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
    state: hudLiveFramePromoted
      ? 'DATABASE_RENDERER_DEPLOYED_SOLO_160X84_34_995FPS'
      : 'OCI_DATABASE_PIXELS_TWO_POV_30FPS_PASS',
    evidenceArtifactSha256: hudLiveFramePromoted
      ? hudLiveFrameAuthority.sha256
      : liveFrameAuthority.sha256,
    authorityTickerEvidenceArtifactSha256: deCpsAuthority.sha256,
    databasePixelRelease: {
      venue: 'OCI Autonomous Database Always Free 26ai',
      renderer: 'DATABASE_PIXELS',
      width: 320,
      height: 200,
      framesPerPlayer: 300,
      players: 2,
      fps: [34.182, 34.133],
      cadenceP95Milliseconds: [33.0, 32.8],
      cadenceP99Milliseconds: [41.7, 37.5],
      confirmedFrameDrops: [0, 0],
      checkpointTic: 512,
      checkpointCrossing: 'PASS',
      maximumPublicationGapMilliseconds: 62.666,
      authoritySha256: liveFrameAuthority.sha256,
      rendererSha256:
        '302d574ec500330b5fe08c55593ee8d61c81930e37d68ba6dc963c35f6b996c7',
      coordinatorSha256:
        '9e7d2e17d5d386d12498d65130387e14ee23d478ab794b8538677fa7b9163559',
      evidence: ociDatabasePixelReleaseEvidencePath
    },
    currentHudDeployment: hudLiveFramePromoted ? {
      authoritySha256: hudLiveFrameAuthority.sha256,
      rendererSha256:
        authority.liveFrameRenderer.deployedOutputSha256,
      coordinatorSha256:
        authority.liveFrameRenderer.deployedCoordinatorSha256,
      status: 'SOLO_160X84_PERFORMANCE_PASS_TWO_POV_30FPS_AVERAGE_P95_OPEN',
      productionShapeServerFps: 72.562,
      productionShapeServerP50Milliseconds: 13.145,
      productionShapeServerP95Milliseconds: 18.598,
      latestPublicSoloFps: 34.691,
      latestPublicSoloCadenceP95Milliseconds: 32.1,
      repeatPublicSoloFps: 34.752,
      repeatPublicSoloCadenceP95Milliseconds: 32.1,
      repeatPublicSoloMaximumIntervalMilliseconds: 63.4,
      repeatPublicSoloStarvations: 1,
      confirmedFrameDrops: [0, 0],
      currentTwoPovDiagnostic: {
        status: 'AVERAGE_30FPS_PASS_P95_OPEN',
        fps: [30.599, 30.536],
        cadenceP95Milliseconds: [47.7, 51.2],
        uniqueFrames: [300, 300],
        confirmedFrameDrops: [0, 0],
        coordinatorSha256:
          authority.liveFrameRenderer.deployedCoordinatorSha256,
        evidence: 'artifacts/performance/pmle-live-frame-hud-fix/' +
          'oci-160x84-two-pov-phase-stagger-2026-07-29.json'
      },
      evidence: [
        ociHudDatabasePixelEvidencePath,
        ociHudSoloPrimaryEvidencePath,
        ociHudSoloRepeatEvidencePath,
        ociHudSoloPostflightEvidencePath
      ],
      historicalTwoPovProducer: {
        profile: 'unified-160x56-live-frame',
        rendererSha256:
          'c60a34dd81d6e184be7262f494ff3070adb1ab2fb926ecaafedc4043b22cf93c',
        coordinatorSha256:
          '8f005189021ddf246ee154ce8fcf44a719dd6e571943e55ddc251d46e865cd50',
        sustainedFps: 25.701,
        renderAverageMillisecondsRange: [28.387, 29.559],
        publishAverageMillisecondsRange: [1.996, 2.136],
        evidence: ociFrameStageEvidencePath
      }
    } : null,
    workload: 'two-player deathmatch authoritative exact command stream',
    tics: 5250,
    throughputTicsPerSecond: 302.419,
    slowestPeakTicsPerSecond: 140.845,
    routePassTicsPerSecond: [317.029, 302.419],
    digestBinding: 'FULL_PER_TIC_CHAIN_PASS',
    cumulativeDigestSha256:
      '36b454b6eeda79e4f6869ba2b29eab4a885fd1970b972b7daad6ce5b692012ee',
    browserUniqueMovingFps:
      ociHostedBrowserFull.browser.performance.fps,
    browserUniqueMovingP95Milliseconds:
      ociHostedBrowserFull.browser.performance.p95IntervalMs,
    localDevelopmentThroughputTicsPerSecond: 19.788,
    localDevelopmentPeakCombatMillisecondsPerTic: '106-141',
    historicalPreDeCps: {
      artifactSha256: lastSoakedAuthority.sha256,
      throughputTicsPerSecond: 3.961,
      sessionCpuMillisecondsPerTic: 253.600,
      p50MillisecondsPerTic: 244.672,
      p95MillisecondsPerTic: 374.710
    },
    interpretedArithmeticNanosecondsPerIteration: 373.169,
    compiledArithmeticNanosecondsPerIteration: 2.792,
    compiledArithmeticThreshold: 'PASS_BELOW_15_NS',
    fullArtifactCompilation: 'DIAGNOSTIC_HANG_MLE_PARK',
    hiddenCompilationProductionEnabled: false,
    autonomousVenue: {
      provider: 'OCI',
      region: 'us-ashburn-1',
      database: 'doomdb-adb',
      tier: 'Always Free 26ai',
      arithmeticNanosecondsPerIteration: '171-189',
      gatherNanosecondsPerByte: 91,
      jitVerdict: 'CLOSED_ABOVE_100_NS',
      authorityTicker35Hz: 'PASS',
      authorityRouteMinimumTicsPerSecond: 302.419,
      authoritySlowestPeakTicsPerSecond: 140.845,
      liveExactDatabaseRendering:
        'CLOSED_CURRENT_SHAPES_SPECIALIZED_COSTING_PENDING',
      exactFramePersistenceP95Milliseconds: 212.095,
      databaseFrameStageSeparatedDiagnostic: {
        classification: 'DIAGNOSTIC_NOT_GATE',
        artifactSha256:
          '118c37717b362d9e7669b5a3a1e73c87b3916479b6e53651f08e85be9ae8f2d3',
        samples: 300,
        uniqueFrames: 300,
        exactFrameChain: 'PASS',
        authorityStepP95Milliseconds: 10.022,
        rasterP95Milliseconds: 207.488,
        rawEgressP95Milliseconds: 9.287,
        boundedRingPublishP95Milliseconds: 2.694,
        pipelineP95Milliseconds: 222.569,
        pipelineFramesPerSecondAtP95: 4.493,
        databaseRaster30Fps: 'FAIL',
        evidence: ociDatabaseFrameEvidencePath
      },
      wasm2jsPresentationCostDiagnostic: {
        classification: 'DIAGNOSTIC_NOT_GATE',
        tier: 'PRESENTATION_DIAGNOSTIC_ONLY',
        verdict: 'DVR_ONLY_ON_COST',
        artifactSha256:
          '8f740a68a8eac249a9cbe8afcedf98e63d165e8d88b99c7e7f70893e59e01610',
        artifactBytes: 14435019,
        rasterLowerBoundP50Milliseconds: 133.341,
        rasterLowerBoundP95Milliseconds: 140.960,
        pureMleJsP95Milliseconds: 21.478,
        wasm2jsRelativeSpeed: 0.152,
        moduleCreateMilliseconds: 3651.713,
        firstCallMilliseconds: 2402.216,
        linearMemoryBytes: 72876032,
        evidence: ociWasm2jsPresentationCostEvidencePath
      },
      plainMleRasterFloorDiagnostic: {
        classification: 'DIAGNOSTIC_NOT_GATE',
        verdict: 'PLAUSIBLE_COSTING_ONLY',
        pixels: 64000,
        effectivePasses: 3,
        interpretedFullKernelP95Milliseconds: 21.232,
        interpretedFullKernelP95NanosecondsPerPixel: 331.750,
        normalizedPassP95Milliseconds: 7.077,
        normalizedPassP95NanosecondsPerPixel: 110.583,
        compiledNanosecondsPerPixel: 'UNAVAILABLE_PRIVILEGE',
        exactRendererToControlRatio: 9.66,
        specializedRenderer: 'NOT_STARTED',
        evidence: ociPlainMleRasterFloorEvidencePath
      },
      deCpsPresentationDiagnostic: {
        classification: 'DIAGNOSTIC_NOT_GATE',
        artifactSha256:
          '118c37717b362d9e7669b5a3a1e73c87b3916479b6e53651f08e85be9ae8f2d3',
        samples: 100,
        uniqueFrames: 100,
        exactNodeFrameChain: 'PASS',
        pipelineP95Milliseconds: 191.276,
        exact30Fps: 'FAIL',
        temporaryLobsDelta: 2,
        locatorHygiene: 'FAIL',
        frame300: 'NOT_RUN_100_FRAME_MISS',
        evidence:
          'artifacts/performance/pmle-presentation-decps/REPORT.md'
      },
      note: 'authority, database-hosted browser, complete WAN qualification, and production Java-removal audit pass',
      evidence: ociReleaseVenueEvidencePath
    },
    deCpsCandidate: {
      promotionState: deCpsPromoted
        ? (deCpsDeploymentState ===
            'SOURCE_PINNED_DATABASE_DEPLOYMENT_PENDING'
          ? 'PROMOTED_SOURCE_DATABASE_DEPLOYMENT_PENDING'
          : (deCpsInterventionRequired
            ? `PROMOTED_${deCpsDeploymentState}`
            : (deCpsLifecycleQualified
              ? 'PROMOTED_LIFECYCLE_QUALIFIED_PEAK_ACCELERATION_ACTIVE'
              : 'PROMOTED_RECOVERY_LIFECYCLE_SOAK_PENDING')))
        : 'LEDGER_RECOVERY_LIFECYCLE_SOAK_PENDING',
      artifactSha256:
        '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3',
      artifactBytes: 1081335,
      performanceMeasurementArtifactSha256:
        '2848ef7a8dc4799de7faa46bcf304f4ac3d351da97be94b144a53f3300607f29',
      finalArtifactRankState: 'PASS_WITHIN_5_PERCENT',
      exactStreamTics: 5250,
      canonicalCheckpoints: 5251,
      canonicalParity: 'PASS',
      canonical330: 'PASS',
      coopEveryTic762: 'PASS',
      membershipRecovery100: 'PASS',
      ledgerEveryTic13272: deCpsPromoted ? 'PASS' : 'PENDING',
      throughputTicsPerSecond: 19.788,
      p50MillisecondsPerTic: 36.640,
      p95MillisecondsPerTic: 142.665,
      p99MillisecondsPerTic: 196.411,
      maximumMillisecondsPerTic: 376.974,
      comparableBaselineTicsPerSecond: 6.002,
      routeSpeedup: 3.297,
      quietWindowMillisecondsPerTic: '10-11',
      peakWindowMillisecondsPerTic: '106-141',
      hiddenImmediateCompilation: 'VOID_MLE_PARK_NO_TICKER',
      hiddenHotCompilation: 'VOID_MLE_PARK_NO_TICKER',
      nodeProfile: {
        state: 'PASS',
        sampledMilliseconds: 542.891,
        tickerSampledMilliseconds: 462.148,
        profilerControlMilliseconds: 80.743,
        sightBspPercent: 23.558,
        sightEligible: false,
        mobjFlagLongPercent: 14.042,
        activeStateDispatchPercent: 9.299,
        movementAiPercent: 8.368,
        selectedCategoriesAmdahlCeiling: 2.235,
        mobjLowWordCandidate: {
          state: 'REJECT_BELOW_5_PERCENT',
          p50ImprovementPercent: 1.035,
          p95ImprovementPercent: 4.122,
          throughputImprovementPercent: 2.707,
          peakMedianImprovementPercent: 1.401
        },
        defaultAsyncJit: {
          state: 'LANDING_SIGNAL_REPRODUCTION_PENDING',
          landingWindowThroughTic: 800,
          wallMedianImprovementPercent: 25.501,
          monotonicThroughputImprovementPercent: 41.079,
          clockExclusions: 4,
          clockSamples: 10500
        },
        nextMeasuredCandidate: 'DEFAULT_ASYNC_FRESH_SESSION_REPRODUCTION'
      },
      evidence: 'artifacts/performance/pmle-decps-rank/REPORT.md'
    },
    wasm2jsStatus: 'REJECT_BINARYEN_131_TIC0_LONG_HIGH_WORD_LOSS',
    wasm2jsEvidence:
      'artifacts/performance/pmle-wasm2js/REPORT.md',
    requiredTicsPerSecond: 35,
    targetFps: 30,
    wanQualification: {
      state: 'PASS',
      transport: 'WAIT_FREE_IMMEDIATE_BATCHING',
      transportLegs: 2,
      selectedPlayoutDepthTics: 6,
      profiles: ['50+/-10 ms', '100+/-20 ms', '200+/-40 ms'],
      scoredSecondsPerProfile: 600,
      warmupSecondsPerProfile: 90,
      cadenceP99Milliseconds: '34.5-36.2',
      occupancyMedianTics: '4-5',
      maximumNeutralSubstitutionPercent: 0.0710,
      mirrorPoisons: 0,
      presentationResyncs: 0,
      evidence: ociWaitFreeWanEvidencePath
    },
    productionJavaRemovalAudit: {
      state: 'PASS',
      javaObjects: 0,
      javaSpecs: 0,
      javaDependencies: 0,
      legacyApiObjects: 0,
      mleModules: 1,
      mleEnvironments: 1,
      mleCallSpecs: 25,
      evidence: ociJavaRemovalEvidencePath
    },
    note: hudLiveFramePromoted
      ? '160x84 OCI solo passes; current two-POV path clears 30 FPS average while its strict p95 cadence gate remains open'
      : 'OCI authority, confirmed browser presentation, WAN qualification, and Java-removal audit pass'
  },
  remaining: [
    {id: 'LIFECYCLE', state: deCpsLifecycleQualified ? 'DONE' : 'NEXT',
      label: deCpsPromoted
        ? (deCpsLifecycleQualified
          ? 'Admission and full lifecycle battery passed on de-CPS authority'
          : 'Recovery and final soak remain; async and warm-slot race batteries pass')
        : 'Admission and full lifecycle battery on e485 fixed-128'},
    {id: 'SHAPE', state: deCpsPromoted ? 'DONE' : 'ACTIVE',
      label: deCpsPromoted
        ? 'De-CPS authority promoted; OCI route and peak 35 Hz gates passed'
        : 'De-CPS candidate promotion battery and peak-combat acceleration'},
    {id: 'SOAK', state: deCpsLifecycleQualified ? 'DONE' : 'PENDING',
      label: deCpsLifecycleQualified
        ? '30-minute de-CPS promoted-artifact soak passed'
        : '30-minute promoted-artifact soak pending'},
    {id: 'WAN', state: 'DONE',
      label: 'Wait-free immediate batching passed all three 10-minute OCI WAN profiles'},
    {id: 'JAVA-AUDIT', state: 'DONE',
      label: 'Production Java-removal source and exact-release OCI catalog audits pass'},
    {id: 'DVR', state: 'OPEN',
      label: 'HUD, automap, intermission, finale and audit/DVR presentation'},
    {id: 'ADB', state: 'DONE',
      label: hudLiveFramePromoted
        ? 'Current 160x84 OCI solo passes; two-POV average clears 30 FPS and p95 remains open'
        : 'OCI authority 35 Hz, full digest chain, hosted statics, and browser 30 FPS passed'}
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
    hiddenJit: hiddenJitPath,
    warmRestore: warmRestorePath,
    highAwakeRecovery: highAwakeRecoveryPath,
    warmSlotRecycle: warmSlotRecyclePath,
    deCpsSourcePromotion: deCpsSourceEvidencePath,
    deCpsDatabaseDeployment: deCpsStateEvidencePath,
    autonomousVenue: adbVenueEvidencePath,
    currentAdmission: currentAdmissionPath,
    asyncAdmissionRaces: asyncAdmissionRacePath,
    currentWarmLifecycle: currentWarmLifecyclePath,
    deCpsNodeProfile: nodeProfilePath,
    mobjLowWordDecision: mobjLowWordDecisionPath,
    asyncJitDecision: asyncJitDecisionPath,
    ociReleaseVenue: ociReleaseVenueEvidencePath,
    ociHostedBrowser: ociHostedBrowserEvidencePath,
    ociHostedBrowserFullEvidence: ociHostedBrowserFullEvidencePath,
    ociHostedBrowserScoringIncident:
      ociHostedBrowserScoringIncidentPath,
    ociWaitFreeWanQualification: ociWaitFreeWanEvidencePath,
    ociJavaRemovalAudit: ociJavaRemovalEvidencePath,
    ociHudDatabasePixelRequalification:
      hudLiveFramePromoted ? ociHudDatabasePixelEvidencePath : null,
    ociHudSoloPrimary:
      hudLiveFramePromoted ? ociHudSoloPrimaryEvidencePath : null,
    ociHudSoloRepeat:
      hudLiveFramePromoted ? ociHudSoloRepeatEvidencePath : null,
    ociHudSoloPostflight:
      hudLiveFramePromoted ? ociHudSoloPostflightEvidencePath : null,
    ociFrameStageDecomposition:
      hudLiveFramePromoted ? ociFrameStageEvidencePath : null,
    ociDeCpsPresentationDiagnostic: ociDeCpsPresentationEvidencePath,
    ociDatabaseFrameDiagnostic: ociDatabaseFrameEvidencePath,
    ociWasm2jsPresentationCost: ociWasm2jsPresentationCostEvidencePath,
    ociPlainMleRasterFloor: ociPlainMleRasterFloorEvidencePath,
    deCpsDatabaseDeploymentState:
      deCpsState === null ? deCpsSourceEvidencePath : deCpsStatePath
  }
};

const serialized = `${JSON.stringify(status, null, 2)}\n`;
for (const relative of ['client/staging/mle-status.json', 'client/dist/mle-status.json']) {
  fs.writeFileSync(path.join(root, relative), serialized, {mode: 0o644});
}
process.stdout.write(`PASS MLE-DASHBOARD-STATUS authority=${authority.outputSha256}` +
  ` ledger=13272 soak=1800\n`);
