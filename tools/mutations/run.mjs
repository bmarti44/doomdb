import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const sourceRoot = path.resolve(import.meta.dirname, '../..');
const manifestPath = process.argv[2] ? path.resolve(process.argv[2]) : path.join(sourceRoot, 'tools/mutations/canaries.json');
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const outcomes = [];

for (const mutation of manifest.mutations) {
  const scratch = fs.mkdtempSync(path.join(os.tmpdir(), `doom-mutation-${mutation.id}-`));
  fs.cpSync(path.join(sourceRoot, 'evaluator/dummy/mutation'), path.join(scratch, 'evaluator/dummy/mutation'), { recursive: true });
  const target = path.join(scratch, mutation.target);
  const before = fs.readFileSync(target, 'utf8');
  if (!before.includes(mutation.find)) throw new Error(`${mutation.id}: patch did not apply`);
  fs.writeFileSync(target, before.replace(mutation.find, mutation.replace));
  const child = spawnSync(process.execPath, [path.join(scratch, 'evaluator/dummy/mutation/test.mjs')], { encoding: 'utf8' });
  const observation = JSON.parse(child.stdout || '{}');
  const infrastructureGreen = observation.health === true && observation.built === true && observation.deployed === true;
  const killed = child.status === 1 && infrastructureGreen && observation.semantic === false && observation.reason === mutation.reason;
  const survived = child.status === 0 && infrastructureGreen && observation.semantic === true;
  const passed = mutation.expected === 'killed' ? killed : survived;
  outcomes.push({ id: mutation.id, expected: mutation.expected, passed, observation });
  fs.rmSync(scratch, { recursive: true, force: true });
}

const passed = outcomes.every((outcome) => outcome.passed);
process.stdout.write(JSON.stringify({ passed, outcomes }));
process.exit(passed ? 0 : 1);
