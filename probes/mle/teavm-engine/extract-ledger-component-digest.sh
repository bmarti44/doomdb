#!/bin/sh
set -eu

extract_digest() {
  label=$1
  input=$2
  case "$label" in
    *[!A-Za-z0-9._-]*|'')
      printf 'invalid component profile label: %s\n' "$label" >&2
      return 2
      ;;
  esac

  # SQLcl may fold a long DBMS_OUTPUT marker at its configured line width.
  # Reassemble only component-profile records until their digest field has at
  # least 64 physical characters; the anchored sed below remains the
  # fail-closed syntax and exact-length gate.
  normalized=$(awk '
    /^PMLE_LEDGER_COMPONENT_PROFILE[|]/ {
      record=$0
      split(record, parts, "cumulative_sha256=")
      while (length(parts[2]) < 64 && (getline continuation) > 0) {
        record=record continuation
        split(record, parts, "cumulative_sha256=")
      }
      print record
    }
  ' "$input")
  digest=$(printf '%s\n' "$normalized" | sed -n \
    "s/^PMLE_LEDGER_COMPONENT_PROFILE|PASS|label=${label}|.*|cumulative_sha256=\\([0-9a-f]\\{64\\}\\)$/\\1/p" \
  )
  count=$(printf '%s\n' "$digest" | awk 'NF { count++ } END { print count + 0 }')
  if [ "$count" -ne 1 ]; then
    printf 'expected exactly one component digest for %s, found %s\n' \
      "$label" "$count" >&2
    return 1
  fi
  printf '%s\n' "$digest"
}

self_test() {
  fixture=$(mktemp "${TMPDIR:-/tmp}/pmle-component-extractor.XXXXXX")
  trap 'rm -f "$fixture"' EXIT HUP INT TERM
  expected=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

  printf '%s\n' \
    "PMLE_LEDGER_COMPONENT_PROFILE|PASS|label=synthetic|tics=500|cumulative_sha256=$expected" \
    >"$fixture"
  actual=$(extract_digest synthetic "$fixture")
  [ "$actual" = "$expected" ] || {
    printf 'component digest extractor self-test mismatch: expected=%s actual=%s\n' \
      "$expected" "$actual" >&2
    return 1
  }

  {
    printf '%s' \
      'PMLE_LEDGER_COMPONENT_PROFILE|PASS|label=synthetic|tics=500|cumulative_sha256=0123456789ab'
    printf '%s\n' \
      'cdef0123456789abcdef0123456789abcdef0123456789abcdef'
  } >"$fixture"
  actual=$(extract_digest synthetic "$fixture")
  [ "$actual" = "$expected" ] || {
    printf 'component digest wrapped extractor self-test mismatch: expected=%s actual=%s\n' \
      "$expected" "$actual" >&2
    return 1
  }

  printf '%s\n' \
    "PMLE_LEDGER_COMPONENT_PROFILE|PASS|label=synthetic|tics=500|cumulative_sha256=${expected}|trailing=corruption" \
    >"$fixture"
  if extract_digest synthetic "$fixture" >/dev/null 2>&1; then
    printf '%s\n' 'component digest extractor accepted a non-terminal digest' >&2
    return 1
  fi

  printf 'PMLE_LEDGER_COMPONENT_EXTRACTOR|PASS|synthetic_sha256=%s\n' "$expected"
}

case "${1:-}" in
  --self-test)
    [ "$#" -eq 1 ] || {
      printf '%s\n' 'usage: extract-ledger-component-digest.sh --self-test' >&2
      exit 2
    }
    self_test
    ;;
  '')
    printf '%s\n' 'usage: extract-ledger-component-digest.sh LABEL LOG' >&2
    exit 2
    ;;
  *)
    [ "$#" -eq 2 ] || {
      printf '%s\n' 'usage: extract-ledger-component-digest.sh LABEL LOG' >&2
      exit 2
    }
    extract_digest "$1" "$2"
    ;;
esac
