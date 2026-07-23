#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
order="$root/sql/bootstrap/production-order.txt"
purge="$root/sql/bootstrap/001_purge_production_ojvm.sql"
cloud="$root/scripts/verify-cloud-database.sh"
policy="$root/deploy/cloud/t11.1/source-policy.json"

for oracle_source in \
  java/mochadoom-ojvm/src/doomdb/mocha/DoomDbMochaAdapter.java \
  scripts/mochadoom/build-ojvm-jar.sh \
  sql/accel/030_mochadoom_calls.sql; do
  [[ -f "$root/$oracle_source" ]] || {
    printf 'development OJVM oracle was removed: %s\n' "$oracle_source" >&2
    exit 1
  }
done

for required in \
  sql/bootstrap/001_purge_production_ojvm.sql \
  sql/schema/061_mle_production_config.sql \
  sql/sim/086_mle_authority_delta.sql \
  sql/sim/087_mle_transition_transport.sql \
  @mle-module \
  sql/sim/088_mle_match_runtime.sql \
  sql/sim/084_multiplayer_worker.sql \
  sql/sim/085_session_cleanup.sql \
  sql/rest/010_doom_api.sql \
  sql/rest/020_ords_enable.sql; do
  grep -Fxq "$required" "$order" || {
    printf 'production bootstrap entry missing: %s\n' "$required" >&2;exit 1; }
done

for forbidden in \
  sql/accel/019_ojvm_unified_worker_calls.sql \
  sql/accel/020_ojvm_renderer_calls.sql \
  sql/accel/030_mochadoom_calls.sql \
  sql/sim/078_retained_render_worker.sql \
  sql/sim/080_unified_worker.sql \
  sql/sim/082_mochadoom_bridge.sql; do
  ! grep -Fxq "$forbidden" "$order" || {
    printf 'OJVM production bootstrap entry survived: %s\n' "$forbidden" >&2
    exit 1
  }
done

grep -q "object_type like 'JAVA%'" "$purge"
grep -q "LANGUAGE\\[\\[:space:\\]\\].*JAVA" "$purge"
grep -q "production OJVM purge failed" "$purge"
grep -Fq '$if $$doom_dev_ojvm $then' \
  "$root/sql/rest/010_doom_api.sql"
grep -Fq '$if $$doom_dev_ojvm $then' \
  "$root/sql/sim/084_multiplayer_worker.sql"
grep -Fq '$if $$doom_dev_ojvm $then' \
  "$root/sql/sim/085_session_cleanup.sql"
grep -q 'p_enabled=>false' "$root/sql/rest/020_ords_enable.sql"
[[ "$(grep -c \"p_object=>'DOOM_API'\" \
  "$root/sql/rest/020_ords_enable.sql")" -eq 1 ]]
awk '
  /p_object=>\047DOOM_API\047/ { doom=NR }
  /\$if \$\$doom_dev_ojvm \$then/ { conditional=NR }
  END { exit !(doom>0 && conditional>doom) }
' "$root/sql/rest/020_ords_enable.sql"

jq -e '.bootstrapOrder=="sql/bootstrap/production-order.txt" and
  .mle.runtime=="JavaScript" and (.ojvm|not)' "$policy" >/dev/null
grep -q "plsql_ccflags='doom_dev_ojvm:false'" "$cloud"
grep -q 'load-cloud-assets.sh' "$cloud"
grep -q 'load-mle-module.sh.*--production' "$cloud"
! grep -Eq 'loadjava|build-ojvm|load-cloud-ojvm|ojvm-preflight|ojvm-postload' \
  "$cloud"
grep -q "T111_JAVA_REMOVAL" \
  "$root/deploy/cloud/t11.1/catalog-observation.sql"
grep -q "l_mle_specs<>24" \
  "$root/deploy/cloud/t11.1/catalog-observation.sql"
grep -q "LEGACY_NEW_GAME_ABSENT" "$root/scripts/t11.1-cloud-api.mjs"
grep -q "POLL_TRANSITIONS" "$root/scripts/t11.1-cloud-api.mjs"

node --check "$root/scripts/t11.1-cloud-api.mjs"
node --check "$root/scripts/t11.1-deployment-manifest.mjs"
node --check "$root/scripts/t11.1-build-evidence.mjs"
bash -n "$cloud" "$root/scripts/load-cloud-assets.sh" \
  "$root/probes/mle/teavm-engine/load-mle-module.sh"

printf 'PASS PRODUCTION-JAVA-REMOVAL-SOURCE MLE-only manifest, purge, catalog, API, dev-oracle-preserved\n'
