#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sql_client="${SQL_CLIENT:-sql}"
admin_username="${ADB_ADMIN_USERNAME:-${ADB_USERNAME:-}}"
admin_password="${ADB_ADMIN_PASSWORD:-${ADB_PASSWORD:-}}"
policy="$root/deploy/cloud/t11.1/source-policy.json"
evidence=/tmp/doomdb-t111-evidence.json
tmp=''; transport_installed=0
phase=preflight

die(){ printf 'T11.1 NOT RUN: %s\n' "$*" >&2; exit 1; }
sha(){ if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"|awk '{print $1}'; else shasum -a 256 "$1"|awk '{print $1}'; fi; }
show_failure(){
  local log=$1
  [[ -f "$log" ]] || return 0
  node "$root/scripts/redact-cloud-output.mjs" <"$log" |
    tail -80 >&2
}
sql_input(){
  printf '%s\n' 'whenever oserror exit failure rollback' 'whenever sqlerror exit sql.sqlcode rollback' 'set echo off verify off define off'
  credential_line="connect $ADB_USERNAME/\"$ADB_PASSWORD\"@$ADB_CONNECTION_STRING"
  printf '%s\n' "$credential_line"
  printf '%s\n' "alter session set plsql_ccflags='doom_dev_ojvm:false';"
  command cat "$1"
}
sql_file_timeout(){ local seconds=$1; shift; sql_input "$1" |
  timeout "$seconds" "$sql_client" -s /nolog |
  node "$root/scripts/redact-cloud-output.mjs"; }
sql_file(){ sql_file_timeout 1800 "$1"; }
admin_sql_file(){
  local input=$1
  {
    printf '%s\n' 'whenever oserror exit failure rollback' \
      'whenever sqlerror exit sql.sqlcode rollback' \
      'set echo off verify off define off'
    printf 'connect %s/"%s"@%s\n' \
      "$admin_username" "$admin_password" "$ADB_CONNECTION_STRING"
    command cat "$input"
    printf '%s\n' 'exit success commit'
  } | timeout 1800 "$sql_client" -s /nolog |
    node "$root/scripts/redact-cloud-output.mjs"
}
cleanup(){
  local status=$?;trap - EXIT HUP INT TERM
  if [[ "$transport_installed" == 1 && -n "$tmp" ]]; then
    if ! sql_file "$root/deploy/local/probes/transport/uninstall.sql" >"$tmp/transport-cleanup.log" 2>&1; then status=1; fi
  fi
  if [[ "$status" != 0 && -n "$tmp" && -d "$tmp" ]]; then
    failure_dir=$(mktemp -d "${TMPDIR:-/tmp}/doomdb-t111-failure.XXXXXX")
    chmod 700 "$failure_dir"
    for source in "$tmp"/*.log "$tmp"/*.json; do
      [[ -f "$source" && ! -L "$source" ]] || continue
      node "$root/scripts/redact-cloud-output.mjs" <"$source" \
        >"$failure_dir/$(basename "$source")"
      chmod 600 "$failure_dir/$(basename "$source")"
    done
    printf 'T11.1 redacted failure diagnostics retained: %s\n' \
      "$failure_dir" >&2
  fi
  [[ -z "$tmp" ]] || rm -rf "$tmp"
  unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN ADB_PASSWORD ADB_CONNECTION_STRING ADB_ORDS_BASE_URL
  unset ADB_ADMIN_PASSWORD
  if [[ "$status" != 0 ]]; then
    printf 'T11.1 FAIL: phase=%s (redacted underlying diagnostics shown above where available)\n' \
      "$phase" >&2
  fi
  exit "$status"
}
trap cleanup EXIT HUP INT TERM
rm -f "$evidence"

[[ "${DOOMDB_CLOUD_EXECUTE:-}" == YES ]] || die 'execution requires DOOMDB_CLOUD_EXECUTE=YES'
for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR ADB_ORDS_BASE_URL ADB_LOCAL_SEED_EVIDENCE ADB_EXPECTED_MAX_CPU ADB_EXPECTED_MAX_STORAGE_GB ADB_EXPECTED_AUTOSCALING; do
  [[ -n "${!name:-}" ]] || die "required environment variable is absent: $name"
done
[[ "$ADB_EXPECTED_MAX_CPU" =~ ^[1-9][0-9]*$ ]] || die 'ADB_EXPECTED_MAX_CPU must be a positive integer'
[[ "$ADB_EXPECTED_MAX_STORAGE_GB" =~ ^[1-9][0-9]*$ ]] || die 'ADB_EXPECTED_MAX_STORAGE_GB must be a positive integer'
[[ "$ADB_EXPECTED_AUTOSCALING" == true || "$ADB_EXPECTED_AUTOSCALING" == false ]] || die 'ADB_EXPECTED_AUTOSCALING must be true or false'
[[ "$ADB_USERNAME" =~ ^[A-Za-z][A-Za-z0-9_\$#]{0,127}$ ]] || die 'ADB_USERNAME is not a simple Oracle identifier'
[[ "$ADB_USERNAME" == DOOM ]] ||
  die 'production managed-ORDS schema must be DOOM'
[[ "$admin_username" =~ ^[A-Za-z][A-Za-z0-9_\$#]{0,127}$ ]] ||
  die 'ADB_ADMIN_USERNAME is not a simple Oracle identifier'
[[ "$ADB_PASSWORD" != *'"'* && "$ADB_PASSWORD" != *$'\n'* && "$ADB_PASSWORD" != *$'\r'* ]] || die 'ADB_PASSWORD cannot be represented safely in a SQLcl connect command'
[[ "$admin_password" != *'"'* && "$admin_password" != *$'\n'* &&
    "$admin_password" != *$'\r'* ]] ||
  die 'ADB_ADMIN_PASSWORD cannot be represented safely in a SQLcl connect command'
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

command -v "$sql_client" >/dev/null 2>&1 || die 'pinned SQLcl is unavailable'
sql_version=$("$sql_client" -version 2>&1 |
  sed -n 's/.*Production Build: \([0-9][0-9.]*\).*/\1/p')
[[ "$sql_version" == 26.2.0.181.2110 ]] || die "SQLcl version mismatch (required 26.2.0.181.2110)"
for tool in node curl jq gzip base64 openssl timeout; do command -v "$tool" >/dev/null 2>&1 || die "$tool is unavailable"; done
tmp=$(mktemp -d "${TMPDIR:-/tmp}/doomdb-t111.XXXXXX");chmod 700 "$tmp";touch "$tmp/permission-probe";chmod 600 "$tmp/permission-probe"
export TNS_ADMIN="$ADB_WALLET_DIR"

# Provenance/catalog vocabulary is pinned here as well as in the reviewed SQL:
# ADB_IS_AUTONOMOUS ADB_SERVICE ADB_WORKLOAD, PRODUCT_COMPONENT_VERSION,
# V$PDBS, PRODUCT_COMPONENT_VERSION, USER_OBJECTS, USER_ERRORS, USER_CONSTRAINTS,
# USER_SYS_PRIVS, USER_TAB_PRIVS, and ORDS_METADATA.

# Pinned entrance sources: tests/verify-oracle-probes.sh and scripts/verify-transport.sh
node - "$root" "$policy" <<'NODE'
import crypto from 'node:crypto';import fs from 'node:fs';import path from 'node:path';
const [root,policyPath]=process.argv.slice(2),p=JSON.parse(fs.readFileSync(policyPath));
for(const [name,[rel,want]] of Object.entries(p.p0)){const got=crypto.createHash('sha256').update(fs.readFileSync(path.join(root,rel))).digest('hex');if(got!==want)throw Error(`P0 source drift: ${name}`)}
NODE
node "$root/tests/verify-production-drop-inventory.mjs" \
  >"$tmp/drop-inventory.log"
"$root/tests/verify-oracle-probes.sh" >"$tmp/p0-static.log"
cmp -s "$root/probes/oracle/capabilities.sql" "$root/cloud/probes/oracle/capabilities.sql" || die 'cloud capability probe is not byte-identical'

# Live P0 capability probe runs before any production deployment and owns cleanup.
phase=capability_probe
ORACLE_ADMIN_CONNECT="$admin_username/\"$admin_password\"@$ADB_CONNECTION_STRING" \
ORACLE_CONNECT_IDENTIFIER="$ADB_CONNECTION_STRING" ORACLE_PROBE_TABLESPACE=DATA \
SQL_CLIENT="$sql_client" \
PROBE_SQL="$root/cloud/probes/oracle/capabilities.sql" \
timeout 1800 "$root/probes/oracle/run.sh" 2>&1 |
  node "$root/scripts/redact-cloud-output.mjs" >"$tmp/capabilities.log" || {
    show_failure "$tmp/capabilities.log";exit 1; }

# Re-assert the reviewed direct-grant surface after the capability probe and
# before installing any production object. This is idempotent and tracked in
# the deployment manifest.
phase=schema_privileges
if ! admin_sql_file "$root/deploy/cloud/t11.1/schema-grants.sql" \
    >"$tmp/schema-grants.log" 2>&1; then
  show_failure "$tmp/schema-grants.log";exit 1
fi

# Live transport install, managed-ORDS execution, and unconditional uninstall.
phase=transport_probe
if ! sql_file "$root/deploy/local/probes/transport/install.sql" \
    >"$tmp/transport-install.log" 2>&1; then
  show_failure "$tmp/transport-install.log";exit 1
fi
transport_installed=1
if ! DOOM_ORDS_URL="$ADB_ORDS_BASE_URL" timeout 1800 \
    "$root/scripts/verify-transport.sh" >"$tmp/transport.log" 2>&1; then
  show_failure "$tmp/transport.log";exit 1
fi
if ! sql_file "$root/deploy/local/probes/transport/uninstall.sql" \
    >"$tmp/transport-uninstall.log" 2>&1; then
  show_failure "$tmp/transport-uninstall.log";exit 1
fi
transport_installed=0

# Resolve the production sql/schema, sql/seed, sql/engine, and sql/rest
# bootstrap into schema/asset and MLE-runtime SQLcl
# inputs. The explicit @mle-module boundary is where pinned IWAD assets and the
# SHA-fenced TeaVM module are loaded; no loadjava/OJVM step exists.
ledger="$tmp/deployment.ledger"
phase=deployment_assembly
pre_sql="$tmp/deploy-pre-mle.sql"
post_sql="$tmp/deploy-post-mle.sql"
: >"$ledger";: >"$pre_sql";: >"$post_sql"
chmod 600 "$ledger" "$pre_sql" "$post_sql"
printf 'schema|%s|%s\n' \
  'deploy/cloud/t11.1/schema-grants.sql' \
  "$(sha "$root/deploy/cloud/t11.1/schema-grants.sql")" >>"$ledger"
for file in "$pre_sql" "$post_sql"; do
  printf '%s\n' 'whenever oserror exit failure rollback' 'whenever sqlerror exit sql.sqlcode rollback' 'set echo off verify off define off' >>"$file"
done
credential_line="connect $ADB_USERNAME/\"$ADB_PASSWORD\"@$ADB_CONNECTION_STRING"
printf '%s\n' "$credential_line" >>"$pre_sql"
printf '%s\n' "$credential_line" >>"$post_sql"
printf '%s\n' "alter session set plsql_ccflags='doom_dev_ojvm:false';" >>"$pre_sql"
printf '%s\n' "alter session set plsql_ccflags='doom_dev_ojvm:false';" >>"$post_sql"
deployment_phase=pre
least_grants_written=0
while IFS= read -r entry || [[ -n "$entry" ]]; do
  [[ -z "$entry" || "$entry" == \#* ]] && continue
  if [[ "$entry" == '@mle-module' ]]; then
    deployment_phase=post
    continue
  fi
  if [[ "$entry" == '@mle-tic0-bank' ]]; then
    [[ "$deployment_phase" == post ]] ||
      die 'tic-zero checkpoint bank must follow the MLE module boundary'
    printf 'engine|%s|%s\n' \
      'probes/mle/teavm-engine/load-tic0-checkpoint-bank.sh' \
      "$(sha "$root/probes/mle/teavm-engine/load-tic0-checkpoint-bank.sh")" \
      >>"$ledger"
    "$root/probes/mle/teavm-engine/load-tic0-checkpoint-bank.sh" --emit-sql \
      >>"$post_sql"
    printf '%s\n' 'commit;' >>"$post_sql"
    continue
  fi
  if [[ "$entry" == '@mle-live-frame-module' ]]; then
    [[ "$deployment_phase" == post ]] ||
      die 'live-frame module must follow the MLE authority boundary'
    printf 'engine|%s|%s\n' \
      'probes/mle/load-live-frame-module.sh' \
      "$(sha "$root/probes/mle/load-live-frame-module.sh")" >>"$ledger"
    continue
  fi
  [[ "$deployment_phase" == pre ]] &&
    deploy_sql="$pre_sql" || deploy_sql="$post_sql"
  if [[ "$entry" == '@seed-manifest' ]]; then
    while IFS= read -r seed; do
      path="sql/seed/$seed";file="$root/$path";printf 'seed|%s|%s\n' "$path" "$(sha "$file")" >>"$ledger"
      if [[ "$seed" == 160_asset_texels_*.sql ]]; then node "$root/tools/wad/at-load-sql.mjs" "$file" >>"$deploy_sql"; else command cat "$file" >>"$deploy_sql"; fi
      printf '%s\n' 'commit;' >>"$deploy_sql"
    done < <(node "$root/tools/wad/seed-load-order.mjs")
    continue
  fi
  [[ "$entry" =~ ^sql/(bootstrap|schema|engine|spatial|bsp|accel|render|sim|rest)/[A-Za-z0-9._/-]+\.sql$ && "$entry" != *..* ]] || die "unsafe bootstrap entry: $entry"
  case "$entry" in
    sql/bootstrap/*|sql/schema/*) domain=schema;;
    sql/rest/*) domain=rest;;
    *) domain=engine;;
  esac
  # Reduce the public privilege surface after the REST objects exist but
  # before FINALIZE_RUNTIME starts retained warm sessions. Revoking a table
  # grant after prewarm would wait on their library-cache pins.
  if [[ "$entry" == sql/schema/059_finalize_runtime.sql ]]; then
    least_entry=deploy/cloud/t11.1/least-grants.sql
    printf 'rest|%s|%s\n' "$least_entry" \
      "$(sha "$root/$least_entry")" >>"$ledger"
    command cat "$root/$least_entry" >>"$deploy_sql"
    printf '%s\n' 'commit;' >>"$deploy_sql"
    least_grants_written=1
  fi
  printf '%s|%s|%s\n' "$domain" "$entry" "$(sha "$root/$entry")" >>"$ledger";command cat "$root/$entry" >>"$deploy_sql";printf '%s\n' 'commit;' >>"$deploy_sql"
done <"$root/sql/bootstrap/production-order.txt"
[[ "$least_grants_written" == 1 ]] ||
  die 'least-privilege reduction was not placed before runtime finalization'
printf '%s\n' 'exit success commit' >>"$pre_sql"
printf '%s\n' 'exit success commit' >>"$post_sql"

node - "$root/versions.lock" "$tmp/mle-artifact.json" <<'NODE'
import fs from 'node:fs';
const [lockPath,outPath]=process.argv.slice(2);
const lock=JSON.parse(fs.readFileSync(lockPath)),t=lock.teaVM;
const artifact={schema:1,runtime:'MLE_JAVASCRIPT',teaVMVersion:t.version,
  compilerRelease:t.compilerRelease,targetType:t.targetType,
  moduleType:t.moduleType,optimizationLevel:t.optimizationLevel,
  minifying:t.minifying,profile:t.profile,
  inputBytecodeSha256:t.inputBytecodeSha256,
  mochaBytecodeSha256:t.mochaBytecodeSha256,
  authority:{bytes:t.outputBytes,sha256:t.outputSha256},
  tablePack:{bytes:t.canonicalTablePackBytes,
    sha256:t.canonicalTablePackSha256},
  liveFrameRenderer:{
    profile:t.liveFrameRenderer.profile,
    requiredAuthorityBytes:t.liveFrameRenderer.authorityCandidateBytes,
    requiredAuthoritySha256:t.liveFrameRenderer.authorityCandidateSha256,
    bytes:t.liveFrameRenderer.outputBytes,
    sha256:t.liveFrameRenderer.outputSha256,
    coordinatorBytes:t.liveFrameRenderer.coordinatorBytes,
    coordinatorSha256:t.liveFrameRenderer.coordinatorSha256,
    worldPackBytes:t.liveFrameRenderer.worldPackBytes,
    worldPackSha256:t.liveFrameRenderer.worldPackSha256,
    compositorPackBytes:t.liveFrameRenderer.compositorPackBytes,
    compositorPackSha256:t.liveFrameRenderer.compositorPackSha256,
    wallAssetBytes:t.liveFrameRenderer.wallAssetBytes,
    wallAssetSha256:t.liveFrameRenderer.wallAssetSha256,
    flatAssetBytes:t.liveFrameRenderer.flatAssetBytes,
    flatAssetSha256:t.liveFrameRenderer.flatAssetSha256,
    spriteAssetBytes:t.liveFrameRenderer.spriteAssetBytes,
    spriteAssetSha256:t.liveFrameRenderer.spriteAssetSha256,
    uiAssetBytes:t.liveFrameRenderer.uiAssetBytes,
    uiAssetSha256:t.liveFrameRenderer.uiAssetSha256},
  iwadSha256:lock.freedoom.freedoom1WadSha256};
fs.writeFileSync(outPath,`${JSON.stringify(artifact)}\n`,{mode:0o600});
NODE
node "$root/scripts/t11.1-deployment-manifest.mjs" "$ledger" \
  "$tmp/deployment.json" "$tmp/mle-artifact.json"
phase=deployment_pre_mle
if ! timeout 14400 "$sql_client" -s /nolog <"$pre_sql" |
    node "$root/scripts/redact-cloud-output.mjs" >"$tmp/deployment-pre.log"; then
  tail -80 "$tmp/deployment-pre.log" >&2
  exit 1
fi
phase=asset_load
if ! "$root/scripts/load-cloud-assets.sh" >"$tmp/asset-load.log" 2>&1; then
  show_failure "$tmp/asset-load.log";exit 1
fi
"$root/probes/mle/teavm-engine/load-mle-module.sh" --production --emit-sql \
  >"$tmp/load-mle-module.sql"
phase=mle_load
if ! sql_file_timeout 14400 "$tmp/load-mle-module.sql" \
    >"$tmp/mle-load.log" 2>&1; then
  show_failure "$tmp/mle-load.log";exit 1
fi
phase=live_frame_mle_load
"$root/probes/mle/load-live-frame-module.sh" --emit-sql \
  >"$tmp/load-live-frame-module.sql"
if ! sql_file_timeout 14400 "$tmp/load-live-frame-module.sql" \
    >"$tmp/live-frame-mle-load.log" 2>&1; then
  show_failure "$tmp/live-frame-mle-load.log";exit 1
fi
phase=deployment_post_mle
if ! timeout 14400 "$sql_client" -s /nolog <"$post_sql" |
    node "$root/scripts/redact-cloud-output.mjs" >"$tmp/deployment-post.log"; then
  tail -80 "$tmp/deployment-post.log" >&2
  exit 1
fi

phase=catalog_and_api
if ! sql_file "$root/deploy/cloud/t11.1/catalog-observation.sql" \
    >"$tmp/catalog.log" 2>&1; then
  show_failure "$tmp/catalog.log";exit 1
fi
if ! sql_file "$root/deploy/cloud/t11.1/seed-observation.sql" \
    >"$tmp/cloud-seeds.log" 2>&1; then
  show_failure "$tmp/cloud-seeds.log";exit 1
fi
ords_schema_root=${ADB_ORDS_BASE_URL%/}
if ! curl --connect-timeout 20 --max-time 180 --fail-with-body --silent \
    --show-error "$ords_schema_root/public_health/" \
    >"$tmp/managed-ords-health.json" 2>"$tmp/managed-ords-health.err"; then
  show_failure "$tmp/managed-ords-health.err"
  show_failure "$tmp/managed-ords-health.json"
  exit 1
fi
if ! ADB_ORDS_BASE_URL="$ADB_ORDS_BASE_URL" timeout 3600 \
    node "$root/scripts/t11.1-cloud-api.mjs" >"$tmp/api.json" 2>&1; then
  show_failure "$tmp/api.json";exit 1
fi

cpu=$(sed -n 's/^T111_RESOURCES|\([0-9][0-9]*\)|.*/\1/p' "$tmp/catalog.log")
storage=$(sed -n 's/^T111_RESOURCES|[0-9][0-9]*|\([0-9][0-9]*\)$/\1/p' "$tmp/catalog.log")
[[ -n "$cpu" && "$cpu" -le "$ADB_EXPECTED_MAX_CPU" ]] || die 'live CPU exceeds declared resource policy'
[[ -n "$storage" && "$storage" -le "$ADB_EXPECTED_MAX_STORAGE_GB" ]] || die 'live storage exceeds declared resource policy'

phase=evidence
candidate="$tmp/doomdb-t111-evidence.json"
node "$root/scripts/t11.1-build-evidence.mjs" "$policy" "$tmp/capabilities.log" "$tmp/transport.log" "$tmp/catalog.log" "$ADB_LOCAL_SEED_EVIDENCE" "$tmp/cloud-seeds.log" "$tmp/api.json" "$tmp/deployment.json" "$candidate"
node "$root/evaluator/t11.1/validate-evidence.mjs" "$candidate" >"$tmp/validation.log"
rg -n -i '(password|authorization|bearer |wallet|private_key|aws_access|secret_access|connection_string|adb_username|adb_password|https://|jdbc:|oracle\.net|tnsnames)' "$candidate" && die 'secret or endpoint material reached evidence'
mv "$candidate" /tmp/doomdb-t111-evidence.json
printf 'PASS T11.1-CLOUD-DATABASE (live Autonomous Database and managed ORDS evidence published)\n'
