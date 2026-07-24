# Checkpoint-map ledger runtime anomaly — 2026-07-24

Status: **open; active correctness run must reach its natural terminal
marker**.

The exhaustive every-tic differential for authority artifact
`103e15e913b3a8f9a84497af601666fde5f47a720ac4b22fd7843db2559b665e`
started at approximately 2026-07-24 01:17 America/New_York. At eight hours
elapsed its Oracle server process remained CPU-active at approximately 99.7%
with no SQL*Plus terminal output or error. The evidence log retained its
single-execution, exclusive-create header and exact authority/table/oracle
pins.

The earlier `a942cd2d…` exhaustive ledger record was created at 12:27 and
reached its final modification at 13:33 on 2026-07-23, approximately 66
minutes. That historical comparison is not yet a controlled A/B, but the
roughly sevenfold-plus elapsed-time difference is too large to leave
unrecorded.

Attribution constraints:

- the later Fable diagnostic session (`SID 42`, serial `60842`, action
  `MLE park`) appeared only after roughly seven hours of the ledger run and
  therefore cannot explain the preceding elapsed time;
- the ledger server process remained on CPU rather than blocked;
- no DoomDB build, compile, verifier, wasm2js work, or second intentional
  database gate was launched by Sol during the run;
- current SQL*Plus output is buffered, so no trustworthy tic frontier exists
  for this pre-progress-marker invocation;
- the original `pgrep` fence watched the short-lived SQL generator rather than
  the run-lifetime SQL*Plus process; at 09:52 local time a temporary
  run-lifetime lock was backfilled against the still-live launcher PID 64235,
  and future runners own that lock from launch through terminal cleanup;
- the run is correctness evidence, not a performance A/B.

Required closure after the terminal marker:

1. record exact elapsed/CPU time and terminal verdict without restarting;
2. disclose the late parked session in the provenance sidecar;
3. clean the parked session and establish a quiet host;
4. run the approved two-tic progress smoke for the future batched ledger;
5. do not infer a `103e…` ticker regression from this run alone—separately
   compare canonical-material export cost and bare ticker cost for `a942…`
   versus `103e…` if the terminal duration remains anomalous.

The correctness promotion rule is unchanged: no PASS is claimed before the
single active execution emits its terminal marker.

## Static scope audit

The `103e…` source delta builds `IdentityHashMap` indexes only inside
`checkpointLength()`. The every-tic ledger invokes the authoritative ticker
and canonical-material exporter, not checkpoint save/restore. The rejected
Batch-2 FixedDiv/flag candidate is a different 1,169,459-byte artifact
(`92d3468e…`); its modified Mocha bytecode was reverted before the 1,170,639
byte checkpoint candidate was built. Some adapter-only property-test exports
remain reachable but are not invoked by the ledger.

Therefore the static audit finds no direct algorithmic path from the identity
map construction to every-tic work. It cannot exclude a generated-shape or
runtime effect from the newly reachable collection implementation. The
post-terminal controlled A/B must separately time:

- bare ticker only;
- canonical materialization only;
- RAW canonical export;
- native SHA/digest work;
- combined ticker plus evidence work.

The queued, opt-in harness is
`probes/mle/teavm-engine/run-ledger-component-ab.sh`. It is fenced from the
promotion ledger and active matches, records host quiescence plus environment
and deployed-artifact metadata for each cell, compares the cumulative
canonical digest across both artifacts, and restores the production module
under an EXIT trap. It must not run until this correctness execution has
reached its terminal marker and `103e…` has been promoted to its
content-addressed client artifact path.

This decomposition prevents an anomalous correctness-gate duration from being
misreported as either a ticker regression or harmless evidence overhead.
