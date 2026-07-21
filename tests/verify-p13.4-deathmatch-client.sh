#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
DOOMDB_MATCH_MODE=DEATHMATCH DOOMDB_TEST_ORDS_RESTART=0 \
  tests/verify-p13.3-multiplayer-client.sh
