# High-awake checkpoint SAVE diagnostic — 2026-07-24

Status: **DIAGNOSTIC_NOT_GATE — fixed-128 checkpointing is operationally
plausible**.

The promoted `103e…` authority replayed the preserved two-player deathmatch
stream with 20 awake monsters. Diagnostic hook mode 2 forced serialization at
tic 256 without changing the production cadence decision recorded at that
tic.

```
PMLE_HIGH_AWAKE_CHECKPOINT_SAVE|DIAGNOSTIC_NOT_GATE|tic=256|frontier=256|awake=20|decision=DEFER_HIGH|save_ms=673.142|publish_ms=2.186
```

The `DEFER_HIGH` decision proves that the diagnostic hook did not masquerade
as a production checkpoint decision. The 673.142 ms serializer cost is far
below the former multi-second checkpoint hitch and is small relative to the
45-second restore/replay/publish phase budget. This result permits evaluation
of fixed cadence 128, but it does not authorize changing cadence before the
stage-decomposed maximum-distance recovery rerun.

The first attempted run was aborted before measurement after its hook value
was rejected by the independently named legacy
`DOOM_MATCH_CHECKPOINT_HOOK_CK` constraint. The in-place migration and
fresh-install schemas now agree on hook domain `(0,1,2)`. A second,
source-inspection defect was then corrected: the tic-scoped diagnostic flag
had been set at tic 256 but the firing predicate still required tic 64. The
source verifier now requires the semantic firing form
`l_checkpoint_diagnostic=1 or l_checkpoint_due=1` and rejects the stale
tic-64-only predicate.
