import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const digest = (file) => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');

export function verifyIntegrity(repoRoot, integrityPath = path.join(repoRoot, 'evaluator/integrity.json')) {
  const manifest = JSON.parse(fs.readFileSync(integrityPath, 'utf8'));
  const failures = [];
  for (const [relative, expected] of Object.entries(manifest.files)) {
    const file = path.join(repoRoot, relative);
    if (!fs.existsSync(file)) failures.push(`${relative}: missing`);
    else if (digest(file) !== expected) failures.push(`${relative}: hash mismatch`);
  }
  return failures;
}
