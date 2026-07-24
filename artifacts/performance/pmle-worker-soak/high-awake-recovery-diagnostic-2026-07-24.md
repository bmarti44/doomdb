# Maximum-distance high-awake recovery diagnostic — 2026-07-24

Status: **DIAGNOSTIC_NOT_GATE — measured SLA miss; cadence-retune input**.

This run intentionally measured the existing 128–256-tic density-aware
checkpoint candidate at its worst scheduled replay distance. It is not a
production acceptance result and does not classify deterministic recovery as
failed.

Environment and provenance:

```
PMLE_ENVIRONMENT|cpu_count=2|resource_plan=DEFAULT_PLAN|cpu_managed=ON|pdb_cpu_count=2|pdb_utilization_limit=50|pdb_running_sessions_limit=2|pdb_plan=DEFAULT_CDB_PLAN
PMLE_ARTIFACT|source_bytes=1170639|source_sha256=103e15e913b3a8f9a84497af601666fde5f47a720ac4b22fd7843db2559b665e|table_bytes=180272|table_sha256=058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44
FIXTURE|path=tests/fixtures/mle-live-deathmatch-2026-07-23.json|file_sha256=3f625da2ab4166426c008a430a994d504e4ce65be1a9bede24b30abcb227d6b4|expanded_sha256=fa7637570c30d3a33cbf8456e98268890e9f5bd82f5ba39fd7f69b139ddc4085|mode=DEATHMATCH|players=2|skill=3
```

Terminal measurement:

```
PMLE_HIGH_AWAKE_RECOVERY|DIAGNOSTIC_NOT_GATE|probe_tic=368|checkpoint_tic=128|frontier=383|distance=255|awake=20|sustained_samples=3|elapsed_ms=104584|sla_60s=FAIL
```

`elapsed_ms` covers authority kill, restore, deterministic replay, and
authoritative publish. It excludes production detection. With the 15-second
backstop budget added, the estimated end-to-end duration is 119,584 ms.
Therefore the 256-tic forced maximum is not compatible with the 60-second
recovery SLA at this sustained peak density.

The run activated generation 1, preloaded 379 command changes per player
starting at tic 1, observed three consecutive `DEFER_HIGH` probes with 20
awake monsters, killed at the last tic before the scheduled forced
checkpoint, restored generation 2, and reproduced the durable frontier at tic
383. Generation fencing and deterministic replay worked; checkpoint spacing
is the failed hypothesis.

Two harness hardenings follow from this diagnostic:

- the feed extractor now requires anchored counts and an explicit
  match-generation equality fence after activation;
- the exact killed warm-slot incarnation is reset through the lifecycle
  gateway after recovery, preventing a dead authority row from retaining
  capacity.

The next cadence decision is deferred until checkpoint `SAVE` cost is measured
at 20 awake monsters under this same `103e…` artifact. If the serializer fix
removed the former hitch, fixed cadence 128 is evaluated before any more
complex awake-stratified policy.

## Stage-decomposed rerun

After adding diagnostic-only worker timestamps, the same maximum-distance
scenario completed with a clean terminal record:

```
PMLE_HIGH_AWAKE_RECOVERY_STAGES|PASS|checkpoint_tic=128|frontier=383|restore_ms=18809.302|replay_ms=76065.318|publish_ms=173.251|worker_total_ms=95047.871|caller_overhead_ms=1391.129
PMLE_HIGH_AWAKE_RECOVERY|DIAGNOSTIC_NOT_GATE|probe_tic=368|checkpoint_tic=128|frontier=383|distance=255|awake=20|sustained_samples=3|elapsed_ms=96439|detection_budget_ms=15000|estimated_total_ms=111439|phase_budget_45s=FAIL|sla_60s=FAIL
```

Replay cost is 298.3 ms/tic, close to the independently measured
approximately 290 ms peak live-engine cost. The proposed extra
approximately 120 ms/tic SQL replay penalty is therefore refuted. The two
large terms are ordinary peak-density engine replay (76.065 seconds) and a
fixed 18.809-second checkpoint restore.

Projected from the measured terms:

- fixed 128: approximately 58.3 seconds for the measured phase, FAIL;
- fixed 64: approximately 39.2 seconds for the measured phase, arithmetically
  PASS, but it would synchronously serialize for approximately 673 ms every
  1.8 seconds and is not adopted;
- fixed 128 becomes viable if checkpoint restore falls below approximately
  5.5 seconds at the same peak replay rate.

One pre-terminal rerun produced the same stage shape but correctly failed a
harness assertion after the resumed paced authority advanced beyond tic 383
using already-preloaded commands. Recovery-stage telemetry itself binds the
published recovery frontier exactly to tic 383; the post-recovery live
frontier is now required to be monotonic rather than artificially frozen.
