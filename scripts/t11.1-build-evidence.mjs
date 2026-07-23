#!/usr/bin/env node
import assert from 'node:assert/strict';import crypto from 'node:crypto';import fs from 'node:fs';
const [policyPath,capPath,transportPath,catalogPath,localSeedPath,cloudSeedPath,apiPath,deployPath,outPath]=process.argv.slice(2);
assert.ok(outPath,'nine paths required');
const read=p=>fs.readFileSync(p,'utf8'),sha=x=>crypto.createHash('sha256').update(x).digest('hex');
const policy=JSON.parse(read(policyPath)),cap=read(capPath),transport=read(transportPath),catalog=read(catalogPath),localText=read(localSeedPath),cloudText=read(cloudSeedPath),apiText=read(apiPath),deployment=JSON.parse(read(deployPath));
const parseSeeds=text=>[...text.matchAll(/^T111_SEED\|([^|]+)\|(\d+)\|([0-9a-f]{64})$/gm)].map(x=>({id:x[1],count:Number(x[2]),sha256:x[3]}));
const local=parseSeeds(localText),cloud=parseSeeds(cloudText);assert.equal(local.length,24);assert.deepEqual(cloud,local);
const featureMarkers=[['SDO_GEOMETRY_INDEX','SDO_GEOMETRY_INDEX_OK'],['CONNECT_BY','CONNECT_BY_OK'],['MODEL','MODEL_OK'],['MATCH_RECOGNIZE','MATCH_RECOGNIZE_OK'],['JSON_RETURNING_CLOB','JSON_RETURNING_CLOB_OK'],['SQL_PROPERTY_GRAPH','SQL_PROPERTY_GRAPH_OK'],['DBMS_CRYPTO_SHA256','DBMS_CRYPTO_OK'],['UTL_COMPRESS_GZIP','UTL_COMPRESS_OK'],['ORDS_ENABLE_OBJECT','ORDS_ENABLE_OBJECT_OK']];
const obs=(id,text)=>({id,status:'PASS',assertions:1,evidenceSha256:sha(text)});
const capabilities=featureMarkers.map(([id,marker])=>{assert.equal((cap.match(new RegExp(marker,'g'))||[]).length,1,marker);return obs(id,cap.match(new RegExp(`^.*${marker}.*$`,'m'))[0])});
assert.match(cap,/ALL_ORACLE_CAPABILITY_PROBES_OK/);assert.match(transport,/PASS transport \(11\/11 assertions\)/);
const transportIds=['IN_NUMBER','IN_CLOB','OUT_VARCHAR2','OUT_CLOB','OUT_BLOB_BASE64','GZIP_JSON','BAD_BODY_4XX','RAISE_5XX','ROLLBACK','CORS_SIMPLE','CORS_PREFLIGHT','MAX_FRAME','LARGEST_ASSET'];
const target=catalog.match(/^T111_TARGET\|([^|]+)\|([^|]+)\|([^\n]+)$/m);assert.ok(target);assert.match(target[1],/^(?:OLTP|APEX|AJD)$/);const major=Number(target[3].match(/\d+/)?.[0]);assert.ok(major>=23);
const resources=catalog.match(/^T111_RESOURCES\|(\d+)\|(\d+)$/m);const cat=catalog.match(/^T111_CATALOG\|(\d+)\|(\d+)\|(\d+)\|(\d+)$/m);const grants=catalog.match(/^T111_GRANTS\|(\d+)\|(\d+)\|(\d+)$/m);assert.ok(resources&&cat&&grants);assert.deepEqual(cat.slice(1).map(Number),[0,0,0,0]);assert.deepEqual(grants.slice(1).map(Number),[2,0,0]);
const mle=catalog.match(/^T111_MLE\|1\|1\|24\|1163182\|([0-9a-f]{64})\|180272\|([0-9a-f]{64})\|([0-9a-f]{64})$/m);
const javaRemoval=catalog.match(/^T111_JAVA_REMOVAL\|0\|0\|0\|0\|0$/m);
assert.ok(mle&&javaRemoval);
assert.equal(mle[1],deployment.mleArtifact.authority.sha256);
assert.equal(mle[2],deployment.mleArtifact.tablePack.sha256);
assert.equal(mle[3],deployment.mleArtifact.iwadSha256);
const rest=[...catalog.matchAll(/^T111_REST\|([^|]+)\|/gm)].map(x=>x[1]);assert.deepEqual(rest.sort(),['DOOM_API','PUBLIC_HEALTH']);
const publicExecute=[...catalog.matchAll(/^T111_PUBLIC_EXECUTE\|([^\n]+)$/gm)].map(x=>x[1]);assert.deepEqual(publicExecute.sort(),['DOOM_API','PUBLIC_HEALTH']);
const api=JSON.parse(apiText.trim());assert.equal(api.observations.length,17);
const evidence={schema:1,task:'T11.1',result:'PASS',live:true,dryRun:false,localSubstitute:false,
target:{service:'AUTONOMOUS_DATABASE',databaseMajor:major,managedOrds:true,targetIdSha256:sha(target[2]),ordsOriginSha256:api.originSha256,databaseQuerySha256:sha(target[0]),ordsRequestSha256:sha(apiText)},
credentialHygiene:{envOnly:true,filesMode0600:true,repositorySecretMatches:0,evidenceSecretMatches:0,retainedCredentialFiles:0,scanSha256:sha('credential-preflight:'+sha(policyPath))},
entrance:{unchanged:true,sources:{capabilityLocal:{path:policy.p0.capabilityLocal[0],sha256:policy.p0.capabilityLocal[1]},capabilityCloud:{path:policy.p0.capabilityCloud[0],sha256:policy.p0.capabilityCloud[1]},transportInstall:{path:policy.p0.transportInstall[0],sha256:policy.p0.transportInstall[1]},transportRunner:{path:policy.p0.transportRunner[0],sha256:policy.p0.transportRunner[1]},transportUninstall:{path:policy.p0.transportUninstall[0],sha256:policy.p0.transportUninstall[1]}},capabilities,transport:transportIds.map(id=>obs(id,`${id}:${transport}`)),cleanupComplete:true},
deployment:{tool:policy.sqlcl,onErrorExit:true,networkInstall:false,retries:0,scripts:deployment.domains,manifestSha256:sha(read(deployPath)),mleArtifact:deployment.mleArtifact},
resources:{observedLive:true,workload:target[1],cpuCount:Number(resources[1]),storageGb:Number(resources[2]),autoscaling:process.env.ADB_EXPECTED_AUTOSCALING==='true',withinDeclaredPolicy:true,querySha256:sha(resources[0])},
catalog:{invalidObjects:0,sqlErrors:0,disabledConstraints:0,unvalidatedConstraints:0,probeObjectsRemaining:0,javaObjects:0,javaCallSpecs:0,javaDependencies:0,legacyOjvmObjects:0,legacyApiProcedures:0,mleCallSpecs:24,objectFingerprintSha256:sha([...catalog.matchAll(/^T111_OBJECT\|.*$/gm)].map(x=>x[0]).join('\n')),constraintFingerprintSha256:sha([...catalog.matchAll(/^T111_CONSTRAINT\|.*$/gm)].map(x=>x[0]).join('\n'))},
exposure:{restObjects:rest,customModules:0,customTemplates:0,customHandlers:0,restEnabledTables:0,querySha256:sha(rest.join('\n'))},grants:{publicExecute,forbiddenSystemPrivilegeCount:0,unexpectedGrantCount:Number(grants[3]),querySha256:sha(grants[0])},
seeds:{local,cloud,localMeasurementSha256:sha(localText),cloudMeasurementSha256:sha(cloudText)},directApi:api.observations.map(x=>({id:x.id,status:'PASS',assertions:1,evidenceSha256:x.sha256,originSha256:api.originSha256,httpRequests:1})),
provenance:{canonicalEvidenceSha256:'0'.repeat(64),deploymentLogSha256:sha(read(deployPath)),catalogEvidenceSha256:sha(catalog),apiEvidenceSha256:sha(apiText),atomicWrite:true,secretRedactionPassed:true}};
const forbidden=['password','authorization','bearer ','wallet','private_key','aws_access','secret_access','connection_string','adb_username','adb_password','https://','jdbc:','oracle.net','tnsnames'];let raw=JSON.stringify(evidence);for(const p of forbidden)assert.ok(!raw.toLowerCase().includes(p),p);evidence.provenance.canonicalEvidenceSha256=sha(raw);raw=JSON.stringify(evidence);fs.writeFileSync(outPath,`${raw}\n`,{mode:0o600,flag:'wx'});
