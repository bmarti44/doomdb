# T12.1 performance evidence driver

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
