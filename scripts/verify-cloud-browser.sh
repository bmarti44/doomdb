#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
policy="$root/deploy/cloud/t11.2/source-policy.json"
evidence=/tmp/doomdb-t112-evidence.json
tmp=''
phase=preflight

not_run(){ printf 'T11.2 NOT RUN: %s\n' "$*" >&2; exit 2; }
die(){ printf 'T11.2 FAIL: phase=%s: %s\n' "$phase" "$*" >&2; exit 1; }
sha(){ if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"|awk '{print $1}'; else shasum -a 256 "$1"|awk '{print $1}'; fi; }
show_failure(){
  local log=$1
  [[ -f "$log" ]] || return 0
  node "$root/scripts/redact-cloud-output.mjs" <"$log" | tail -80 >&2
}
cleanup(){
  local status=$?
  trap - EXIT HUP INT TERM
  if [[ "$status" != 0 && -n "$tmp" && -d "$tmp" ]]; then
    failure_dir=$(mktemp -d "${TMPDIR:-/tmp}/doomdb-t112-failure.XXXXXX")
    chmod 700 "$failure_dir"
    for source in "$tmp"/*.log "$tmp"/*.json; do
      [[ -f "$source" && ! -L "$source" ]] || continue
      node "$root/scripts/redact-cloud-output.mjs" <"$source" \
        >"$failure_dir/$(basename "$source")"
      chmod 600 "$failure_dir/$(basename "$source")"
    done
    if [[ -d "$tmp/live" ]]; then
      mkdir -p "$failure_dir/live"
      chmod 700 "$failure_dir/live"
      for source in "$tmp"/live/*.headers "$tmp"/live/*.err \
        "$tmp"/live/*.verdict.json; do
        [[ -f "$source" && ! -L "$source" ]] || continue
        node "$root/scripts/redact-cloud-output.mjs" <"$source" \
          >"$failure_dir/live/$(basename "$source")"
        chmod 600 "$failure_dir/live/$(basename "$source")"
      done
    fi
    if [[ -f /tmp/doomdb-t112-playwright.json &&
        ! -L /tmp/doomdb-t112-playwright.json ]]; then
      node "$root/scripts/redact-cloud-output.mjs" \
        </tmp/doomdb-t112-playwright.json \
        >"$failure_dir/playwright-report.json"
      chmod 600 "$failure_dir/playwright-report.json"
    fi
    printf 'T11.2 redacted failure diagnostics retained: %s\n' \
      "$failure_dir" >&2
  fi
  [[ -z "$tmp" ]] || rm -rf "$tmp"
  unset ADB_PASSWORD ADB_CONNECTION_STRING ADB_ORDS_BASE_URL \
    T112_HOSTED_INDEX_URL T112_BROWSER_LEDGER \
    DOOMDB_CLOUD_EXECUTE
  exit "$status"
}
trap cleanup EXIT HUP INT TERM
rm -f "$evidence" /tmp/doomdb-t112-playwright.json

[[ "${DOOMDB_CLOUD_EXECUTE:-}" == YES ]] ||
  not_run 'DOOMDB_CLOUD_EXECUTE=YES is required'
for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
  ADB_ORDS_BASE_URL SQL_CLIENT; do
  [[ -n "${!name:-}" ]] ||
    not_run "required external authority is absent: $name"
done
[[ "$ADB_USERNAME" == DOOM ]] ||
  not_run 'hosted application schema must be DOOM'
[[ "$ADB_CONNECTION_STRING" =~ ^[A-Za-z0-9._:/?=@-]+$ ]] ||
  not_run 'connection identifier contains unsupported characters'
[[ "$ADB_ORDS_BASE_URL" =~ ^https://[^/?#]+/ords/doom/?$ ]] ||
  not_run 'managed ORDS must be the HTTPS DOOM schema root'
[[ -d "$ADB_WALLET_DIR" && ! -L "$ADB_WALLET_DIR" ]] ||
  not_run 'wallet directory is invalid'
[[ -x "$SQL_CLIENT" ]] || not_run 'pinned SQLcl is unavailable'
for tool in node curl jq timeout; do
  command -v "$tool" >/dev/null 2>&1 || not_run "$tool is unavailable"
done
playwright_version=$(node -p "require('./node_modules/@playwright/test/package.json').version")
[[ "$playwright_version" == 1.61.0 ]] ||
  not_run 'pinned Playwright 1.61.0 is unavailable'
[[ -s /tmp/doomdb-t111-evidence.json ]] ||
  not_run 'passing T11.1 managed ORDS evidence is absent'
node "$root/evaluator/t11.1/validate-evidence.mjs" \
  /tmp/doomdb-t111-evidence.json >/dev/null ||
  not_run 'T11.1 evidence is not valid'
tmp=$(mktemp -d "${TMPDIR:-/tmp}/doomdb-t112.XXXXXX")
chmod 700 "$tmp"
mkdir -p "$tmp/client-dist" "$tmp/live"
chmod 700 "$tmp/client-dist" "$tmp/live"
export TNS_ADMIN="$ADB_WALLET_DIR"
ords_root=${ADB_ORDS_BASE_URL%/}
export T112_HOSTED_INDEX_URL="$ords_root/app/"
export T112_BROWSER_LEDGER="$tmp/browser-ledger.json"

sql_run(){
  local source=$1 output=$2
  {
    printf '%s\n' 'whenever oserror exit failure rollback' \
      'whenever sqlerror exit sql.sqlcode rollback' \
      'set echo off verify off define off'
    printf 'connect %s/"%s"@%s\n' \
      "$ADB_USERNAME" "$ADB_PASSWORD" "$ADB_CONNECTION_STRING"
    command cat "$source"
    printf '%s\n' 'exit success commit'
  } | timeout 1800 "$SQL_CLIENT" -s /nolog |
    node "$root/scripts/redact-cloud-output.mjs" >"$output"
}

phase=source_and_build
bash "$root/tests/verify-t11.2-source.sh" >"$tmp/source.log"
"$root/node_modules/.bin/tsc" -p "$root/client/tsconfig.json" \
  --noEmit false --outDir "$tmp/client-dist"
cp "$root/client/dist/play/index.html" "$tmp/client-dist/index.html"
cp "$root/client/staging/multiplayer.html" "$tmp/client-dist/multiplayer.html"
cp "$root/client/staging/solo.html" "$tmp/client-dist/solo.html"
cp "$root/vendor/freedoom/0.13.0/COPYING.txt" \
  "$tmp/client-dist/COPYING-freedoom.txt"
cp "$root/deploy/cloud/t11.2/SOURCE.txt" "$tmp/client-dist/SOURCE.txt"
node "$root/scripts/t11.2-build-client.mjs" "$root" "$tmp/client-dist" \
  "$ADB_ORDS_BASE_URL" "$tmp/build-manifest.json" \
  "$tmp/artifact-allowlist.txt" "$tmp/loader-manifest.tsv"
chmod 600 "$tmp/build-manifest.json" "$tmp/artifact-allowlist.txt" \
  "$tmp/loader-manifest.tsv"

phase=hosted_schema
if ! sql_run "$root/deploy/cloud/t11.2/install-hosted-statics.sql" \
    "$tmp/install.log" 2>"$tmp/install.err"; then
  show_failure "$tmp/install.err"
  show_failure "$tmp/install.log"
  exit 1
fi

phase=database_asset_load
if ! ADB_CONNECTION_STRING="$ADB_CONNECTION_STRING" ADB_USERNAME="$ADB_USERNAME" \
    ADB_PASSWORD="$ADB_PASSWORD" ADB_WALLET_DIR="$ADB_WALLET_DIR" \
    "$root/scripts/load-hosted-statics.sh" "$tmp/client-dist" \
      "$tmp/loader-manifest.tsv" >"$tmp/load.log" 2>&1; then
  show_failure "$tmp/load.log"
  exit 1
fi

phase=live_static_inventory
cat >"$tmp/catalog.sql" <<'SQL'
set pagesize 0 feedback off heading off verify off echo off trimout on trimspool on linesize 32767 serveroutput on size unlimited
select 'T112_ASSET|'||asset_path||'|'||content_type||'|'||cache_control||'|'||
  content_sha256||'|'||content_length||'|'||dbms_lob.getlength(payload)||'|'||
  lower(rawtohex(dbms_crypto.hash(payload,4)))
  from doom_hosted_asset order by asset_path;
select 'T112_ORDS|'||
  (select count(*) from user_ords_modules where name='doom.hosted.app')||'|'||
  (select count(*) from user_ords_templates t join user_ords_modules m
    on m.id=t.module_id where m.name='doom.hosted.app')||'|'||
  (select count(*) from user_ords_handlers h join user_ords_templates t
    on t.id=h.template_id join user_ords_modules m on m.id=t.module_id
    where m.name='doom.hosted.app')||'|'||
  (select count(*) from user_ords_enabled_objects)
  from dual;
begin
  for r in (
    select parsing_object,type,status from user_ords_enabled_objects
      order by parsing_object
  ) loop
    dbms_output.put_line('T112_ENABLED|'||trim(r.parsing_object)||'|'||
      trim(r.type)||'|'||trim(r.status));
  end loop;
end;
/
SQL
if ! sql_run "$tmp/catalog.sql" "$tmp/catalog.log" \
    2>"$tmp/catalog.err"; then
  show_failure "$tmp/catalog.err"
  show_failure "$tmp/catalog.log"
  exit 1
fi
node "$root/scripts/t11.2-verify-database-inventory.mjs" \
  "$tmp/build-manifest.json" "$tmp/catalog.log" \
  >"$tmp/catalog-verdict.json"

while IFS= read -r key; do
  [[ -n "$key" ]] || continue
  safe=${key//\//__}
  expected_type=$(jq -r --arg key "$key" \
    '.objects[]|select(.key==$key)|.contentType' "$tmp/build-manifest.json")
  expected_cache=$(jq -r --arg key "$key" \
    '.objects[]|select(.key==$key)|.cacheControl' "$tmp/build-manifest.json")
  expected_sha=$(jq -r --arg key "$key" \
    '.objects[]|select(.key==$key)|.sha256' "$tmp/build-manifest.json")
  url="$T112_HOSTED_INDEX_URL$key"
  if [[ "$key" == index.html ]]; then url="$T112_HOSTED_INDEX_URL"; fi
  if ! curl --proto '=https' --tlsv1.2 --fail-with-body --silent --show-error \
      --max-redirs 0 --user-agent 'DoomDB-T11.2-verifier' \
      --header "Accept: ${expected_type%%;*}" \
      --dump-header "$tmp/live/$safe.headers" \
      --output "$tmp/live/$safe.body" "$url" \
      2>"$tmp/live/$safe.err"; then
    show_failure "$tmp/live/$safe.err"
    show_failure "$tmp/live/$safe.body"
    exit 1
  fi
  [[ "$(sha "$tmp/live/$safe.body")" == \
    "$(jq -r --arg key "$key" '.objects[]|select(.key==$key)|.sha256' \
      "$tmp/build-manifest.json")" ]] || die "live bytes differ: $key"
  node "$root/scripts/t11.2-verify-live-headers.mjs" \
    "$tmp/live/$safe.headers" "$expected_type" "$expected_cache" \
    "$expected_sha" \
    >"$tmp/live/$safe.verdict.json"
  : >"$tmp/live/$safe.not-modified.body"
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error \
    --max-redirs 0 --user-agent 'DoomDB-T11.2-verifier' \
    --header "If-None-Match: \"$expected_sha\"" \
    --dump-header "$tmp/live/$safe.not-modified.headers" \
    --output "$tmp/live/$safe.not-modified.body" "$url" \
    2>"$tmp/live/$safe.not-modified.err"
  node "$root/scripts/t11.2-verify-not-modified.mjs" \
    "$tmp/live/$safe.not-modified.headers" \
    "$tmp/live/$safe.not-modified.body" "$expected_cache" "$expected_sha" \
    >"$tmp/live/$safe.not-modified.verdict.json"
done <"$tmp/artifact-allowlist.txt"

phase=browser_30fps
"$root/node_modules/.bin/playwright" test \
  -c "$root/deploy/cloud/t11.2/playwright.config.ts"
[[ -s "$T112_BROWSER_LEDGER" && -s /tmp/doomdb-t112-playwright.json ]] ||
  die 'browser ledger or Playwright report is absent'

phase=runtime_postflight
match_sha=$(jq -r '.cleanup.matchSha256' "$T112_BROWSER_LEDGER")
first_tic=$(jq -r '.performance.firstTic' "$T112_BROWSER_LEDGER")
last_tic=$(jq -r '.performance.lastTic' "$T112_BROWSER_LEDGER")
[[ "$match_sha" =~ ^[0-9a-f]{64}$ &&
    "$first_tic" =~ ^[0-9]+$ && "$last_tic" =~ ^[0-9]+$ ]] ||
  die 'browser runtime identity is malformed'
cat >"$tmp/runtime-postflight.sql" <<SQL
set pagesize 0 feedback off heading off verify off echo off trimout on trimspool on linesize 32767
select 'T112_RUNTIME|match_sha256='||
  lower(rawtohex(standard_hash(m.match_id,'SHA256')))||
  '|authority_sha256='||source_.authority_sha256||
  '|renderer_sha256='||source_.renderer_sha256||
  '|coordinator_sha256='||source_.coordinator_sha256||
  '|current_tic='||m.current_tic||
  '|checkpoint_count='||
    (select count(*) from doom_match_checkpoint cp
      where cp.match_id=m.match_id and cp.generation=m.generation
        and cp.tic between $first_tic and $last_tic)||
  '|checkpoint_unmeasured_count='||
    (select count(*) from doom_match_checkpoint cp
      where cp.match_id=m.match_id and cp.generation=m.generation
        and cp.tic between $first_tic and $last_tic and cp.tic>0
        and cp.save_elapsed_ms=0 and cp.publish_elapsed_ms=0)||
  '|checkpoint_slow_count='||
    (select count(*) from doom_match_checkpoint cp
      where cp.match_id=m.match_id and cp.generation=m.generation
        and cp.tic between $first_tic and $last_tic
        and (greatest(cp.save_elapsed_ms,cp.publish_elapsed_ms)>250
          or exists(select 1 from doom_match_slow_call slow_
            where slow_.match_id=cp.match_id
              and slow_.generation=cp.generation and slow_.tic=cp.tic
              and slow_.checkpoint_save_ms is not null)))||
  '|checkpoint_max_step_ms='||
    to_char(coalesce((select max(slow_.elapsed_ms)
      from doom_match_slow_call slow_
      where slow_.match_id=m.match_id and slow_.generation=m.generation
        and slow_.tic between $first_tic and $last_tic
        and slow_.checkpoint_save_ms is not null),0),
      'FM999999990D999','NLS_NUMERIC_CHARACTERS=''.,''')||
  '|checkpoint_max_save_ms='||
    to_char(coalesce((select max(cp.save_elapsed_ms)
      from doom_match_checkpoint cp
      where cp.match_id=m.match_id and cp.generation=m.generation
        and cp.tic between $first_tic and $last_tic),0),
      'FM999999990D999','NLS_NUMERIC_CHARACTERS=''.,''')||
  '|checkpoint_max_publish_ms='||
    to_char(coalesce((select max(cp.publish_elapsed_ms)
      from doom_match_checkpoint cp
      where cp.match_id=m.match_id and cp.generation=m.generation
        and cp.tic between $first_tic and $last_tic),0),
      'FM999999990D999','NLS_NUMERIC_CHARACTERS=''.,''')||
  '|checkpoint_max_stage_ms='||
    to_char(coalesce((select max(greatest(
        cp.save_elapsed_ms,cp.publish_elapsed_ms))
      from doom_match_checkpoint cp
      where cp.match_id=m.match_id and cp.generation=m.generation
        and cp.tic between $first_tic and $last_tic),0),
      'FM999999990D999','NLS_NUMERIC_CHARACTERS=''.,''')
  from doom_match m cross join doom_mle_live_frame_source source_
 where source_.artifact_id=1
   and lower(rawtohex(standard_hash(m.match_id,'SHA256')))='$match_sha';
SQL
if ! sql_run "$tmp/runtime-postflight.sql" "$tmp/runtime-postflight.log" \
    2>"$tmp/runtime-postflight.err"; then
  show_failure "$tmp/runtime-postflight.err"
  show_failure "$tmp/runtime-postflight.log"
  exit 1
fi
node "$root/scripts/t11.2-verify-runtime-postflight.mjs" \
  "$tmp/runtime-postflight.log" "$match_sha" "$first_tic" "$last_tic" \
  "$root/versions.lock" "$tmp/runtime-postflight.json"

phase=evidence
candidate="$tmp/doomdb-t112-evidence.json"
node "$root/scripts/t11.2-build-hosted-evidence.mjs" \
  "$policy" "$tmp/build-manifest.json" "$tmp/catalog-verdict.json" \
  "$tmp/live" "$T112_BROWSER_LEDGER" /tmp/doomdb-t112-playwright.json \
  "$tmp/runtime-postflight.json" "$T112_HOSTED_INDEX_URL" "$candidate"
node "$root/evaluator/t11.2/validate-evidence.mjs" "$candidate" >/dev/null
if rg -n -i '(authorization|bearer |password|wallet|private_key|adb_ords|https://|jdbc:|oraclecloudapps|game_token|session_id)' \
    "$candidate" >/dev/null; then
  die 'credential or target material reached retained evidence'
fi
mv "$candidate" "$evidence"
printf 'PASS T11.2-CLOUD-BROWSER (database-hosted ORDS client >=30 unique moving FPS)\n'
