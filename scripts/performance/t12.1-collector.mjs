import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import {spawn} from 'node:child_process';
import {CONTRACT, scanRedacted, validateDatabaseObservations} from './t12.1-evidence.mjs';

const MAX_COLLECTOR_BYTES = 16 * 1024 * 1024;

export async function runCollector(command, request, environment = process.env) {
  assert.ok(Array.isArray(command) && command.length > 0, 'collector command is required');
  assert.ok(command.every(value => typeof value === 'string' && value.length > 0), 'invalid collector command');
  assert.ok(!command.some(value => /(?:password|credential|authorization|bearer|token|jdbc:|https?:\/\/)/i.test(value)),
    'collector command may not contain credentials or targets; use its private environment');
  const child = spawn(command[0], command.slice(1), {env: environment, stdio: ['pipe', 'pipe', 'pipe']});
  const stdout = [];
  const stderr = [];
  let bytes = 0;
  child.stdout.on('data', chunk => {
    bytes += chunk.length;
    if (bytes > MAX_COLLECTOR_BYTES) child.kill('SIGKILL');
    else stdout.push(chunk);
  });
  child.stderr.on('data', chunk => {
    if (stderr.reduce((sum, item) => sum + item.length, 0) < 64 * 1024) stderr.push(chunk);
  });
  child.stdin.end(JSON.stringify(request));
  const exitCode = await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', resolve);
  });
  const stderrBody = Buffer.concat(stderr);
  assert.equal(exitCode, 0, `database collector failed (exit ${exitCode}; diagnostic sha256 ${
    crypto.createHash('sha256').update(stderrBody).digest('hex')
  })`);
  assert.ok(bytes <= MAX_COLLECTOR_BYTES, 'database collector output exceeded limit');
  const result = JSON.parse(Buffer.concat(stdout).toString('utf8'));
  scanRedacted(result, 'collector output');
  return result;
}

export async function collectDatabaseEvidence(command, replayIdentity, environment) {
  const result = await runCollector(command, {
    schema: 1,
    task: CONTRACT.task,
    action: 'collect-complete-observations',
    replayIdentity,
    planFormat: 'ALLSTATS LAST',
    cursorCatalog: 'V$SQL',
    families: CONTRACT.families,
    poses: CONTRACT.poses,
    commands: CONTRACT.commands,
    expectedFrames: CONTRACT.frames,
    excludeStageTimersFromPayload: true
  }, environment);
  return validateDatabaseObservations(result);
}
