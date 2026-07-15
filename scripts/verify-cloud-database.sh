#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
policy="$root/deploy/cloud/t11.1/source-policy.json"
evidence=/tmp/doomdb-t111-evidence.json
tmp=''; transport_installed=0

die(){ printf 'T11.1 NOT RUN: %s\n' "$*" >&2; exit 1; }
sha(){ if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"|awk '{print $1}'; else shasum -a 256 "$1"|awk '{print $1}'; fi; }
sql_input(){
  printf '%s\n' 'whenever oserror exit failure rollback' 'whenever sqlerror exit sql.sqlcode rollback' 'set echo off verify off define off'
  credential_line="connect $ADB_USERNAME/\"$ADB_PASSWORD\"@$ADB_CONNECTION_STRING"
  printf '%s\n' "$credential_line"
  command cat "$1"
}
sql_file(){ sql_input "$1" | timeout 1800 sql -s /nolog | node "$root/scripts/redact-cloud-output.mjs"; }
cleanup(){
  local status=$?;trap - EXIT HUP INT TERM
  if [[ "$transport_installed" == 1 && -n "$tmp" ]]; then
    if ! sql_file "$root/deploy/local/probes/transport/uninstall.sql" >"$tmp/transport-cleanup.log" 2>&1; then status=1; fi
  fi
  [[ -z "$tmp" ]] || rm -rf "$tmp"
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN ADB_PASSWORD ADB_CONNECTION_STRING ADB_ORDS_BASE_URL
  exit "$status"
}
trap cleanup EXIT HUP INT TERM
rm -f "$evidence"

for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR ADB_ORDS_BASE_URL ADB_LOCAL_SEED_EVIDENCE ADB_EXPECTED_MAX_CPU ADB_EXPECTED_MAX_STORAGE_GB ADB_EXPECTED_AUTOSCALING; do
  [[ -n "${!name:-}" ]] || die "required environment variable is absent: $name"
done
[[ "$ADB_EXPECTED_MAX_CPU" =~ ^[1-9][0-9]*$ ]] || die 'ADB_EXPECTED_MAX_CPU must be a positive integer'
[[ "$ADB_EXPECTED_MAX_STORAGE_GB" =~ ^[1-9][0-9]*$ ]] || die 'ADB_EXPECTED_MAX_STORAGE_GB must be a positive integer'
[[ "$ADB_EXPECTED_AUTOSCALING" == true || "$ADB_EXPECTED_AUTOSCALING" == false ]] || die 'ADB_EXPECTED_AUTOSCALING must be true or false'
[[ "$ADB_CONNECTION_STRING" =~ ^[A-Za-z0-9._:/?=@-]+$ ]] || die 'connection identifier contains unsupported characters'
[[ "$ADB_ORDS_BASE_URL" =~ ^https://[^/?#]+/ords/[A-Za-z0-9._~-]+/?$ ]] || die 'managed ORDS base must be an HTTPS schema root without query or fragment'
[[ -d "$ADB_WALLET_DIR" && ! -L "$ADB_WALLET_DIR" ]] || die 'wallet directory must be a real directory'
[[ "$(cd "$ADB_WALLET_DIR" && pwd -P)" != "$root"* ]] || die 'wallet directory must be outside the repository'
while IFS= read -r credential_file; do
  [[ -f "$credential_file" && ! -L "$credential_file" ]] || die 'wallet entries must be regular files'
  mode=$(stat -f '%Lp' "$credential_file" 2>/dev/null || stat -c '%a' "$credential_file")
  [[ "$mode" == 600 || "$mode" == 400 ]] || die 'wallet files must have mode 0600 or stricter'
done < <(find "$ADB_WALLET_DIR" -mindepth 1 -maxdepth 1 -print)
[[ -s "$ADB_LOCAL_SEED_EVIDENCE" ]] || die 'fresh local seed evidence is absent or empty'

command -v sql >/dev/null 2>&1 || die 'pinned SQLcl is unavailable'
sql_version=$(sql -version 2>&1 | sed -n '1{s/[^0-9]*\([0-9][0-9.]*\).*/\1/p;}')
[[ "$sql_version" == 26.2.0.181.2110 ]] || die "SQLcl version mismatch (required 26.2.0.181.2110)"
for tool in node curl jq gzip base64 openssl timeout; do command -v "$tool" >/dev/null 2>&1 || die "$tool is unavailable"; done
tmp=$(mktemp -d "${TMPDIR:-/tmp}/doomdb-t111.XXXXXX");chmod 700 "$tmp";touch "$tmp/permission-probe";chmod 600 "$tmp/permission-probe"
export TNS_ADMIN="$ADB_WALLET_DIR"

# Provenance/catalog vocabulary is pinned here as well as in the reviewed SQL:
# ADB_IS_AUTONOMOUS ADB_SERVICE ADB_WORKLOAD, PRODUCT_COMPONENT_VERSION,
# V$PDBS, DBMS_CLOUD, USER_OBJECTS, USER_ERRORS, USER_CONSTRAINTS,
# USER_SYS_PRIVS, USER_TAB_PRIVS, and ORDS_METADATA.

# Pinned entrance sources: tests/verify-oracle-probes.sh and scripts/verify-transport.sh
node - "$root" "$policy" <<'NODE'
import crypto from 'node:crypto';import fs from 'node:fs';import path from 'node:path';
const [root,policyPath]=process.argv.slice(2),p=JSON.parse(fs.readFileSync(policyPath));
for(const [name,[rel,want]] of Object.entries(p.p0)){const got=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,rel))).digest('hex');if(got!==want)throw Error(`P0 source drift: ${name}`)}
NODE
"$root/tests/verify-oracle-probes.sh" >"$tmp/p0-static.log"
cmp -s "$root/probes/oracle/capabilities.sql" "$root/cloud/probes/oracle/capabilities.sql" || die 'cloud capability probe is not byte-identical'

# Live P0 capability probe runs before any production deployment and owns cleanup.
ORACLE_ADMIN_CONNECT="$ADB_USERNAME/\"$ADB_PASSWORD\"@$ADB_CONNECTION_STRING" \
ORACLE_CONNECT_IDENTIFIER="$ADB_CONNECTION_STRING" SQL_CLIENT=sql \
PROBE_SQL="$root/cloud/probes/oracle/capabilities.sql" \
timeout 1800 "$root/probes/oracle/run.sh" 2>&1 | node "$root/scripts/redact-cloud-output.mjs" >"$tmp/capabilities.log"

# Live transport install, managed-ORDS execution, and unconditional uninstall.
sql_file "$root/deploy/local/probes/transport/install.sql" >"$tmp/transport-install.log";transport_installed=1
DOOM_ORDS_URL="$ADB_ORDS_BASE_URL" timeout 1800 "$root/scripts/verify-transport.sh" >"$tmp/transport.log" 2>&1
sql_file "$root/deploy/local/probes/transport/uninstall.sql" >"$tmp/transport-uninstall.log";transport_installed=0

# Resolve the exact local sql/schema, sql/seed, sql/engine, and sql/rest sources
# into one SQLcl input while retaining the byte order from the local bootstrap.
ledger="$tmp/deployment.ledger";deploy_sql="$tmp/deploy.sql";: >"$ledger";: >"$deploy_sql";chmod 600 "$ledger" "$deploy_sql"
printf '%s\n' 'whenever oserror exit failure rollback' 'whenever sqlerror exit sql.sqlcode rollback' 'set echo off verify off define off' >>"$deploy_sql"
credential_line="connect $ADB_USERNAME/\"$ADB_PASSWORD\"@$ADB_CONNECTION_STRING"
printf '%s\n' "$credential_line" >>"$deploy_sql"
while IFS= read -r entry || [[ -n "$entry" ]]; do
  [[ -z "$entry" || "$entry" == \#* ]] && continue
  if [[ "$entry" == '@seed-manifest' ]]; then
    while IFS= read -r seed; do
      path="sql/seed/$seed";file="$root/$path";printf 'seed|%s|%s\n' "$path" "$(sha "$file")" >>"$ledger"
      if [[ "$seed" == 160_asset_texels_*.sql ]]; then node "$root/tools/wad/at-load-sql.mjs" "$file" >>"$deploy_sql"; else command cat "$file" >>"$deploy_sql"; fi
      printf '%s\n' 'commit;' >>"$deploy_sql"
    done < <(node "$root/tools/wad/seed-load-order.mjs")
    continue
  fi
  [[ "$entry" =~ ^sql/(bootstrap|schema|engine|spatial|bsp|accel|render|sim)/[A-Za-z0-9._/-]+\.sql$ && "$entry" != *..* ]] || die "unsafe bootstrap entry: $entry"
  case "$entry" in sql/bootstrap/*|sql/schema/*) domain=schema;; *) domain=engine;; esac
  printf '%s|%s|%s\n' "$domain" "$entry" "$(sha "$root/$entry")" >>"$ledger";command cat "$root/$entry" >>"$deploy_sql";printf '%s\n' 'commit;' >>"$deploy_sql"
done <"$root/sql/bootstrap/order.txt"
for entry in sql/rest/010_doom_api.sql sql/rest/020_ords_enable.sql deploy/cloud/t11.1/least-grants.sql; do
  printf 'rest|%s|%s\n' "$entry" "$(sha "$root/$entry")" >>"$ledger";command cat "$root/$entry" >>"$deploy_sql";printf '%s\n' 'commit;' >>"$deploy_sql"
done
printf '%s\n' 'exit success commit' >>"$deploy_sql"
node "$root/scripts/t11.1-deployment-manifest.mjs" "$ledger" "$tmp/deployment.json"
timeout 14400 sql -s /nolog <"$deploy_sql" | node "$root/scripts/redact-cloud-output.mjs" >"$tmp/deployment.log"

sql_file "$root/deploy/cloud/t11.1/catalog-observation.sql" >"$tmp/catalog.log"
sql_file "$root/deploy/cloud/t11.1/seed-observation.sql" >"$tmp/cloud-seeds.log"
curl --connect-timeout 20 --max-time 180 --fail-with-body --silent --show-error "$ADB_ORDS_BASE_URL/public_health/" >"$tmp/managed-ords-health.json"
ADB_ORDS_BASE_URL="$ADB_ORDS_BASE_URL" timeout 3600 node "$root/scripts/t11.1-cloud-api.mjs" >"$tmp/api.json"

cpu=$(sed -n 's/^T111_RESOURCES|\([0-9][0-9]*\)|.*/\1/p' "$tmp/catalog.log")
storage=$(sed -n 's/^T111_RESOURCES|[0-9][0-9]*|\([0-9][0-9]*\)$/\1/p' "$tmp/catalog.log")
[[ -n "$cpu" && "$cpu" -le "$ADB_EXPECTED_MAX_CPU" ]] || die 'live CPU exceeds declared resource policy'
[[ -n "$storage" && "$storage" -le "$ADB_EXPECTED_MAX_STORAGE_GB" ]] || die 'live storage exceeds declared resource policy'

candidate="$tmp/doomdb-t111-evidence.json"
node "$root/scripts/t11.1-build-evidence.mjs" "$policy" "$tmp/capabilities.log" "$tmp/transport.log" "$tmp/catalog.log" "$ADB_LOCAL_SEED_EVIDENCE" "$tmp/cloud-seeds.log" "$tmp/api.json" "$tmp/deployment.json" "$candidate"
node "$root/evaluator/t11.1/validate-evidence.mjs" "$candidate" >"$tmp/validation.log"
rg -n -i '(password|authorization|bearer |wallet|private_key|aws_access|secret_access|connection_string|adb_username|adb_password|https://|jdbc:|oracle\.net|tnsnames)' "$candidate" && die 'secret or endpoint material reached evidence'
mv "$candidate" /tmp/doomdb-t111-evidence.json
printf 'PASS T11.1-CLOUD-DATABASE (live Autonomous Database and managed ORDS evidence published)\n'
