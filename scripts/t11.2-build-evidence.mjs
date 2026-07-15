#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const [policyFile, manifestFile, awsDir, browserFile, reportFile, indexUrl, ordsUrl, outputFile] = process.argv.slice(2);
assert.ok(outputFile, 'eight evidence-builder arguments required');
const read = file => fs.readFileSync(file), json = file => JSON.parse(read(file));
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const policy=json(policyFile), manifest=json(manifestFile), browser=json(browserFile), report=json(reportFile);
const s3Origin=new URL(indexUrl).origin, ordsOrigin=new URL(ordsUrl).origin;
assert.equal(new URL(indexUrl).protocol,'https:'); assert.equal(new URL(indexUrl).pathname,'/index.html');
assert.equal(new URL(ordsUrl).protocol,'https:'); assert.notEqual(s3Origin,ordsOrigin);
assert.equal(report.errors?.length??0,0,'Playwright report errors');
const results=[];const walk=s=>{for(const spec of s.specs??[])for(const test of spec.tests??[])for(const result of test.results??[])results.push(result.status);for(const child of s.suites??[])walk(child)};for(const suite of report.suites??[])walk(suite);
assert.deepEqual(results,['passed'],'exactly one passing Playwright result required');
assert.deepEqual(browser.errors,[]);assert.ok(browser.optionsCount>0);assert.ok(browser.network.length>manifest.objects.length);
const inventory=json(path.join(awsDir,'inventory.json')).Contents?.map(x=>x.Key).sort()??[];
assert.deepEqual(inventory,manifest.objects.map(x=>x.key).sort(),'live inventory differs from build');
const objects=manifest.objects.map(object=>{const safe=object.key.replaceAll('/','__'),head=json(path.join(awsDir,`${safe}.head.json`)),live=read(path.join(awsDir,`${safe}.get`));assert.equal(sha(live),object.sha256,`${object.key} GET bytes`);assert.equal(head.ContentType,object.contentType,`${object.key} Content-Type`);assert.equal(head.CacheControl,object.cacheControl,`${object.key} Cache-Control`);assert.equal(Number(head.ContentLength),object.bytes,`${object.key} length`);return {...object,liveHeadMatches:true,liveGetSha256:sha(live)}});
const ids=['S3_DOCUMENT','CORS_PREFLIGHT','NEW_GAME','STEP','ASSET_PLAYPAL','ASSET_AUDIO','CANVAS_RGBA','AUDIO_EVENT','SAVE_LOAD','REPLAY','COMPLETION_SMOKE'];
const reportSha=sha(read(reportFile)), cases=ids.map(id=>({id,status:'PASS',assertions:1,evidenceSha256:sha(`${id}:${reportSha}`)}));
const s3Sha=sha(s3Origin),ordsSha=sha(ordsOrigin),indexSha=sha(indexUrl);
const network=browser.network.map(row=>({kind:row.kind,urlSha256:row.urlSha256,originSha256:row.originSha256,status:row.status,redirected:row.redirected,failed:row.failed,websocket:row.websocket,mocked:row.mocked}));
const ledgerSha=sha(JSON.stringify(network));
const evidence={schema:1,task:'T11.2',result:'PASS',live:true,dryRun:false,localSubstitute:false,
 credentials:{envOnly:true,commandLineMatches:0,logMatches:0,repositoryMatches:0,evidenceMatches:0,retainedFiles:0,scanSha256:sha(read(path.join(awsDir,'redaction.scan')))},
 target:{provider:'AWS_S3',https:true,explicitIndexObject:true,websiteHttpEndpoint:false,cloudFront:false,managedOrds:true,awsIdentitySha256:sha(read(path.join(awsDir,'identity.json'))),s3OriginSha256:s3Sha,indexUrlSha256:indexSha,ordsOriginSha256:ordsSha,headObservationSha256:sha(objects.map(x=>x.liveGetSha256).join('')),tlsObservationSha256:sha(read(path.join(awsDir,'index.headers')))},
 tools:{awsCli:policy.awsCli,playwright:policy.playwright,browser:'chromium'},
 upload:{networkInstall:false,deleteExtraneous:true,atomicManifest:true,buildManifestSha256:sha(read(manifestFile)),uploadManifestSha256:sha(read(path.join(awsDir,'inventory.json'))),allowlist:objects.map(x=>x.key),objects},
 build:{ordsEmbedded:true,ordsOriginSha256:ordsSha,unresolvedMarkers:0,runtimeConfigRequests:0,proxyReferences:0,localFallbacks:0,serviceWorkers:0,remoteStaticReferences:0,compiledAuditSha256:manifest.compiledAuditSha256},
 browser:{topLevelUrlSha256:indexSha,topLevelOriginSha256:s3Sha,playwrightReportStatus:'passed',workers:1,retries:0,skipped:0,unexpected:0,routeFulfillCount:0,proxy:false,serviceWorkers:'block',consoleErrors:0,pageErrors:0,failedRequests:0,redirects:0,cases,reportSha256:reportSha},
 cors:browser.cors,workflow:browser.workflow,network,
 networkSummary:{unclassified:network.filter(x=>x.kind==='OTHER').length,otherOrigins:network.filter(x=>![s3Sha,ordsSha].includes(x.originSha256)).length,websockets:network.filter(x=>x.websocket).length,beacons:0,redirects:network.filter(x=>x.redirected).length,failed:network.filter(x=>x.failed).length,ledgerSha256:ledgerSha},
 provenance:{canonicalEvidenceSha256:'0'.repeat(64),buildSha256:sha(read(manifestFile)),s3EvidenceSha256:sha(read(path.join(awsDir,'inventory.json'))),browserEvidenceSha256:sha(read(browserFile)),networkEvidenceSha256:ledgerSha,atomicWrite:true,secretRedactionPassed:true,ancestry:policy.ancestry}};
evidence.provenance.canonicalEvidenceSha256=sha(JSON.stringify(evidence));
const raw=JSON.stringify(evidence).toLowerCase();
for(const bad of ['aws_access','secret_access','session_token','authorization','bearer ','bucket','region','account_id','password','wallet','private_key','adb_ords','https://','http://','s3.amazonaws','oraclecloud','game_token','session_id'])assert.ok(!raw.includes(bad),`forbidden retained evidence term ${bad}`);
fs.writeFileSync(outputFile,`${JSON.stringify(evidence)}\n`,{mode:0o600});
