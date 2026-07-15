# T10.3 independent local end-to-end evaluator

This evaluator accepts only two complete, isolated, fresh-volume local stack
runs. The host driver owns lifecycle and live inspection; all visible P0-P10
SQL, API, simulation, mutation and Playwright families execute inside the
read-only evaluator container. A final confined evaluator invocation compares
the two retained evidence records after both projects and their volumes have
been removed.

The 16 stable IDs declare 816 assertions. Missing commands, empty output,
partial assertion totals, skips, retries, timeouts, signals, unhealthy services,
resource drift, writable evaluator inputs, missing hash domains, catalog drift,
artifact leakage, or any repeated-run difference fail closed. Cloud and
Performance are deliberately identified as later P11/P12 rows and are not
falsely marked green by this local P10 gate.

## Production handoff

The implementation supplies `scripts/verify-local-e2e.sh`, a container-capable
test-only SQL transport, complete `verify.sh` routes through T10.2, and the
required production observations named by `fixtures.json`. It must not edit this
directory. The driver must create unpredictable unique projects and credentials,
prove no matching resources preexist, enforce the reviewed bounds, inspect the
live resource/sandbox state, retain only secret-free evidence, remove volumes on
every path, then ask this evaluator's `run-container.mjs compare` mode to compare
the records.

`T103_CORRECTNESS <domain> <sha256>` lines must hash canonical production
observations, not logs, timestamps, container identifiers, compressed
nondeterminism, or evaluator fixtures. Exactly the 16 reviewed domains are
accepted. The schema and artifact ledgers are independently emitted by this
directory's catalog and byte-level auditors.

This evaluator does not start a stack, change production orchestration, add test
shortcuts, update snapshots, or manufacture local completion evidence.
