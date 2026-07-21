#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
DOOMDB_MATCH_MODE=COOP DOOMDB_TEST_ORDS_RESTART=0 \
  DOOMDB_MULTIPLAYER_FRAMES=300 tests/verify-p13.3-multiplayer-client.sh
