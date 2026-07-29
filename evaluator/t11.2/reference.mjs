import assert from 'node:assert/strict';
import crypto from 'node:crypto';

export const sha=value=>crypto.createHash('sha256')
  .update(typeof value==='string'?value:JSON.stringify(value)).digest('hex');
const hex=value=>typeof value==='string'&&/^[0-9a-f]{64}$/.test(value);
const exact=(actual,want,label)=>
  assert.deepEqual([...actual].sort(),[...want].sort(),label);
const addressed=key=>/[.-]([0-9a-f]{8,64})\.(?:js|bin|css|png|ico|svg|webmanifest)$/.test(key);

export function validatePolicy(policy){
  assert.equal(policy.schema,1);
  assert.equal(policy.task,'T11.2');
  assert.match(policy.sqlcl,/^26\.2\./);
  assert.equal(policy.playwright,'1.61.0');
  assert.ok(policy.allowedExtensions.includes('.bin'));
  assert.ok(policy.allowedExtensions.includes('.txt'));
  assert.equal(policy.contentTypes['.bin'],'application/octet-stream');
  assert.equal(policy.cachePolicy.immutable,
    'public, max-age=31536000, immutable');
  for(const digest of Object.values(policy.ancestry))assert.ok(hex(digest));
  return true;
}

export function validateEvidence(evidence,policy){
  validatePolicy(policy);
  assert.equal(evidence.schema,2);
  assert.equal(evidence.task,'T11.2');
  assert.equal(evidence.result,'PASS');
  assert.equal(evidence.live,true);
  assert.equal(evidence.dryRun,false);
  assert.equal(evidence.localSubstitute,false);
  const raw=JSON.stringify(evidence).toLowerCase();
  for(const forbidden of ['authorization','bearer ','password','wallet',
    'private_key','adb_ords','https://','http://','oraclecloudapps',
    'game_token','session_id','localhost','127.0.0.1','placeholder']){
    assert.ok(!raw.includes(forbidden),`forbidden retained value ${forbidden}`);
  }

  assert.equal(evidence.target.provider,
    'OCI_AUTONOMOUS_DATABASE_HOSTED_ORDS');
  assert.equal(evidence.target.https,true);
  assert.equal(evidence.target.managedOrds,true);
  assert.equal(evidence.target.databaseResidentStatics,true);
  assert.equal(evidence.target.sameOrigin,true);
  assert.ok(hex(evidence.target.originSha256));
  assert.ok(hex(evidence.target.indexUrlSha256));
  assert.deepEqual(evidence.tools,
    {sqlcl:policy.sqlcl,playwright:policy.playwright,browser:'chromium'});

  const deployment=evidence.deployment;
  assert.equal(deployment.atomicDatabaseTransaction,true);
  assert.equal(deployment.deleteExtraneous,true);
  assert.equal(deployment.dedicatedModule,'doom.hosted.app');
  assert.equal(deployment.moduleCount,1);
  assert.equal(deployment.templateCount,2);
  assert.equal(deployment.handlerCount,2);
  exact(deployment.autoRestObjects,['DOOM_API','PUBLIC_HEALTH'],
    'anonymous AutoREST surface');
  assert.ok(hex(deployment.buildManifestSha256));
  assert.ok(hex(deployment.databaseCatalogSha256));
  assert.equal(deployment.objects.length,17);
  assert.equal(new Set(deployment.objects.map(object=>object.key)).size,
    deployment.objects.length);
  assert.ok(deployment.objects.some(object=>object.key==='index.html'));
  assert.ok(deployment.objects.some(object=>object.key==='COPYING-freedoom.txt'));
  assert.ok(deployment.objects.some(object=>object.key==='SOURCE.txt'));
  for(const object of deployment.objects){
    assert.match(object.key,/^[A-Za-z0-9][A-Za-z0-9._-]{0,254}$/);
    const extension='.'+object.key.split('.').at(-1).toLowerCase();
    assert.ok(policy.allowedExtensions.includes(extension));
    assert.equal(object.contentType,policy.contentTypes[extension]);
    assert.ok(hex(object.sha256)&&hex(object.databaseSha256)
      &&hex(object.liveGetSha256)&&hex(object.liveObservationSha256));
    assert.equal(object.sha256,object.databaseSha256);
    assert.equal(object.sha256,object.liveGetSha256);
    assert.equal(object.liveHeadersMatch,true);
    assert.ok(Number.isInteger(object.bytes)&&object.bytes>0);
    if(object.key==='index.html')
      assert.equal(object.cacheControl,policy.cachePolicy.index);
    else if(addressed(object.key)){
      assert.equal(object.cacheControl,policy.cachePolicy.immutable);
      assert.equal(object.nameDigestMatches,true);
      const token=object.key.match(/[.-]([0-9a-f]{8,64})\./)[1];
      assert.ok(object.sha256.startsWith(token));
    }else assert.equal(object.cacheControl,policy.cachePolicy.mutable);
  }

  const audit=evidence.payloadAudit;
  assert.equal(audit.privateFiles,0);
  assert.equal(audit.sourceMaps,0);
  assert.equal(audit.staleEngineArtifacts,0);
  for(const key of ['authoritySha256','presentationSha256',
    'coordinatorSha256','iwadSha256','freedoomLicenseSha256',
    'sourceNoticeSha256'])assert.ok(hex(audit[key]),key);

  const browser=evidence.browser;
  assert.equal(browser.playwrightReportStatus,'passed');
  assert.equal(browser.workers,1);
  assert.equal(browser.retries,0);
  assert.equal(browser.routeFulfillCount,0);
  assert.equal(browser.proxy,false);
  assert.equal(browser.serviceWorkers,'block');
  assert.equal(browser.verifiedBlobModuleLoads,0);
  assert.equal(browser.consoleErrors,0);
  assert.equal(browser.pageErrors,0);
  assert.equal(browser.failedRequests,0);
  assert.equal(browser.redirects,0);
  exact(browser.cases.map(row=>row.id),[
    'DATABASE_HOSTED_DOCUMENT','SAME_ORIGIN_API',
    'AUTHORITATIVE_MLE_MATCH','CONFIRMED_ONLY_CHAIN',
    'DATABASE_FRAMEBUFFER_SOURCE','UNIQUE_MOVING_300','CLIENT_30_FPS',
    'CHECKPOINT_TAIL','CAPACITY_RELEASE'
  ],'browser cases');
  for(const row of browser.cases){
    assert.equal(row.status,'PASS');
    assert.ok(row.assertions>0&&hex(row.evidenceSha256));
  }
  assert.equal(browser.performance.frames,300);
  assert.equal(browser.performance.uniqueFrames,300);
  assert.equal(browser.performance.sequentialTics,true);
  assert.equal(browser.performance.databasePixelFrames,true);
  assert.ok(browser.performance.fps>=30);
  assert.ok(browser.performance.p95IntervalMs<=33.333);
  assert.ok(browser.performance.p99IntervalMs<=2*1000/35);
  assert.ok(browser.performance.maxIntervalMs<=100);
  assert.ok(hex(browser.performance.frameChainSha256));
  assert.equal(browser.cleanup.released,true);
  assert.ok(hex(browser.cleanup.matchSha256));
  assert.ok(hex(browser.reportSha256));

  const runtime=evidence.runtime;
  assert.equal(runtime.source,'DATABASE_POSTFLIGHT');
  assert.equal(runtime.matchSha256,browser.cleanup.matchSha256);
  assert.equal(runtime.firstTic,browser.performance.firstTic);
  assert.equal(runtime.lastTic,browser.performance.lastTic);
  assert.ok(Number.isInteger(runtime.currentTic)&&
    runtime.currentTic>=runtime.lastTic);
  assert.ok(Number.isInteger(runtime.checkpointCount)&&
    runtime.checkpointCount<=1);
  assert.equal(runtime.checkpointUnmeasuredCount,0);
  assert.equal(runtime.checkpointSlowCount,0);
  assert.ok(runtime.checkpointMaxStepMs>=0&&runtime.checkpointMaxStepMs<=100);
  assert.ok(runtime.checkpointMaxSaveMs>=0&&runtime.checkpointMaxSaveMs<=250);
  assert.ok(runtime.checkpointMaxPublishMs>=0&&
    runtime.checkpointMaxPublishMs<=250);
  assert.ok(runtime.checkpointMaxStageMs>=0&&runtime.checkpointMaxStageMs<=250);
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
  assert.equal(runtime.authoritySha256,audit.authoritySha256);
  assert.equal(runtime.rendererSha256,audit.presentationSha256);
  assert.equal(runtime.coordinatorSha256,audit.coordinatorSha256);

  assert.ok(evidence.network.length>deployment.objects.length);
  for(const row of evidence.network){
    assert.ok(['DATABASE_STATIC','ORACLE_API'].includes(row.kind));
    assert.ok(hex(row.urlSha256)&&
      row.originSha256===evidence.target.originSha256);
    assert.ok(row.status>=200&&row.status<300||
      row.kind==='DATABASE_STATIC'&&row.status===304);
    assert.equal(row.redirected,false);
    assert.equal(row.failed,false);
    assert.equal(row.websocket,false);
    assert.equal(row.mocked,false);
  }
  assert.deepEqual(evidence.networkSummary,{
    unclassified:0,otherOrigins:0,websockets:0,redirects:0,failed:0,
    ledgerSha256:evidence.networkSummary.ledgerSha256});
  assert.ok(hex(evidence.networkSummary.ledgerSha256));
  assert.equal(evidence.credentials.envOnly,true);
  assert.equal(evidence.credentials.repositoryMatches,0);
  assert.equal(evidence.credentials.evidenceMatches,0);
  assert.equal(evidence.credentials.retainedFiles,0);
  assert.equal(evidence.credentials.secretRedactionPassed,true);
  for(const key of ['canonicalEvidenceSha256','buildSha256',
    'databaseEvidenceSha256','browserEvidenceSha256',
    'runtimeEvidenceSha256'])
    assert.ok(hex(evidence.provenance[key]),key);
  assert.equal(evidence.provenance.atomicWrite,true);
  assert.deepEqual(evidence.provenance.ancestry,policy.ancestry);
  return true;
}

export function makeEvidence(policy){
  const digest=sha('asset');
  const names=[
    'index.html','solo.html','multiplayer.html','api.js','audio.js',
    'authority-wan.js','canvas.js','codec.js','input.js','palette.js','patch.js',
    'pixel-batch.js','presentation-state.js',
    `main-${digest.slice(0,12)}.js`,`multiplayer-${digest.slice(0,12)}.js`,
    'COPYING-freedoom.txt','SOURCE.txt'
  ];
  const objects=names.map((key,index)=>{
    const extension='.'+key.split('.').at(-1);
    const bytes=Buffer.from(index===0?'index':`asset-${index}`);
    const objectSha=sha(bytes);
    // Content-addressed fixture names must match their bytes.
    const finalKey=addressed(key)?key.replace(digest.slice(0,12),
      objectSha.slice(0,12)):key;
    const immutable=addressed(finalKey);
    return {key:finalKey,sha256:objectSha,databaseSha256:objectSha,
      liveGetSha256:objectSha,liveObservationSha256:sha(`header-${index}`),
      bytes:bytes.length,contentType:policy.contentTypes[extension],
      cacheControl:finalKey==='index.html'?policy.cachePolicy.index:
        immutable?policy.cachePolicy.immutable:policy.cachePolicy.mutable,
      nameDigestMatches:immutable,liveHeadersMatch:true};
  });
  const origin=sha('origin');
  const network=Array.from({length:26},(_,index)=>({
    kind:index<17?'DATABASE_STATIC':'ORACLE_API',
    urlSha256:sha(`url-${index}`),originSha256:origin,method:'GET',status:200,
    redirected:false,failed:false,websocket:false,mocked:false
  }));
  const performance={frames:300,uniqueFrames:300,sequentialTics:true,
    databasePixelFrames:true,fps:34.9,p95IntervalMs:29.2,
    p99IntervalMs:31.1,maxIntervalMs:34.0,firstTic:1,lastTic:300,
    frameChainSha256:sha('frames')};
  const cases=['DATABASE_HOSTED_DOCUMENT','SAME_ORIGIN_API',
    'AUTHORITATIVE_MLE_MATCH','CONFIRMED_ONLY_CHAIN','UNIQUE_MOVING_300',
    'DATABASE_FRAMEBUFFER_SOURCE','CLIENT_30_FPS','CHECKPOINT_TAIL',
    'CAPACITY_RELEASE'].map(id=>({
      id,status:'PASS',assertions:1,evidenceSha256:sha(id)}));
  return {schema:2,task:'T11.2',result:'PASS',live:true,dryRun:false,
    localSubstitute:false,target:{provider:'OCI_AUTONOMOUS_DATABASE_HOSTED_ORDS',
      https:true,managedOrds:true,databaseResidentStatics:true,sameOrigin:true,
      originSha256:origin,indexUrlSha256:sha('index')},
    tools:{sqlcl:policy.sqlcl,playwright:policy.playwright,browser:'chromium'},
    deployment:{atomicDatabaseTransaction:true,deleteExtraneous:true,
      buildManifestSha256:sha('build'),databaseCatalogSha256:sha('catalog'),
      dedicatedModule:'doom.hosted.app',moduleCount:1,templateCount:2,
      handlerCount:2,autoRestObjects:['DOOM_API','PUBLIC_HEALTH'],objects},
    payloadAudit:{privateFiles:0,sourceMaps:0,staleEngineArtifacts:0,
      authoritySha256:sha('authority'),presentationSha256:sha('presentation'),
      coordinatorSha256:sha('coordinator'),
      iwadSha256:sha('iwad'),freedoomLicenseSha256:sha('license'),
      sourceNoticeSha256:sha('source')},
    browser:{playwrightReportStatus:'passed',workers:1,retries:0,
      routeFulfillCount:0,proxy:false,serviceWorkers:'block',
      verifiedBlobModuleLoads:0,consoleErrors:0,
      pageErrors:0,failedRequests:0,redirects:0,cases,performance,
      cleanup:{released:true,status:200,matchSha256:sha('match')},
      reportSha256:sha('report')},
    runtime:{source:'DATABASE_POSTFLIGHT',matchSha256:sha('match'),
      firstTic:1,lastTic:300,currentTic:300,checkpointCount:0,
      checkpointUnmeasuredCount:0,checkpointSlowCount:0,
      checkpointMaxStepMs:0,checkpointMaxSaveMs:1,
      checkpointMaxPublishMs:.5,checkpointMaxStageMs:1,
      checkpointTimingSource:'EXACT_STAGE_PLUS_SPARSE_GT_100MS_TOTAL',
      checkpointTailGateMs:250,browserPresentationTailGateMs:100,
      checkpointStageSemantics:'MAX_INDIVIDUAL_PREPARE_OR_EXPORT',
      authoritySha256:sha('authority'),rendererSha256:sha('presentation'),
      coordinatorSha256:sha('coordinator')},
    network,networkSummary:{unclassified:0,otherOrigins:0,websockets:0,
      redirects:0,failed:0,ledgerSha256:sha('network')},
    credentials:{envOnly:true,repositoryMatches:0,evidenceMatches:0,
      retainedFiles:0,secretRedactionPassed:true},
    provenance:{canonicalEvidenceSha256:sha('canonical'),
      buildSha256:sha('build'),databaseEvidenceSha256:sha('db'),
      browserEvidenceSha256:sha('browser'),
      runtimeEvidenceSha256:sha('runtime'),atomicWrite:true,
      ancestry:{...policy.ancestry}}};
}
