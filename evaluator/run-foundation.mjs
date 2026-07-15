import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { validateResult } from './lib/result-validator.mjs';

const label = process.argv[2] || 'T0.4';
if (!['T0.4', 'P0'].includes(label)) throw new Error(`unknown evaluator label: ${label}`);
const repoRoot = path.resolve(import.meta.dirname, '..');
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), 'doom-evaluator-result-'));
const resultPath = path.join(scratch, 'result.json');
const nonce = crypto.randomBytes(24).toString('hex');
const child = spawnSync(process.execPath, [path.join(repoRoot, 'evaluator/foundation-child.mjs'), resultPath, nonce], { cwd: repoRoot, encoding: 'utf8' });
if (child.status !== 0) {
  fs.rmSync(scratch, { recursive: true, force: true });
  process.stderr.write(child.stderr || child.stdout || 'foundation child failed without diagnostics\n');
  process.exit(child.status ?? 1);
}
if (!fs.existsSync(resultPath)) {
  fs.rmSync(scratch, { recursive: true, force: true });
  throw new Error('foundation child produced no machine result');
}
const summary = validateResult(path.join(repoRoot, 'evaluator/manifest/test-ids.json'), resultPath, nonce);
fs.rmSync(scratch, { recursive: true, force: true });
process.stdout.write(`PASS ${label} (${summary.passed}/${summary.total} assertions)\n`);
