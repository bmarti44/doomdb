#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
archive="$root/vendor/freedoom/0.13.0/freedoom-0.13.0.zip"
archive_sha256=3f9b264f3e3ce503b4fb7f6bdcb1f419d93c7b546f4df3e874dd878db9688f59
wad_member=freedoom-0.13.0/freedoom1.wad
wad_sha256=7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d

fail() {
  printf 'verify Freedoom vendor: %s\n' "$*" >&2
  exit 1
}

assertions=0
pass() {
  assertions=$((assertions + 1))
}

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    fail 'neither sha256sum nor shasum is available'
  fi
}

[[ -f "$archive" ]] || fail 'pinned release archive is missing'
pass

[[ "$(sha256_file "$archive")" == "$archive_sha256" ]] || fail 'release archive SHA-256 mismatch'
pass

[[ "$(unzip -Z1 "$archive" | awk -v member="$wad_member" '$0 == member { count++ } END { print count + 0 }')" == 1 ]] || fail 'freedoom1.wad is missing or duplicated in archive'
pass

tmp="$(mktemp -d "${TMPDIR:-/tmp}/doomdb-freedoom.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
unzip -p "$archive" "$wad_member" > "$tmp/freedoom1.wad" || fail 'could not extract freedoom1.wad'
[[ -s "$tmp/freedoom1.wad" ]] || fail 'extracted freedoom1.wad is empty'
pass

[[ "$(sha256_file "$tmp/freedoom1.wad")" == "$wad_sha256" ]] || fail 'freedoom1.wad SHA-256 mismatch'
pass

[[ "$(LC_ALL=C dd if="$tmp/freedoom1.wad" bs=4 count=1 2>/dev/null)" == IWAD ]] || fail 'freedoom1.wad does not have an IWAD header'
pass

for legal_file in COPYING.txt CREDITS.txt CREDITS-MUSIC.txt; do
  copied="$root/vendor/freedoom/0.13.0/$legal_file"
  [[ -f "$copied" ]] || fail "$legal_file copy is missing"
  unzip -p "$archive" "freedoom-0.13.0/$legal_file" > "$tmp/$legal_file" || fail "could not read $legal_file from archive"
  cmp -s "$copied" "$tmp/$legal_file" || fail "$legal_file differs from the release archive"
  pass
done

[[ "$(awk -F '\t' '$1 == "freedoom" && $3 == "0.13.0" && $6 == "BSD-3-Clause" { count++ } END { print count + 0 }' "$root/reports/license-ledger.tsv")" == 1 ]] || fail 'license/source ledger lacks the unique Freedoom 0.13.0 BSD-3-Clause row'
pass

printf 'PASS T2.1 (%s/%s assertions; offline)\n' "$assertions" "$assertions"
