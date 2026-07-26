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
  assert.equal(deployment.objects.length,24);
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
  for(const key of ['authoritySha256','presentationSha256','iwadSha256',
    'freedoomLicenseSha256','sourceNoticeSha256'])assert.ok(hex(audit[key]),key);

  const browser=evidence.browser;
  assert.equal(browser.playwrightReportStatus,'passed');
  assert.equal(browser.workers,1);
  assert.equal(browser.retries,0);
  assert.equal(browser.routeFulfillCount,0);
  assert.equal(browser.proxy,false);
  assert.equal(browser.serviceWorkers,'block');
  assert.equal(browser.verifiedBlobModuleLoads,2);
  assert.equal(browser.consoleErrors,0);
  assert.equal(browser.pageErrors,0);
  assert.equal(browser.failedRequests,0);
  assert.equal(browser.redirects,0);
  exact(browser.cases.map(row=>row.id),[
    'DATABASE_HOSTED_DOCUMENT','SAME_ORIGIN_API',
    'AUTHORITATIVE_MLE_MATCH','CONFIRMED_ONLY_CHAIN',
    'UNIQUE_MOVING_300','CLIENT_30_FPS','CAPACITY_RELEASE'
  ],'browser cases');
  for(const row of browser.cases){
    assert.equal(row.status,'PASS');
    assert.ok(row.assertions>0&&hex(row.evidenceSha256));
  }
  assert.equal(browser.performance.frames,300);
  assert.equal(browser.performance.uniqueFrames,300);
  assert.equal(browser.performance.sequentialTics,true);
  assert.ok(browser.performance.fps>=30);
  assert.ok(browser.performance.p95IntervalMs<=33.333);
  assert.ok(hex(browser.performance.frameChainSha256));
  assert.equal(browser.cleanup.released,true);
  assert.ok(hex(browser.cleanup.matchSha256));
  assert.ok(hex(browser.reportSha256));

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
    'databaseEvidenceSha256','browserEvidenceSha256'])
    assert.ok(hex(evidence.provenance[key]),key);
  assert.equal(evidence.provenance.atomicWrite,true);
  assert.deepEqual(evidence.provenance.ancestry,policy.ancestry);
  return true;
}

export function makeEvidence(policy){
  const digest=sha('asset');
  const names=[
    'index.html','solo.html','multiplayer.html','api.js','audio.js',
    'authority-batch.js','authority-mirror.js','authority-wan.js',
    'authority.js','canvas.js','codec.js','input.js','palette.js','patch.js',
    'presentation-state.js','teavm-browser.js',
    `main-${digest.slice(0,12)}.js`,`multiplayer-${digest.slice(0,12)}.js`,
    `doom-mle-authority-${digest.slice(0,12)}.js`,
    `doom-mle-presentation-${digest.slice(0,12)}.js`,
    `canonical-runtime-v2-${digest.slice(0,12)}.bin`,
    `freedoom1-${digest.slice(0,12)}.bin`,
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
    kind:index<24?'DATABASE_STATIC':'ORACLE_API',
    urlSha256:sha(`url-${index}`),originSha256:origin,method:'GET',status:200,
    redirected:false,failed:false,websocket:false,mocked:false
  }));
  const performance={frames:300,uniqueFrames:300,sequentialTics:true,
    fps:34.9,p95IntervalMs:29.2,firstTic:1,lastTic:300,
    frameChainSha256:sha('frames')};
  const cases=['DATABASE_HOSTED_DOCUMENT','SAME_ORIGIN_API',
    'AUTHORITATIVE_MLE_MATCH','CONFIRMED_ONLY_CHAIN','UNIQUE_MOVING_300',
    'CLIENT_30_FPS','CAPACITY_RELEASE'].map(id=>({
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
      iwadSha256:sha('iwad'),freedoomLicenseSha256:sha('license'),
      sourceNoticeSha256:sha('source')},
    browser:{playwrightReportStatus:'passed',workers:1,retries:0,
      routeFulfillCount:0,proxy:false,serviceWorkers:'block',
      verifiedBlobModuleLoads:2,consoleErrors:0,
      pageErrors:0,failedRequests:0,redirects:0,cases,performance,
      cleanup:{released:true,status:200,matchSha256:sha('match')},
      reportSha256:sha('report')},
    network,networkSummary:{unclassified:0,otherOrigins:0,websockets:0,
      redirects:0,failed:0,ledgerSha256:sha('network')},
    credentials:{envOnly:true,repositoryMatches:0,evidenceMatches:0,
      retainedFiles:0,secretRedactionPassed:true},
    provenance:{canonicalEvidenceSha256:sha('canonical'),
      buildSha256:sha('build'),databaseEvidenceSha256:sha('db'),
      browserEvidenceSha256:sha('browser'),atomicWrite:true,
      ancestry:{...policy.ancestry}}};
}
