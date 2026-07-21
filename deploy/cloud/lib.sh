#!/bin/sh

cloud_die() {
  printf 'cloud deploy: %s\n' "$*" >&2
  exit 1
}

cloud_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    cloud_die 'SHA-256 tool unavailable'
  fi
}

cloud_require_value() {
  cloud_name=$1
  eval "cloud_value=\${$cloud_name-}"
  [ -n "$cloud_value" ] || cloud_die "required environment variable is absent: $cloud_name"
}

cloud_check_execute_guard() {
  [ "${DOOMDB_CLOUD_EXECUTE-}" = 'YES' ] ||
    cloud_die 'execution requires DOOMDB_CLOUD_EXECUTE=YES in addition to --execute'
}

cloud_validate_adb_credentials() {
  case "$ADB_USERNAME" in
    ''|[!A-Za-z]*|*[!A-Za-z0-9_\$#]*)
      cloud_die 'ADB_USERNAME is not a simple Oracle identifier' ;;
  esac
  [ "${#ADB_USERNAME}" -le 128 ] ||
    cloud_die 'ADB_USERNAME exceeds the Oracle identifier limit'
  case "$ADB_CONNECTION_STRING" in
    ''|*[!A-Za-z0-9._:/?=@-]*)
      cloud_die 'ADB_CONNECTION_STRING contains unsupported characters' ;;
  esac
  cloud_cr=$(printf '\r')
  case "$ADB_PASSWORD" in
    *"\""*|*"$cloud_cr"*)
      cloud_die 'ADB_PASSWORD cannot be represented safely in a SQLcl connect command' ;;
  esac
  [ "$(printf '%s' "$ADB_PASSWORD" | wc -l | tr -d ' ')" -eq 0 ] ||
    cloud_die 'ADB_PASSWORD cannot contain a newline'
}

cloud_check_tool_version() {
  cloud_tool=$1
  cloud_expected=$2
  cloud_actual=$($cloud_tool --version 2>&1 | sed -n '1{s/[^0-9]*\([0-9][0-9.]*\).*/\1/p;}')
  [ "$cloud_actual" = "$cloud_expected" ] ||
    cloud_die "$cloud_tool version is ${cloud_actual:-unknown}; expected $cloud_expected"
}

cloud_validate_allowlist() {
  cloud_dir=$1
  cloud_allowlist=$2
  [ -d "$cloud_dir" ] || cloud_die "artifact directory does not exist: $cloud_dir"
  [ -f "$cloud_allowlist" ] || cloud_die "artifact allowlist does not exist: $cloud_allowlist"
  cloud_expected=${TMPDIR:-/tmp}/doomdb-cloud-expected.$$
  cloud_actual=${TMPDIR:-/tmp}/doomdb-cloud-actual.$$
  trap 'rm -f "$cloud_expected" "$cloud_actual"' EXIT HUP INT TERM
  LC_ALL=C sed '/^$/d' "$cloud_allowlist" | LC_ALL=C sort > "$cloud_expected"
  while IFS= read -r cloud_entry; do
    case "$cloud_entry" in
      /*|../*|*/../*|*/..|.|..|*'//'*) cloud_die "unsafe allowlist entry: $cloud_entry" ;;
    esac
  done < "$cloud_expected"
  (cd "$cloud_dir" && find . -type f -print | sed 's#^./##' | LC_ALL=C sort) > "$cloud_actual"
  cmp -s "$cloud_expected" "$cloud_actual" || {
    printf 'cloud deploy: artifact set differs from allowlist\n' >&2
    diff -u "$cloud_expected" "$cloud_actual" >&2 || true
    exit 1
  }
  while IFS= read -r cloud_entry; do
    [ ! -L "$cloud_dir/$cloud_entry" ] || cloud_die "symlink artifact is forbidden: $cloud_entry"
  done < "$cloud_expected"
}
