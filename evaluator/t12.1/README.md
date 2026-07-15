# T12.1 independent evaluator

This fail-closed evaluator accepts a baseline only after a real fixed 300-frame
Section 6.6 replay. Frames 0-29 are warm observations; all 270 later frames are
externally timed. It requires complete per-frame latency, database, ORDS,
decode/blit, R1/R2 and payload-byte evidence, but enforces no portable FPS floor.

Every exercised SQL family must retain `ALLSTATS LAST` runtime operations and
redacted `V$SQL` parse/execution snapshots. Its normalized bound shape and
force-matching signature must be invariant across four poses and five command
classes. Bind values, raw SQL, endpoints and session identities are forbidden.
Stage timers are evidence only and may not enter public response keys.

The production driver writes samples, plans, cursor snapshots, payload ledger,
replay identity and report as separately hashed artifacts below
`artifacts/performance/t12.1/`. Validation rereads their bytes and hashes, scans
them recursively for secrets, and rejects partial, synthetic, dry-run or
non-atomic results. Evaluator self-checks do not start Oracle or inspect unfinished
production. Run the live gate with `evaluator/t12.1/run-visible.sh` only after the
baseline driver and upstream cloud gate exist.
