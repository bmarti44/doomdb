import assert from 'node:assert/strict';
import crypto from 'node:crypto';

export const sha = value => crypto.createHash('sha256').update(
  typeof value === 'string' || Buffer.isBuffer(value) ? value : canonical(value)
).digest('hex');

export function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`;
  if (value && typeof value === 'object') return `{${Object.keys(value).sort().map(k => `${JSON.stringify(k)}:${canonical(value[k])}`).join(',')}}`;
  return JSON.stringify(value);
}

const exactKeys = (value, keys, label) => assert.deepEqual(Object.keys(value).sort(), [...keys].sort(), `${label} exact keys`);
const hex = value => typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);

export function validateFixtures(f) {
  assert.equal(f.schema, 1);
  assert.equal(f.task, 'T10.3');
  assert.equal(f.freshRuns, 2);
  assert.match(f.projectPrefix, /^doomdb-t103-$/);
  assert.deepEqual(Object.keys(f.timeoutsSeconds).sort(), ['bootstrap','playwright','shutdown','suite','wholeGate']);
  for (const [name, seconds] of Object.entries(f.timeoutsSeconds)) assert.ok(Number.isInteger(seconds) && seconds >= 60 && seconds <= 14400, `${name} bounded timeout`);
  assert.equal(f.databaseResources.nanoCpus, 2_000_000_000);
  assert.equal(f.databaseResources.memoryBytes, 2_147_483_648);
  assert.deepEqual(f.requiredServices, ['db','ords','evaluator']);
  assert.equal(f.containerPolicy.readOnly, true);
  assert.equal(f.containerPolicy.user, '1000:1000');
  assert.deepEqual(f.containerPolicy.capDrop, ['ALL']);
  assert.equal(f.containerPolicy.noNewPrivileges, true);
  assert.equal(f.containerPolicy.dockerSocket, false);
  assert.equal(f.containerPolicy.hostPid, false);
  assert.equal(f.containerPolicy.workspaceReadOnly, true);
  assert.deepEqual(f.containerPolicy.networkPeers, ['db','ords']);
  assert.equal(f.suiteFamilies.length, 24);
  assert.equal(new Set(f.suiteFamilies.map(s => s.id)).size, 24);
  assert.equal(new Set(f.suiteFamilies.map(s => s.command)).size, 24);
  for (const s of f.suiteFamilies) {
    exactKeys(s, ['id','kind','command','minPassRecords'], `suite ${s.id}`);
    assert.match(s.id, /^(?:P[0-3]|T(?:4\.[1-3]|5\.[1-4]|6\.[1-4]|7\.[1-3]|8\.[1-2]|9\.1|10\.[1-2])|FOUNDATION)-[A-Z0-9.-]+$/);
    assert.match(s.command, /^\.\/verify\.sh (?:phase P[0-3]|task T(?:4\.[1-3]|5\.[1-4]|6\.[1-4]|7\.[1-3]|8\.[1-2]|9\.1|10\.[1-2])|evaluator-self-test)$/);
    assert.ok(Number.isInteger(s.minPassRecords) && s.minPassRecords > 0);
  }
  assert.equal(f.coreCapabilities.length, 14);
  assert.equal(new Set(f.coreCapabilities).size, 14);
  assert.deepEqual(f.excludedLaterCapabilities, ['Cloud','Performance']);
  assert.equal(f.hashDomains.length, 16);
  assert.equal(new Set(f.hashDomains).size, 16);
  assert.deepEqual(f.schemaPolicy.enabledRestObjects, ['DOOM_API','PUBLIC_HEALTH']);
  return true;
}

export function validateArtifactPath(value,f) {
  assert.match(value,/^(?:client\/dist|sql)\//,'production artifact root');
  const lower=value.toLowerCase();
  assert.ok(!f.forbiddenArtifactPatterns.some(x=>lower.includes(x.toLowerCase())),'forbidden artifact path');
  return true;
}

export function validateRun(record, f) {
  exactKeys(record, ['schema','task','runId','fresh','infrastructure','suites','capabilities','correctnessHashes','artifactLedger','schemaLedger'], 'run');
  assert.equal(record.schema, 1);
  assert.equal(record.task, 'T10.3');
  assert.match(record.runId, /^doomdb-t103-[0-9a-f]{16,64}$/);
  assert.equal(record.fresh, true);
  exactKeys(record.infrastructure, ['services','nanoCpus','memoryBytes','evaluatorSandbox','timeoutsEnforced','credentialsClean','startedFromNoResources','volumesRemoved'], 'infrastructure');
  assert.deepEqual(record.infrastructure.services, ['db:healthy','ords:healthy','evaluator:exited-0']);
  assert.equal(record.infrastructure.nanoCpus, f.databaseResources.nanoCpus);
  assert.equal(record.infrastructure.memoryBytes, f.databaseResources.memoryBytes);
  assert.equal(record.infrastructure.evaluatorSandbox, true);
  assert.equal(record.infrastructure.timeoutsEnforced, true);
  assert.equal(record.infrastructure.credentialsClean, true);
  assert.equal(record.infrastructure.startedFromNoResources, true);
  assert.equal(record.infrastructure.volumesRemoved, true);
  assert.equal(record.suites.length, f.suiteFamilies.length);
  assert.deepEqual(record.suites.map(s => s.id), f.suiteFamilies.map(s => s.id));
  for (let i=0;i<record.suites.length;i++) {
    const actual=record.suites[i], expected=f.suiteFamilies[i];
    exactKeys(actual, ['id','exitCode','passRecords','assertions','outputSha256','durationMs'], `suite result ${actual.id}`);
    assert.equal(actual.id, expected.id);
    assert.equal(actual.exitCode, 0);
    assert.ok(Number.isInteger(actual.passRecords) && actual.passRecords >= expected.minPassRecords);
    assert.ok(Number.isInteger(actual.assertions) && actual.assertions > 0);
    assert.ok(hex(actual.outputSha256));
    assert.ok(Number.isInteger(actual.durationMs) && actual.durationMs > 0 && actual.durationMs <= f.timeoutsSeconds.suite*1000);
  }
  assert.deepEqual(Object.keys(record.capabilities), f.coreCapabilities);
  for (const value of Object.values(record.capabilities)) assert.equal(value, 'GREEN');
  assert.deepEqual(Object.keys(record.correctnessHashes), f.hashDomains);
  for (const value of Object.values(record.correctnessHashes)) assert.ok(hex(value), 'canonical correctness SHA-256');
  assert.ok(Array.isArray(record.artifactLedger) && record.artifactLedger.length > 0);
  for (const item of record.artifactLedger) { exactKeys(item,['path','bytes','sha256'],'artifact'); validateArtifactPath(item.path,f); assert.ok(Number.isInteger(item.bytes)&&item.bytes>0); assert.ok(hex(item.sha256)); }
  assert.deepEqual([...record.artifactLedger].sort((a,b)=>a.path.localeCompare(b.path)), record.artifactLedger, 'artifact ledger sorted');
  exactKeys(record.schemaLedger,['invalidObjects','disabledOrUnvalidatedConstraints','enabledRestObjects','forbiddenObjects','objectFingerprintSha256','constraintFingerprintSha256'],'schema ledger');
  assert.equal(record.schemaLedger.invalidObjects,0);
  assert.equal(record.schemaLedger.disabledOrUnvalidatedConstraints,0);
  assert.deepEqual(record.schemaLedger.enabledRestObjects,['DOOM_API','PUBLIC_HEALTH']);
  assert.deepEqual(record.schemaLedger.forbiddenObjects,[]);
  assert.ok(hex(record.schemaLedger.objectFingerprintSha256));
  assert.ok(hex(record.schemaLedger.constraintFingerprintSha256));
  return true;
}

export function deterministicLedger(record) {
  return {
    suites: record.suites.map(({id,passRecords,assertions})=>({id,passRecords,assertions})),
    capabilities: record.capabilities,
    correctnessHashes: record.correctnessHashes,
    artifactLedger: record.artifactLedger,
    schemaLedger: record.schemaLedger
  };
}

export function compareRuns(a,b,f) {
  validateRun(a,f); validateRun(b,f);
  assert.notEqual(a.runId,b.runId,'independent project identities');
  assert.deepEqual(deterministicLedger(a),deterministicLedger(b),'byte-stable deterministic evidence');
  return sha(deterministicLedger(a));
}

export function parseSuiteOutput(text, expected) {
  assert.ok(typeof text==='string' && text.length>0,'nonempty output');
  assert.ok(!/(^|\n)\s*(?:SKIP|NOT RUN|TODO|TIMEOUT|Bail out!|FAIL)\b/i.test(text),'no fail/skip markers');
  const passRecords=(text.match(/(^|\n)PASS\b/g)||[]).length;
  assert.ok(passRecords>=expected.minPassRecords,`${expected.id} pass records`);
  const counts=[...text.matchAll(/(?:\(|\b)(\d+)\s*\/\s*(\d+)(?:\)|\b)/g)];
  assert.ok(counts.length>0,`${expected.id} assertion counts`);
  let assertions=0;
  for(const m of counts){const got=Number(m[1]), total=Number(m[2]);assert.equal(got,total,`${expected.id} complete count`);assert.ok(total>0);assertions+=total}
  return {passRecords,assertions,outputSha256:sha(text)};
}
