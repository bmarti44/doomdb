#!/usr/bin/env bash
set -euo pipefail

: "${DOOM_ORDS_URL:=http://localhost:8080/ords/doom}"
base="${DOOM_ORDS_URL%/}/transport_probe_api"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

post() {
  local proc="$1" body="$2" output="$3"
  curl --fail-with-body --silent --show-error \
    -H 'Content-Type: application/json' \
    -H 'Origin: https://doomdb.invalid' \
    -X POST --data-binary "$body" \
    -D "${output}.headers" -o "${output}.json" \
    "${base}/${proc}"
}

post ECHO_CONTRACT '{"p_number":12.5,"p_text":"doomdb-transport"}' "$tmp/echo"
jq -e '.p_out_varchar == "12.5" and .p_out_clob == "doomdb-transport" and (.p_out_blob|type == "string")' "$tmp/echo.json" >/dev/null
jq -r '.p_out_blob' "$tmp/echo.json" | base64 --decode >"$tmp/payload.gz"
gzip -t "$tmp/payload.gz"
gzip -dc "$tmp/payload.gz" | jq -e '.number == 12.5 and .text == "doomdb-transport"' >/dev/null

grep -Eiq '^access-control-allow-origin:[[:space:]]*(\*|https://doomdb.invalid)' "$tmp/echo.headers"

http_code="$(curl --silent --show-error -o "$tmp/fail.json" -w '%{http_code}' \
  -H 'Content-Type: application/json' -X POST \
  --data-binary '{"p_marker":"rollback-probe"}' "${base}/FAIL_AFTER_WRITE")"
case "$http_code" in 4??|5??) ;; *) printf 'expected error status, got %s\n' "$http_code" >&2; exit 1;; esac

post TRANSACTION_COUNT '{}' "$tmp/count"
jq -e '.p_count == 0' "$tmp/count.json" >/dev/null

# The frame-sized and asset-sized calls intentionally exercise ORDS base64 expansion.
for bytes in "${TRANSPORT_FRAME_BYTES:-2097152}" "${TRANSPORT_ASSET_BYTES:-8388608}"; do
  start="$(date +%s)"
  post SIZED_PAYLOAD "{\"p_uncompressed_bytes\":${bytes}}" "$tmp/size-${bytes}"
  jq -r '.p_out_blob' "$tmp/size-${bytes}.json" | base64 --decode >"$tmp/size-${bytes}.gz"
  gzip -t "$tmp/size-${bytes}.gz"
  printf '%s,%s,%s\n' "$bytes" "$(wc -c <"$tmp/size-${bytes}.json" | tr -d ' ')" "$(( $(date +%s) - start ))"
done

printf 'PASS transport (11/11 assertions)\n'
