import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const source = fs.readFileSync(path.join(root, 'tools/wad/parser.ts'), 'utf8');
const mutations = [
  ['parser-big-endian-u16', 'return this.view.getUint16(offset, true);', 'return this.view.getUint16(offset, false);'],
  ['parser-first-duplicate', 'for (let i = directory.length - 1; i >= 0; i -= 1)', 'for (let i = 0; i < directory.length; i += 1)'],
  ['parser-cross-map-marker', 'const rows = directory.slice(start + 1, end);', 'const rows = directory.slice(start + 1);'],
  ['parser-node-flag-signed', "const child = (raw) => ({ subsector: (raw & 0x8000) !== 0, id: raw & 0x7fff });", "const child = (raw) => ({ subsector: raw < 0, id: raw });"],
  ['parser-ignore-reference-check', "if (v1 >= vertexCount || v2 >= vertexCount) fail('WAD_LINEDEF_VERTEX_REF');", "if (false) fail('WAD_LINEDEF_VERTEX_REF');"],
  ['parser-tall-post-absolute', 'const top = previousTop >= 0 && rawTop <= previousTop ? previousTop + rawTop : rawTop;', 'const top = rawTop;'],
  ['parser-zero-transparent', "const pixels = Array.from(r.slice(cursor, length, 'WAD_PATCH_POST_STREAM'));", "const pixels = Array.from(r.slice(cursor, length, 'WAD_PATCH_POST_STREAM')).filter((pixel) => pixel !== 0);"],
  ['parser-conflate-thing-modes', 'notSinglePlayer: (flags & 0x10) !== 0,', 'notSinglePlayer: (flags & 0x10) === 0,'],
  ['parser-blockmap-no-header', 'if (r.u16(cursor) !== 0)', 'if (r.u16(cursor += 2) !== 0)'],
  ['parser-nondeterministic-json', 'schema: 1,\n    wad:', 'schema: 1,\n    timestamp: Date.now(),\n    wad:'],
];

const outcomes = [];
for (const [id, find, replace] of mutations) {
  if (!source.includes(find)) throw new Error(`${id}: source patch did not apply`);
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), `doom-t2.2-${id}-`));
  try {
    fs.mkdirSync(path.join(scratch, 'tools/wad'), { recursive: true });
    fs.mkdirSync(path.join(scratch, 'evaluator'), { recursive: true });
    fs.cpSync(path.join(root, 'evaluator/t2.2'), path.join(scratch, 'evaluator/t2.2'), { recursive: true });
    fs.copyFileSync(path.join(root, 'evaluator/integrity.json'), path.join(scratch, 'evaluator/integrity.json'));
    fs.copyFileSync(path.join(root, 'tools/wad/parse.mjs'), path.join(scratch, 'tools/wad/parse.mjs'));
    fs.copyFileSync(path.join(root, 'tools/wad/parser.mjs'), path.join(scratch, 'tools/wad/parser.mjs'));
    fs.writeFileSync(path.join(scratch, 'tools/wad/parser.ts'), source.replace(find, replace));

    const selfCheck = spawnSync(process.execPath, ['evaluator/t2.2/self-check.mjs'], { cwd: scratch, encoding: 'utf8' });
    const visible = spawnSync(process.execPath, ['evaluator/t2.2/run-visible.mjs'], { cwd: scratch, encoding: 'utf8' });
    const infrastructureGreen = selfCheck.status === 0 && !/SyntaxError|ERR_MODULE_NOT_FOUND/.test(`${visible.stdout}${visible.stderr}`);
    const killed = infrastructureGreen && visible.status === 1 && /AssertionError/.test(visible.stderr);
    outcomes.push({ id, killed, infrastructureGreen });
  } finally {
    fs.rmSync(scratch, { recursive: true, force: true });
  }
}

if (!outcomes.every((outcome) => outcome.killed)) {
  process.stderr.write(`${JSON.stringify({ passed: false, outcomes }, null, 2)}\n`);
  process.exit(1);
}
process.stdout.write(`PASS T2.2-MUTATIONS (${outcomes.length}/${outcomes.length} semantic mutants killed)\n`);
