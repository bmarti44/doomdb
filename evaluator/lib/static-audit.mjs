import fs from 'node:fs';
import path from 'node:path';

const textExtensions = new Set(['.js', '.mjs', '.cjs', '.ts', '.tsx', '.sql', '.sh', '.yaml', '.yml', '.json', '.html', '.css']);

export function auditProduction(repoRoot, policy) {
  const violations = [];
  const patterns = policy.forbiddenPatterns.map((rule) => [rule.id, new RegExp(rule.pattern, 'i')]);
  const visit = (entry) => {
    const stat = fs.lstatSync(entry);
    if (stat.isSymbolicLink()) {
      violations.push({ id: 'production-symlink', file: path.relative(repoRoot, entry) });
      return;
    }
    if (stat.isDirectory()) {
      for (const name of fs.readdirSync(entry).sort()) visit(path.join(entry, name));
      return;
    }
    if (!textExtensions.has(path.extname(entry))) return;
    const relative = path.relative(repoRoot, entry).split(path.sep).join('/');
    const lower = relative.toLowerCase();
    for (const segment of policy.forbiddenPathSegments) {
      if (lower.split('/').includes(segment.toLowerCase())) violations.push({ id: 'forbidden-path', file: relative, detail: segment });
    }
    const text = fs.readFileSync(entry, 'utf8');
    for (const [id, pattern] of patterns) {
      if (pattern.test(text)) violations.push({ id, file: relative });
    }
  };
  for (const root of policy.productionRoots) {
    const absolute = path.join(repoRoot, root);
    if (fs.existsSync(absolute)) visit(absolute);
  }
  return violations;
}
