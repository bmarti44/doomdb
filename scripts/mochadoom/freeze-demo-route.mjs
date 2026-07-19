import assert from 'node:assert/strict';
import fs from 'node:fs';

const [source, target, countText, skillText, acceptedText] = process.argv.slice(2);
if (!source || !target || !countText || !skillText || !acceptedText) {
  throw Error('usage: node freeze-demo-route.mjs demo.lmp route.json count skill accepted.json');
}
const bytes = fs.readFileSync(source);
const count = Number(countText), skill = Number(skillText);
const accepted = JSON.parse(acceptedText);
assert.equal(bytes[0], 109, 'only Doom 1.9 demos are supported');
assert.equal(bytes[2], 1, 'route must target episode 1');
assert.equal(bytes[3], 1, 'route must target map 1');
assert.ok(Number.isInteger(count) && count > 0);
assert.ok(Number.isInteger(skill) && skill >= 1 && skill <= 5);

const signed = value => value > 127 ? value - 256 : value;
const commands = [];
for (let index = 0, offset = 13; index < count; index += 1, offset += 4) {
  assert.ok(offset + 3 < bytes.length && bytes[offset] !== 0x80, 'demo ended early');
  const forward = signed(bytes[offset]), strafe = signed(bytes[offset + 1]);
  const buttons = bytes[offset + 3];
  commands.push({turn: -signed(bytes[offset + 2]), forward, strafe,
    run: Number(Math.abs(forward) >= 40 || Math.abs(strafe) >= 40),
    fire: Number((buttons & 1) !== 0), use: Number((buttons & 2) !== 0),
    weapon: (buttons & 4) === 0 ? 0 : ((buttons >> 3) & 7) + 1,
    pause: 0, automap: 0, menu: 'NONE', cheat: ''});
}
for (const run of JSON.parse(process.env.DOOM_ROUTE_PATCH ?? '[]')) {
  assert.ok(Number.isInteger(run.repeat) && run.repeat > 0, 'patch repeat');
  for (let index = 0; index < run.repeat; index += 1) commands.push({turn: 0,
    forward: 0, strafe: 0, run: 0, fire: 0, use: 0, weapon: 0, pause: 0,
    automap: 0, menu: 'NONE', cheat: '', ...run.command});
}
const runs = [];
for (const command of commands) {
  const previous = runs.at(-1);
  if (previous && JSON.stringify(previous.command) === JSON.stringify(command)) previous.repeat += 1;
  else runs.push({repeat: 1, command});
}
const route = {schema: 1, map: 'E1M1', skill, envelopeVersion: 2,
  encoding: 'ordered v2 signed-axis command runs',
  purpose: process.env.DOOM_ROUTE_PURPOSE
    ?? 'T8.2 no-cheat browser-visible death and new-game restart fixture',
  ...(process.env.DOOM_ROUTE_NO_CHEATS === '1' ? {constraints: {noCheats: true}} : {}),
  source: {name: 'fde1m1-783.lmp',
    url: 'https://www.mediafire.com/file/4te2d29o3mpqxk7/fde1m1-783.zip/file',
    sha256: 'c8373065e1bfbccc69614f26b1ccfd0a5a8476b45797eb988f3ceecec3e37ac4',
    author: 'Cactaceae', recording: 'Freedoom 0.13.0 E1M1 -complevel 3',
    sourceTics: count}, commandCount: commands.length, runs, accepted};
fs.mkdirSync(new URL('../../artifacts/t8.2-live/', import.meta.url), {recursive: true});
fs.writeFileSync(target, `${JSON.stringify(route, null, 2)}\n`);
process.stdout.write(`WROTE ${target} (${commands.length} commands, ${runs.length} runs)\n`);
