#!/bin/sh
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
failures=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1" >&2; failures=$((failures + 1)); }
need() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "$1 is available"
  else
    fail "$1 is unavailable"
  fi
}

for command_name in docker node npm jq curl unzip; do need "$command_name"; done

if command -v sha256sum >/dev/null 2>&1; then
  hash_command=sha256sum
elif command -v shasum >/dev/null 2>&1; then
  hash_command='shasum -a 256'
else
  hash_command=
  fail "neither sha256sum nor shasum is available"
fi
if [ -n "$hash_command" ]; then
  actual=$(printf abc | $hash_command | awk '{print $1}')
  [ "$actual" = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad" ] &&
    pass "portable SHA-256 implementation is correct ($hash_command)" ||
    fail "portable SHA-256 implementation returned an incorrect digest"
fi

if command -v jq >/dev/null 2>&1 && jq -e . versions.lock >/dev/null 2>&1; then
  pass "versions.lock is valid JSON"
else
  fail "versions.lock is missing or invalid"
fi

expected_node=$(jq -r '.node.version' versions.lock 2>/dev/null)
actual_node=$(node --version 2>/dev/null | sed 's/^v//')
[ "$actual_node" = "$expected_node" ] && pass "Node is exactly $expected_node" ||
  fail "Node is $actual_node; expected $expected_node (use .nvmrc)"

expected_npm=$(jq -r '.node.npm' versions.lock 2>/dev/null)
actual_npm=$(npm --version 2>/dev/null)
[ "$actual_npm" = "$expected_npm" ] && pass "npm is exactly $expected_npm" ||
  fail "npm is $actual_npm; expected $expected_npm"

[ "$(tr -d '[:space:]' < .nvmrc 2>/dev/null)" = "$expected_node" ] &&
  pass ".nvmrc matches versions.lock" || fail ".nvmrc does not match versions.lock"

if node - <<'NODE'
const fs = require('fs');
const pkg = JSON.parse(fs.readFileSync('package.json'));
const lock = JSON.parse(fs.readFileSync('package-lock.json'));
const versions = JSON.parse(fs.readFileSync('versions.lock'));
if (lock.lockfileVersion !== 3 || !lock.packages || !lock.packages['']) process.exit(1);
if (lock.packages[''].engines.node !== versions.node.version) process.exit(1);
if (pkg.packageManager !== `npm@${versions.node.npm}`) process.exit(1);
for (const [name, version] of Object.entries(pkg.devDependencies || {})) {
  if (/^[~^*]|[<>=]|\s|\|/.test(version)) process.exit(1);
  if (versions.packages[name] !== version) process.exit(1);
  if (!lock.packages[`node_modules/${name}`] || lock.packages[`node_modules/${name}`].version !== version) process.exit(1);
}
NODE
then
  pass "package manifest and lock contain only exact direct dependency versions"
else
  fail "package manifest/lock is missing, floating, or inconsistent with versions.lock"
fi

tmp=${TMPDIR:-/tmp}/doomdb-offline-npm.$$
rm -rf "$tmp"
mkdir -p "$tmp"
cp package.json package-lock.json "$tmp/"
if (cd "$tmp" && npm ci --offline --ignore-scripts --no-audit --no-fund >/dev/null 2>&1); then
  pass "npm dependencies install from cache in offline mode"
else
  fail "npm offline install failed; run scripts/cache_dependencies.sh while online"
fi
rm -rf "$tmp"

if docker compose version >/dev/null 2>&1; then pass "Docker Compose is available"; else fail "Docker Compose is unavailable"; fi
if docker info >/dev/null 2>&1; then pass "Docker daemon is reachable"; else fail "Docker daemon is unreachable"; fi

case "$(uname -m)" in
  x86_64|amd64) platform=linux/amd64 ;;
  arm64|aarch64) platform=linux/arm64 ;;
  *) platform=; fail "unsupported host architecture: $(uname -m)" ;;
esac
[ -n "$platform" ] && pass "host architecture maps to $platform"

if [ -n "$platform" ] && docker info >/dev/null 2>&1; then
  image_list=${TMPDIR:-/tmp}/doomdb-verify-images.$$
  jq -r --arg platform "$platform" '.images | to_entries[] | [.key, .value.tag, .value[$platform]] | @tsv' versions.lock > "$image_list"
  while IFS="$(printf '\t')" read -r name tag digest; do
    case "$tag" in
      *:latest|*@*|*:) fail "$name has a floating or malformed tag: $tag"; continue ;;
      *:*) : ;;
      *) fail "$name has no explicit tag: $tag"; continue ;;
    esac
    if ! printf '%s\n' "$digest" | awk '/^sha256:[0-9a-f]{64}$/ { ok=1 } END { exit !ok }'; then
      fail "$name has an invalid platform digest"
      continue
    fi
    if docker image inspect "$tag@$digest" >/dev/null 2>&1; then
      pass "$name image is cached at $digest"
    else
      fail "$name image is not cached at $digest; run scripts/cache_dependencies.sh while online"
    fi
  done < "$image_list"
  rm -f "$image_list"
fi

required_licenses='node npm typescript playwright-test playwright playwright-core typescript-platform-binaries fsevents oracle-free-image ords-image playwright-image freedoom aws-cli sqlcl'
for component_id in $required_licenses; do
  if awk -F '\t' -v id="$component_id" 'NR > 1 && $1 == id { found=1 } END { exit !found }' reports/license-ledger.tsv; then
    pass "license ledger includes $component_id"
  else
    fail "license ledger is missing $component_id"
  fi
done

available_kb=$(df -Pk . | awk 'NR == 2 {print $4}')
minimum_kb=$((20 * 1024 * 1024))
if [ "${available_kb:-0}" -ge "$minimum_kb" ]; then
  pass "at least 20 GiB disk is available"
else
  fail "less than 20 GiB disk is available"
fi

credential_state() {
  label=$1
  shift
  present=yes
  for variable_name in "$@"; do
    eval "value=\${$variable_name-}"
    [ -n "$value" ] || present=no
  done
  if [ "$present" = yes ]; then printf 'INFO: %s credentials PRESENT\n' "$label"; else printf 'INFO: %s credentials ABSENT\n' "$label"; fi
}
credential_state AWS AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_REGION
credential_state ADB ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD

if [ "$failures" -ne 0 ]; then
  printf 'ENV RESULT: FAIL (%s checks failed)\n' "$failures" >&2
  exit 1
fi
printf 'ENV RESULT: PASS\n'
