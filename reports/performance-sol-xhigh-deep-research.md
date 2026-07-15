# Sol/xhigh independent performance research

Date: 2026-07-15
Scope: read-only repository audit plus primary Oracle documentation and primary
rendering research. No production SQL, evaluator, golden, plan, or database
state was changed.

## Executive verdict

The current build is not interactively playable. The fastest verified public
`NEW_GAME` measurement is 26.30 seconds, equivalent to about 0.038 presented
frames per second. A 30 FPS gate allows 33.3 ms per presented frame, so the
measured first frame is approximately **790 times too slow**. The 4.63x T12.0
improvement was important, but repeating optimizations of that size would still
not be enough.

The repository has **not yet isolated every slow component**. T12.0 records a
fixed-pose world, selected-masked, presentation, and aggregate public
`NEW_GAME`, but it does not contain the promised one-command and four-command
`STEP` timings, per-operation `ALLSTATS LAST`, ordinary moving-frame samples,
or separate RLE/JSON/hash/LOB/gzip/ORDS/browser measurements. A read-only
attempt to inspect `V$SQL` as `DOOM` failed with `ORA-00942`, so the T12.1
credential-private collector needs a suitably privileged observation adapter.
No conclusion that the complete hot path is isolated is defensible before that
evidence exists.

Ordinary optimizer knobs, ORDS pool settings, compression changes, or two-core
parallelism cannot credibly close a 790x gap. The only plausible route is to
remove orders of magnitude of relational work: precompute immutable render
math, stop joining every ray to every frustum candidate, materialize the portal
walk once, and stop rebuilding/ranking a second 64,000-row canvas after the
world frame already exists. Even that route has no evidence yet that 33.3 ms is
achievable on Oracle Free's hard two-core/2-GB limit. Oracle documents those
limits explicitly ([Oracle AI Database Free licensing restrictions](https://docs.oracle.com/en/database/oracle/oracle-database/26/xeinl/licensing-restrictions.html)).

Parity work should remain paused until a cold-cache representative moving
`STEP` meets the playable gate, not merely a cached spawn, pause, menu, replay,
or exact-retry response.

The eventual 640x400 request makes work reduction more important. The current
pass must retain the approved 320x200 canonical frame and goldens, but new
derived relations should use an explicit resolution-profile key/seed generator
rather than burying another set of 320/200 literals in the hot path. A naive
640x400 raster has four times as many pixels and twice as many columns. If all
pixel work scaled linearly, a renderer that only just reached 33.3 ms at
320x200 would take about 133 ms, or 7.5 FPS, at 640x400. Meeting 30 FPS at the
larger raster ultimately requires more headroom or another approximately 4x
reduction in per-pixel work; it cannot be treated as a free follow-on.

## Charter boundary

All recommendations below keep these invariants:

- SQL owns visibility, projection, sampling, composition, and RLE.
- PL/SQL may orchestrate a bounded list of set-based statements, but cannot
  loop over pixels, walls, sprites, or objects.
- The canonical output remains exact 320x200 palette indices; reviewed frame
  and state hashes and the decompressed public JSON schema remain identical.
- `MATCH_RECOGNIZE` still creates constant-color column runs.
- ORDS AutoREST remains the only dynamic HTTP surface.
- No MLE, Java, WASM, `UTL_TCP`, native extension, alternate middle tier,
  resolution reduction, approximation, interpolation, or client rendering is
  proposed.

## What is measured locally

These are repository measurements, not claims derived from web sources.

| Observation | Measured result | Meaning |
| --- | ---: | --- |
| Original direct `DOOM_R2_PIXEL_ROWS` | >70 s | Renderer SQL materialization dominated before transport. |
| Original direct masked path | >50 s | Masked rendering was independently very expensive. |
| Non-shipping shared local derivation | 35.39 s world; 40.67 s masked | Repeated relational expansion was a real bottleneck. |
| Original clean public `NEW_GAME` | 121.79 s | Clean first-frame baseline. |
| T12.0 fixed-pose baseline | 12.11 s world; 4.70 s selected masked; 18.11 s presentation | The staged-era local comparison points. |
| Selected staged statements | about 10.64 s and 14.08 s total in two runs | Variation remained in R1 hit generation. |
| Selected public `NEW_GAME` | 26.30 s twice; 28.01 s after fresh bootstrap | Exact hashes and 92,658 compressed bytes were retained. |

The sources also establish these structural facts:

1. `render_payload` materializes raw R1 hits, world pixels, selected masked
   pixels, final presentation pixels, and RLE in separate GTT statements.
2. T12.0 shares raw R1 hits, but world and masked statements still independently
   evaluate `DOOM_R2_STAGED_PORTAL_HIT_ROWS` (`MATCH_RECOGNIZE`) and repeat
   active-hit, interval, clip-window, and wall-depth analytics.
3. The presentation statement constructs a 64,000-row canvas, unions all
   candidate layers, and performs `ROW_NUMBER` over every pixel even though a
   complete staged world frame already exists.
4. The masked statement recomputes a static `ROW_NUMBER` over all opaque `AT`
   texels to find one first opaque texel per asset, and repeatedly resolves a
   static sprite catalog view.
5. The frame hash path creates 64,000 XML elements containing hex, removes XML
   tags, converts the hex CLOB back into a BLOB, and then hashes it.
6. Turning is exactly 5.625 degrees per command. Starting map angles and every
   subsequent player angle therefore occupy only 64 orientations, while the
   renderer currently repeats trigonometric expressions for each expanded ray.

## Required bottleneck isolation before selecting another revision

Capture cold and warm data separately for `NEW_GAME`, one-command `STEP`, and
four-command `STEP`; within `STEP`, distinguish a no-op/unchanged presentation,
a turn, translation, sector motion, monster-heavy combat, automap, menu, and
intermission. Cache hits and misses must be separate populations.

For every representative frame, collect out-of-band elapsed/CPU/buffer/TEMP
and actual-versus-estimated row counts for:

1. command validation and simulation packages;
2. state serialization and state hash;
3. frustum candidate generation;
4. ray/segment analytic intersections and sort;
5. portal `MATCH_RECOGNIZE`, intervals, and clip windows;
6. world span classification and 64,000 texel/colormap samples;
7. masked wall geometry, sprite projection, sampling, and winner selection;
8. presentation/canvas composition;
9. frame RLE;
10. column JSON aggregation;
11. frame-byte construction and SHA-256;
12. audio/document JSON, UTF-8 conversion, and `UTL_COMPRESS`;
13. PL/SQL OUT-BLOB copy and ORDS base64 marshaling;
14. browser base64 decode, gunzip, JSON parse, RLE expansion, palette mapping,
    and canvas blit.

Use `/*+ GATHER_PLAN_STATISTICS */` in diagnostic-only statement variants and
`DBMS_XPLAN.DISPLAY_CURSOR(..., 'ALLSTATS LAST')`; Oracle documents that this
exposes actual rows and execution statistics for the last cursor
([optimizer statistics example](https://docs.oracle.com/en/database/oracle/oracle-database/23/tgsql/optimizer-statistics-concepts.html)). Also collect plan hash, child number,
parse calls, executions, buffer gets, CPU, elapsed time, direct writes, workarea
spill, and row-source starts. `V$SQL_PLAN_STATISTICS_ALL` is specifically meant
to compare estimates and execution statistics, including SQL workarea memory
([execution-plan documentation](https://docs.oracle.com/en/database/oracle/oracle-database/26/tgsql/generating-and-displaying-execution-plans.html)). Real-Time SQL Monitoring is useful but is a Tuning Pack feature, so it must not become a Free-portable acceptance dependency
([Oracle SQL monitoring documentation](https://docs.oracle.com/en/database/oracle/oracle-database/23/tgsql/monitoring-database-operations.html)).

The 30-FPS check should use cold application-render caches for the fixed
representative replay, warm Oracle buffers/cursors after the 30-frame warmup,
and at least 270 externally timed unique moving frames. Report p50 and p95; do
not average cache hits together with misses.

## Ranked opportunities

Impact is the expected effect on a cache-miss moving gameplay frame. It is an
inference from the measured shape and source inspection until isolated probes
exist.

| Rank | Candidate | Expected impact | Feasibility | Free + Autonomous portability | Exactness risk | Required measurement |
| ---: | --- | --- | --- | --- | --- | --- |
| 1 | Exact ray/segment cardinality collapse: precompute 64x320 ray coefficients, precompute denormalized segment coefficients, then range-join each segment only to screen columns in its exact angular interval | Very high | Medium | High | Medium-high at FOV, wrap, endpoint, and near-plane boundaries | Candidate-ray pairs before/after, R1 CPU/buffers/TEMP, every T4/T5 geometry mutation and frame golden |
| 2 | Materialize the active portal stream, intervals, clip windows, and termination depth once per frame and reuse them for world and masked consumers | High | High | High | Low-medium | Separate portal/world/masked timings and exact two-way row parity with canonical views |
| 3 | Replace the second full-canvas union/rank with bounded set-based composition: insert world directly into final frame GTT, then deterministic `MERGE`/insert of sparse masked, weapon, HUD, and mode overlays | High | High | High | Medium because tie ordering must remain exact | Presentation row-source counts, sort/TEMP removal, full T5.4 presentation and source-kind assertions |
| 4 | WAD BSP front-to-back candidate traversal and relational occlusion, using `CONNECT BY` plus ordered SQL state rather than brute frustum candidates | Potentially very high | Low-medium | High | High | Visited nodes/subsectors/segs per pose, exact equality against analytic canonical renderer on all visible/held-back transforms |
| 5 | Persist immutable derived relations: render-seg endpoints/deltas/cross constants/sides/sectors; ray table; sprite catalog; first opaque texel; animation table; asset sampling metadata | Medium-high | High | High | Low | Per-stage CPU/buffers and bootstrap hash/provenance checks |
| 6 | Exact SQL-owned render/layer cache keyed by a complete render-input digest | Enormous on a hit; near zero on a novel moving frame | Medium | High | High if the key omits any dependency | Cold/hot hit ratio by mode, cache-miss p95, mutation of every key dependency, bounded eviction/concurrency |
| 7 | GTT/optimizer hygiene: test `TEMP_UNDO_ENABLED=TRUE`, necessary-index-only GTTs, realistic stats/cardinality buckets, and a verified plan baseline after the shape stabilizes | Low-medium | High | Medium-high; privileges must be probed | Low | Redo/undo/TEMP, insert cost versus read benefit, child cursors and plan hashes across pose classes |
| 8 | Post-render construction: chunked hex aggregation for frame bytes, JSON generation `RETURNING BLOB`, remove redundant CLOB-to-UTF8 copy, explicitly release temporary LOBs | Medium only if post-render is material; cannot fix renderer | High | High after identical capability probe | Medium for byte identity | Independent stage timers and exact decompressed bytes/frame SHA/payload schema |
| 9 | Spatial/index experiment: verify the domain index is used, stage one selective frustum candidate set, enable/probe spatial vector acceleration, compare R-tree candidates with BSP/range pruning | Low-medium alone | High | High | Low if exact predicate remains | Domain-index plan, candidate count/selectivity, spatial CPU, exact predicate parity |
| 10 | DOP 2 / Autonomous consumer-group experiment | At most a small single-digit multiple, not 790x | Medium | Low-medium | Low correctness; high throughput/concurrency risk | Single-client p50/p95 plus four-client throughput and queueing on both targets |
| 11 | ORDS pool/cache configuration | Negligible for a 26-second single request; throughput only | High locally | Low for managed ORDS controls | Low | DB-complete-to-last-byte time, queue time, concurrent clients |
| 12 | Database In-Memory/vector features | Unlikely to help indexed 64K point probes and not baseline-portable | Low | Low | Low correctness, high deployment/cost risk | Only after row-source proof of scan/group bottleneck |

### Resolution scaling

The opportunity ranks intentionally favor work that survives a larger raster:

| Work | Expected scaling from 320x200 to 640x400 | Design implication |
| --- | --- | --- |
| Pose lookup, one frustum, static seg metadata, sector snapshot | Approximately constant per frame | Compute/materialize once outside column and pixel relations. |
| BSP traversal and coarse visible-subsector selection | Mostly resolution-independent, with clip bookkeeping dependent on screen coverage | Highest long-term leverage; parameterize screen bounds. |
| Rays, ray/seg intersections, portal ordering | Roughly proportional to width (2x) after exact column-range pruning | Seed `(resolution_profile,orientation,column)` rays and normalized camera coordinates. |
| World floor/ceiling/wall sampling | Proportional to pixels (4x) unless span/runs remove work | Keep geometry/span selection separate from raster sampling and avoid repeated per-pixel joins. |
| Sprite projection | Geometry approximately constant; covered sprite samples grow with projected area, up to 4x | Cache state-to-asset resolution and rasterize only clipped bounds. |
| Presentation ranking/composition | 4x if a full candidate canvas is sorted | Sparse set-based overlay composition is essential. |
| Frame hash and browser palette/blit | 4x bytes/pixels | Use direct/chunked byte construction and typed buffers; measure separately. |
| RLE/JSON/gzip/base64/network | Content-dependent, plausibly 2-4x | Preserve schema now, but budget transport explicitly at the larger profile. |

Do not precompute 640x400 production frames or change the API in the current
golden pass. Do make the proposed ray generator, screen-column interval math,
row/column axis relations, clip bounds, projection constants, cache keys, and
evidence schemas explicitly parameterizable. The exact 320x200 profile remains
the only selected profile until its evaluator and charter are amended.

### Why ranks 1-5 are the core path

The present R1 shape first chooses frustum linedefs, joins their segs, and then
joins that set to all 320 rays before rejecting most ray/segment pairs. The
camera rays are coherent and the scene is static. Primary rendering research
supports exploiting coherence and preprocessed visibility rather than treating
every ray independently: Wald et al. reported more than an order-of-magnitude
improvement from coherent ray tracing ([primary paper](https://doi.org/10.1111/1467-8659.00508)), and the foundational BSP work explicitly preprocesses a static environment so a viewpoint-dependent traversal supplies visibility order at runtime ([Fuchs, Kedem, and Naylor, SIGGRAPH 1980](https://doi.org/10.1145/800250.807481)). These papers do not prove an Oracle speedup; they support the inference that reducing candidate pairs and using the already-ingested BSP are the right algorithmic levers.

The safest first implementation slice is not the full BSP rewrite. It is:

1. seed the 20,480 exact `(orientation,column)` ray rows (64x320);
2. seed one render-seg row per WAD seg with endpoints, deltas, static cross
   coefficient, length, linedef/sidedef ids, and immutable texture metadata;
3. derive a conservative exact screen-column interval for each seg, including
   wrap and camera-plane cases, and retain the existing determinant/t/u tests as
   the final authority;
4. materialize portal/interval/window rows once;
5. compose the already-selected layers without a 64K candidate rerank.

This keeps the canonical renderer as the independent oracle. It should be
abandoned if actual candidate pairs do not collapse or if two distinct attempts
fail to produce large gains; micro-tuning around a still-explosive join will not
reach the gate.

Oracle itself may create a cursor-duration in-memory temporary table when it
chooses the temporary-table transformation
([Oracle query transformations](https://docs.oracle.com/en/database/oracle/oracle-database/23/tgsql/query-transformations.html)). The T12.0 evidence shows that leaving this choice to a very large expanded view was unstable, so explicit bounded GTT stages remain reasonable. Oracle supports shared or session-specific GTT statistics and explains their cursor-sharing consequences
([Oracle optimizer statistics](https://docs.oracle.com/en/database/oracle/oracle-database/23/tgsql/optimizer-statistics-concepts.html)). Do not gather session statistics every frame; compare stable shared cardinality classes or explicit cardinality hints against actual row counts, then preserve a verified plan. A SQL plan baseline constrains the optimizer to accepted plans, whereas a SQL profile corrects estimates without fixing one plan
([SQL plan management](https://docs.oracle.com/en/database/oracle/oracle-database/19/tgsql/overview-of-sql-plan-management.html)).

### Caching and incremental rendering: useful but not proof of playability

Oracle's server result cache is not applicable to the current production frame
query: results involving temporary tables cannot be cached, and an active
transaction referencing queried objects is also ineligible
([Oracle result-cache requirements and restrictions](https://docs.oracle.com/en/database/oracle/oracle-database/26/tgdba/tuning-result-cache.html)). Dynamic session, player, sector, and object DML would also make broad result caching high-churn. `RESULT_CACHE_MODE=FORCE` is therefore not a solution.

A project-owned relational cache can remain within the charter if SQL computes
the frame and the cache key. It must never contain evaluator or golden data.
Recommended cache levels are:

- a bootstrap- or first-use-generated spawn/world layer keyed by the complete
  render inputs, allowing later `NEW_GAME` calls to reuse SQL-produced runs;
- static title/menu/intermission backgrounds and HUD glyph placements;
- world-layer cache separate from sprite/HUD layers;
- exact full-frame cache for retry, replay, rewind, load, or a revisited exact
  render state;
- optional per-column cache only if measured hit rates justify it.

The key must cover exact player pose/view bob, mode, tic-dependent animation
phases, every live sector height/light, every visible line/switch state, all
rendered mobj state/pose, weapon/HUD/key/ammo/health values, pause/menu/automap
state, and all immutable asset/renderer revision hashes. The safer design stores
separate world, masked, and presentation digests with explicit dependencies.

This can make repeated spawn/menu/replay frames very fast, but ordinary movement
changes pose-dependent wall projection and floor/ceiling sampling across most of
the image. Turning does not shift columns by an exact integer because the camera
plane maps columns nonlinearly. Cache hits must therefore not be used to claim
30-FPS unique gameplay. Likewise, an incremental renderer may reuse conservative
candidate sets across a swept player motion, but it must still prove no newly
visible seg is omitted and retain all exact intersections; approximate screen
shifts are forbidden.

### Static materialization and indexing

Materialized views or ordinary seed tables are appropriate for immutable WAD
derivations, but not for live session render state. Oracle materialized views can
be refreshed on demand and used by query rewrite, subject to repeatability and
determinism restrictions
([CREATE MATERIALIZED VIEW](https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/CREATE-MATERIALIZED-VIEW.html)). Directly named, seed-generated relational tables are simpler and more predictable here.

Specific static relations to benchmark:

- `DOOM_RENDER_RAY(orientation_ordinal,column_no,angle_radians,direction_x,
  direction_y,plane_x,plane_y,cam_x,ray_x,ray_y,ray_length_squared)`;
- `DOOM_RENDER_SEG` with endpoints, deltas, line cross constant, side ids,
  sector ids, offsets, flags, length, and subsector membership;
- `DOOM_RENDER_SPRITE_STATE` resolving state/rotation to asset dimensions,
  offsets, and flip once;
- `DOOM_ASSET_FIRST_OPAQUE` and any other per-asset min/max opaque bounds;
- a real animation-definition table rather than repeated `UNION ALL ... DUAL`;
- optional per-asset/light lookup only after `AT` and colormap row-source timing
  proves those indexed probes dominate.

The existing `AT(a,x,y)` primary key already supports exact texel probes. Adding
more indexes without row-source evidence can increase GTT/static maintenance and
memory pressure. Extended column-group or expression statistics help only when
actual-versus-estimated rows show correlation errors; Oracle describes their
purpose as improving selectivity and group cardinality estimates
([extended statistics](https://docs.oracle.com/en/database/oracle/oracle-database/26/tgsql/managing-extended-statistics.html)).

### Spatial strategy

Keep `SDO_FILTER` only as a primary MBR candidate filter and retain exact
determinant/t/u acceptance. Oracle's spatial query model explicitly states that
the primary filter is a cheaper superset and exact secondary work is needed for
an accurate result
([Oracle Spatial query model](https://docs.oracle.com/en/database/oracle/oracle-database/23/spatl/query-model.html)).

Probe `SPATIAL_VECTOR_ACCELERATION=TRUE`; Oracle says it defaults to true from
21c and accelerates spatial operators and metadata caching
([spatial vector acceleration](https://docs.oracle.com/en/database/oracle/oracle-database/23/spatl/spatial_vector_acceleration-system-parameter.html)). This is low-risk but cannot be presumed to reduce the much larger ray/segment and pixel work. Stage the frustum candidate set once and record whether the spatial index is actually used. Compare it with angular-range and BSP candidate counts. A new spatial index on individual segs may reduce false positives but doubles geometry rows from 1,175 linedefs to 2,057 segs; it should be accepted only on measured total R1 time, not candidate selectivity alone.

### GTT, undo, and plan controls

Test `ALTER SESSION SET TEMP_UNDO_ENABLED=TRUE` before the ORDS pooled session
first touches a GTT. Oracle advises this for applications using temporary
objects; temporary undo avoids redo for temporary-table undo and can improve
performance
([temporary undo](https://docs.oracle.com/en/database/oracle/oracle-database/21/admin/managing-undo.html), [parameter reference](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/TEMP_UNDO_ENABLED.html)). This primarily reduces staging overhead and redo; it is not an algorithmic 790x lever. It must be probed on both Free and Autonomous because the session setting and managed service privileges may differ.

Audit every GTT primary-key/index cost. `FRAME_WORLD_PIXEL` is inserted and then
copied into another 64K GTT; direct insertion into the final frame plus sparse
set-based overlay updates may remove one table and index build per frame. Compare
heap insert plus later sort against indexed insert for `FRAME_R1_HIT`, portal
hits, pixels, and RLE. Do not use `TRUNCATE`, autonomous transactions, or a
commit inside rendering.

The current private `_optimizer_use_feedback` hint is a cloud-portability risk.
Prefer a supported stable shape, accurate statistics, documented hints, and an
accepted plan baseline after evidence. Disabling `OPTIMIZER_ADAPTIVE_STATISTICS`
does not disable all statistics feedback; Oracle documents the distinction
([optimizer adaptive statistics](https://docs.oracle.com/en/database/oracle/oracle-database/23/refrn/OPTIMIZER_ADAPTIVE_STATISTICS.html)).

### RLE, JSON, frame hashing, and LOBs

`MATCH_RECOGNIZE` remains mandatory. Benchmark the current pattern after the
final frame is already ordered; do not replace it with a different codec before
proving it dominates.

The current XML-per-pixel frame-byte path is a strong post-render candidate.
One exact SQL alternative is to assign row-major ordinals, `LISTAGG` fixed
two-digit hex into several sub-32K chunks, XML/LOB-aggregate only those few
chunks in order, convert the final 128,000 hex characters once, and retain the
same SHA-256. This changes no hash definition. It must pass byte-for-byte frame
BLOB comparison before selection.

Oracle SQL/JSON generation can return a `BLOB` containing AL32UTF8 text
([JSON generation overview](https://docs.oracle.com/en/database/oracle/oracle-database/23/adjsn/overview-json-generation.html), [JSON_ARRAYAGG](https://docs.oracle.com/en/database/oracle/oracle-database/26/sqlrf/JSON_ARRAYAGG.html)). Building the canonical response directly as BLOB may eliminate the final CLOB-to-UTF8 copy. Native binary JSON/OSON is useful for stored/queryable documents, but the public payload must be canonical textual JSON inside gzip, so OSON adds a serialization step and is not a default win.

Explicitly release no-longer-needed temporary LOBs and measure temporary LOB
counts/space under pooled ORDS concurrency. Oracle warns that accumulated
temporary LOBs can considerably slow the system
([temporary LOB guidance](https://docs.oracle.com/en/database/oracle/oracle-database/23/adlob/before-you-begin.html)). Value LOBs are optimized for SQL-query fetches, but PL/SQL OUT binds become reference temporary LOBs, so they do not remove this responsibility
([Oracle value LOBs](https://docs.oracle.com/en/database/oracle/oracle-database/23/adlob/value-based-LOBs.html)).

Changing gzip level or RLE shape cannot be prioritized until materialization is
below the gate and transport dominates. The 92,658-byte gzip BLOB expands under
AutoREST base64; this representation is fixed by the P0/charter contract.

### In-Memory, vectorization, and parallel execution

Database In-Memory is a poor baseline recommendation. Locally it competes for
Oracle Free's total 2-GB memory; in Autonomous it is available only with the
ECPU model at a minimum 16 ECPUs
([Autonomous Database In-Memory](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/autonomous-in-memory.html)). It is intended for scan/filter/join/group analytic workloads and must be populated and warmed. The renderer mostly needs selective geometry and exact texel lookups after candidate pruning. Oracle Spatial can scan in-memory virtual columns without a spatial index, but that is not portable to the required small local target
([Spatial In-Memory support](https://docs.oracle.com/en/database/oracle/oracle-database/23/spatl/database-memory-support-oracle-spatial.html)).

Oracle's `VECTOR` data type and vector-search indexes do not vectorize arbitrary
ray math or texture sampling. Encoding a 200-pixel palette column as an AI
vector would complicate unsigned byte identity and still require relational
construction/serialization; reject unless a minimal exact prototype proves a
full end-to-end win on both targets.

At most two local cores exist. A DOP-2 experiment might reduce one CPU-bound
statement, but parallel setup, GTT DML restrictions, and concurrent ORDS users
can erase the latency gain. Autonomous service/consumer group choice also
controls concurrency and resources. Treat parallelism as a measured finishing
experiment after work reduction, never the main plan.

### ORDS transport

ORDS 26.2 AutoREST returns BLOB/CLOB values as base64 by default
([ORDS 26.2 Developer's Guide](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.2/orddg/oracle-rest-data-services-developers-guide.pdf)). A media-resource/custom-handler path could avoid that representation, but custom handlers are explicitly forbidden, so it is not an option.

Local ORDS settings such as initial/max JDBC connections and per-connection
statement cache can reduce connection creation, queueing, and parse overhead;
Oracle documents `jdbc.InitialLimit`, `jdbc.MaxLimit`, and
`jdbc.MaxStatementsLimit`
([ORDS configuration](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.1/ordig/about-REST-configuration-files.html)). They will not turn 26 seconds of database work into 33 ms, and managed ORDS does not expose the same local controls. ORDS metadata cache is helpful mainly when service-count metadata lookup is material
([ORDS performance considerations](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.2/ordig/miscellaneous-configuration-options-of-ORDS.html)). Measure ORDS only after subtracting database-complete time.

## Recommended execution order under the playable gate

1. Complete the missing stage isolation on cold-cache moving `STEP` frames and
   publish actual row-source statistics. Do not resume parity.
2. Prototype, without replacing the canonical oracle, the combined static ray
   table + render-seg table + exact screen-column interval filter. Require a
   large candidate-pair and R1 latency collapse.
3. Materialize portal hits/interval windows once and feed both world/masked.
4. Precompute sprite catalog/first-opaque/animation/static geometry relations.
5. Replace presentation union/rank with bounded set-based base-frame plus sparse
   overlay composition.
6. Re-measure a cold-cache 300-frame ordinary moving replay. If cache-miss p95
   is still orders of magnitude above 33.3 ms, test the higher-risk BSP
   front-to-back design. Be prepared to conclude that the gate is infeasible on
   Oracle Free under the current charter.
7. Only after renderer materialization approaches the budget, optimize frame
   hashing, JSON-to-BLOB, temporary LOB lifecycle, gzip, ORDS, and browser work.
8. Add exact SQL-owned caches for spawn/static modes/replay as latency and
   concurrency improvements, but keep their results separate from unique-frame
   playability.
9. Run all T5-T7 correctness and mutation gates after every selected candidate;
   no hash, schema, frame, ownership, or resolution relaxation is acceptable.

## Decision

The next optimization attempt should combine ranks 1 and 2 only if separate
diagnostics show both R1 pair generation and repeated portal analytics are
material; otherwise target the single largest measured row source. The next
presentation attempt should be rank 3. These are technically distinct and
large enough to test whether the 30-FPS goal is even in reach.

If those architectural attempts plus the BSP alternative leave cold-cache
moving frames above the budget by more than a small constant factor, further
index/hint/ORDS work should not be marketed as a path to playability. At that
point the honest outcome is a demonstrated charter-versus-hardware feasibility
blocker requiring user direction, not a parity resumption.
