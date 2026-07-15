import fs from 'node:fs';
import path from 'node:path';

const forbidden = [
  [/\.only\s*\(/, '.only'],
  [/\.(?:skip|fixme)\s*\(/, 'skip/fixme'],
  [/test\.skip\b|describe\.skip\b/, 'skip'],
];

export function guardTestSources(root) {
  const failures = [];
  if (!fs.existsSync(root)) return failures;
  const visit = (entry) => {
    const stat = fs.lstatSync(entry);
    if (stat.isSymbolicLink()) throw new Error(`symlink not allowed: ${entry}`);
    if (stat.isDirectory()) {
      for (const name of fs.readdirSync(entry).sort()) visit(path.join(entry, name));
      return;
    }
    if (!/\.(?:[cm]?[jt]s|tsx?)$/.test(entry)) return;
    const text = fs.readFileSync(entry, 'utf8');
    for (const [pattern, reason] of forbidden) {
      if (pattern.test(text)) failures.push({ file: entry, reason });
    }
  };
  visit(root);
  return failures;
}
