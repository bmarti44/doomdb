# DMC1 checkpoint identity-index optimization — 2026-07-24

Status: **performance candidate accepted; promotion gates pending**.

## Root cause

Checkpoint envelope construction resolved every thinker, subsector, sector
root, and block-map root with a fresh linear identity scan. At the E1M1
tic-32 population this performs hundreds of thousands of interpreted object
comparisons. Populated-state pre-touch could not remove that algorithmic
cost.

The candidate builds temporary `IdentityHashMap` index tables once per
checkpoint and retains the existing DMC1 field order, values, and restore
codec.

## Direct Oracle MLE A/B

Both cells ran on Oracle AI Database 26ai Free under the frozen
`DEFAULT_CDB_PLAN` 50% PDB utilization / two-running-session cap, with the
pool parked and host quiet.

| tic 32 checkpoint | Baseline | Identity map | Speedup |
| --- | ---: | ---: | ---: |
| first call | 4,915.731 ms | 577.876 ms | 8.51x |
| repeated call | 4,795.301 ms | 604.912 ms | 7.93x |
| bytes | 88,378 | 88,378 | identical length |

Earlier live worker measurements reached 9.86–10.20 seconds because the
same scan-heavy serializer ran under production-shaped contention. The
isolated A/B attributes the structural improvement without relying on that
noisier comparison.

## Exactness

Against the same-source ADVANCED baseline, the candidate produced an
identical 88,378-byte checkpoint:

`52486bdcbec08ea0da5084646091076982cbf316c913c2c474432ce2ef4692a2`

The Node build smoke also restores the checkpoint and verifies continuation.
The separately pinned production artifact emits a different DMC1 hash
because it predates other current-source consistency-ring changes; it is not
the byte-identity baseline for this isolated A/B.

## Placement verdict

The specific nine-second tic-32 freeze is eliminated, not hidden behind a
larger liveness timeout. A roughly 0.6-second synchronous checkpoint is still
a presentation hitch, so checkpoint placement/incremental construction
remains a product-quality follow-on. It does not justify reverting the
8x serializer improvement.

Promotion still requires the lifecycle batch's canonical, 762-tic,
membership/recovery, checkpoint restore, and admission-latency gates.

