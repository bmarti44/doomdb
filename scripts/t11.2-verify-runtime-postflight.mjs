#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {normalizeDbOutput} from './lib/db-output.mjs';

const [logPath,matchSha256,firstTicText,lastTicText,versionsPath,outputPath] =
  process.argv.slice(2);
assert.ok(outputPath,
  'usage: t11.2-verify-runtime-postflight.mjs LOG MATCH_SHA FIRST_TIC LAST_TIC VERSIONS OUTPUT');
assert.match(matchSha256,/^[0-9a-f]{64}$/);
const firstTic=Number(firstTicText),lastTic=Number(lastTicText);
assert.ok(Number.isInteger(firstTic)&&firstTic>=0);
assert.ok(Number.isInteger(lastTic)
  &&lastTic-firstTic>=299&&lastTic-firstTic<=359);
const versions=JSON.parse(fs.readFileSync(versionsPath,'utf8'));
const live=versions.teaVM?.liveFrameRenderer;
assert.ok(live,'live-frame provenance is absent');
const deployedRendererSha256=live.deployedOutputSha256??live.outputSha256;
const deployedCoordinatorSha256=
  live.deployedCoordinatorSha256??live.coordinatorSha256;
assert.match(deployedRendererSha256,/^[0-9a-f]{64}$/);
assert.match(deployedCoordinatorSha256,/^[0-9a-f]{64}$/);

const normalized=normalizeDbOutput(fs.readFileSync(logPath,'utf8'));
const markers=normalized.filter(line=>
  line.startsWith('T112_RUNTIME|'));
assert.equal(markers.length,1,'exactly one T112 runtime marker is required');
const fields=Object.fromEntries(markers[0].split('|').slice(1).map(field=>{
  const split=field.indexOf('=');
  assert.ok(split>0,`invalid runtime marker field: ${field}`);
  return [field.slice(0,split),field.slice(split+1)];
}));
for(const field of ['match_sha256','authority_sha256','renderer_sha256',
  'coordinator_sha256'])
  assert.match(fields[field]??'',/^[0-9a-f]{64}$/,field);
assert.equal(fields.match_sha256,matchSha256);
assert.equal(fields.authority_sha256,live.authorityCandidateSha256);
assert.equal(fields.renderer_sha256,deployedRendererSha256);
assert.equal(fields.coordinator_sha256,deployedCoordinatorSha256);

const integer=name=>{
  const value=Number(fields[name]);
  assert.ok(Number.isInteger(value)&&value>=0,name);
  return value;
};
const decimal=name=>{
  const value=Number(fields[name]);
  assert.ok(Number.isFinite(value)&&value>=0,name);
  return value;
};
const currentTic=integer('current_tic');
const checkpointCount=integer('checkpoint_count');
const checkpointUnmeasuredCount=integer('checkpoint_unmeasured_count');
const checkpointSlowCount=integer('checkpoint_slow_count');
const checkpointMaxStepMs=decimal('checkpoint_max_step_ms');
const checkpointMaxSaveMs=decimal('checkpoint_max_save_ms');
const checkpointMaxPublishMs=decimal('checkpoint_max_publish_ms');
const checkpointMaxStageMs=decimal('checkpoint_max_stage_ms');
const backgroundCheckpointTailGateMs=250;
assert.ok(currentTic>=lastTic,'database frontier trails browser evidence');
// The 300-frame browser score is intentionally shorter than the 512-tic
// recovery interval, so ordinary play is not forced through a serializer
// tail. It can cross at most one boundary depending on its starting offset.
// The separate maximum-distance recovery and checkpoint-crossing gates own
// cadence/recovery evidence; a checkpoint that does land here must still meet
// every timing and temporary-LOB assertion below.
assert.ok(checkpointCount<=1,'scored window crossed multiple checkpoint bounds');
assert.equal(checkpointUnmeasuredCount,0,
  'scored checkpoint timing was not recorded');
// DOOM_MATCH_SLOW_CALL is written for total steps above 100 ms. A checkpoint
// row there is therefore a direct release-gate failure even if client
// buffering happened to conceal it.
assert.equal(checkpointSlowCount,0,
  'post-commit checkpoint exceeded its Free-tier background bound');
assert.ok(checkpointMaxStepMs<=100);
assert.ok(checkpointMaxSaveMs<=backgroundCheckpointTailGateMs);
assert.ok(checkpointMaxPublishMs<=backgroundCheckpointTailGateMs);
// Checkpoint work runs after the authoritative tic and a partial framebuffer
// flush. Its wall bound permits one edition-enforced Resource Manager quantum
// above the measured ~94 ms serializer. The independent browser gate remains
// the unchanged <=100 ms authority for visible pauses.
assert.ok(checkpointMaxStageMs<=backgroundCheckpointTailGateMs);

const result={
  schema:1,result:'PASS',matchSha256,firstTic,lastTic,currentTic,
  checkpointCount,checkpointUnmeasuredCount,checkpointSlowCount,
  checkpointMaxStepMs,
  checkpointMaxSaveMs,checkpointMaxPublishMs,checkpointMaxStageMs,
  // Save/publication durations are recorded for every durable checkpoint.
  // Total step duration remains the sparse >100 ms slow-call backstop.
  checkpointTimingSource:'EXACT_STAGE_PLUS_SPARSE_GT_100MS_TOTAL',
  checkpointTailGateMs:backgroundCheckpointTailGateMs,
  browserPresentationTailGateMs:100,
  checkpointStageSemantics:'MAX_INDIVIDUAL_PREPARE_OR_EXPORT',
  authoritySha256:fields.authority_sha256,
  rendererSha256:fields.renderer_sha256,
  coordinatorSha256:fields.coordinator_sha256
};
fs.writeFileSync(outputPath,`${JSON.stringify(result)}\n`,{
  mode:0o600,flag:'wx'
});
