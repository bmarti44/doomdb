#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const [rootArg, buildArg, ordsArg, manifestArg, allowlistArg] = process.argv.slice(2);
assert.ok(rootArg && buildArg && ordsArg && manifestArg && allowlistArg,
  'usage: t11.2-build-client.mjs ROOT BUILD_DIR ORDS_BASE MANIFEST ALLOWLIST');
const root = path.resolve(rootArg), build = path.resolve(buildArg);
const policy = JSON.parse(fs.readFileSync(path.join(root, 'deploy/cloud/t11.2/source-policy.json')));
const ords = new URL(ordsArg.endsWith('/') ? ordsArg : `${ordsArg}/`);
assert.equal(ords.protocol, 'https:', 'managed ORDS must use HTTPS');
assert.equal(ords.username, ''); assert.equal(ords.password, '');
assert.equal(ords.search, ''); assert.equal(ords.hash, '');
assert.match(ords.pathname, /^\/ords\/[A-Za-z0-9._~-]+\/$/, 'managed ORDS must be a schema root');

const apiPath = path.join(build, 'api.js'), indexPath = path.join(build, 'index.html');
assert.ok(fs.statSync(apiPath).isFile(), 'compiled api.js absent');
assert.ok(fs.statSync(indexPath).isFile(), 'compiled index.html absent');
let api = fs.readFileSync(apiPath, 'utf8');
const marker = "const ROOT = '/ords/doom/doom_api/';";
assert.equal(api.split(marker).length - 1, 1, 'same-origin API marker must occur exactly once');
const apiBase = new URL('doom_api/', ords).href;
api = api.replace(marker, `const ROOT = ${JSON.stringify(apiBase)};`);
fs.writeFileSync(apiPath, api, {mode: 0o644});

const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const mainPath = path.join(build, 'main.js');
let main = fs.readFileSync(mainPath, 'utf8');
const coopMarker = "coop.href = '/play/multiplayer.html#mode=COOP';";
const multiplayerMarker = "multiplayer.href = '/play/multiplayer.html';";
assert.equal(main.split(coopMarker).length - 1, 1, 'single-player co-op link marker');
assert.equal(main.split(multiplayerMarker).length - 1, 1,
  'single-player multiplayer link marker');
main = main
  .replace(coopMarker, "coop.href = '/multiplayer.html#mode=COOP';")
  .replace(multiplayerMarker, "multiplayer.href = '/multiplayer.html';");
fs.writeFileSync(mainPath, main, {mode: 0o644});
const multiplayerPath = path.join(build, 'multiplayer.js');
let multiplayer = fs.readFileSync(multiplayerPath, 'utf8');
assert.equal(multiplayer.split("'/play/multiplayer.html'").length - 1, 1, 'multiplayer share marker');
multiplayer = multiplayer.replace("'/play/multiplayer.html'", "'/multiplayer.html'");
fs.writeFileSync(multiplayerPath, multiplayer, {mode: 0o644});
const multiplayerIndexPath = path.join(build, 'multiplayer.html');
let multiplayerIndex = fs.readFileSync(multiplayerIndexPath, 'utf8');
assert.equal((multiplayerIndex.match(/\/play\/multiplayer\.js/g) ?? []).length, 1, 'multiplayer entry marker');
multiplayerIndex = multiplayerIndex.replace('/play/multiplayer.js', '/multiplayer.js');
fs.writeFileSync(multiplayerIndexPath, multiplayerIndex, {mode: 0o644});
const soloIndexPath = path.join(build, 'solo.html');
let soloIndex = fs.readFileSync(soloIndexPath, 'utf8');
assert.equal((soloIndex.match(/\/play\/multiplayer\.js/g) ?? []).length, 1,
  'solo MLE entry marker');
soloIndex = soloIndex.replace('/play/multiplayer.js', '/multiplayer.js');
fs.writeFileSync(soloIndexPath, soloIndex, {mode: 0o644});

const mainBytes = fs.readFileSync(mainPath);
const mainDigest = sha(mainBytes);
const addressedMain = `main-${mainDigest.slice(0, 12)}.js`;
fs.renameSync(mainPath, path.join(build, addressedMain));
const multiplayerBytes = fs.readFileSync(multiplayerPath);
const multiplayerDigest = sha(multiplayerBytes);
const addressedMultiplayer = `multiplayer-${multiplayerDigest.slice(0, 12)}.js`;
fs.renameSync(multiplayerPath, path.join(build, addressedMultiplayer));
let index = fs.readFileSync(indexPath, 'utf8');
assert.equal((index.match(/\/play\/main\.js/g) ?? []).length, 1,
  'menu index must contain one main entry');
index = index.replace('/play/main.js', `/${addressedMain}`);
fs.writeFileSync(indexPath, index, {mode: 0o644});
for (const entryPath of [multiplayerIndexPath,soloIndexPath]) {
  const entry = fs.readFileSync(entryPath, 'utf8');
  assert.equal((entry.match(/\/multiplayer\.js/g) ?? []).length, 1,
    'MLE index must contain one client entry');
  fs.writeFileSync(entryPath,
    entry.replace('/multiplayer.js', `/${addressedMultiplayer}`), {mode: 0o644});
}

const files = fs.readdirSync(build, {recursive: true})
  .filter(name => fs.statSync(path.join(build, name)).isFile())
  .map(name => name.split(path.sep).join('/')).sort();
assert.ok(files.length >= 2 && files.includes('index.html'), 'compiled artifact inventory incomplete');
const addressed = name => /[.-]([0-9a-f]{8,64})\.(?:js|bin|css|png|ico|svg|webmanifest)$/.exec(name);
const objects = files.map(key => {
  assert.ok(!key.startsWith('/') && !key.includes('..') && !key.includes('\\'), `unsafe key ${key}`);
  const lower = key.toLowerCase();
  for (const bad of policy.forbiddenFragments) assert.ok(!lower.includes(bad), `forbidden artifact ${key}`);
  const ext = path.extname(key).toLowerCase();
  assert.ok(policy.allowedExtensions.includes(ext), `extension not allowlisted: ${key}`);
  const bytes = fs.readFileSync(path.join(build, key)), digest = sha(bytes), match = addressed(key);
  let cacheControl = policy.cachePolicy.mutable, nameDigestMatches = false;
  if (key === 'index.html') cacheControl = policy.cachePolicy.index;
  else if (match) {
    assert.ok(digest.startsWith(match[1]), `content address does not match bytes: ${key}`);
    cacheControl = policy.cachePolicy.immutable; nameDigestMatches = true;
  }
  return {key, sha256: digest, bytes: bytes.length, contentType: policy.contentTypes[ext], cacheControl, nameDigestMatches};
});
const textExtensions = new Set(['.html', '.js', '.css', '.svg', '.webmanifest']);
const compiled = files.filter(name => textExtensions.has(path.extname(name).toLowerCase()))
  .map(name => fs.readFileSync(path.join(build, name), 'utf8')).join('\n');
assert.ok(compiled.includes(apiBase), 'managed ORDS base was not embedded');
assert.ok(!compiled.includes(marker), 'same-origin API fallback survived');
assert.ok(!/(?:serviceWorker|navigator\.serviceWorker|localhost|127\.0\.0\.1|__ORDS_|runtime-config|reverse.?proxy|proxy_pass|\/api\/proxy)/i.test(compiled),
  'compiled output contains a forbidden fallback or runtime configuration marker');
assert.ok(!/https?:\/\//i.test(compiled.split(apiBase).join('')), 'compiled output contains a remote static or alternate API origin');
const manifest = {schema: 1, task: 'T11.2', ordsOriginSha256: sha(ords.origin), compiledAuditSha256: sha(compiled), objects};
fs.writeFileSync(manifestArg, `${JSON.stringify(manifest)}\n`, {mode: 0o600});
fs.writeFileSync(allowlistArg, `${objects.map(x => x.key).join('\n')}\n`, {mode: 0o600});
