#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/doomdb-env-rejections.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT HUP INT TERM

make_case() {
  case_root=$1
  mkdir -p "$case_root/scripts" "$case_root/reports"
  cp "$ROOT/.nvmrc" "$ROOT/package.json" "$ROOT/package-lock.json" "$ROOT/versions.lock" "$case_root/"
  cp "$ROOT/scripts/verify_env.sh" "$case_root/scripts/"
  cp "$ROOT/reports/license-ledger.tsv" "$case_root/reports/"
}

expect_rejection() {
  name=$1
  expected=$2
  case_root=$3
  if (cd "$case_root" && sh scripts/verify_env.sh) > "$case_root/output" 2>&1; then
    echo "FAIL: $name mutation was accepted" >&2
    exit 1
  fi
  if grep -F "$expected" "$case_root/output" >/dev/null; then
    echo "PASS: $name mutation was rejected for the intended reason"
  else
    echo "FAIL: $name mutation failed for an unintended reason" >&2
    sed -n '1,160p' "$case_root/output" >&2
    exit 1
  fi
}

floating="$TMP_ROOT/floating"
make_case "$floating"
(cd "$floating" && node -e 'const fs=require("fs"); const p="versions.lock"; const v=JSON.parse(fs.readFileSync(p)); v.images.playwright.tag="mcr.microsoft.com/playwright:latest"; fs.writeFileSync(p, JSON.stringify(v,null,2)+"\n")')
expect_rejection floating-tag "has a floating or malformed tag" "$floating"

unlocked="$TMP_ROOT/unlocked"
make_case "$unlocked"
(cd "$unlocked" && node -e 'const fs=require("fs"); const p="package.json"; const v=JSON.parse(fs.readFileSync(p)); v.devDependencies.typescript="^7.0.2"; fs.writeFileSync(p, JSON.stringify(v,null,2)+"\n")')
expect_rejection unlocked-package "package manifest/lock is missing, floating, or inconsistent" "$unlocked"

license="$TMP_ROOT/license"
make_case "$license"
(cd "$license" && node -e 'const fs=require("fs"); const p="reports/license-ledger.tsv"; const lines=fs.readFileSync(p,"utf8").split("\n").filter(line => !line.startsWith("sqlcl\t")); fs.writeFileSync(p, lines.join("\n"))')
expect_rejection missing-license "license ledger is missing sqlcl" "$license"

if grep -E 'docker[[:space:]]+(pull|manifest)|curl[[:space:]].*https?://|npm[[:space:]]+(install|view)' "$ROOT/scripts/verify_env.sh" >/dev/null; then
  echo "FAIL: verifier contains a network-capable fetch operation" >&2
  exit 1
fi
grep -F 'npm ci --offline' "$ROOT/scripts/verify_env.sh" >/dev/null || {
  echo "FAIL: verifier does not force npm offline mode" >&2
  exit 1
}
echo "PASS: verifier contains no fetch operation and forces npm offline mode"
