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
  sql/schema/039_retained_render_overlap.sql \
  sql/schema/060_grants.sql \
  sql/sim/080_unified_worker.sql \
  sql/sim/082_mochadoom_bridge.sql; do
  ! grep -Fxq "$forbidden" "$order" || {
    printf 'OJVM production bootstrap entry survived: %s\n' "$forbidden" >&2
    exit 1
  }
done

# A filename denylist is not a complete production fence: a new bootstrap
# entry could otherwise introduce a differently named Java call spec. Scan the
# resolved SQL order as well. The purge script is the sole intentional source
# of the LANGUAGE-JAVA vocabulary because it detects and removes old call
# specs before the MLE-only schema is installed.
while IFS= read -r entry || [[ -n "$entry" ]]; do
  [[ -z "$entry" || "$entry" == \#* || "$entry" == @* ]] && continue
  [[ "$entry" =~ ^sql/[A-Za-z0-9._/-]+\.sql$ &&
      "$entry" != *..* && -f "$root/$entry" ]] || {
    printf 'invalid production bootstrap entry: %s\n' "$entry" >&2
    exit 1
  }
  [[ "$entry" == sql/bootstrap/001_purge_production_ojvm.sql ]] && continue
  if grep -Eiq \
      'LANGUAGE[[:space:]]+JAVA|CREATE[[:space:]]+(OR[[:space:]]+REPLACE[[:space:]]+)?JAVA|LOADJAVA' \
      "$root/$entry"; then
    printf 'production bootstrap contains Java/OJVM DDL: %s\n' "$entry" >&2
    exit 1
  fi
done <"$order"

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
grep -q "object_name='DOOM_WORKER_API'" \
  "$root/sql/rest/020_ords_enable.sql"
grep -q 'l_worker_api_exists=1' \
  "$root/sql/rest/020_ords_enable.sql"
[[ "$(grep -Fc "p_object=>'DOOM_API'" \
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
grep -q "PMLE_OCI_JAVA_REMOVAL|PASS" \
  "$root/probes/mle/teavm-engine/audit-oci-java-removal.sql"
grep -q "diagnostic_objects=0" \
  "$root/probes/mle/teavm-engine/run-oci-java-removal-audit.sh"
grep -q "hosted_modules=1|hosted_templates=2|hosted_handlers=2" \
  "$root/probes/mle/teavm-engine/run-oci-java-removal-audit.sh"
grep -q "verify-production-java-removal-source.sh" \
  "$root/probes/mle/teavm-engine/run-oci-java-removal-audit.sh"
grep -q "l_mle_specs<>25" \
  "$root/deploy/cloud/t11.1/catalog-observation.sql"
grep -q "LEGACY_NEW_GAME_ABSENT" "$root/scripts/t11.1-cloud-api.mjs"
grep -q "POLL_TRANSITIONS" "$root/scripts/t11.1-cloud-api.mjs"

node --check "$root/scripts/t11.1-cloud-api.mjs"
node --check "$root/scripts/t11.1-deployment-manifest.mjs"
node --check "$root/scripts/t11.1-build-evidence.mjs"
bash -n "$cloud" "$root/scripts/load-cloud-assets.sh" \
  "$root/probes/mle/teavm-engine/load-mle-module.sh"

printf 'PASS PRODUCTION-JAVA-REMOVAL-SOURCE MLE-only manifest, purge, catalog, API, dev-oracle-preserved\n'
