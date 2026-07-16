# T12.1 performance evidence driver

The pulled-forward T12.0 clean-room BSP/projection implementation is exercised
separately with `run-t12.0-bsp-kernel.sh`. It compiles the real-map Java 11
kernel inside the pinned database container, audits every retained candidate
against independent SQL intersection equations, and fails closed on a missing
pair, greater-than-25% candidate retention, or greater-than-3 ms p95. It is an
algorithm-selection harness, not production or final T12.1 evidence.

`DoomStateCodecBench.java` and the `ojvm-state-codec-*.sql` scripts preserve the
rejected canonical-state serializer spike.  It is byte/SHA exact, but its six
internal-JDBC row walks measured 69.286/106.270 ms p50/p95.  The call specs are
not part of bootstrap and the live probe objects are removed after measurement.

`run-p12.0-resident-simulation-probe.sh` exercises the first approved retained
simulation slice inside OJVM. A worker loads the player frontier once, applies
validated turn commands from a compact binary batch without JDBC, and returns a
compact binary delta for SQL persistence. The probe requires exact parity for
270 scalar turns and four packed turns, plus atomic rejection of an invalid
batch. Its internal ten-million-turn sample is a kernel-only diagnostic and is
never an end-to-end FPS claim.

The same harness validates the selected exact-numeric boundary. Oracle JDBC
`NUMBER` matches all 1,152 SQL movement delta encodings and a representative
quadratic collision root byte-for-byte. The selected path preloads SQL-built
64-angle deltas; runtime trigonometry is not part of the worker hot loop.

`verify-performance-baseline.mjs` has two fail-closed modes. With one evidence
path it verifies an already collected baseline and every referenced artifact.
With `--collect REPLAY EVIDENCE`, it performs the real 300-frame replay and
atomically publishes the raw samples, plans, cursor snapshot, payload ledger,
replay identity, report and final evidence envelope.

Live collection requires `T121_LIVE_CONFIRMED=YES`, `T121_ORDS_BASE_URL`, and
`T121_DB_COLLECTOR_COMMAND`. The collector command is a JSON argv array. Targets
and database credentials belong only in that collector process's private
environment; argv and output containing them are rejected. The driver sends the
collector a JSON request on stdin. The collector must wait for and return the
complete redacted observation document containing:

- exactly three `ALLSTATS LAST` plan records (`step`, `frame`, and `asset`),
  including runtime starts, rows, and elapsed microseconds;
- redacted before/after `V$SQL` counters for those families;
- all 60 pose/command statement-shape observations;
- all 300 out-of-band database, ORDS, R1, and R2 stage samples.

The public HTTP response is independently timed and decoded by the driver. Stage
timers are rejected if they occur among response-body keys. No live adapter is
provided until the T11.2 cloud/browser gate and a reviewed fixed replay exist;
the source and artifact tests intentionally do not start or benchmark a service.

## T12.2 optimization ledger

`run-performance-optimization.mjs --publish CAPTURE EVIDENCE` consumes only
externally captured 300-frame sample files, retained source diffs, and complete
correctness/mutation machine reports. Publication requires
`T122_LIVE_CONFIRMED=YES`; the driver never substitutes synthetic timings. It
derives p50/p95/FPS, the dominant stage, improvement and accept/rollback result,
then atomically writes a content-addressed attempt ledger and final report.
Correctness and mutation JSON payloads omit `machineReportSha256`; the driver
hashes their finite bytes and records that external digest in the evidence
envelope, so payload integrity is content-addressed without a self-reference.

The capture plan follows `t12.2-capture-plan.schema.json`. Its baseline pins and
verifies the approved T12.1 envelope and supplies a separately retained external
sample file containing T12.2's payload-stage timing. Paths are relative to the
plan, while output artifacts are confined beneath
`artifacts/performance/t12.2`. Every attempt must preserve the frozen schema and
golden hashes, target the preceding best revision's measured bottleneck, retain
its diff even on regression, and pass complete correctness and mutation gates.
The validator requires the journal to stop at the first pair of consecutive,
technically distinct, reviewed attempts below five percent. The selected best
revision is independently replayed locally and in cloud; reported FPS and
latencies are derived direct measurements with no portable threshold claim.
