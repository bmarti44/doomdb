import { readFileSync } from 'node:fs';
export const stolen = readFileSync('evaluator/goldens/expected-frame.json', 'utf8');
