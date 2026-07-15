# Sol/max rendering bottleneck research after fresh 10046 triage

Date: 2026-07-15
JavaBox reference: commit `8241259df9d0a52b2a4e5a49b2133b90bc44e7bd`
Authority for local measurements:
`reports/performance-T12.0-render-triage-2026-07-15.md`

This pass is architecture research, not a performance claim. It did not copy,
translate, or derive implementation code, tables, constants, control flow, or
data from JavaBox, Mocha Doom, id Doom, or another engine. JavaBox and id Doom
were used only to corroborate public high-level renderer organization.

## Verdict

The new trace makes the stopping decision sharper: **do not spend another
iteration optimizing the selected relational pixel renderer, and do not revive
the brute 320-by-2,057 Java intersection kernel.** The production SQL path is
not one bottleneck that is amenable to a better index. It is an ordered chain of
row representations that are each too expensive for a 33.3 ms response:

- world pixels: 6.53 s;
- masked pixels: 1.21 s;
- R1 hits: 1.18 s;
- final/base/presentation pixel-row writes: 0.66 s combined; and
- SQL RLE: 0.24 s.

The 0.24-second RLE stage alone is 7.2 times the whole-frame budget. Even a
perfect no-I/O world plan would retain 5.62 seconds of world CPU. Larger PGA can
remove only a fraction of the 6.53-second world stage; it cannot remove the
64,000-row ownership/sampling work, repeated probes, analytic ranking, later
64,000-row writes, or 45,317-row codec.

The credible renderer route is now a **small-method, verified-JIT, clean-room
OJVM renderer that reduces visible work before rasterization**:

1. traverse the ingested WAD BSP front-to-back;
2. reject child bounding boxes outside the frustum or behind already solid
   screen-column coverage;
3. project only surviving seg fragments using DoomDB's existing equations and
   exact tie contracts;
4. draw opaque walls by columns, accumulate floors/ceilings by plane boundary
   arrays and draw horizontal spans, and defer masked fragments for exact
   back-to-front composition;
5. sample packed, revision-keyed primitive asset arrays into one reusable
   indexed framebuffer; and
6. generate hash, exact Java RLE/JSON, GZIP, and the caller-owned BLOB without
   materializing relational pixels or runs.

This is necessary but not sufficient for 30 FPS. Render-free simulation is
currently 41.410 ms p50 / 70.581 ms p95, already over the complete 33.3 ms
deadline. The renderer and simulation workstreams must independently reach
approximately 20 ms p95 and 10 ms p95, respectively, with 3.3 ms left for
handoff/ORDS/browser work. No renderer result can be called playable while the
simulation p95 remains 70.581 ms.

## Evidence notation

- **Measured** means observed in the repository's local traces or disposable
  probes.
- **Source-backed** means stated by a linked primary source.
- **Inference** means a proposed design or expected effect that must pass the
  stated spike; it is not presented as achieved performance.

## What is actually slowest

### 1. World ownership and sampling is the dominant stage

**Measured.** `DOOM_R2_STAGED_PIXEL_ROWS` consumes 6.53 seconds elapsed and
5.62 seconds CPU for 64,000 output rows. Its most damaging row sources are:

- 26,165 selected wall pixels, about 2.52 seconds;
- 37,835 plane pixels, about 1.56 seconds;
- a 4,762,030-row wall-candidate by 182-sector Cartesian intermediate, about
  1.42 seconds;
- 64,000 indexed texture probes, about 0.98 seconds across lookup operators;
- four large one-pass hash workareas, including 56.7 and 41.6 MB desired
  workareas receiving only 3.9 and 3.5 MB and spilling 48 and 36 MB; and
- 255,411 consistent gets, 122,194 current gets, and 14,685 physical reads.

**Inference.** The highest-impact change is not a revised sector join. It is to
stop representing screen ownership as relational candidate pixels. The hot
unit should be a projected visible primitive plus column/vertical bounds, with
pixels expanded exactly once in primitive arrays.

### 2. Masked rendering is ranking work, not texel work

**Measured.** The bounded path reduces the old 31.68-million-pixel shape to
34,750 candidates, but still costs 1.21 seconds. Approximately 1.08 seconds is
in the final window/rank portion. `DOOM_SCREEN_COLUMN` is full-scanned 3,505
times and costs about 0.45 seconds; texture probes cost only about 0.085 seconds.

**Inference.** Masked walls and sprites should remain projected fragments until
opaque depth/clip bounds are complete. A primitive index array sorted once by
the canonical depth and tie keys, followed by bounded column writes, replaces
per-pixel window ranking. A boolean “solid column” is insufficient for portals
and sprites: the design needs per-column upper/lower opaque clip bounds and, for
the exceptional disjoint case, a compact interval list.

### 3. The accepted-hit representation is independently over budget

**Measured.** R1 costs 1.18 seconds for 12,558 hits even after seg-to-column
bounds. Roughly 0.94 seconds comes from 2,018 repeated ray-table lookups/range
scans and about 0.68 seconds overlaps the final per-column ordered window sort.

**Inference.** Rays, projection scales, screen angles, and seg geometry belong
in dense primitive arrays. BSP traversal should reduce candidate segs before
the exact determinant/projection test. Per-column hit lists should be bounded
scratch arrays or eliminated by front-to-back immediate processing; they must
not become database rows or general Java objects.

### 4. Pixel-row composition and RLE cannot remain production stages

**Measured.** Inserting 64,000 base pixels costs 0.39 seconds, sparse
presentation merge costs 0.27 seconds, and 45,317-row `MATCH_RECOGNIZE` RLE
costs 0.24 seconds. Together they consume 0.90 seconds after visibility and
sampling.

**Inference.** The production hot path must draw world, masked content, weapon,
HUD, and overlays into one reusable `byte[64000]`, then scan that array once to
produce the canonical run order and JSON. The SQL framebuffer and
`MATCH_RECOGNIZE` stay independently callable as the oracle, never as a hidden
production fallback.

### 5. Memory pressure amplifies SQL latency but is not its cause

**Measured.** Oracle Free was at 1.939 GiB of its 2 GiB container limit, had
907 PGA over-allocations and about 4.9 GB cumulative extra bytes read/written.
The world query spills multiple workareas.

**Source-backed.** Oracle AI Database Free limits processing to two cores and
RAM to 2 GB. [Oracle Free licensing restrictions](https://docs.oracle.com/en/database/oracle/oracle-database/26/xeinl/licensing-restrictions.html)

**Inference.** A moderate PGA rebalance may make triage less noisy, but it is a
dead end for the 30 FPS objective. The target renderer should be single-threaded
and allocation-flat. It should leave the second core and memory headroom for
simulation, database services, ORDS, and JIT compilation.

## Why JavaBox is useful—and what it does not prove

**Source-backed.** At the pinned commit, JavaBox runs a persistent OpenJDK 21
Zero interpreter in WebAssembly and reports Mocha Doom at approximately 30 FPS.
Its canvas adapter accesses an existing `DataBufferInt`, copies the packed frame
to shared WASM memory, and refuses publication more frequently than every 33 ms.
[JavaBox README](https://github.com/bmarti44/javabox/tree/8241259df9d0a52b2a4e5a49b2133b90bc44e7bd),
[Canvas adapter](https://github.com/bmarti44/javabox/blob/8241259df9d0a52b2a4e5a49b2133b90bc44e7bd/container/doom/adapter/CanvasRenderer.java)

**Source-backed architectural corroboration.** Its included renderer is divided
around persistent renderer state, BSP traversal, visible planes, visible
sprites, wall/column functions, and span functions. The original id repository
independently exposes the same high-level BSP, column, and plane-span
organization. [JavaBox renderer directory](https://github.com/bmarti44/javabox/tree/8241259df9d0a52b2a4e5a49b2133b90bc44e7bd/container/doom/src/rr),
[id Doom renderer directory](https://github.com/id-Software/DOOM/tree/master/linuxdoom-1.10)

**Inference.** This is strong feasibility evidence for persistent arrays,
front-to-back work rejection, wall columns, plane spans, and one packed
framebuffer. It is not a benchmark for DoomDB: the 33 ms check is a limiter,
not an uncapped p95 measurement; the environment, renderer semantics, payload,
database transaction, and Java runtime differ. No JavaBox/Mocha/id code may be
used to implement the recommendation.

## Ranked action matrix

Scores are relative to the present 10.57-second database render. “Kill” means
stop that experiment, retain its evidence, and move to the next branch.

| Rank | Recommendation | Expected impact | Risk | Falsifiable spike | Kill threshold |
| ---: | --- | --- | --- | --- | --- |
| 1 | Split and synchronously JIT-compile isolated primitive kernels | Enables the whole route; potentially orders of magnitude versus interpreted/row-source work | Medium: OJVM compiler behavior | Separate classes/methods for BSP traversal, projection, wall columns, planes, masked draw, codec; run `COMPILE_METHOD` and verify every hot method compiled | Any hot method cannot compile in 60 s, is not reported compiled, or the no-JDBC composite kernel is >12 ms p95 |
| 2 | BSP front-to-back candidate rejection plus exact solid/vertical column coverage | Removes most of the 2,057-by-320 candidate work and all SQL hit rows | High: portal/occlusion exactness | Traverse 681 nodes/682 subsectors using ingested arrays; output only primitive IDs/ranges; compare candidate sufficiency and final pixels to SQL corpus | >3 ms p95 traversal/projection, >25% of seg-column brute pairs retained at ordinary poses, or any missing SQL winner |
| 3 | Wall-column plus plane-span rasterizer into one indexed framebuffer | Removes the 6.53 s world stage and 64k-row base insert | High: exact sampling/ties/sky/animated sectors | Render opaque world only for 300 oracle poses; stage timers and byte differential | >8 ms p95 world draw at 320x200 or any unexplained pixel mismatch after boundary fixtures |
| 4 | Primitive masked-fragment pass | Removes the 1.21 s rank/window stage | High: stable depth ties and portal clipping | Bound/sort projected masked primitives once; compare 7,106 selected pixels and full frame | >3 ms p95, unbounded scratch growth, or any tie/occlusion mismatch |
| 5 | Revision-keyed packed relational assets and primitive session cache | Eliminates millions of first-use row/object operations from steady frames | Medium: ORDS pooled sessions duplicate caches | Bootstrap-generate relational BLOB packs with digests; cold/warm each real pool session and mutate revision key | >12 MiB retained per pooled session, >5 ms warm snapshot load, stale data, or cross-session leakage |
| 6 | One-pass Java hash/RLE/JSON/GZIP into a caller-owned BLOB | Removes 0.90 s post-render SQL and bounds handoff | Medium: exact order, payload size, BLOB calls | Real 45k-run/92,658-byte corpus; compare `Blob.setBinaryStream` and <=32,767-byte chunk writes at compression levels that preserve contract | >5 ms p95 codec plus handoff, any decompressed-byte/RLE mismatch, or unbounded temporary allocations |
| 7 | Allocation-flat persistent scratch state | Reduces p95/GC variance under 2 GB | Low to medium | Record per-frame allocations/session heap and GC for 300 unique frames | Any full GC, >1 ms p95 GC/call-state migration, or growing retained memory |
| 8 | Exact temporal/column reuse as an optional later branch | Pose-dependent; likely small on moving acceptance frames | High: invalidation complexity | Measure unchanged primitive signatures/columns over the mandated moving corpus before implementing reuse | Fewer than 25% unchanged columns at p95, or dependency-key cost exceeds saved raster work |

### Composite gates

Do not integrate these pieces into `DOOM_API` until all of the following pass in
one persistent database session after 30 warmups:

- no-JDBC render kernel: <=12 ms p95;
- warm dynamic snapshot plus full render: <=17 ms p95;
- renderer, exact codec, and BLOB handoff: <=20 ms p95;
- every selected hot method reports native compilation; and
- 300-frame exact framebuffer/hash/RLE/decompressed-payload corpus is green.

The full 30 FPS acceptance remains 270 unique moving frames at <=33.3 ms p50
and p95 through the real API. These component limits are rejection gates, not
substitutes for that acceptance.

## OJVM code shape after the monolithic compile stall

**Measured.** The production-shaped monolithic probe took 1,133.9 ms p50 /
1,461.5 ms p95 and synchronous `COMPILE_CLASS` stalled for minutes before the
session was killed. Its 244,435-byte payload was also much larger than the real
92,658-byte response. The result rejects both the brute architecture and the
monolithic code shape.

**Source-backed.** OJVM JIT can compile hot methods to native code, persist
compiled methods across calls/sessions/instances, and exposes
`DBMS_JAVA.COMPILE_METHOD(classname, methodname, methodsig)`. Its compiler runs
as one MMON worker and consumes resources comparable to an active Java session.
[Oracle JVM JIT](https://docs.oracle.com/en/database/oracle/oracle-database/26/jjdev/Oracle-JVM-JIT.html)

**Source-backed.** The JVM class-file format caps a method's Code attribute
below 65,536 bytes. This is a format ceiling rather than OJVM's observed stall
threshold, but it reinforces keeping hot methods bounded and auditable.
[JVM Specification 11, Code attribute](https://docs.oracle.com/javase/specs/jvms/se11/html/jvms-4.html#jvms-4.7.3)

**Inference.** Use 6–10 cohesive hot methods, not hundreds of tiny calls and not
one generated mega-method. Keep orchestration out of pixel loops. Compile each
named method separately, record its signature, return count, elapsed compile
time, and `USER_JAVA_METHODS.IS_COMPILED`. A compile timeout is a failed gate,
not permission to benchmark interpreted code. Warm and measure only after the
MMON compile work is complete so compilation does not contend with the frame.

Suggested independently testable boundaries:

1. `locateAndTraverseBsp`;
2. `projectVisibleSegs`;
3. `drawOpaqueColumns`;
4. `buildAndDrawPlaneSpans`;
5. `drawMaskedFragments`;
6. `composePresentation`;
7. `encodeRunsAndJson`; and
8. `gzipAndWriteBlob`.

This method list is a new DoomDB decomposition, not a transcription of an
external engine.

## Primitive arrays, caches, and internal JDBC

**Source-backed.** Java running inside the database must use the server-side
internal JDBC driver for the same database session. Oracle recommends
`OracleDriver.defaultConnection()` because it is faster and uses fewer
resources, says not to close that default connection, and says to close
statements at the end of each call.
[Oracle JDBC developer guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/jjdbc/jdbc-developers-guide.pdf),
[server-side internal driver](https://docs.oracle.com/en/database/oracle/oracle-database/23/jjdbc/server-side-internal-driver.html)

**Source-backed.** OJVM `static` fields are private to a database session and
persist across calls in that session. In shared-server mode, static-reachable
objects migrate to session space at end-of-call, so large static graphs have a
memory and performance cost. [Database sessions imposed on Java](https://docs.oracle.com/en/database/oracle/oracle-database/26/jjdev/Java-application-database-session.html),
[shared-server end-of-call migration](https://docs.oracle.com/en/database/oracle/oracle-database/26/jjdev/shared-server-consideration.html),
[OJVM memory usage](https://docs.oracle.com/en/database/oracle/oracle-database/26/jjdev/about-Java-memory-usage.html)

**Inference.** Use structure-of-arrays with exact-width primitive fields:

- BSP nodes: partition origin/delta, two children, four child bounding boxes;
- subsectors: first/count and resolved sector;
- segs: endpoints/deltas, linedef/sidedef/sector IDs, facing, static texture
  references, precomputed exact-safe projection terms;
- sectors/sides: compact mutable value arrays refreshed per frame;
- assets: palette bytes plus opacity bitsets, texture-column offset tables,
  flats, sprite metrics, PLAYPAL, and COLORMAP; and
- scratch: framebuffer, column clip bounds, projected-fragment arrays, plane
  top/bottom bounds, span starts, and codec/output buffers.

Avoid boxed collections, streams, comparators, per-pixel records, and per-frame
`String` fragments in hot methods. Sort primitive indexes with the full
canonical tie tuple. Reuse `MessageDigest`; Java 11 documents that `digest()`
resets it. Reuse `Deflater` only if exact gzip construction tests pass; Java 11
documents `reset()` for a new input while retaining level and strategy.
[Java 11 MessageDigest](https://docs.oracle.com/en/java/javase/11/docs/api/java.base/java/security/MessageDigest.html),
[Java 11 Deflater](https://docs.oracle.com/en/java/javase/11/docs/api/java.base/java/util/zip/Deflater.html)

The best load shape is likely a small number of revision-keyed relational BLOB
packs generated at bootstrap, not a JDBC fetch of 3,040,239 asset-pixel rows.
This remains database-owned data: packs are deterministic derivations with
source digests, not a WAD or renderer embedded in the Java JAR. Load immutable
packs once per pooled database session; query only the bounded dynamic snapshot
each frame. Cap the real ORDS pool and prewarm every configured session because
static caches are not shared between database sessions.

## Exact payload handoff

**Measured.** A synthetic coherent framebuffer plus GZIP returned as SQL RAW
averaged 6.8 ms, whereas BLOB variants averaged 29.7–32.0 ms. The realistic
monolithic probe mutated a caller-created 244,435-byte BLOB but did not isolate
handoff from its >1.1-second renderer, so it does not answer the BLOB question.

**Source-backed.** The server-side internal driver has 32,767-byte limitations
for some SQL-statement BLOB data interfaces. Oracle recommends `java.sql.Blob`
and documents stream/locator access and BLOB prefetch behavior.
[Oracle JDBC LOB guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/jjdbc/LOBs-and-BFiles.html)

**Inference.** Run a handoff-only spike using the actual decompressed JSON and
92,658-byte compressed payload distribution:

1. PL/SQL creates and owns the temporary BLOB locator.
2. Java renders/encodes into reusable byte buffers.
3. Compare one buffered `Blob.setBinaryStream` write with three or more
   <=32,767-byte locator writes.
4. Separately time JSON construction, SHA, deflate, and locator mutation.
5. Test incompressible and maximum-run corpus frames, not the 499-byte coherent
   microprobe.

If BLOB handoff remains above 5 ms p95, use fixed bounded RAW OUT chunks plus
PL/SQL `DBMS_LOB.WRITEAPPEND` only if the combined external measurement wins.
Do not use one Java call per chunk. Do not move transport to `UTL_TCP` or a
custom ORDS handler.

## Exactness-preserving visibility design

The largest implementation risk is treating a traditional BSP renderer as
automatically equivalent to the current analytic SQL oracle. It is not.

**Inference.** Preserve exactness through a hybrid contract:

- BSP traversal and child bounding boxes may remove candidates only when a
  conservative proof says they cannot own a pixel.
- Projection, determinant/range tests, texture coordinates, lighting, animation
  selection, and stable ties remain DoomDB's reviewed equations.
- A one-sided or vertically closed wall may mark a screen X range solid. An
  open portal may update only upper/lower opaque clip bounds; it may not hide the
  entire column.
- Plane accumulation is keyed by every value that affects the canonical sample:
  sector/plane identity, height, texture/sky, light/colormap, animation phase,
  and visible bounds. Horizontal spans are merely an iteration order over the
  same exact samples.
- Masked fragments retain all canonical depth and tie fields until final
  composition.
- Every pruning decision gets a debug mode that records the discarded primitive
  and independently asks the SQL oracle whether it could have won a pixel.

This lets the SQL renderer remain a genuinely independent oracle rather than
making Java match a different renderer's output by fixture patching.

## Scaling to 640x400

**Inference.** Resolution remains directly related to performance, but the
recommended architecture changes the scaling law:

- BSP traversal and visible primitive discovery are mostly resolution
  independent;
- screen-column projection/clip work scales approximately with width (2x);
- framebuffer sampling, overlays, hashing, and raw bytes scale with pixels
  (4x); and
- run count, JSON, GZIP, base64, and network bytes plausibly scale between 2x
  and 4x depending on scene entropy.

A 320x200 renderer that consumes the full 20 ms p95 renderer budget probably
will not provide 30 FPS at 640x400. Make every buffer/profile dimension dynamic
now, but require a 320x200 renderer+codec target nearer 8–12 ms p95 if 640x400
at 30 FPS is a real future requirement.

The non-obvious future bottleneck is no longer geometry; it is the exact
45k-run JSON transport. A profile-specific packed indexed-frame payload would
remove run-object/JSON expansion and scale much better, while the browser would
still only decode palette indices and blit. That would change the approved
public decompressed schema and therefore requires a later explicit charter
amendment plus local/Autonomous AutoREST proof. It must not be smuggled into the
current 320x200 optimization.

## Temporal and incremental rendering

**Inference.** Temporal reuse is not a first-order route for the mandated unique
moving corpus:

- turning changes every ray and usually every projected wall boundary;
- translation changes depths, texture coordinates, and plane samples across
  much of the screen;
- sector motion, sprites, weapon state, lighting animation, and palette effects
  broaden invalidation; and
- discovering whether a column is unchanged can approach the cost of producing
  its primitive signature.

Safe reuse still exists for immutable texture columns, animation mappings,
colormaps, sprite metrics, geometry, ray tables, unchanged presentation tiles,
and exact full-frame dependency-cache hits. Those are cache design, not a claim
that repeated frames satisfy 30 FPS. Before implementing column reuse, measure
the primitive signature change rate over the exact 270-frame acceptance corpus;
kill it if p95 reuse is below 25% or if dependency hashing costs more than a
fresh column draw.

## Autonomous and AutoREST constraints

**Source-backed.** Autonomous AI Database supports OJVM, but `JAVAVM` must be
enabled with `DBMS_CLOUD_ADMIN.ENABLE_FEATURE` and the instance restarted.
[Use Oracle Java on Autonomous AI Database](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/autonomous-oracle-java.html),
[DBMS_CLOUD_ADMIN ENABLE_FEATURE](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/dbms-cloud-admin.html)

**Source-backed.** AutoREST represents BLOB/CLOB content in its documented JSON
form, including base64 for binary content. That means response size and encode/
decode costs remain in the external deadline even when renderer execution is
fast. [ORDS Developer's Guide](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/25.4/orddg/oracle-rest-data-services-developers-guide.pdf)

**Inference.** Local OJVM JIT success does not prove Autonomous native compile
status, memory behavior, or end-to-end latency. P11 must probe `JAVAVM`, load and
resolve the exact checked-in Java 11 classes, verify compilation by method, and
repeat the component and external distributions. Cloud network latency must be
reported separately; it cannot be hidden by server-side frame caching.

## Dead ends and deferred experiments

### Reject now

- **More SQL join/index tuning as the 30 FPS route.** It cannot remove 5.62 s
  world CPU, 0.66 s pixel-row composition, or 0.24 s RLE.
- **PGA/TEMP tuning as the route.** It can recover part of spill time, not the
  orders-of-magnitude CPU/row gap.
- **The brute analytic Java renderer.** The measured kernel is >1.1 seconds and
  its monolithic compile stalls.
- **Production SQL `MATCH_RECOGNIZE`.** Its 240 ms stage alone fails the total
  deadline; retain it only as the independent oracle.
- **JavaBox's 33 ms limiter.** A cap skips publication; it does not accelerate a
  frame or establish uncapped p95.
- **MLE JavaScript, `UTL_TCP`, ORDS tuning, network tuning, DOP 2, or parallel
  SQL.** None removes the measured representation work; DOP also competes for
  the two available cores.
- **Client rendering/prediction/interpolation, lower resolution, missing
  effects, repeated frames, or batch-final-only frames.** All violate the
  accepted performance/correctness contract.
- **GPU, Vector API, `Unsafe`, native libraries, extproc, or OS/network access.**
  They are outside the Java 11/OJVM/Autonomous clean-room contract and add
  deployment/security incompatibility.

### Defer until the renderer is under 20 ms p95

- parallel Java rendering;
- incremental/dirty-column rendering;
- compression-level tuning;
- ORDS pool/LOB/base64 finishing work; and
- 640x400 activation or a packed-frame schema amendment.

## Recommended next execution order

1. Build a **non-production disposable JIT suite** with separate traversal,
   projection, wall, plane, masked, and codec methods. Verify each through
   `COMPILE_METHOD`; record compile wall time and native status.
2. Implement only the **BSP candidate/coverage kernel** against ingested
   geometry. Add conservative-pruning audit output and compare with SQL winners.
   Stop if it misses the 3 ms p95 or candidate-retention gate.
3. Add **opaque world columns and plane spans** into one reusable palette buffer;
   require exact world bytes and <=8 ms p95.
4. Add **masked primitive fragments**; require exact full world+masked bytes and
   <=3 ms p95 for the stage.
5. Add **packed relational asset inputs and revision-keyed session caches**;
   benchmark every real ORDS pooled session cold/warm and enforce the memory cap.
6. Add **presentation plus one-pass exact codec/BLOB handoff**; require full
   renderer <=20 ms p95 and the 300-frame parity corpus.
7. In parallel, continue reducing render-free SQL simulation from 70.581 ms to
   <=10 ms p95. Only then run the real 270-unique-frame <=33.3 ms API/browser
   gate.

The first useful proof is therefore not another full renderer. It is a
method-by-method native-compilation table plus a conservative BSP kernel that
shows how many seg-column pairs survive, how many nodes/subsectors are visited,
and whether every SQL-winning primitive remains present. That spike can falsify
the architecture quickly without contaminating production or weakening parity.
