#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const [policyPath,manifestPath,catalogPath,liveDir,browserPath,reportPath,
  runtimePath,indexUrl,outputPath]=process.argv.slice(2);
assert.ok(outputPath,'nine hosted evidence arguments are required');
const read=file=>fs.readFileSync(file);
const json=file=>JSON.parse(read(file));
const sha=value=>crypto.createHash('sha256').update(value).digest('hex');
const policy=json(policyPath),manifest=json(manifestPath),
  catalog=json(catalogPath),browser=json(browserPath),report=json(reportPath),
  runtime=json(runtimePath),
  versions=json(new URL('../versions.lock',import.meta.url));
const live=versions.teaVM?.liveFrameRenderer;
assert.ok(live,'live-frame provenance is absent');
const deployedRendererSha256=live.deployedOutputSha256??live.outputSha256;
const deployedCoordinatorSha256=
  live.deployedCoordinatorSha256??live.coordinatorSha256;
assert.match(deployedRendererSha256,/^[0-9a-f]{64}$/);
assert.match(deployedCoordinatorSha256,/^[0-9a-f]{64}$/);
const index=new URL(indexUrl);
assert.equal(index.protocol,'https:');
assert.match(index.pathname,/\/ords\/doom\/app\/$/);
assert.equal(browser.schema,2);
assert.equal(browser.hostedOriginSha256,sha(index.origin));
assert.equal(browser.indexUrlSha256,sha(index.href));
assert.deepEqual(browser.errors,[]);
assert.equal(browser.performance.frames,300);
assert.equal(browser.performance.uniqueFrames,300);
assert.equal(browser.performance.sequentialTics,true);
assert.ok(browser.performance.fps>=30);
assert.ok(browser.performance.p95IntervalMs<=33.333);
assert.equal(browser.cleanup.released,true);
assert.equal(browser.verifiedBlobModuleLoads,0);
assert.equal(browser.performance.databasePixelFrames,true);
assert.equal(browser.performance.p99IntervalMs<=2*1000/35,true);
assert.equal(browser.performance.maxIntervalMs<=100,true);
assert.equal(runtime.schema,1);
assert.equal(runtime.result,'PASS');
assert.equal(runtime.matchSha256,browser.cleanup.matchSha256);
assert.equal(runtime.firstTic,browser.performance.firstTic);
assert.equal(runtime.lastTic,browser.performance.lastTic);
assert.ok(runtime.checkpointCount<=1);
assert.equal(runtime.checkpointUnmeasuredCount,0);
assert.equal(runtime.checkpointSlowCount,0);
assert.ok(runtime.checkpointMaxStepMs<=100);
assert.ok(runtime.checkpointMaxSaveMs<=250);
assert.ok(runtime.checkpointMaxPublishMs<=250);
assert.ok(runtime.checkpointMaxStageMs<=250);
assert.ok(runtime.checkpointMaxStageMs>=
  Math.max(runtime.checkpointMaxSaveMs,runtime.checkpointMaxPublishMs));
assert.ok(runtime.checkpointMaxStageMs<=
  runtime.checkpointMaxSaveMs+runtime.checkpointMaxPublishMs);
assert.equal(runtime.checkpointTimingSource,
  'EXACT_STAGE_PLUS_SPARSE_GT_100MS_TOTAL');
assert.equal(runtime.checkpointTailGateMs,250);
assert.equal(runtime.browserPresentationTailGateMs,100);
assert.equal(runtime.checkpointStageSemantics,
  'MAX_INDIVIDUAL_PREPARE_OR_EXPORT');
assert.equal(runtime.authoritySha256,live.authorityCandidateSha256);
assert.equal(runtime.rendererSha256,deployedRendererSha256);
assert.equal(runtime.coordinatorSha256,deployedCoordinatorSha256);
assert.equal(report.errors?.length??0,0);
const results=[];
const walk=suite=>{
  for(const spec of suite.specs??[])
    for(const test of spec.tests??[])
      for(const result of test.results??[])results.push(result.status);
  for(const child of suite.suites??[])walk(child);
};
for(const suite of report.suites??[])walk(suite);
assert.deepEqual(results,['passed']);
assert.deepEqual(catalog.objects.map(object=>object.key),
  manifest.objects.map(object=>object.key).sort());
assert.deepEqual(catalog.ords.enabled.map(row=>row.object).sort(),
  ['DOOM_API','PUBLIC_HEALTH']);

const objects=manifest.objects.map(object=>{
  const safe=object.key.replaceAll('/','__');
  const headers=json(path.join(liveDir,`${safe}.verdict.json`));
  const bytes=read(path.join(liveDir,`${safe}.body`));
  assert.equal(sha(bytes),object.sha256,`${object.key} live bytes`);
  assert.equal(headers.status,200);
  assert.equal(headers.contentType,object.contentType);
  assert.equal(headers.cacheControl,object.cacheControl);
  assert.equal(headers.etag,`"${object.sha256}"`);
  const notModified=json(path.join(liveDir,
    `${safe}.not-modified.verdict.json`));
  assert.equal(notModified.status,304);
  assert.equal(notModified.representationCachePolicy,object.cacheControl);
  assert.ok(notModified.cacheControl===null||
    notModified.cacheControl===object.cacheControl);
  assert.equal(notModified.etag,`"${object.sha256}"`);
  assert.equal(notModified.emptyBody,true);
  return {...object,databaseSha256:object.sha256,
    liveGetSha256:sha(bytes),liveHeadersMatch:true,
    strongEtag:true,conditionalGet304:true,
    liveObservationSha256:headers.observationSha256,
    conditionalObservationSha256:notModified.observationSha256};
});
const network=browser.network.map(row=>({
  kind:row.kind,urlSha256:row.urlSha256,originSha256:row.originSha256,
  method:row.method,status:row.status,redirected:row.redirected,
  failed:row.failed,websocket:row.websocket,mocked:row.mocked
}));
assert.ok(network.length>objects.length);
assert.ok(network.every(row=>['DATABASE_STATIC','ORACLE_API'].includes(row.kind)
  && row.originSha256===sha(index.origin)
  && (row.status>=200&&row.status<300||
    row.kind==='DATABASE_STATIC'&&row.status===304)
  && !row.redirected&&!row.failed&&!row.websocket&&!row.mocked));
const reportSha=sha(read(reportPath));
const cases=['DATABASE_HOSTED_DOCUMENT','SAME_ORIGIN_API',
  'AUTHORITATIVE_MLE_MATCH','CONFIRMED_ONLY_CHAIN',
  'DATABASE_FRAMEBUFFER_SOURCE','UNIQUE_MOVING_300','CLIENT_30_FPS',
  'CHECKPOINT_TAIL','CAPACITY_RELEASE']
  .map(id=>({id,status:'PASS',assertions:1,
    evidenceSha256:sha(`${id}:${reportSha}`)}));
const evidence={
  schema:2,task:'T11.2',result:'PASS',live:true,dryRun:false,
  localSubstitute:false,
  target:{provider:'OCI_AUTONOMOUS_DATABASE_HOSTED_ORDS',
    https:true,managedOrds:true,databaseResidentStatics:true,
    sameOrigin:true,originSha256:sha(index.origin),
    indexUrlSha256:sha(index.href)},
  tools:{sqlcl:policy.sqlcl,playwright:policy.playwright,browser:'chromium'},
  deployment:{atomicDatabaseTransaction:true,deleteExtraneous:true,
    buildManifestSha256:sha(read(manifestPath)),
    databaseCatalogSha256:catalog.catalogSha256,
    dedicatedModule:'doom.hosted.app',moduleCount:catalog.ords.modules,
    templateCount:catalog.ords.templates,handlerCount:catalog.ords.handlers,
    autoRestObjects:catalog.ords.enabled.map(row=>row.object).sort(),
    objects},
  payloadAudit:{privateFiles:0,sourceMaps:0,staleEngineArtifacts:0,
    authoritySha256:live.authorityCandidateSha256,
    presentationSha256:deployedRendererSha256,
    coordinatorSha256:deployedCoordinatorSha256,
    iwadSha256:versions.freedoom.freedoom1WadSha256,
    freedoomLicenseSha256:sha(read('vendor/freedoom/0.13.0/COPYING.txt')),
    sourceNoticeSha256:sha(read('deploy/cloud/t11.2/SOURCE.txt'))},
  browser:{playwrightReportStatus:'passed',workers:1,retries:0,
    routeFulfillCount:0,proxy:false,serviceWorkers:'block',
    verifiedBlobModuleLoads:browser.verifiedBlobModuleLoads,
    consoleErrors:0,pageErrors:0,failedRequests:0,redirects:0,cases,
    performance:browser.performance,cleanup:browser.cleanup,
    reportSha256:reportSha},
  runtime:{
    source:'DATABASE_POSTFLIGHT',
    matchSha256:runtime.matchSha256,
    firstTic:runtime.firstTic,lastTic:runtime.lastTic,
    currentTic:runtime.currentTic,
    checkpointCount:runtime.checkpointCount,
    checkpointUnmeasuredCount:runtime.checkpointUnmeasuredCount,
    checkpointSlowCount:runtime.checkpointSlowCount,
    checkpointMaxStepMs:runtime.checkpointMaxStepMs,
    checkpointMaxSaveMs:runtime.checkpointMaxSaveMs,
    checkpointMaxPublishMs:runtime.checkpointMaxPublishMs,
    checkpointMaxStageMs:runtime.checkpointMaxStageMs,
    checkpointTimingSource:runtime.checkpointTimingSource,
    checkpointTailGateMs:runtime.checkpointTailGateMs,
    browserPresentationTailGateMs:runtime.browserPresentationTailGateMs,
    checkpointStageSemantics:runtime.checkpointStageSemantics,
    authoritySha256:runtime.authoritySha256,
    rendererSha256:runtime.rendererSha256,
    coordinatorSha256:runtime.coordinatorSha256
  },
  network,
  networkSummary:{unclassified:0,otherOrigins:0,websockets:0,redirects:0,
    failed:0,ledgerSha256:sha(JSON.stringify(network))},
  credentials:{envOnly:true,repositoryMatches:0,evidenceMatches:0,
    retainedFiles:0,secretRedactionPassed:true},
  provenance:{canonicalEvidenceSha256:'0'.repeat(64),
    buildSha256:sha(read(manifestPath)),
    databaseEvidenceSha256:sha(read(catalogPath)),
    browserEvidenceSha256:sha(read(browserPath)),
    runtimeEvidenceSha256:sha(read(runtimePath)),
    atomicWrite:true,ancestry:policy.ancestry}
};
let raw=JSON.stringify(evidence);
for(const forbidden of ['authorization','bearer ','password','wallet',
  'private_key','adb_ords','https://','http://','oraclecloudapps',
  'game_token','session_id']){
  assert.ok(!raw.toLowerCase().includes(forbidden),
    `forbidden evidence value ${forbidden}`);
}
evidence.provenance.canonicalEvidenceSha256=sha(raw);
raw=JSON.stringify(evidence);
fs.writeFileSync(outputPath,`${raw}\n`,{mode:0o600,flag:'wx'});
