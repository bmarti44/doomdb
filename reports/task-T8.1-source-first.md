# T8.1 source-first implementation

Status: **PARKED pending an available live integration slot and independent
route and visual review**.

The frozen evaluator and manifest were not modified. No shared bootstrap, tic
transaction, root verification, or routing file was changed, and no Oracle,
ORDS, or browser process was used.

## Delivered

- `scripts/t8.1-route-tools.mjs` verifies the exact frozen T8.1 manifest and all
  of its listed files before expanding the 26 run-length records into the exact
  1,393 ordinary version-one commands. It materializes bounded single, varied,
  and four-command partitions, nine milestone boundaries, a route summary, and
  a fail-closed empty milestone ledger.
- `scripts/t8.1-capture-route.mjs` is an adapter-driven live runner for four
  fresh executions and database replay. It accepts only authoritative milestone
  evidence, validates dense 320x200 RLE and response hashes, emits actual PNGs,
  explicitly checks replay's reconstructed tic-zero cursor, and compares
  state/frame/PNG/counter ledgers across batching modes. It emits separate route
  summary, PNG, repeatability, and authoritative-observation evidence while
  leaving all approval and golden fields empty.
- `tests/verify-t8.1-source.mjs` checks the frozen manifest binding, exact
  command and milestone contract, legal batch partitions, materialized artifact
  schema, fail-closed ledgers, and absence of invented approvals.

Generated candidate artifacts live in `artifacts/t8.1-candidate/`. They are
explicitly unproven and are not goldens.

## Source-first evidence

```text
PASS T8.1-EVAL-SELF-CHECK (31/31 fixture-contract assertions)
PASS T8.1-EVAL-MUTATION-SELF-CHECK (24/24 isolated mutations killed)
PASS T8.1-SOURCE-POLICY-SELF-CHECK
PASS T8.1-SOURCE-FIRST-UNIT
PASS T8.1-CANDIDATE-MATERIALIZED (1393 commands; 9 milestones; no approved goldens)
```

## Ordered live handoff

T7.1-T7.3 production is now accepted and the source tooling is rebound to the
schema-corrected frozen manifest
`5d67fa78932123407f390208933cf18bd174604f91bbec73bd43d744d5b665c5`.
When the live integration slot is available, an independently controlled adapter
must invoke only the public game/replay procedures and supply evaluator-owned
authoritative milestone queries. The capture must pass all four fresh partition
executions plus replay, then the actual route summary and all nine actual PNGs
must be reviewed. Only a separate evaluator-author turn may populate approved
script, state/frame, summary, or screenshot hashes and re-freeze the evaluator.
Until then the live gate remains intentionally closed.
