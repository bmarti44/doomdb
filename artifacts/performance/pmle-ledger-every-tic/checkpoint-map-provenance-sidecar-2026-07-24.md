# Checkpoint-map every-tic ledger provenance — 2026-07-24

Status: **database correctness gate PASS; runner epilogue incident
recorded; no rerun**.

The exclusive-create evidence log
`run-checkpoint-map-2026-07-24.log` contains exactly:

- one `PMLE_LEDGER_PROVENANCE|BEGIN|executions=1` marker;
- one pinned authority/table/OJVM tuple:
  `103e15e9…` / `058cd0df…` / `2a102cb4…`;
- one database artifact tuple matching the pinned authority and table pack;
- one terminal
  `PMLE_TEAVM_LEDGER_DIFFERENTIAL|PASS|tics=13272|deep_every=1`;
- one
  `PMLE_LEDGER_PROVENANCE|CONFIRMED|executions=1|terminal_markers=1`;
- no second invocation and no checkpoint/restore-based resume.

The file was created at 2026-07-24 01:17:40 -04:00 and received its terminal
marker at 2026-07-24 10:00:02 -04:00: 8 hours, 42 minutes, 22 seconds
(31,342 seconds) of wall time under the recorded Free-edition 50% PDB CPU
cap. The run was CPU-active throughout.

The launcher exited with status 2 after the terminal database marker because
`run-ledger-differential.sh` was edited during the already-running execution.
The in-flight SQL had already been generated and submitted; the edit affected
only shell text parsed after SQL*Plus returned. The resulting error was:

```
unexpected EOF while looking for matching '"'
```

This is a harness-epilogue defect, not a differential failure. It did not
alter the submitted command stream, the MLE or OJVM artifacts, or any of the
13,272 per-tic comparisons. The run is not restarted: the terminal database
PASS and single-execution provenance are preserved, while the nonzero wrapper
exit remains disclosed here.

The run predated cumulative progress blocks, UTC runtime markers, and the
run-lifetime lock. Those are future-run observability/fencing changes and are
not retroactively claimed. A temporary lock was backfilled while the legacy
run remained active and is removed only after this terminal record.

A later Fable diagnostic parked `SID 42`, serial `60842`, action `MLE park`
roughly seven hours after ledger launch. It cannot explain the preceding
runtime anomaly. After the terminal marker, `ALTER SYSTEM KILL SESSION`
interrupted the parked call; its still-open SQL*Plus client was then terminated
inside the container. A final `v$session` query returned zero rows for the
exact `42,60842` incarnation before post-ledger compilation or measurement.
