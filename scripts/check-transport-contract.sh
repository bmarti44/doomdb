#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
install="$root/deploy/local/probes/transport/install.sql"
runner="$root/scripts/verify-transport.sh"

test -s "$install"
test -s "$root/deploy/local/probes/transport/uninstall.sql"
test -x "$runner"
grep -q 'ords.enable_object' "$install"
! grep -Eqi 'ords\.define_(module|template|handler)' "$install"
grep -q 'utl_compress.lz_compress' "$install"
grep -q 'application/json' "$runner"
grep -q 'base64 --decode' "$runner"
grep -q 'gzip -t' "$runner"
grep -q 'TRANSACTION_COUNT' "$runner"
grep -q 'TRANSPORT_FRAME_BYTES' "$runner"
grep -q 'TRANSPORT_ASSET_BYTES' "$runner"

printf 'PASS T0.3-static (12/12 assertions)\n'
