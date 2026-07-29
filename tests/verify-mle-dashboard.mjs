#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

const staging = fs.readFileSync('client/staging/index.html', 'utf8');
const dist = fs.readFileSync('client/dist/index.html', 'utf8');
const versions = JSON.parse(fs.readFileSync('versions.lock', 'utf8'));
assert.equal(dist, staging, 'published dashboard differs from staging source');
for (const marker of [
  'Oracle AI Database 26ai Free',
  'MLE authority',
  '/play/multiplayer.html',
  "fetch('/mle-status.json'",
  'OJVM oracle stays in repository/dev tooling only',
  'Cold MLE initialization now measures 4.542–4.826 seconds',
  'full browser reached its first confirmed frame in 5.223 seconds',
  'separate Co-op and Multiplayer shortcuts remain on the right',
  'single normal lifecycle writer',
  'explicitly VOIDED',
  '58,875/58,858 confirmed presentations',
  'three-profile WAN qualification',
  '50/100/200 ms profiles',
  'Presentation / DVR',
  'capacity held closed; operator intervention required',
  'capacity state unproven; operator intervention required',
  'id="performance-truth"',
  "data.gates.ledgerEveryTic13272==='PASS_CURRENT_AUTHORITY'",
  "const deCps=data.performance.deCpsCandidate",
  'two distinct player viewpoints',
  'id="authority-summary"',
  'id="determinism-truth"',
  'database pixels · browser framebuffer consumer',
  'no gate is inherited across an authority pin change'
]) {
  assert.ok(staging.includes(marker), `dashboard marker missing: ${marker}`);
}
for (const stale of [
  'new games use Mocha Doom in OJVM',
  'cloud certification next',
  'Current play page:</strong> new <code>/play/</code> games use Mocha Doom in OJVM',
  "document.querySelector('#ledger-state').textContent='PASS · 13,272'",
  '<h2>Final pinned authority</h2>',
  'full HUD + animated face · confirmed replica',
  '<strong id="ledger-state">PASS · 13,272</strong>',
  '<strong id="authority-artifact">e485b9418e58…</strong>'
]) {
  assert.ok(!staging.includes(stale), `stale dashboard claim survived: ${stale}`);
}
const status = JSON.parse(fs.readFileSync('client/dist/mle-status.json', 'utf8'));
const deCpsPromoted = versions.teaVM.outputSha256 ===
  '5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3';
const liveFramePromoted = versions.teaVM.outputSha256 ===
  'c613bb5106d6572d1023ae6caf9045f52d493005bc1be001326acd3826d8eae1';
const hudLiveFramePromoted = versions.teaVM.outputSha256 ===
  '66dd235cde82a8b8fbcac88bb905912bacfd6ea40671d2808e5951ce290ce873';
assert.equal(status.schema, 1);
assert.equal(status.artifacts.authority.sha256,
  versions.teaVM.outputSha256);
assert.equal(status.artifacts.presentation.sha256,
  'e55d5f1138fa94d4fc7efd0acf27cbc89cb8a894e3d6828d84837a364b4426dc');
assert.equal(status.gates.presentationHud96Tics, 'PASS');
assert.equal(status.gates.ledgerEveryTic13272,
  hudLiveFramePromoted
  ? 'HISTORICAL_PASS_C613_NODE_5250_PARITY_CURRENT'
  : deCpsPromoted || liveFramePromoted
  ? 'PASS_CURRENT_AUTHORITY'
  : 'HISTORICAL_PASS_103E');
if (!deCpsPromoted) {
  assert.equal(status.gates.databaseAuthorityDeployment, 'PASS');
  assert.equal(status.artifacts.authority.deploymentQualification,
    'DATABASE_DEPLOYED_LIFECYCLE_RERUN_PENDING');
} else if (status.gates.databaseAuthorityDeployment === 'PENDING') {
  assert.equal(status.artifacts.authority.deploymentQualification,
    'SOURCE_PINNED_DATABASE_DEPLOYMENT_PENDING');
} else if (status.gates.databaseAuthorityDeployment ===
    'INTERVENTION_REQUIRED') {
  assert.ok([
    'INTERVENTION_REQUIRED_CAPACITY_HELD_CLOSED',
    'INTERVENTION_REQUIRED_CAPACITY_UNPROVEN',
  ].includes(status.artifacts.authority.deploymentQualification));
  assert.match(
    status.artifacts.authority.deploymentInterventionReason,
    /^[a-z0-9_]+$/,
  );
} else {
  assert.equal(status.gates.databaseAuthorityDeployment, 'PASS');
  assert.ok([
    'DATABASE_DEPLOYED_LIFECYCLE_RERUN_PENDING',
    'DATABASE_DEPLOYED_LIFECYCLE_QUALIFIED',
  ].includes(status.artifacts.authority.deploymentQualification));
}
for (const gate of [
  'warmRestoreDirectMleAb',
  'highAwakeMaximumDistanceRecovery',
  'warmSlotRecycle',
]) {
  assert.equal(status.gates[gate], deCpsPromoted
    ? (status.artifacts.authority.deploymentQualification ===
        'DATABASE_DEPLOYED_LIFECYCLE_QUALIFIED'
      ? 'PASS_CURRENT_AUTHORITY'
      : 'HISTORICAL_PASS_E485_PENDING_RERUN')
    : 'PASS');
}
const lifecycleQualified = status.artifacts.authority.deploymentQualification ===
  'DATABASE_DEPLOYED_LIFECYCLE_QUALIFIED';
assert.equal(status.gates.finalWorkerSoak,
  lifecycleQualified ? 'PASS_CURRENT_AUTHORITY' : 'PENDING_RERUN');
assert.equal(status.gates.lifecycleHardening,
  lifecycleQualified ? 'PASS_CURRENT_AUTHORITY' : 'PENDING_RERUN');
assert.equal(status.gates.asyncAdmissionRaces,
  hudLiveFramePromoted ? 'HISTORICAL_PASS_5EC' : 'PASS_CURRENT_AUTHORITY');
assert.equal(status.gates.warmSlotLifecycle,
  hudLiveFramePromoted ? 'HISTORICAL_PASS_5EC' : 'PASS_CURRENT_AUTHORITY');
assert.equal(status.gates.postHardeningCausalSoak, 'HISTORICAL_PASS');
assert.equal(status.gates.soloMleAuthority, 'PASS');
assert.equal(status.gates.warmPoolAdmissionP95,
  lifecycleQualified ? 'PASS_CURRENT_AUTHORITY' : 'PENDING_RERUN');
assert.equal(status.gates.warmStandbyHealing,
  lifecycleQualified ? 'PASS_CURRENT_AUTHORITY' : 'PENDING_RERUN');
assert.equal(status.solo.legacyEndpointCalls, 0);
assert.equal(status.solo.startupOptimization,
  'deploy-time retained MLE pool, exact tic-zero restore, and headless init diet');
assert.equal(status.solo.warmAdmissionP95Seconds, 4.906);
assert.equal(status.solo.warmAdmissionSamples, 10);
assert.equal(status.solo.sequentialAuthorityFirstAdmittableSeconds, 28);
assert.equal(status.soak.promotedAttemptState, 'VOIDED');
assert.equal(status.soak.postDietPartialPlateauProven, false);
assert.deepEqual(status.soak.causalSoakPresentations, [6286, 6287]);
assert.equal(status.soak.artifactSha256,
  'a942cd2dcbdc8fa523a51af27aefc778ea9fbbebfe93f0a03fe4856c6df6c8e2');
assert.equal(status.soak.qualification,
  'LAST_FULLY_SOAKED_SUPERSEDED_ARTIFACT');
assert.deepEqual(status.soak.browserPresentations, [58875, 58858]);
assert.equal(status.soak.maxConfirmedLagTics, 17);
assert.equal(status.soak.resourceManagerCpuQuantumSamples, 0);
assert.equal(status.architecture.productionOjvm, false);
assert.equal(status.performance.state,
  hudLiveFramePromoted
    ? 'DATABASE_RENDERER_DEPLOYED_TWO_POV_SUSTAINED_25_701FPS_GATE_OPEN'
    : 'OCI_DATABASE_PIXELS_TWO_POV_30FPS_PASS');
assert.equal(status.performance.throughputTicsPerSecond, 302.419);
assert.equal(status.performance.slowestPeakTicsPerSecond, 140.845);
assert.equal(status.performance.digestBinding, 'FULL_PER_TIC_CHAIN_PASS');
assert.equal(
  status.performance.browserUniqueMovingFps,
  34.31929570761499);
assert.equal(
  status.performance.browserUniqueMovingP95Milliseconds,
  32.19999980926514);
assert.equal(status.performance.evidenceArtifactSha256,
  'c613bb5106d6572d1023ae6caf9045f52d493005bc1be001326acd3826d8eae1');
assert.equal(status.architecture.livePresentation,
  'Complete 320x200 indexed frames generated by MLE and delivered through ORDS');
assert.equal(status.artifacts.liveFrameRenderer.sha256,
  versions.teaVM.liveFrameRenderer.deployedOutputSha256);
assert.deepEqual(status.performance.databasePixelRelease.fps,
  [34.182, 34.133]);
assert.deepEqual(
  status.performance.databasePixelRelease.cadenceP95Milliseconds,
  [33, 32.8]);
assert.deepEqual(
  status.performance.databasePixelRelease.confirmedFrameDrops,
  [0, 0]);
assert.equal(status.performance.databasePixelRelease.checkpointCrossing,
  'PASS');
if (hudLiveFramePromoted) {
  assert.equal(status.gates.databasePixelTwoPov300,
    'DEPLOYED_SUSTAINED_PRODUCER_25_701FPS_30FPS_GATE_OPEN');
  assert.equal(
    status.performance.currentHudDeployment.sustainedNoPixelPollingProducerFps,
    25.701);
  assert.deepEqual(
    status.performance.currentHudDeployment.twoPovRenderAverageMillisecondsRange,
    [28.387, 29.559]);
  assert.deepEqual(
    status.performance.currentHudDeployment.twoPovPublishAverageMillisecondsRange,
    [1.996, 2.136]);
}
assert.equal(status.sessionCleanup.capacityReuse, 'PASS');
assert.equal(status.sessionCleanup.browserCloseReleaseMilliseconds, 321);
assert.equal(status.performance.wasm2jsStatus,
  'REJECT_BINARYEN_131_TIC0_LONG_HIGH_WORD_LOSS');
assert.equal(
  status.performance.historicalPreDeCps.sessionCpuMillisecondsPerTic,
  253.6);
assert.equal(status.performance.interpretedArithmeticNanosecondsPerIteration,
  373.169);
assert.equal(status.performance.compiledArithmeticNanosecondsPerIteration,
  2.792);
assert.equal(status.performance.compiledArithmeticThreshold, 'PASS_BELOW_15_NS');
assert.equal(status.performance.fullArtifactCompilation,
  'DIAGNOSTIC_HANG_MLE_PARK');
assert.equal(status.performance.hiddenCompilationProductionEnabled, false);
assert.equal(status.performance.autonomousVenue.authorityTicker35Hz, 'PASS');
assert.equal(
  status.performance.autonomousVenue.exactFramePersistenceP95Milliseconds,
  212.095);
assert.equal(status.performance.autonomousVenue.liveExactDatabaseRendering,
  'CLOSED_CURRENT_SHAPES_SPECIALIZED_COSTING_PENDING');
assert.equal(
  status.performance.autonomousVenue.databaseFrameStageSeparatedDiagnostic
    .rasterP95Milliseconds,
  207.488);
assert.equal(
  status.performance.autonomousVenue.databaseFrameStageSeparatedDiagnostic
    .rawEgressP95Milliseconds,
  9.287);
assert.equal(
  status.performance.autonomousVenue.wasm2jsPresentationCostDiagnostic
    .verdict,
  'DVR_ONLY_ON_COST');
assert.equal(
  status.performance.autonomousVenue.wasm2jsPresentationCostDiagnostic
    .rasterLowerBoundP95Milliseconds,
  140.960);
assert.equal(
  status.performance.autonomousVenue.wasm2jsPresentationCostDiagnostic
    .linearMemoryBytes,
  72876032);
assert.equal(
  status.performance.autonomousVenue.plainMleRasterFloorDiagnostic.verdict,
  'PLAUSIBLE_COSTING_ONLY');
assert.equal(
  status.performance.autonomousVenue.plainMleRasterFloorDiagnostic
    .normalizedPassP95Milliseconds,
  7.077);
assert.equal(
  status.performance.autonomousVenue.plainMleRasterFloorDiagnostic
    .compiledNanosecondsPerPixel,
  'UNAVAILABLE_PRIVILEGE');
assert.equal(
  status.performance.autonomousVenue.plainMleRasterFloorDiagnostic
    .specializedRenderer,
  'NOT_STARTED');
assert.equal(
  status.performance.autonomousVenue.deCpsPresentationDiagnostic
    .pipelineP95Milliseconds,
  191.276);
assert.equal(
  status.performance.autonomousVenue.deCpsPresentationDiagnostic
    .exactNodeFrameChain,
  'PASS');
assert.equal(
  status.performance.autonomousVenue.deCpsPresentationDiagnostic.exact30Fps,
  'FAIL');
assert.equal(
  status.performance.autonomousVenue.deCpsPresentationDiagnostic
    .locatorHygiene,
  'FAIL');
assert.equal(status.performance.deCpsCandidate.canonicalParity, 'PASS');
assert.equal(status.performance.deCpsCandidate.exactStreamTics, 5250);
assert.equal(status.performance.deCpsCandidate.throughputTicsPerSecond, 19.788);
assert.equal(status.performance.deCpsCandidate.routeSpeedup, 3.297);
assert.equal(status.performance.deCpsCandidate.finalArtifactRankState,
  'PASS_WITHIN_5_PERCENT');
assert.equal(status.performance.deCpsCandidate.nodeProfile.sightEligible, false);
assert.equal(status.performance.deCpsCandidate.nodeProfile.mobjFlagLongPercent,
  14.042);
assert.equal(status.performance.deCpsCandidate.promotionState,
  deCpsPromoted
    ? (status.gates.databaseAuthorityDeployment === 'PENDING'
      ? 'PROMOTED_SOURCE_DATABASE_DEPLOYMENT_PENDING'
      : (status.gates.databaseAuthorityDeployment === 'INTERVENTION_REQUIRED'
        ? `PROMOTED_${status.artifacts.authority.deploymentQualification}`
        : (lifecycleQualified
          ? 'PROMOTED_LIFECYCLE_QUALIFIED_PEAK_ACCELERATION_ACTIVE'
          : 'PROMOTED_RECOVERY_LIFECYCLE_SOAK_PENDING')))
    : 'LEDGER_RECOVERY_LIFECYCLE_SOAK_PENDING');
assert.equal(status.performance.deCpsCandidate.coopEveryTic762, 'PASS');
assert.equal(status.performance.deCpsCandidate.membershipRecovery100, 'PASS');
assert.equal(status.performance.deCpsCandidate.ledgerEveryTic13272,
  deCpsPromoted ? 'PASS' : 'PENDING');
assert.equal(status.remaining.find(item => item.id === 'SHAPE').state,
  deCpsPromoted ? 'DONE' : 'ACTIVE');
assert.equal(status.performance.requiredTicsPerSecond, 35);
assert.equal(status.solo.measuredFps, null);
assert.equal(status.playModes.singlePlayer.state, 'AVAILABLE');
assert.equal(status.playModes.coop.path, '/play/multiplayer.html#mode=COOP');
assert.equal(status.playModes.multiplayer.path,
  '/play/multiplayer.html#mode=DEATHMATCH');
assert.equal(status.remaining.find(item => item.id === 'ADB').state, 'DONE');
assert.equal(
  status.remaining.find(item => item.id === 'WAN').state,
  'DONE');
assert.equal(
  status.remaining.find(item => item.id === 'JAVA-AUDIT').state,
  'DONE');
assert.equal(status.performance.wanQualification.state, 'PASS');
assert.equal(
  status.performance.wanQualification.selectedPlayoutDepthTics,
  6);
assert.equal(
  status.performance.wanQualification.maximumNeutralSubstitutionPercent,
  0.071);
assert.equal(status.performance.productionJavaRemovalAudit.state, 'PASS');
assert.equal(status.performance.productionJavaRemovalAudit.javaObjects, 0);
for (const [name, relativePath] of Object.entries(status.evidence)) {
  assert.match(relativePath, /^[a-zA-Z0-9._/-]+$/,
    `dashboard evidence path is malformed: ${name}`);
  assert.ok(!relativePath.split('/').includes('..'),
    `dashboard evidence path escapes the repository: ${name}`);
  assert.ok(fs.existsSync(relativePath),
    `dashboard evidence path is missing: ${name}=${relativePath}`);
}
console.log('PASS MLE-DASHBOARD (current artifacts, evidence, links, and honesty gates)');
