# Sol/max 30 FPS architecture research

Date: 2026-07-15
Scope: repository inspection, local read-only capability probes, isolated OJVM
microbenchmarks performed by the orchestrator and cleaned up afterward, and
primary-source research. The research did not copy or translate JavaBox,
Mocha Doom, or id Software renderer code.

## Executive verdict

The current SQL pixel-row/GTT architecture cannot reach 30 FPS. The selected
moving frame is conservatively 7.84 seconds, while 30 FPS permits 33.3 ms: a
roughly 235x reduction is required. More decisively, the current final
`MATCH_RECOGNIZE` RLE stage alone is measured at 0.28 seconds, 8.4 times the
entire budget even if simulation, rendering, hashing, JSON, compression, ORDS,
networking, browser decode, and blitting were free. World sampling is about
4.03 seconds and selected masked sampling about 1.98 seconds. BSP pruning and
SQL plan work can improve those stages, but cannot rescue the mandatory
64,000-row materialization and RLE hot path by two orders of magnitude.

There is now one measured route in the right order of magnitude: a clean-room,
project-owned Java stored procedure running inside Oracle JVM (OJVM), reading
the authoritative relational data through the in-process server-side JDBC
driver, rendering into primitive arrays, and returning the exact existing
payload. Local disposable probes produced these 100-frame means:

| Isolated probe | Mean per frame |
| --- | ---: |
| Unique 64,000-byte Java array computation | 16.0 ms |
| Same result returned through a 64 KB `java.sql.Blob` | 29.7 ms |
| Coherent 320x200 palette generation + GZIP + temporary BLOB | 32.0 ms |
| Coherent generation + GZIP returned as `byte[]`/SQL `RAW` | 6.8 ms |

The last compressed probe was only 499 bytes and is not representative of the
current 92,658-byte compressed response. These numbers prove viability for a
realistic spike, not 30 FPS acceptance. They also show that temporary-BLOB
construction and transfer can consume nearly the complete budget and must be
designed explicitly.

The local database is Oracle AI Database 26ai Free 23.26.2 with OJVM version
23.26.2, embedded JDK 11.0.31, `Java=TRUE`, valid `DBMS_JAVA`, `loadjava`
installed, and `java_jit_enabled=TRUE`. However, `/dev/shm` is currently mounted
`rw,nosuid,nodev,noexec` and is only 64 MB. Oracle requires OJVM JIT shared
memory to be mounted read/write and executable, without `noexec` or `nosuid`.
Therefore the existing microbenchmarks may not represent native JIT performance;
JIT eligibility must be repaired and proved before extrapolating them.

An OJVM production renderer conflicts with the current charter. In particular,
PLAN Sections 0.1, 0.3, 1.6, 2.3, and P12.0 require SQL/set-based rendering,
forbid Java stored procedures in the render path, and require production
`MATCH_RECOGNIZE` RLE. Section 0.4 requires an explicit human charter amendment;
the performance requirement cannot silently override those clauses. The narrow
amendment recommended below preserves Oracle/database ownership, relational
state and assets, the exact decompressed payload and frame/state hashes, SQL
simulation, AutoREST, and the SQL renderer as an independent oracle. It changes
only which in-database execution language owns the production render and codec
hot path.

## Why OJVM changes the feasibility class

Oracle documents that OJVM runs in the database process and address space. Its
server-side internal JDBC driver reaches SQL through an in-process function
call, not an Oracle Net round trip, and all reads participate in the calling
database session and transaction. A Java call specification has minimal dispatch
overhead. OJVM JIT can compile hot methods to native machine code and persist
compiled methods across calls, sessions, and instances.

That permits the renderer to replace millions of SQL row-source operations and
multiple 64,000-row GTT writes with:

1. a few bounded relational snapshot queries;
2. primitive structure-of-arrays geometry and asset caches;
3. approximately 658,000 simple ray/seg intersection tests at 320 columns x
   2,057 E1M1 segs, plus 64,000 direct palette samples;
4. one reusable 64,000-byte indexed framebuffer;
5. one in-memory exact RLE/JSON/hash/GZIP pass; and
6. one bounded payload handoff to the already-required AutoREST BLOB.

The first renderer should reproduce the current project-owned analytic SQL
algorithm, not implement Doom's renderer. Brute iteration over 2,057 compact
seg records is inexpensive in compiled Java and has much lower exactness risk
than immediately replacing the reviewed visibility semantics with a different
BSP walk. BSP/front-to-back occlusion is the second implementation only if the
analytic array renderer lacks headroom or when 640x400 is activated.

Oracle Free remains limited to two CPU cores and 2 GB RAM. This makes a compact
single-threaded primitive-array renderer preferable to parallel workers and
object graphs. The current database contains 3,040,239 flattened asset pixels,
566 assets, 2,057 segs, and about 280 live mobjs. Packed indices plus opacity,
geometry, rays, colormaps, and lookup metadata should fit in roughly 5-12 MB of
per-session Java cache rather than millions of Java row objects.

Primary Oracle sources:

- [Server-Side Internal JDBC Driver](https://docs.oracle.com/en/database/oracle/oracle-database/23/jjdbc/server-side-internal-driver.html)
- [Stored procedure run-time contexts and call specifications](https://docs.oracle.com/en/database/oracle/oracle-database/26/jjdev/stored-procedures-runtime-contexts.html)
- [OJVM JIT compiler and `/dev/shm` requirements](https://docs.oracle.com/en/database/oracle/oracle-database/26/jjdev/Oracle-JVM-JIT.html)
- [Java database-session state and session-private static fields](https://docs.oracle.com/en/database/oracle/oracle-database/26/jjdev/Java-application-database-session.html)
- [OJVM memory usage](https://docs.oracle.com/en/database/oracle/oracle-database/26/jjdev/about-Java-memory-usage.html)
- [Oracle AI Database Free two-core/2-GB restrictions](https://docs.oracle.com/en/database/oracle/oracle-database/26/xeinl/licensing-restrictions.html)

## JavaBox findings and clean-room boundary

JavaBox is useful feasibility evidence, but not reusable renderer source. At
commit `8241259df9d0a52b2a4e5a49b2133b90bc44e7bd`, its README reports Mocha Doom
running at approximately 30 FPS under an OpenJDK 21 Zero interpreter compiled to
WebAssembly. Its canvas adapter does not make rendering fast: it merely caps
publication at 33 ms, obtains the existing `DataBufferInt` without a Graphics2D
copy, and copies the packed framebuffer into shared WASM memory. Its included
Mocha Doom renderer uses the expected front-to-back BSP, screen-column solid
occlusion, wall-column drawing, floor/ceiling spans, cached texture columns, and
persistent arrays. The 33 ms limiter is a ceiling, not proof of uncapped p95.

Relevant user-repository sources:

- [JavaBox repository and architecture](https://github.com/bmarti44/javabox/tree/8241259df9d0a52b2a4e5a49b2133b90bc44e7bd)
- [CanvasRenderer packed-buffer publication and 33 ms cap](https://github.com/bmarti44/javabox/blob/8241259df9d0a52b2a4e5a49b2133b90bc44e7bd/container/doom/adapter/CanvasRenderer.java)
- [JavaBox's included renderer orchestration](https://github.com/bmarti44/javabox/blob/8241259df9d0a52b2a4e5a49b2133b90bc44e7bd/container/doom/src/rr/RendererState.java)

The included Mocha Doom tree is GPLv3-derived, and the original id Software Doom
release is GPLv2. The current DoomDB charter independently forbids copied,
translated, mechanically generated, or embedded Doom-engine implementation and
control flow regardless of whether GPL compliance could otherwise be arranged.
No JavaBox/Mocha/id source, tables, constants, arrays, or translated methods may
enter DoomDB. The OJVM renderer must be authored from DoomDB's existing
project-owned SQL equations, public WAD-format facts, hand calculations, and
approved goldens. JavaBox and the id repository may support architectural
choices only. The original id repository independently confirms the high-level
column/span/BSP organization:

- [id Software Doom source release](https://github.com/id-Software/DOOM)
- [Original BSP renderer source](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_bsp.c)
- [Original column/span drawing source](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_draw.c)
- [Original plane-span source](https://github.com/id-Software/DOOM/blob/master/linuxdoom-1.10/r_plane.c)

## Required narrow charter amendment

Before production integration, obtain explicit approval for all of these exact
changes and no broader delegation:

1. Permit a project-owned Java 11 stored procedure inside OJVM to perform
   visibility, projection, palette sampling, masked composition, presentation,
   frame hashing, RLE encoding, canonical JSON generation, and GZIP for the
   production frame response.
2. Keep SQL/PLSQL authoritative for simulation, transactions, state hashes,
   state/history/save/replay data, and all relational game and asset facts.
3. Require Java to bulk-read those facts from the same Oracle transaction via
   server-side internal JDBC. It may cache only immutable, revision-keyed
   relational derivations; it may not embed a WAD, engine-definition data, a
   second simulation, evaluator data, or expected outputs.
4. Preserve the exact 320x200 palette frame, frame/state hashes, decompressed
   JSON schema and values, AutoREST surface, audio semantics, and browser role.
5. Move `MATCH_RECOGNIZE` RLE out of the production 33 ms path but retain it as
   the mandatory independent SQL oracle for every reviewed/golden frame and a
   substantial generated moving-frame corpus. Java RLE must match it exactly.
6. Retain the canonical SQL renderer byte-locked as an independent correctness
   oracle. Java is selected only after byte-for-byte equality and all T5-T7
   correctness/mutation gates pass.
7. Explicitly prohibit copying or translating JavaBox, Mocha Doom, id Doom, or
   any other engine into the Java implementation.

The measured 280 ms RLE stage is the specific proof that item 5 must change to
meet 33.3 ms. Keeping production `MATCH_RECOGNIZE` while claiming 30 FPS is not
a credible option.

## Prioritized implementation architecture

### 1. Establish a valid JIT baseline

The Compose database service should override Docker's default shared-memory
mount with an executable, suid-capable tmpfs, for example:

```yaml
services:
  db:
    tmpfs:
      - /dev/shm:rw,exec,suid,size=256m,mode=1777
```

`shm_size` alone is insufficient because it ordinarily retains `noexec` and
`nosuid`. Validate the rendered Compose configuration first. Recreate only the
database container while preserving the named database volume. After startup:

- `findmnt`/`mount` must show `rw,exec,suid` for `/dev/shm`, with neither
  `noexec` nor `nosuid`;
- `java_jit_enabled` must be `TRUE`;
- `DBMS_JAVA.COMPILE_CLASS` on the disposable probe and later production
  renderer must return a positive compiled-method count;
- corresponding `USER_JAVA_METHODS.IS_COMPILED` rows must be `YES`;
- database health and zero-invalid-object checks must pass; and
- the four microbenchmarks above must be repeated cold, interpreted if safely
  controllable, JIT-warmed, and after database restart.

Compile checked-in Java with `--release 11`; the local embedded OJVM is JDK
11.0.31 even though the database product is 26ai. Load and resolve at bootstrap,
and synchronously compile the hot classes before acceptance measurement.
Oracle documents `loadjava -resolve` and schema-object resolution here:
[OJVM schema object compilation](https://docs.oracle.com/en/database/oracle/oracle-database/26/jjdev/schema-objects-compilation.html).

### 2. Run a representative kernel and handoff spike before full implementation

The next disposable Java probe must not use a trivially coherent 499-byte
output. It must execute the approximate real work shape:

- 320 x 2,057 determinant/intersection calculations over primitive arrays;
- bounded stable hit ordering with the production `(t, linedef, seg, facing)`
  tie keys;
- 64,000 indexed texture/colormap lookups with realistic locality;
- masked writes and sparse HUD overlays;
- SHA-256;
- approximately 45,000 color runs and canonical JSON comparable to the current
  response; and
- GZIP output near the current 92,658-byte payload, plus incompressible and
  worst-corpus cases.

Compare two payload handoffs:

1. Preferred: PL/SQL creates the temporary output BLOB, passes the initialized
   locator into Java, and Java writes into that locator with `Blob.setBytes` or
   `setBinaryStream`. This tests whether the measured 23 ms RAW-versus-BLOB
   difference was mostly Java-side locator creation.
2. Fallback: Java returns eight fixed `RAW(32767)` OUT chunks and a total length;
   bounded PL/SQL uses `DBMS_LOB.WRITEAPPEND` to assemble the AutoREST BLOB.
   Eight chunks cover 262,136 bytes. First measure the actual maximum compressed
   payload over the full frame corpus; increase the fixed bound if necessary.

Oracle recommends the standard `java.sql.Blob` interface and documents BLOB
mutation here: [Oracle JDBC BLOB API](https://docs.oracle.com/en/database/oracle/oracle-database/26/jajdb/oracle/sql/BLOB.html).
Java OUT parameters map to one-element Java arrays; SQL `RAW` is compatible with
`byte[]`: [call-spec parameter modes and mappings](https://docs.oracle.com/en/database/oracle/oracle-database/18/jjdev/defining-call-specifications.html).

Kill this route early if, after verified JIT warmup, the realistic kernel plus
chosen payload handoff exceeds 20 ms p95 in a persistent SQL session. A target
of 15 ms p95 is preferable because simulation and ORDS still need budget.

### 3. Add relational packed immutable inputs

Do not fetch 3,040,239 `AT` rows through JDBC on every new pooled session. Add a
bootstrap-derived relational pack, generated only from reviewed relational
assets, such as:

```text
DOOM_RENDER_ASSET_PACK(
  renderer_revision, asset_id, width, height,
  palette_pixels_blob, opacity_bits_blob, content_sha256
)
```

Keep geometry, sector, sidedef, animation, ray, sprite-metric, and colormap
sources relational. Java loads them into primitive arrays on the first render
in each database session. Cache structure-of-arrays, not per-row objects. Key
every cache by WAD SHA, renderer/profile revision, and packed-table digest; a
mismatch forces a reload. Do not serialize a WAD or third-party engine into the
JAR.

OJVM static fields are private to a database session and persist across calls in
that session. ORDS can use multiple pooled sessions, so each session must warm
its own immutable cache. Keep the local ORDS pool small enough for the two-core,
2-GB target, prewarm every configured pooled connection, and verify cache
persistence through actual consecutive AutoREST calls. Oracle documents ORDS
pool minimum/maximum settings here: [ORDS pool configuration](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.1/ordig/about-REST-configuration-files.html).

### 4. Implement the exact analytic array renderer first

Use the existing SQL renderer as the specification and oracle:

- read preseeded 64-orientation ray values rather than recomputing trigonometry;
- use Java `double` only where the SQL contract uses `BINARY_DOUBLE`, retain
  exact integer/decimal inputs where tie boundaries require them, and test every
  boundary;
- scan compact seg arrays per column, apply the exact determinant/t/u predicates,
  and stable-sort accepted hits using all canonical tie keys;
- reproduce the portal walk, sector intervals, clip windows, wall/floor/ceiling/
  sky sampling, light/colormap selection, masked walls, sprites, weapon, HUD,
  menu, automap, pause, intermission, and death presentation;
- write directly to one reusable palette-index framebuffer, with no per-frame
  Java object allocation in pixel loops and no frame GTTs;
- use separate reusable scratch arrays per column for hits/windows; and
- return only after exact frame bytes, frame SHA, RLE, audio JSON, canonical JSON,
  and GZIP are complete.

The live snapshot should use a bounded number of prepared, set-based queries for
the player/session, 182 live sector values, line/switch state, approximately 280
mobjs, and presentation/audio state. The internal JDBC connection is the same
transaction and can see the simulation writes before commit. Close statements
and result sets at each call as Oracle recommends; cache immutable data arrays,
not open JDBC resources.

### 5. Optimize with BSP/columns/spans only after exact analytic parity

If the clean analytic renderer misses the budget or 640x400 needs headroom, add
independently authored versions of these architectural reductions, each behind
byte-for-byte differential tests:

1. front-to-back traversal of the ingested WAD BSP;
2. node-child bounding-box rejection;
3. screen-column solid occlusion ranges so a covered subtree is skipped;
4. projected wall columns with cached source texture columns;
5. floor/ceiling plane boundary accumulation followed by horizontal spans;
6. primitive sprite fragments clipped against wall column bounds; and
7. persistent, profile-keyed framebuffer and scratch arrays.

These ideas are supported by JavaBox and the original renderer sources, but the
implementation must be derived from DoomDB's equations and fixtures. Do not port
their control flow. Avoid Java parallel rendering initially: Oracle Free has two
cores, database/ORDS work needs one of them, and OJVM thread scheduling adds
p95/GC risk. Parallelism is a later isolated experiment only.

## Render-free simulation gate

Renderer replacement alone is insufficient unless SQL simulation and state
history fit the remaining budget. The current public four-tic timing is up to
about 0.46 seconds above a one-turn frame, but pose/run variance makes that an
invalid per-tic estimate. Before full renderer work, measure
`DOOM_TIC_TX.APPLY_BATCH`, state-document/hash construction, history capture,
and response-cache bookkeeping with rendering bypassed on a throwaway session.

After a 30-call warmup, capture at least 270 unique one-tic samples for:

- turn only;
- forward/strafe collision;
- sector motion and switches;
- ordinary monster advancement;
- monster-heavy combat/projectiles/damage/pickups; and
- history/replay capture boundaries.

Report per-stage CPU, elapsed, reads, writes, and p50/p95. The preferred
render-free simulation/state target is at most 8-10 ms p95, leaving approximately
20 ms for OJVM render/payload and 3-5 ms for local ORDS/browser overhead. The
logical 35 Hz simulation also has an independent 28.6 ms/tic deadline. If
ordinary SQL simulation exceeds 10 ms p95, optimize it before integrating the
renderer. If it cannot fit, disclose a second charter conflict rather than hide
it with multi-tic batching, cached frames, interpolation, or repeated display
frames.

## Exactness, security, and deployment gates

### Correctness

- Build a corpus of at least 300 unique SQL-canonical frames spanning every
  approved mode, animation phase, moving sector, sprite rotation/occlusion,
  lighting band, weapon/HUD state, and reviewed boundary case.
- Require byte-for-byte 64,000-byte equality, identical frame/state SHA-256,
  identical RLE tuples, identical decompressed JSON values/order, audio events,
  and completion flags for every corpus frame.
- Run SQL `MATCH_RECOGNIZE` against every corpus framebuffer and compare every
  Java run tuple.
- Pass the complete T5-T7 correctness, held-back, PNG, browser, audio, and
  mutation suites with the canonical SQL renderer still independently callable.
- Mutate every cache-key dependency and prove reload/no-stale-frame behavior.
- Test two concurrent game sessions and pooled database-session reuse; static
  Java state must never leak player/session data. Only immutable arrays may be
  shared across calls in one session.

### Security and provenance

- Load only checked-in, reproducibly built Java 11 classes/JARs and record their
  SHA-256/JAR digest. Resolve at bootstrap and reject invalid Java schema objects.
- Grant no file, socket, process, reflection-bypass, or native-library permission.
  OJVM code needs only same-session internal JDBC and BLOB access.
- Preserve definer/invoker boundaries and existing AutoREST exposure; Java has
  no direct public endpoint.
- Audit source mechanically for JavaBox/Mocha/id package names, copied constants,
  state tables, translated method structure, vendored engines, WAD bytes, and
  evaluator/golden access.
- Keep secrets outside source and preserve the existing ignore/secret audit.

### Local and Autonomous deployment

Autonomous AI Database now officially supports OJVM. It must be enabled with
`DBMS_CLOUD_ADMIN.ENABLE_FEATURE(feature_name => 'JAVAVM')`, followed by a
database restart. Client-side `loadjava` is supported; server-side filesystem
loading is not, and loaded Java cannot invoke OS or network calls. Those
restrictions are compatible with this design. Probe the actual target before
selection and repeat exactness/performance there:
[Use Oracle Java on Autonomous AI Database](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/autonomous-oracle-java.html).

Cloud network RTT can exceed 33.3 ms even when the database is instant. Report
local database, local end-to-end, Autonomous database, and remote end-to-end
latency separately. Do not call a cloud session 30 FPS if geography/network
p95 alone exceeds the limit.

## Performance acceptance matrix

All numbers are external wall-clock p50 and p95 after a 30-frame warmup; internal
timers are diagnostic only. Use at least 270 unique moving frames with exact
render caches cold.

| Gate | Required result |
| --- | --- |
| Verified-JIT realistic kernel + payload handoff | <=20 ms p95; <=15 ms preferred |
| Render-free one-tic SQL simulation/state/history | <=10 ms p95; <=8 ms preferred |
| Complete database transaction through output BLOB | <=25 ms p50 and p95, with <=20 ms preferred |
| Local AutoREST response received and decoded | <=33.3 ms p50 and p95 |
| Browser input-to-new-canonical-frame presentation | <=33.3 ms p50 and p95 |
| Unique sample count | >=270 after 30 warmup frames |
| Correctness | Every byte/hash/RLE/schema/T5-T7/mutation gate green |
| Cache accounting | Exact-cache hits reported separately and excluded |

Include turn, translation, collision, sector motion, ordinary actors,
monster-heavy combat, weapon fire, pickups, pause/menu/automap, save/load, and
replay in separate distributions. Record GC, Java-session cache warm/cold state,
JIT compilation state, ORDS pooled session identity, payload bytes, database
CPU, and Free memory pressure for every outlier class.

## 640x400 design

Make width, height, center, projection, ray table, clip bounds, framebuffer,
scratch arrays, packed-output limits, and cache keys profile-driven from the
first Java spike. At 640x400:

- analytic ray/seg work scales about 2x with width;
- pixel sampling, composition, hashing, and raw bytes scale about 4x;
- RLE/JSON/GZIP can scale 2-4x depending on texture entropy; and
- a renderer that merely reaches 33 ms at 320x200 will likely miss badly.

The 320x200 implementation should therefore target approximately 15-20 ms
end-to-end, not 33 ms, and the renderer-only pixel/codec slice should seek
sub-8-ms p95 if 30 FPS at 640x400 is eventually required. BSP rejection removes
resolution-independent geometry work; column/span rasterization and a future
packed-frame transport amendment address the 4x pixel/JSON cost. Do not claim
640x400 performance from the 320x200 result, and do not reduce effects or
resolution to pass either gate.

## Ranked recommendation

1. **Approve the narrow OJVM/MATCH_RECOGNIZE charter amendment.** Without it,
   the measured mandatory RLE stage alone makes 30 FPS impossible.
2. **Fix and verify OJVM JIT shared memory, then run the realistic kernel and
   locator-vs-RAW handoff spike.** This is the fastest falsifiable test of the
   only route currently in the correct performance class.
3. **Run the render-free simulation gate in parallel with the spike.** Do not
   spend weeks on a renderer if SQL simulation already consumes the budget.
4. **Implement a clean-room analytic primitive-array renderer from DoomDB's SQL
   contracts and use caller-created BLOB output if it wins.** Keep all state and
   immutable inputs relational and revision-keyed.
5. **Move exact RLE/JSON/hash/GZIP into the same Java call, while retaining SQL
   renderer and `MATCH_RECOGNIZE` as mandatory differential oracles.** Multiple
   SQL pixel/GTT/post-processing stages cannot remain in the hot path.
6. **Only then add independent BSP/solid-column/plane-span acceleration for
   extra headroom and 640x400.** JavaBox supports these architectural choices,
   but its code and data remain off limits.
7. **Accept only the external 270-frame p50/p95 gate.** A synthetic microprobe,
   average, cache hit, limiter, repeated frame, batch-final frame, or marketing
   estimate is not 30 FPS.

Packed SQL spans remain a useful fallback experiment if the charter amendment
is denied, but there is no credible evidence that they can remove the measured
235x end-to-end gap while retaining the production 64,000-row
`MATCH_RECOGNIZE` contract. MLE, `UTL_TCP`, ORDS tuning, DOP 2, result caching,
and network changes are not substitutes for the OJVM architecture: none removes
the current per-pixel relational and post-processing work.
