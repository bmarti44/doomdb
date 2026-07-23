#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: ./verify.sh env | secrets | transport | task T0.1..T7.3|T11.1|T11.2|T12.1|T12.2|T13.0..T13.5 | phase P0|P1|P2|P3|P11|P13|PMLE | evaluator-self-test" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage

case "$1" in
  env)
    [[ $# -eq 1 ]] || usage
    scripts/verify_env.sh
    scripts/verify-secrets-ignored.sh
    ;;
  secrets)
    [[ $# -eq 1 ]] || usage
    scripts/verify-secrets-ignored.sh
    ;;
  transport)
    [[ $# -eq 1 ]] || usage
    scripts/check-transport-contract.sh
    scripts/verify-transport.sh
    ;;
  task)
    [[ $# -eq 2 ]] || usage
    case "$2" in
      T0.1)
        scripts/verify_env.sh
        printf 'PASS T0.1 (34/34 assertions)\n'
        ;;
      T0.2)
        tests/verify-oracle-probes.sh
        probes/oracle/run.sh
        ;;
      T0.3)
        scripts/check-transport-contract.sh
        scripts/verify-transport.sh
        printf 'PASS T0.3 (23/23 assertions)\n'
        ;;
      T0.4) node evaluator/run-foundation.mjs T0.4 ;;
      T1.1) DOOMDB_T1_LIVE=1 tests/verify-local-stack.sh ;;
      T1.2)
        tests/verify-bootstrap-static.sh
        tests/verify-bootstrap-live.sh
        printf 'PASS T1.2 (15/15 assertions)\n'
        ;;
      T1.3) tests/verify-cloud-skeleton.sh ;;
      T2.1) tests/verify-freedoom-vendor.sh ;;
      T2.2)
        node evaluator/t2.2/run-visible.mjs
        node tests/verify-wad-parser-mutations.mjs
        printf 'PASS T2.2 (235/235 assertions)\n'
        ;;
      T2.3)
        node evaluator/t2.3/run-visible.mjs
        node tests/verify-engine-defs-mutations.mjs
        printf 'PASS T2.3 (135/135 assertions)\n'
        ;;
      T2.4)
        node evaluator/t2.4/run-visible.mjs
        node tests/verify-seed-mutations.mjs
        printf 'PASS T2.4 (168/168 assertions)\n'
        ;;
      T3.1)
        tests/verify-schema-static.sh
        tests/verify-schema-live.sh
        printf 'PASS T3.1 (37/37 assertions)\n'
        ;;
      T3.2) evaluator/t3.2/run-visible.sh ;;
      T3.3) evaluator/t3.3/run-visible.sh ;;
      T3.4) evaluator/t3.4/run-visible.sh ;;
      T4.1) evaluator/t4.1/run-visible.sh ;;
      T4.2) evaluator/t4.2/run-visible.sh ;;
      T4.3) tests/verify-t4.3-offline.sh ;;
      T5.1)
        evaluator/t5.1/run-visible.sh
        scripts/db_sql.sh tests/verify-t5.1-dynamic.sql
        ;;
      T5.2) evaluator/t5.2/run-visible.sh ;;
      T5.3) evaluator/t5.3/run-visible.sh ;;
      T5.4) evaluator/t5.4/run-visible.sh ;;
      T6.1) evaluator/t6.1/run-visible.sh ;;
      T6.2)
        evaluator/t6.2/run-visible.sh
        scripts/db_sql.sh tests/verify-t6.2-thin-door.sql
        node tests/verify-t6.2-opening-route.mjs
        ;;
      T6.3)
        evaluator/t6.3/run-visible.sh
        scripts/db_sql.sh tests/verify-t6.3-lift-carry.sql
        ;;
      T6.4) evaluator/t6.4/run-visible.sh ;;
      T7.1)
        evaluator/t7.1/run-visible.sh
        scripts/db_sql.sh tests/verify-t7.1-history.sql
        ;;
      T7.2)
        evaluator/t7.2/run-visible.sh
        scripts/db_sql.sh tests/verify-t7.2-history.sql
        scripts/db_sql.sh tests/verify-t7.2-runtime.sql
        scripts/db_sql.sh tests/verify-t7.2-mobj-integrity.sql
        scripts/db_sql.sh tests/verify-t7.2-branch-command-isolation.sql
        scripts/db_sql.sh tests/verify-t7.2-branch-event-isolation.sql
        ;;
      T7.3)
        evaluator/t7.3/run-visible.sh
        scripts/db_sql.sh tests/verify-t7.3-history.sql
        node tests/verify-t7.3-audio.mjs
        ;;
      T11.1)
        tests/verify-t11.1-source.sh
        tests/verify-t11.1-ojvm-artifact.sh
        scripts/collect-t11.1-local-seeds.sh
        export ADB_LOCAL_SEED_EVIDENCE="${ADB_LOCAL_SEED_EVIDENCE:-/tmp/doomdb-t111-local-seed-observation.json}"
        evaluator/t11.1/run-visible.sh
        ;;
      T11.2)
        export T112_COMPLETION_LEDGER="${T112_COMPLETION_LEDGER:-/tmp/doomdb-t112-completion-ledger.json}"
        tests/verify-t11.2-source.sh
        node scripts/build-t11.2-completion-ledger.mjs "$T112_COMPLETION_LEDGER"
        evaluator/t11.2/run-visible.sh
        ;;
      T12.1)
        node tests/verify-t12.1-mocha-replay.mjs
        node tests/verify-performance-baseline-unit.mjs
        node tests/verify-t12.1-local-evidence.mjs
        ;;
      T12.2)
        node tests/verify-performance-optimization-unit.mjs
        node tests/verify-t12.2-local-ledger.mjs
        ;;
      T13.0)
        scripts/db_sql.sh tests/verify-p13.0-multiplayer-probe.sql
        scripts/db_sql.sh scripts/mochadoom/multiplayer-feasibility-benchmark.sql
        ;;
      T13.1)
        node tests/verify-p13.1-multiplayer-schema.mjs
        node tests/verify-p13.1-multiplayer-api.mjs
        scripts/db_sql.sh tests/verify-p13.1-multiplayer-schema.sql
        scripts/db_sql.sh tests/verify-p13.1-multiplayer-api.sql
        scripts/db_sql.sh tests/verify-p13.1-multiplayer-rate-limit.sql
        node tests/verify-p13.1-multiplayer-autorest.mjs
        ;;
      T13.2)
        node tests/verify-p13.2-multiplayer-adapter.mjs
        node tests/verify-p13.2-retained-match-worker.mjs
        scripts/db_sql.sh tests/verify-p13.2-multiplayer-adapter.sql
        scripts/db_sql.sh tests/verify-p13.2-retained-match-worker.sql
        scripts/db_sql.sh tests/verify-p13.2-paced-input.sql
        scripts/db_sql.sh tests/verify-p13.2-active-leave.sql
        bash tests/verify-p13.2-multiplayer-autorest.sh
        ;;
      T13.3)
        bash tests/verify-p13.3-coop-route.sh
        bash tests/verify-p13.3-coop-browser-route.sh
        bash tests/verify-p13.3-multiplayer-client.sh
        ;;
      T13.4)
        scripts/db_sql.sh tests/verify-p13.4-deathmatch-probe.sql
        scripts/db_sql.sh tests/verify-p13.4-deathmatch-lifecycle.sql
        bash tests/verify-p13.4-deathmatch-client.sh
        ;;
      T13.5)
        node tests/verify-p13.5-operations.mjs
        node tests/verify-session-cleanup-static.mjs
        scripts/db_sql.sh tests/verify-p13.5-active-retention.sql
        scripts/db_sql.sh tests/verify-session-cleanup-live.sql
        bash tests/verify-p13.5-multiplayer-performance.sh
        bash tests/verify-p13.5-multiplayer-performance.sh
        DOOMDB_MULTIPLAYER_SOAK_SECONDS="${DOOMDB_MULTIPLAYER_SOAK_SECONDS:-1800}" \
          bash tests/verify-p13.5-multiplayer-soak.sh
        ;;
      *) usage ;;
    esac
    ;;
  phase)
    [[ $# -eq 2 ]] || usage
    case "$2" in
      P0)
        scripts/verify_env.sh
        tests/verify-oracle-probes.sh
        probes/oracle/run.sh
        scripts/check-transport-contract.sh
        scripts/verify-transport.sh
        node evaluator/run-foundation.mjs T0.4
        printf 'PASS P0 (74/74 assertions)\n'
        ;;
      P1)
        DOOMDB_T1_LIVE=1 tests/verify-local-stack.sh
        tests/verify-bootstrap-static.sh
        tests/verify-bootstrap-live.sh
        tests/verify-cloud-skeleton.sh
        printf 'PASS P1 (63/63 assertions)\n'
        ;;
      P2)
        tests/verify-freedoom-vendor.sh
        node evaluator/t2.2/run-visible.mjs
        node tests/verify-wad-parser-mutations.mjs
        node evaluator/t2.3/run-visible.mjs
        node tests/verify-engine-defs-mutations.mjs
        node evaluator/t2.4/run-visible.mjs
        node tests/verify-seed-mutations.mjs
        printf 'PASS P2 (548/548 assertions)\n'
        ;;
      P3) tests/verify-phase-p3.sh ;;
      P11)
        "$0" task T11.1
        "$0" task T11.2
        printf 'PASS P11 (live Autonomous Database, managed ORDS, and S3 browser gates)\n'
        ;;
      P13) bash tests/verify-phase-p13.sh ;;
      PMLE)
        node scripts/build-mle-dashboard-status.mjs
        cp client/staging/index.html client/dist/index.html
        node tests/verify-mle-dashboard.mjs
        tests/verify-pmle-source.sh
        node_modules/.bin/tsc -p client/tsconfig.json --noEmit false \
          --outDir client/staging
        node tests/verify-authority-delta.mjs
        node tests/verify-authority-batch.mjs
        node tests/verify-authority-mirror.mjs
        scripts/db_sql.sh sql/sim/086_mle_authority_delta.sql
        scripts/db_sql.sh tests/verify-mle-authority-delta.sql
        scripts/db_sql.sh sql/sim/087_mle_transition_transport.sql
        scripts/db_sql.sh tests/verify-mle-transition-transport.sql
        probes/mle/run.sh
        ;;
      *) usage ;;
    esac
    ;;
  evaluator-self-test)
    [[ $# -eq 1 ]] || usage
    node evaluator/self-test.mjs
    ;;
  *) usage ;;
esac
