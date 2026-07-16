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
| Lineage fast path | 40.273 ms | 67.708 ms | 85.847 ms | 91.823 ms |
| Exact swept-AABB collision segments | 38.705 ms | 56.227 ms | 73.994 ms | 91.117 ms |
| Native hot PL/SQL (rejected) | 37.804 ms | 49.319 ms | 55.048 ms | 56.983 ms |
| Restart-safe static runtime facts selected | 36.842 ms | 49.503 ms | 58.123 ms | 76.197 ms |

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

The refreshed 30-tic `DBMS_PROFILER` run is reproducible with
`artifacts/performance/t12.0/profile-render-free-simulation.sql`. Before native
compilation, canonical state JSON cost 282.734 ms over 30 tics, swept contact
142.881 ms over 18 calls, command state-BLOB updates 104.398 ms over 30 tics,
and a redundant full-state JSON parse 78.690 ms over 30 tics. The selected
lineage flag removes that parse without changing legacy hashes. A packed
1,175-row immutable collision relation plus a mathematically conservative swept
circle AABB removes the repeated map/sidedef/vertex join and passes all T6.2
collision, tangency, thin-door, and route-prefix gates.

Native compilation of the seven hot PL/SQL bodies is rejected. After the static
runtime relation and optimizer statistics were made restart-safe, native versus
interpreted p95 was 47.714 versus 49.503 ms: a 1.789 ms gain, below the
predeclared 3 ms selection threshold. The selected 182-row immutable sector
runtime relation replaces the per-tic two-direction neighbor aggregation used
by special lighting. The complete T6.1-T6.4 and T7.1-T7.3 evaluator, mutation,
concurrency, history, lifecycle, integrity, branch-isolation, and Chromium gates
pass after these changes.

The remaining ordinary-tic profile is led by state JSON/hash/history, actor
advancement, and interval snapshot writes. Simulation still fails its preferred
10 ms p95 slice and the integrated 33.3 ms response gate. The next structural
slice is an exact streaming canonical state/history writer, followed by
set-based actor/world advancement. A correlated zero-motion SQL-macro fast path
is also rejected after reproducing `ORA-07445 [kkqvmrsla()+283]` following a
restart; it was removed without selection. No playability claim is made.
