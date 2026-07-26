#!/usr/bin/env bash
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
project="$root/probes/mle/teavm-engine"
evidence="$root/artifacts/performance/pmle-cloud"
output="$evidence/oci-exact-release-java-removal-2026-07-26.log"
parser="$root/scripts/require-db-record.mjs"
expected='PMLE_OCI_JAVA_REMOVAL|PASS|java_objects=0|java_specs=0|java_dependencies=0|legacy_objects=0|legacy_api=0|mle_modules=1|mle_environments=1|mle_call_specs=25|source_bytes=1081335|source_sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3|table_bytes=180272|table_sha256=058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44|diagnostic_objects=0|invalid_objects=0|source_errors=0|rest_objects=2|unexpected_rest=0|hosted_modules=1|hosted_templates=2|hosted_handlers=2'

[[ "${DOOMDB_OCI_JAVA_REMOVAL_AUDIT:-NO}" == YES ]] || {
  printf '%s\n' 'exact-release Java-removal audit requires explicit execution authority' >&2
  exit 2
}
for name in ADB_CONNECTION_STRING ADB_USERNAME ADB_PASSWORD ADB_WALLET_DIR \
  SQL_CLIENT; do
  [[ -n "${!name:-}" ]] || {
    printf 'required OCI audit authority is absent: %s\n' "$name" >&2
    exit 2
  }
done
[[ "$ADB_USERNAME" == DOOM ]] || {
  printf '%s\n' 'exact-release audit requires DOOM schema' >&2;exit 2; }
[[ ! -e "$output" ]] || {
  printf 'exact-release Java-removal evidence already exists\n' >&2;exit 1; }

bash "$root/tests/verify-production-java-removal-source.sh"
node "$parser" --self-test
{
  "$root/scripts/adb-doom-sql.sh" "$project/artifact-metadata.sql"
  "$root/scripts/adb-doom-sql.sh" "$project/audit-oci-java-removal.sql"
} | tee "$output"
node "$parser" "$output" 'PMLE_OCI_JAVA_REMOVAL|' "$expected"

printf 'PASS PMLE-OCI-EXACT-RELEASE-JAVA-REMOVAL evidence=%s sha256=%s\n' \
  "${output#"$root/"}" "$(shasum -a 256 "$output" | awk '{print $1}')"
