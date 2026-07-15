# T12.0 render-free simulation profile

Date: 2026-07-15

`DOOM_TIC_TX.APPLY_BATCH` was measured directly so `DOOM_API.RENDER_PAYLOAD`
did not execute. Each distribution uses 30 warmup calls followed by 270 unique
turn tics. The selected protocol commits after each call, matching the public
transaction boundary. The reproducible driver is
`artifacts/performance/t12.0/render-free-simulation.sql`.

| Revision | p50 | p95 | p99 | max |
| --- | ---: | ---: | ---: | ---: |
| Corrected production-boundary baseline | 68.070 ms | 168.871 ms | 212.230 ms | 221.959 ms |
| Bulk actor + light/state reductions | 52.828 ms | 158.353 ms | 180.526 ms | 215.652 ms |
| Exact sound closure selected | 53.413 ms | 82.336 ms | 107.506 ms | 145.990 ms |
| Set-based common actor housekeeping selected | 45.766 ms | 77.846 ms | 96.626 ms | 98.822 ms |
| Packed REJECT and LOS geometry selected | 41.410 ms | 70.581 ms | 84.806 ms | 93.566 ms |

An earlier rollback-only result of 555.921 ms p50 / 1,488.766 ms p95 is
rejected: it kept all 300 calls in one transaction and measured accumulating
undo/version-chain work that the committing public API does not perform.

Line-level `DBMS_PROFILER` evidence at sequence 41 isolated 95.594 ms in 3,724
executions of the procedural `SOUND_REACH` edge query, with 10,780 visited-set
checks. `DOOM_SECTOR_SOUND_REACH` now stores the exact transitive closure of
non-sound-blocked immutable sector edges. Bootstrap converged after 14 adding
rounds to 6,784 reachable pairs; runtime perception uses the composite primary
key. The complete T7.2 evaluator, mutation, history, lifecycle, MOBJ-integrity,
and branch-isolation gates pass.

The remaining ordinary-tic profile is led by state JSON/hash work, actor
housekeeping/advancement, special-sector processing, and history writes.
Simulation still fails its preferred 10 ms p95 slice and the overall 33.3 ms
response gate. No playability claim is made.
