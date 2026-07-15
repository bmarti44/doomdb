import fs from 'node:fs';
import path from 'node:path';

export function loadHiddenSeeds(root = process.env.DOOM_HELD_BACK_DIR) {
  if (!root) return [];
  const canonical = fs.realpathSync(root);
  const files = fs.readdirSync(canonical).sort();
  return files.filter((name) => name.endsWith('.json')).map((name) => {
    const candidate = path.join(canonical, name);
    const real = fs.realpathSync(candidate);
    if (!real.startsWith(`${canonical}${path.sep}`)) throw new Error('hidden seed escapes mount');
    const stat = fs.lstatSync(candidate);
    if (!stat.isFile() || stat.isSymbolicLink()) throw new Error('hidden seed must be a regular file');
    const parsed = JSON.parse(fs.readFileSync(real, 'utf8'));
    if (parsed === null || Array.isArray(parsed) || typeof parsed !== 'object') {
      throw new Error('hidden seed root must be an object');
    }
    return { name, value: parsed };
  });
}
