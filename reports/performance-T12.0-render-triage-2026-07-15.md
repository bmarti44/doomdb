# T12.0 fresh rendering triage

Date: 2026-07-15

This report is the local evidence packet for the next Sol/max research pass.
It profiles the selected exact production renderer; it does not profile a
discarded experiment or the canonical SQL oracle called directly.

## Method and identity

Two consecutive `DOOM_API.NEW_GAME(3)` calls were captured with Oracle event
10046 level 8, `STATISTICS_LEVEL=ALL`, and TKPROF. The temporary `ALTER SESSION`
grant was revoked after each capture. Each throwaway game session was deleted.
Both calls returned the canonical 92,658-byte compressed payload. The database
and ORDS remained healthy, all production objects were valid, and no Java/probe
objects remained.

The first call measured 11,140.362 ms. The immediate second call measured
10,568.592 ms and is the ranking authority below. The same plan hashes and row
counts appeared in both traces. Earlier selected exact observations reached
6.97 seconds; the current loaded instance is under greater memory pressure, but
the stage ordering is stable.

## Ranked database stages

| Rank | Stage / SQL ID | Warm elapsed | CPU | Rows | Physical/TEMP reads |
| ---: | --- | ---: | ---: | ---: | ---: |
| 1 | World pixels `afvrdp0gy5sv3` | 6.53 s | 5.62 s | 64,000 | 14,685 blocks |
| 2 | Selected masked pixels `bwh53um32gq8j` | 1.21 s | 1.18 s | 7,106 | 30 blocks |
| 3 | Bounded R1 hits `cw276y3b2qunv` | 1.18 s | 0.99 s | 12,558 | 0 |
| 4 | Base-frame insert `c50bbdt8xp63d` | 0.39 s | 0.39 s | 64,000 | 0 |
| 5 | Sparse presentation merge `cngx9bk9ff4zn` | 0.27 s | 0.26 s | 12,302 | 0 |
| 6 | RLE `ans0rrdtddwk3` | 0.24 s | 0.24 s | 45,317 | 0 |
| 7 | Portal hits `40hq61zhv57fh` | 0.19 s | 0.19 s | 12,558 | 0 |
| 8 | JSON columns `64hzdn9uq93nz` | 0.16 s | 0.15 s | 1 | 0 |
| 9 | Segment bounds `ga6rvqjqud3n1` | 0.15 s | 0.08 s | 2,018 | 2 blocks |
| 10 | Chunked frame bytes/hash input `a67h9dramwk9t` | 0.11 s | 0.11 s | 1 | 0 |
| 11 | Sector intervals `4qpvha1x4cqdh` | 0.01 s | 0.01 s | 2,084 | 0 |

These statements account for about 10.44 of the 10.57 seconds. New-game state
setup, history, response JSON wrapper, compression call boundary, and cleanup
are not the primary problem.

Thirty FPS allows 33.3 ms for the complete response. The warm database frame is
roughly 317 times over that budget. World sampling alone is roughly 196 times
over it. RLE alone is 7.2 times the complete budget, so retaining production
per-pixel `MATCH_RECOGNIZE` cannot satisfy the target even after visibility is
fixed.

## World-pixel row-source pathology

`DOOM_R2_STAGED_PIXEL_ROWS` begins with one selected session, 320 preseeded
rays, 182 live-over-static sector values, 2,084 sector intervals, 12,558 portal
hits, and a dense 320x200 screen relation. It derives wall and plane candidates,
selects exact ownership, resolves animation/assets, performs indexed `AT`
samples and colormap lookup, and inserts 64,000 GTT rows.

The warm plan shows:

- 26,165 selected wall pixels consuming about 2.52 seconds;
- 37,835 selected plane pixels consuming about 1.56 seconds;
- a 4,762,030-row Cartesian intermediate between wall-pixel candidates and all
  182 sector values, costing about 1.42 seconds before later reduction;
- a 185,363-row plane/interval intermediate;
- 64,000 indexed `AT` texture lookups costing about 0.53 seconds plus 64,000
  index probes costing about 0.45 seconds in the captured row source;
- 64,000 colormap probes costing roughly 0.14 seconds; and
- four large one-pass hash workareas. The two largest wanted 56.7 and 41.6 MB
  but received only about 3.9 and 3.5 MB, spilling 48 and 36 MB. Three more
  spilled about 13, 11, and 11 MB.

The statement performed 255,411 consistent gets, 122,194 current gets, and
14,685 physical reads in the warm trace. It remains CPU-bound as well as
spill-bound: removing the full 0.91-second CPU/elapsed difference would still
leave 5.62 seconds of world CPU.

## Masked-pixel pathology

The selected range-bounded masked path is much faster than its former
31.68-million-pixel Cartesian plan but remains 1.21 seconds:

- 495 source bounds produce 3,505 bounded column fragments and 34,750 sampled
  candidates;
- 18,191 candidates reach the final window rank and 7,106 are selected;
- the rank/window portion consumes about 1.08 seconds;
- `DOOM_SCREEN_COLUMN` is full-scanned 3,505 times in the selected plan,
  consuming about 0.45 seconds despite the range-bounded SQL shape; and
- 34,750 `AT_XY_IX` probes consume about 0.085 seconds.

This stage does not spill to TEMP in the current plan. It is mainly repeated
row-source execution and ranking overhead.

## R1-hit pathology

The exact bounded path reduces 2,057 segs x 320 rays to 2,018 projected seg
bounds and 12,558 accepted hits. It still spends approximately:

- 0.51 seconds performing 2,018 batched table lookups into
  `DOOM_RENDER_RAY`;
- 0.43 seconds in the 2,018 range scans of `DOOM_RENDER_RAY_CAM_IX`; and
- 0.68 seconds in the final per-column hit-order window sort, with overlapping
  operator timings.

It does not spill, but its index/nested-loop and ordered-row representation are
too expensive for a 33.3 ms complete budget.

## Memory and local resource state

Oracle Free is constrained to two CPUs and 2 GiB by Compose. At capture time:

- the database container used about 1.939 GiB of its 2 GiB limit;
- `SGA_TARGET` was 1 GiB and `PGA_AGGREGATE_TARGET` was 256 MiB;
- total PGA allocated was about 551 MiB and maximum observed PGA about 831 MiB;
- `over allocation count` was 907;
- `extra bytes read/written` was approximately 4.9 GB; and
- the TEMP tablespace had grown to about 1,020 MB allocated. No session owned a
  live TEMP segment after profiling, so the allocated TEMP high-water mark is
  not an orphaned running query.

Increasing PGA may reduce the current 0.5-0.9 second I/O component, but cannot
remove the multi-second CPU and row-count cost. Parallelism is also a poor fit
for a two-core database that must simultaneously simulate and serve ORDS.

## Current production architecture

The production path remains entirely database-side:

1. PL/SQL locks/updates authoritative relational game state.
2. SQL materializes session-scoped GTTs for projected seg bounds, R1 hits,
   portal hits, sector intervals, world pixels, and masked pixels.
3. SQL copies the 64,000 world pixels to a final GTT, applies masked pixels, and
   merges sparse weapon/HUD/pause overlays.
4. SQL constructs the frame hash, 45,317 column RLE rows, and canonical JSON.
5. PL/SQL converts/compresses the response and AutoREST returns the BLOB.
6. The browser only decodes, applies PLAYPAL, plays database-issued audio, and
   blits the frame.

The canonical SQL renderer remains byte-locked as the parity oracle. The
approved production direction permits a clean-room Java 11 OJVM render/codec
hot path reading the same transaction through internal JDBC, but no such Java
renderer is selected yet.

## Existing OJVM evidence and failed extrapolation

Disposable microprobes measured a coherent 320x200 generation + GZIP + RAW
return at 6.8 ms mean, demonstrating that compact in-process transport can be
fast. A production-shaped brute probe then performed 320x2,057 intersections,
64,000 samples, SHA-256, per-run JSON, GZIP, and caller-owned BLOB mutation. Its
244,435-byte payload measured 1,133.9 ms p50 / 1,461.5 ms p95. Explicit native
compilation of the monolithic class stalled and was killed cleanly.

Therefore “move the existing brute work into Java” is rejected. The remaining
credible route must both reduce visible work before pixels and use small,
separately compilable hot methods: BSP front-to-back traversal, node bounding
boxes, solid screen-column coverage, wall columns, plane spans, primitive
masked fragments, immutable packed asset/geometry caches, one framebuffer, and
a compact exact codec.

## Previously rejected local shapes

- Per-pixel indexed row-range generation regressed world sampling, including a
  controlled retest after session-cardinality repair.
- Materialized portal/interval clip windows exceeded 60 seconds and exhausted
  UGA; it was killed and removed.
- Splitting world geometry and texel lookup isolated roughly 3.36 and 0.59
  seconds but added an extra 64,000-row insert and regressed end to end.
- Broad CTE materialization, ray materialization, fallback unions, and aggregate
  presentation rewrites all regressed exact public calls.
- MLE JavaScript, `UTL_TCP`, DOP, ORDS tuning, and network changes do not remove
  the measured row-source work.

## Research questions

The research pass should rank concrete approaches for this exact evidence:

1. Clean-room BSP/solid-column/visplane structures suitable for primitive Java
   arrays and exact differential testing against the SQL oracle.
2. OJVM JIT code-shape guidance: method splitting, `COMPILE_METHOD`, bytecode
   limits, session state, GC/allocation avoidance, and verified native status.
3. Efficient bulk internal-JDBC loading and revision-keyed immutable geometry,
   texture-column, colormap, sprite, and flat packs without embedding a WAD.
4. A framebuffer/codec contract that avoids 64,000 SQL rows and 45,317
   production RLE rows while preserving exact indexed pixels and an independent
   SQL/MATCH_RECOGNIZE oracle.
5. Techniques that remain compatible with Oracle Free's two-core/2-GB limit,
   ORDS AutoREST BLOB output, Autonomous OJVM, and eventual 640x400 profiles.
6. Any overlooked Oracle, Java, database-rendering, visibility, temporal
   coherence, incremental rendering, or transport technique that could plausibly
   pass <=20 ms renderer p95 and <=33.3 ms local end-to-end p95.

No recommendation should claim 30 FPS from an average, a repeated frame, a
limiter, a cache hit, a reduced resolution, or a synthetic transport probe.
