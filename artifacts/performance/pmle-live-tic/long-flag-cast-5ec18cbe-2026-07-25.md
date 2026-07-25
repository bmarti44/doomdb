# VOIDED long-flag cast benchmark

Classification: `VOIDED_HARNESS_CLEANUP_PLACEMENT`.

The first current-artifact rerun exited before creating either call
specification because its newly added cleanup block was inserted between the
two preflight idempotent drops. The raw log is preserved unchanged and no
timing cell executed. The cleanup block is now after the benchmark terminal;
the clean `v2` run is the only result eligible for use.
