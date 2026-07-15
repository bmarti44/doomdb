#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';

function inspect(objects) {
  assert.equal(objects.length, 2, 'exactly database and evaluator inspect records');
  const db = objects.find(x => x.Config?.Labels?.['com.docker.compose.service'] === 'db');
  const evaluator = objects.find(x => x.Config?.Labels?.['com.docker.compose.service'] === 'evaluator');
  assert.ok(db, 'database inspect record');
  assert.ok(evaluator, 'evaluator inspect record');
  assert.equal(db.HostConfig.NanoCpus, 2_000_000_000, 'database exactly 2 CPUs');
  assert.equal(db.HostConfig.Memory, 2_147_483_648, 'database exactly 2 GiB');
  assert.equal(evaluator.Config.User, '1000:1000', 'evaluator non-root identity');
  assert.equal(evaluator.HostConfig.ReadonlyRootfs, true, 'evaluator read-only root');
  assert.deepEqual(evaluator.HostConfig.CapDrop, ['ALL'], 'all capabilities dropped');
  assert.ok(evaluator.HostConfig.SecurityOpt.includes('no-new-privileges:true'), 'no-new-privileges');
  assert.equal(evaluator.HostConfig.Privileged, false, 'not privileged');
  assert.equal(evaluator.HostConfig.PidMode, '', 'no host PID namespace');
  assert.ok(!evaluator.Mounts.some(m => m.RW), 'no writable bind or volume mounts');
  assert.ok(!evaluator.Mounts.some(m => m.Source === '/var/run/docker.sock' || m.Destination === '/var/run/docker.sock'), 'no Docker socket');
  assert.ok(evaluator.HostConfig.Tmpfs?.['/tmp']?.includes('size=268435456'), 'bounded scratch tmpfs');
  assert.ok(String(db.Config.Image).includes('@sha256:'), 'database image digest pinned');
  return true;
}

function synthetic() {
  const label = service => ({'com.docker.compose.service': service});
  return [
    {Config:{Image:'oracle@sha256:'+'a'.repeat(64),Labels:label('db')},HostConfig:{NanoCpus:2_000_000_000,Memory:2_147_483_648}},
    {Config:{User:'1000:1000',Labels:label('evaluator')},HostConfig:{ReadonlyRootfs:true,CapDrop:['ALL'],SecurityOpt:['no-new-privileges:true'],Privileged:false,PidMode:'',Tmpfs:{'/tmp':'rw,noexec,nosuid,nodev,size=268435456,uid=1000,gid=1000,mode=700'}},Mounts:[{RW:false,Source:'/private/evidence',Destination:'/evidence'}]}
  ];
}

if (process.argv[2] === '--self-test') {
  assert.equal(inspect(synthetic()), true);
  for (const mutate of [
    x => { x[0].HostConfig.NanoCpus++; },
    x => { x[0].HostConfig.Memory++; },
    x => { x[1].Config.User = 'root'; },
    x => { x[1].HostConfig.ReadonlyRootfs = false; },
    x => { x[1].HostConfig.CapDrop = []; },
    x => { x[1].HostConfig.Privileged = true; },
    x => { x[1].Mounts.push({RW:true,Source:'/var/run/docker.sock',Destination:'/var/run/docker.sock'}); }
  ]) {
    const sample = structuredClone(synthetic());
    mutate(sample);
    assert.throws(() => inspect(sample));
  }
  process.stdout.write('PASS T10.3-INSPECT-UNIT (8/8 topology mutations checked)\n');
} else {
  const input = fs.readFileSync(0, 'utf8');
  inspect(JSON.parse(input));
  process.stdout.write('PASS T10.3-LIVE-TOPOLOGY (14/14 resource and sandbox assertions)\n');
}
