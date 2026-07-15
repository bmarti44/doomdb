#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

for command_name in docker jq npm; do
  command -v "$command_name" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $command_name" >&2
    exit 1
  }
done

case "$(uname -m)" in
  x86_64|amd64) platform=linux/amd64 ;;
  arm64|aarch64) platform=linux/arm64 ;;
  *) echo "ERROR: unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

echo "Caching locked npm dependencies (network is expected in this command)."
npm ci --ignore-scripts

image_list=${TMPDIR:-/tmp}/doomdb-images.$$
trap 'rm -f "$image_list"' EXIT HUP INT TERM
jq -r --arg platform "$platform" '.images[] | .tag + "@" + .[$platform]' versions.lock > "$image_list"
while IFS= read -r image; do
  echo "Caching $image"
  docker pull --platform "$platform" "$image"
done < "$image_list"

echo "Dependency cache is populated; run scripts/verify_env.sh without network access."
