import fs from 'node:fs';
import path from 'node:path';
import { auditProduction } from './lib/static-audit.mjs';

const repoRoot = path.resolve(import.meta.dirname, '..');
const policy = JSON.parse(fs.readFileSync(path.join(repoRoot, 'evaluator/audit-policy.json'), 'utf8'));
const violations = auditProduction(repoRoot, policy);
if (violations.length) {
  process.stderr.write(`${JSON.stringify({ passed: false, violations }, null, 2)}\n`);
  process.exit(1);
}
process.stdout.write(`${JSON.stringify({ passed: true, roots: policy.productionRoots })}\n`);
