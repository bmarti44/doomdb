#!/usr/bin/env node
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const [rootArg, buildArg, ordsArg, manifestArg, allowlistArg, loaderManifestArg] =
  process.argv.slice(2);
assert.ok(rootArg && buildArg && ordsArg && manifestArg && allowlistArg
    && loaderManifestArg,
  'usage: t11.2-build-client.mjs ROOT BUILD_DIR ORDS_BASE MANIFEST ALLOWLIST LOADER_TSV');
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
fs.writeFileSync(apiPath, api, {mode: 0o644});

const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const mainPath = path.join(build, 'main.js');
let main = fs.readFileSync(mainPath, 'utf8');
assert.equal(main.split("coop.href = './multiplayer.html#mode=COOP';").length - 1, 1,
  'single-player co-op link must be app-relative');
assert.equal(main.split("multiplayer.href = './multiplayer.html#mode=DEATHMATCH';").length - 1, 1,
  'single-player multiplayer link must be app-relative');
fs.writeFileSync(mainPath, main, {mode: 0o644});
const multiplayerPath = path.join(build, 'multiplayer.js');
let multiplayer = fs.readFileSync(multiplayerPath, 'utf8');
assert.equal(multiplayer.split("new URL('./multiplayer.html', location.href)").length - 1, 1,
  'multiplayer share URL must be app-relative');
fs.writeFileSync(multiplayerPath, multiplayer, {mode: 0o644});
const multiplayerIndexPath = path.join(build, 'multiplayer.html');
let multiplayerIndex = fs.readFileSync(multiplayerIndexPath, 'utf8');
assert.equal((multiplayerIndex.match(/\.\/multiplayer\.js/g) ?? []).length, 1,
  'multiplayer entry must be app-relative');
fs.writeFileSync(multiplayerIndexPath, multiplayerIndex, {mode: 0o644});
const soloIndexPath = path.join(build, 'solo.html');
let soloIndex = fs.readFileSync(soloIndexPath, 'utf8');
assert.equal((soloIndex.match(/\.\/multiplayer\.js/g) ?? []).length, 1,
  'solo MLE entry must be app-relative');
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
assert.equal((index.match(/\.\/main\.js/g) ?? []).length, 1,
  'menu index must contain one main entry');
index = index.replace('./main.js', `./${addressedMain}`);
fs.writeFileSync(indexPath, index, {mode: 0o644});
for (const entryPath of [multiplayerIndexPath,soloIndexPath]) {
  const entry = fs.readFileSync(entryPath, 'utf8');
  assert.equal((entry.match(/\.\/multiplayer\.js/g) ?? []).length, 1,
    'MLE index must contain one client entry');
  fs.writeFileSync(entryPath,
    entry.replace('./multiplayer.js', `./${addressedMultiplayer}`), {mode: 0o644});
}

// The shipping database-frame client must not publish the historical
// confirmed-state TeaVM fallback. TypeScript still emits every source module,
// so remove this explicitly named diagnostic-only closure before inventory.
for(const diagnosticOnly of [
  'authority.js','authority-batch.js','authority-mirror.js','teavm-browser.js'
]) {
  const diagnosticPath=path.join(build,diagnosticOnly);
  assert.ok(fs.statSync(diagnosticPath).isFile(),
    `expected diagnostic-only client module is absent: ${diagnosticOnly}`);
  fs.rmSync(diagnosticPath);
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
const compiled = files.filter(name => textExtensions.has(path.extname(name).toLowerCase())
    && !/^doom-mle-(?:authority|presentation)-[0-9a-f]{12}\.js$/.test(name))
  .map(name => fs.readFileSync(path.join(build, name), 'utf8')).join('\n');
assert.ok(compiled.includes(marker), 'same-origin API root did not survive compilation');
assert.ok(!/(?:["'`(=])\/play\//.test(compiled),
  'compiled client contains an origin-root /play/ dependency');
assert.ok(!/(?:serviceWorker|navigator\.serviceWorker|localhost|127\.0\.0\.1|__ORDS_|runtime-config|reverse.?proxy|proxy_pass|\/api\/proxy)/i.test(compiled),
  'compiled output contains a forbidden fallback or runtime configuration marker');
assert.ok(!/https?:\/\//i.test(compiled),
  'compiled output contains a remote static or alternate API origin');
const manifest = {schema: 1, task: 'T11.2', ordsOriginSha256: sha(ords.origin), compiledAuditSha256: sha(compiled), objects};
fs.writeFileSync(manifestArg, `${JSON.stringify(manifest)}\n`, {mode: 0o600});
fs.writeFileSync(allowlistArg, `${objects.map(x => x.key).join('\n')}\n`, {mode: 0o600});
const clean = value => {
  assert.ok(!/[\t\r\n]/.test(value), 'loader manifest field contains a delimiter');
  return value;
};
fs.writeFileSync(loaderManifestArg,
  'asset_path\tsha256\tbytes\tcontent_type\tcache_control\n'
    + objects.map(item => [item.key,item.sha256,String(item.bytes),
      item.contentType,item.cacheControl].map(clean).join('\t')).join('\n')
    + '\n', {mode: 0o600});
