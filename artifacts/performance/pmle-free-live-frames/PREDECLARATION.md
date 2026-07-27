# Always Free live database-frame path — predeclaration

Date: 2026-07-26
Venue: Oracle Autonomous Database 26ai Always Free
Goal: database-generated live pixels at least 30 browser-observed unique
moving FPS; the client is limited to framebuffer decode/copy/presentation.

## Frozen budget

- Browser cadence: `p95 <= 33.333 ms`, sustained.
- Current authority step p95: `10.022 ms`.
- Current two-RAW egress p95: `9.287 ms`.
- Current bounded publication p95: `2.694 ms`.
- Complete same-call raster allowance at 30 FPS: `11.330 ms`.
- The current generated exact raster is `207.488 ms p95`; that artifact shape
  is rejected, but it does not close a specialized live renderer.
- DVR persistence and compression are outside this goal.

## Real workload, not a synthetic projection

`probes/mle/run-real-draw-metrics.sh` expands and SHA-verifies the accepted
`live-dm-2026-07-23` 5,250-tic fixture, installs the canonical table pack, and
executes the actual Mocha indexed draw functions over real Freedoom E1M1.
The diagnostic Java process is workload instrumentation only and never enters
the production database path.

The first canonical-stream result is:

- 1,058 columns and 447 spans per frame on average (1,505 commands);
- 2,325 commands at the observed maximum;
- 56,615 drawn pixels per frame on average and 77,869 maximum, including
  overdraw;
- 17 distinct colormap arrays per frame on average and 29 maximum;
- 581 distinct source arrays per frame on average and 890 maximum.

These numbers supersede the production-cardinality synthetic tape as the input
to native-bulk costing.

## Native cardinality floor

`benchmark-oci-free-native-raster-cardinality.sql` measures three components
at both average and peak real cardinality:

1. `UTL_RAW.TRANSLITERATE` with the observed number of LUT groups;
2. optimistic native RAW substring/overlay scatter with the observed command
   and pixel counts;
3. both operations combined.

The scatter cell is deliberately optimistic: vertical column scatter and
visibility/tape generation are not yet included. Therefore:

- `combined_peak p95 >= 11.330 ms` rejects this native compositor route;
- `combined_peak p95 <= 6.000 ms` promotes capture and execution of the exact
  real draw tape;
- between `6.000` and `11.330 ms`, promotion requires a separately measured
  visibility/tape stage that keeps the complete raster at or below
  `11.330 ms p95`;
- no synthetic or component result can itself pass the release gate.

The final gate remains a deployed Always Free browser session producing real
moving/firing database frames at 30 FPS or better with bounded backlog.

## Specialized 160x100 BLOCKMAP renderer cell

The first promoted architecture after native-scatter rejection is an
allocation-free MLE JavaScript renderer at 160x100 indexed pixels, nearest-
neighbor scaled by the client. Its diagnostic input is the accepted route's
5,250 actual player poses plus the checked-in E1M1 BLOCKMAP and linedefs.
The initial cell deliberately renders flat walls/floor/ceiling so it isolates
visibility plus framebuffer authorship before texture, sprite, weapon, and HUD
work.

Predeclared interpretation:

- raster-only `p95 <= 8.000 ms` promotes the layout to presentation-layer
  implementation;
- `p95 >= 15.000 ms` rejects this BLOCKMAP ray layout before feature work;
- between those bounds requires profiling and one measured optimization;
- this component cell cannot pass the release gate. The complete deployed
  authority + raster + ORDS + browser pipeline must still sustain at least
  30 unique moving FPS.

## Full-resolution layout cell

The promoted layout is rerun at the final 320x200 indexed resolution before
presentation features land. This cell still uses flat walls/floor/ceiling, so
it isolates the full-resolution visibility and framebuffer floor.

- `p95 <= 11.330 ms` preserves the complete current raster allowance and
  promotes full-resolution portal/texture work;
- `p95 > 11.330 ms` requires recovering budget from authority/egress or
  changing the visibility layout before presentation features;
- no reduced-resolution result is acceptable as the finished product.

## Authentic wall-texture cell

The next cell keeps full 320x200 visibility and samples the installed,
SHA-fenced Freedoom `wall_texture` renderer pack for every wall pixel. Lighting
uses the canonical 32x256 colormap pack and the intersected sector light
level. Portals are still treated as solid in this isolated cost cell.

- `p95 <= 11.330 ms` promotes portal-aware upper/lower/middle wall bands and
  textured flats;
- `p95 > 11.330 ms` triggers texture-column precomputation/caching before more
  layers;
- authentic assets are mandatory; flat-color output cannot ship.

## Cached authentic column cell

The authentic wall cell showed that repeated interpreted texture/colormap
gathers, not visibility, dominate. The next cell caches complete scaled and
lit 200-byte columns in the database and uses native `TypedArray.set` into a
column-major indexed framebuffer. Column-major is a transport layout only:
the database has already selected every final palette index; the client may
transpose it while decoding to canvas.

- `p95 <= 11.330 ms` promotes the cache architecture to portal bands;
- cache hit/miss counts are mandatory in the evidence;
- sustained performance must include route changes, not a static warmed view.

## Portal-correct authentic wall cell

The next cell replaces the solid-linedef approximation with Doom's sidedef
model.  The pack contains both sides' upper/lower/middle textures and offsets,
front/back sectors, sector floor/ceiling/light values, the captured player
view height, and the original linedef flags.  Each ray continues through
two-sided openings while clipping subsequent upper and lower wall bands.
One-sided middle walls remain opaque.  Output remains database-authored
320x200 column-major indexed pixels using the real Freedoom wall pack.

- `p95 <= 11.330 ms` promotes this portal layout to flat, sprite, weapon, and
  HUD integration;
- `p95 > 11.330 ms` does not authorize a fidelity reduction: profile portal
  traversal and recover boundary budget before adding layers;
- the cell must report portal/solid hit counts and maximum portal depth, and
  a zero-portal result invalidates the measurement;
- static sector heights are diagnostic input only.  Shipping frames must bind
  the same renderer to authoritative per-tic sector heights and presentation
  state.

## Front-to-back BSP portal cell

The first portal cell proved correctness-shaped traversal but raised line
intersection work from roughly 2,414 to 8,390 tests per sampled frame because
each ray independently walked every visible portal.  The next cell consumes
the checked-in E1M1 NODES/SSECTORS/SEGS tree front-to-back.  It projects each
visible seg to a screen interval and updates per-column upper/lower occlusion
clips.  This is the original Doom renderer's visibility shape: each seg is
classified once, while only covered screen columns perform an intersection
and cached native blit.

- `p95 <= 11.330 ms` promotes BSP visibility to the remaining presentation
  layers;
- `p95 > 11.330 ms` requires a measured stage decomposition or recovered
  authority/egress budget; it does not authorize solid portals;
- the rank must report visited seg/subsector counts, portal depth, cache
  behavior, and nonzero opaque coverage;
- this remains a component diagnostic, not the deployed 30 FPS gate.

The first BSP cell reduced line intersections but still walked 462 of 682
subsectors in the sampled frame.  The follow-up adds Doom-shaped back-child
bounding-box rejection after the front child has updated occlusion.  Its
verdict thresholds are unchanged, and it must report bbox checks/rejections
alongside the earlier BSP counters.

The bbox cell reduced visited subsectors to 70 but retained the same 1,870
portal-column operations.  The next cell applies Doom's empty-trigger-line
rejection before projection: a two-sided boundary with equal floor and ceiling
heights and no middle texture does not draw or alter vertical occlusion.
Skipped segs are counted.  Thresholds remain unchanged.

The empty-boundary cell still performed texture-coordinate and light setup for
portal columns that only changed occlusion and emitted no pixels.  The next
cell defers all texel-side setup until an upper/lower band actually intersects
the current clip.  Geometry and output are unchanged; the same thresholds and
counters apply.

The lazy-setup cell was neutral because every covered column still formed a
ray and divided for distance before determining whether any pixels would be
emitted. For a projected seg, the ray/segment denominator—and therefore the
projected wall height—is linear across screen X. The next cell advances that
denominator incrementally and reconstructs distance/ray values only for
columns that actually draw a cached wall band. Portal clipping retains the
same integer projected heights. The `11.330 ms` threshold is unchanged.

The incremental cell preserved every pass checksum and improved the final-two
worst p95 from `37.432` to `34.778 ms`. The next cell moves portal spans that
cannot emit an upper or lower texture band onto a clip-only inner loop. It
updates the same per-column opening bounds without entering the general wall
helper or forming texture coordinates. Clip-only column cardinality is
reported; thresholds remain unchanged.

## Same-window compilation discriminator

Route-shaped passes cover different geometry, so their non-monotonic timing
cannot establish whether the specialized module ever enters an optimized
execution tier. A diagnostic cell repeats poses 500–999 for six consecutive
500-frame passes without changing the module or pack. Pass-level p95 and
throughput are compared only against the identical window:

- at least 20% sustained improvement in both passes 5 and 6 versus pass 2 is
  a compilation signal and authorizes a longer plateau/compilation study;
- less than 10% improvement in both final passes classifies the default
  specialized renderer as compilation-inert on this venue;
- intermediate or unstable results require one longer identical-window cell;
- this is `DIAGNOSTIC_NOT_GATE` and does not alter any renderer acceptance
  threshold.

The six-pass cell landed between the predeclared bands: pass 2 p95 was
`29.997 ms`, while passes 5/6 were `26.363/25.952 ms` (12.1–13.5%).
The required longer cell repeats the identical window for 12 passes. The
median p95 of passes 9–12 is compared with pass 2: at least 20% is a useful
compilation signal; below 10% is inert; 10–20% is classified as minor
warmup/optimization that does not justify a compiler workstream because it
cannot close the current gap.

## TeaVM-generated specialized-visibility discriminator

The plain JavaScript plateau is compilation-inert.  A separate 17 KB TeaVM
0.15.0 `ADVANCED` artifact ports the same primitive-array BSP, bbox, empty-line,
incremental-height, and clip-only visibility kernel, but intentionally omits
texture-cache lookup and framebuffer blits.  It tests generated shape only and
cannot replace either production authority or renderer.

The identical poses 500–999 run for 12 passes:

- final-two p95 `<=5.000 ms` promotes a complete generated-renderer port,
  because it leaves room for the already-native cached blits;
- p95 `>=15.000 ms` rejects TeaVM generation as insufficient for this
  specialized renderer;
- between those values requires an Amdahl projection using the measured plain
  renderer's 1,893 geometry columns and 1,066 native cache blits before any
  full port;
- a pass checksum change relative to the identical prior pass increment,
  clock disagreement, or postflight failure invalidates the cell.

The geometry cell landed at `10.190 ms p95`, inside the Amdahl band. The next
candidate extends that exact generated source with the real 2,545,152-byte
wall asset pack, 18 prelit colormap banks, the same 262K scaled-segment cache,
native array copies into a retained 64,000-byte framebuffer, and the same
portal wall output as the plain module. It still excludes flats, sprites,
weapon, and HUD.

- full wall-raster p95 `<=11.330 ms` promotes the generated shape to remaining
  presentation layers;
- p95 `>=20.000 ms` rejects the full generated wall shape;
- between those values requires recovered egress/authority budget and a
  concurrent-pipeline measurement before more visual layers;
- the asset SHA fence, twelve identical-window pass checksums, two clocks, and
  postflight must all pass.

The full generated wall raster landed at `48.273 ms` final-two worst p95 and
is rejected. Its geometry remained fast, but TeaVM's emitted Java
`System.arraycopy`/array-cache shape did not preserve the native
`TypedArray.set` behavior of the plain JavaScript raster.

## Generated-command/native-raster hybrid

The next cell retains the generated BSP/portal geometry but emits a bounded,
ordered 24-byte command for every actual upper/lower/middle wall span. A
separate ordinary MLE module consumes that tape without a SQL crossing and
performs the previously proven prelit-cache lookup and native
`Uint8Array.set` framebuffer blit. The generated artifact remains
diagnostic-only and does not replace the deterministic authority.

Before timing, five actual E1M1 poses (`0`, `500`, `999`, `2500`, `5249`)
must produce identical 64,000-byte frames in the full generated reference and
hybrid arms. The command buffer must remain bounded and every decoded command
must pass its screen/texture/light/span validation.

- final-two worst p95 `<=11.330 ms` promotes the hybrid wall pipeline to the
  full-route measurement and remaining presentation layers;
- p95 `>=20.000 ms` rejects the hybrid wall pipeline;
- between those values requires a full 5,250-pose route measurement before
  another renderer decision;
- the same-window cell is component evidence only: it cannot claim 30 FPS
  until flats, sprites, weapon, HUD, authority step, and frame delivery are
  present in one deployed gate.

The hybrid produced exact frames but landed at `45.415 ms` final-two worst
p95. Its terminal frame carried 1,173 wall commands (1,133 cache hits and 40
misses), so the interpreted wrapper loop and cache calls erased the generated
geometry gain.

## Generated native-typed-array raster

The next cell keeps geometry and cache lookup inside the generated artifact,
but replaces Java `byte[]` frame/cache columns and `System.arraycopy` with
TeaVM JSO `Uint8Array` storage and its native `set(source, offset)` operation.
This is the direct combination not represented by either failed arm:
compiler-visible BSP/cache control plus the native bulk copy proven in the
plain module.

- the authentic wall pack, portal decisions, framebuffer size, sampled poses,
  twelve-pass window, and `11.330/20.000 ms` promotion/rejection thresholds
  are unchanged;
- a changed frame checksum, failed staging/postflight, or clock disagreement
  invalidates the cell;
- promotion remains only permission to add the missing presentation layers,
  never a complete-renderer or 30 FPS claim.

The native-typed-array generated cell improved pass-level throughput to
`34.8–36.4 FPS`, but final-two worst p95 remained `40.670 ms`. Native bulk
copy was not enough: roughly 1,100 short segment copies per frame still carry
too much call overhead.

## Generated direct-pixel raster

The next cell removes scaled-segment caching and short bulk-copy calls from
the generated raster. It writes the authentic prelit texel directly into a
Java primitive framebuffer in the compiled geometry loop. This exchanges
roughly 1,100 native-call boundaries for a bounded frame-sized primitive
gather/write loop—the workload shape on which the generated authority and
geometry artifacts obtained their venue compilation gain.

- it retains full 320x200 output, portal wall ordering, authentic textures,
  sector lighting, and the same pose stream;
- the twelve-pass output checksum must equal the preceding generated wall
  cells, otherwise the result is invalid regardless of speed;
- the `11.330/20.000 ms` component promotion/rejection thresholds and all
  staging, clock, and postflight rules remain unchanged.

The direct-pixel cell preserved the preceding cumulative frame checksum but
landed at `59.556 ms` final-two worst p95. It is rejected.

## Generated-cache/native-overlay composition

The next cell keeps visibility, texture-coordinate calculation, cache-key
selection, and miss generation in the generated module. Its ordered tape
contains a compact target/slot record for every wall span and carries texel
bytes only on cache misses. A session-persistent PL/SQL cache consumes the
tape in order and composes the two 32,000-byte framebuffer halves with
`UTL_RAW.OVERLAY`; this preserves collision/replacement ordering.

The measurement must include generated tape creation, MLE-to-PL/SQL tape
egress, real-tape parsing, cache updates, and both framebuffer halves. It must
report command count, miss count, tape bytes, and output identity against the
accepted generated frame.

- component p95 `<=20.000 ms` authorizes an integrated authority/ORDS frame
  request cell because it leaves a plausible deployed 33.333 ms envelope;
- component p95 `>=28.571 ms` rejects this final native composition shape;
- between those values requires the integrated request measurement before a
  decision;
- this replaces the earlier `11.330 ms` isolated-raster allowance only for
  the integrated pipeline decision: the release gate remains 30 unique moving
  FPS with complete presentation, not a component projection.

The native-overlay pipeline produced exact frames but landed at `54.634 ms`
final-two worst p95 and is rejected. Real-tape parsing made the native scatter
primitive slower than its synthetic command-cardinality projection.

## Rational-step generated raster

Profiling the direct-pixel source exposes a remaining generated-shape defect:
every wall texel executes floating-point `Math.floor`, modulo, and accumulation
even though Doom texture sampling is a rational fixed-step walk. The next cell
uses an exact integer numerator:

`source = (offset * wallHeight + screenDelta * 128) / wallHeight`

and increments the numerator by 128 for each output pixel. Power-of-two
texture heights use a mask. This preserves the same mathematical nearest
texel mapping without accumulated fixed-point approximation.

- the same authentic assets, 320x200 output, portal ordering, route window,
  checksums, clocks, and postflight apply;
- output must remain byte-identical to the preceding direct-pixel frame cell;
- `p95 <=20.000 ms` promotes a one-write-per-pixel viewport integration;
- `p95 >=28.571 ms` rejects direct generated sampling;
- between those values requires the one-write viewport cell before decision.

The rational-step cell improved sustained throughput to about `27.2 FPS`
(`44.804 ms` final-two worst p95), but it changed a small number of texel
boundary samples and remains over budget.

## One-write portal framebuffer

The next cell removes guaranteed overdraw. The earlier direct cells initialized
all 64,000 pixels, then overwrote every wall span. Front-to-back portal clips
already partition each column into written walls and one final opening. The
candidate writes wall pixels during traversal and fills only that final opening
afterward, so every framebuffer location is assigned exactly once.

- output checksum must match the rational-step cell exactly;
- the rank reports final-frame pixel-write count and it must equal 64,000;
- `p95 <=20.000 ms` promotes viewport flat/sprite integration;
- `p95 >=28.571 ms` rejects the one-write direct raster;
- between those values requires the 168-line viewport plus status-bar
  integration before a decision.

The corrected one-write implementation retained the rational-step checksum but
reported 64,236 writes and measured `37.401/49.479 ms p50/p95` on its first
pass.  The exact-write-count gate stopped the cell.  Since it was already
slower than the rational baseline and the 236 excess writes are only 0.37% of
a frame, this shape is rejected rather than weakening the invariant.

## Small generated real-command raster module

The next cell separates rasterization from the integrated BSP artifact.  A
small TeaVM 0.15.0 module consumes wall-span commands captured from the
accepted 5,250-pose E1M1 route and samples the same prelit wall atlas into a
320x200 column-major framebuffer.  The command distribution, span lengths,
texture coordinates, scale, vertical offset, and light banks come from real
generated geometry; this is not a uniform synthetic pixel loop.

This discriminator asks whether the raster can enter the compiled tier when
its generated module and hot method are small.  Before timing:

- decoded commands and authentic wall data must reproduce the corresponding
  integrated renderer checksum for every captured validation pose;
- the evidence records source, command-pack, wall-pack, generated-artifact,
  and TeaVM input hashes;
- twelve 500-frame passes run on the same Always Free OCI venue with the
  existing two-clock, exclusion-cap, pool-park/restore, and postflight rules.

Verdict:

- final-two worst raster p95 `<=8.000 ms` promotes a split generated
  geometry/raster integration, because a real frame-sized compiled pass then
  leaves credible room for flats, sprites, HUD, boundary, and ORDS delivery;
- p95 `>=20.000 ms` closes this generated-raster compilation shape;
- between requires one integrated 320x168 viewport cell before a decision.

This is a component discriminator only.  It cannot establish the 30 FPS
release claim without the complete Doom presentation layers and deployed
unique-moving-frame gate.

The per-call cell passed full-frame identity but measured `31.998 ms` final-two
worst p95 and `36.5–37.0 FPS` sustained throughput.  It closes the hypothesis
that module size alone makes each call enter a much faster tier.

One production-shape discriminator remains before rejecting the split.  The
shipping authority executes many tics inside a long retained MLE invocation;
the per-frame call-spec rank returns to PL/SQL after every frame.  The small
module therefore adds a 500-frame `renderBatch` export and measures twelve
long invocations over the same real-command stream.

- the checksum of each batch must equal the sum produced by the accepted
  per-frame cell;
- the rank reports amortized wall and `GET_TIME` milliseconds per frame;
- amortized final-two worst `<=8.000 ms/frame` promotes integration in the
  retained worker; `>=20.000 ms/frame` closes long-invocation compilation;
  between requires an integrated retained-worker frame cadence cell.

Batching is only a tier discriminator.  It may not justify delivering frames
in 500-frame bursts; any promoted implementation still has to publish and
present unique frames at the live cadence.

## Pixel-complete framebuffer tape

The small-module result closes server-side framebuffer materialization, not
database pixel authorship.  The existing generated cache already emits an
ordered tape whose miss payloads are literal prelit pixels and whose hits
reference retained literal blocks.  Target offsets, lengths, replacement
order, background palette indices, and every literal value are selected by
the database.  A client decoder performs only deterministic decompression and
copy; it receives no geometry, texture atlas, world state, lighting rule, or
rendering decision.

The next cell isolates generation plus full MLE-to-SQL egress of that encoded
frame over the real 500-pose route.  The previously accepted native-overlay
equivalence proves that decoding the tape yields the same 64,000-byte wall
frame; the cell repeats full-frame comparisons at three poses before timing.
It reports per-frame tape bytes, command count, misses, and wall time.  Cache
state is reset before pass one, so its p95 represents a previously unseen
moving route rather than a replay-warmed dictionary.

- first-pass p95 `<=20.000 ms` promotes expansion into a pixel-complete
  viewport codec (flats, sprites, weapon, and HUD), because generation and
  transport retain credible 30 FPS room;
- first-pass p95 `>=28.571 ms` closes this encoded-frame route;
- between requires a 320x168 viewport plus status-bar prototype before a
  decision.

The final release gate remains decoded 320x200 unique moving frames at
`>=30 FPS` from deployed ORDS.  The codec is a framebuffer transport, not
permission to move rendering or simulation decisions into the browser.

The literal-tape cell passed exact decoding but measured `43.670 ms` cold-route
p95 and is rejected.  Its replay-warm throughput (`40.1–40.6 FPS`) is not
evidence for arbitrary player movement.

## Native Blob ordered composition

Oracle 26ai documents a native Web `Blob` implementation in MLE, and a live
probe proved that an async MLE call specification awaits `Blob.arrayBuffer()`
and returns the exact bytes.  The next candidate changes composition, not
authorship: generated geometry still creates/cache-selects every authentic
prelit pixel span.  The wrapper orders the non-overlapping spans by final
column position, inserts database-selected background pixels for gaps, and
passes those already-rendered byte views to native `Blob` concatenation.

- three complete 64,000-byte frames must equal the generated reference;
- overlap, dictionary desynchronization, a non-64,000-byte Blob, or a
  temporary-LOB cleanup failure invalidates the cell;
- cache is reset before the 500-frame first pass;
- cold-route p95 `<=20.000 ms` promotes the native-Blob viewport codec,
  `>=28.571 ms` rejects it, and the interval requires the actual 168-line
  viewport/status-bar integration.

The measured call includes geometry, literal generation/cache lookup, span
ordering, Blob materialization, conversion to SQL BLOB, and caller-visible
BLOB length/cleanup.  It remains a wall-frame component, not a complete
presentation or release claim.

The Blob candidate passed all exactness prerequisites but measured
`95.056 ms` cold-route p95 and was rejected.

## Compiled framebuffer and atlas layout

The small compiled raster still cleared the framebuffer with a 64,000-pixel
nested loop and sampled a row-major atlas with a multiply and strided read per
wall pixel.  Two exact layout cells therefore follow:

1. initialize a retained 64 KB background framebuffer once and reset each
   candidate frame with one TeaVM `System.arraycopy`;
2. transpose referenced authentic prelit texture columns during retained
   initialization and rewrite command bases, so the selected texels are
   contiguous without changing any output palette index.

Each cell repeats the three complete framebuffer comparisons.  The rank
remains twelve 500-frame per-call passes plus twelve 500-frame retained-batch
passes on OCI.  These are component measurements; promotion means proceeding
to a full command-capture integration, not declaring release.

The full integration gate is predeclared as:

- moving and firing E1M1 input, with real Mocha column, span, masked-sprite,
  weapon, status/HUD, and patch-command cardinality;
- every candidate 320x200 frame is authored in the database; the browser may
  only decode/copy palette indices and scale the completed framebuffer;
- database renderer generation, raster, publication, ORDS retrieval, and
  browser presentation are all inside the measured pipeline;
- `>=30` unique moving presented FPS and frame cadence p95 `<=33.333 ms`;
- title/loading/menu/options, automap, pause, intermission, finale, save/load,
  solo, and multiplayer presentation remain required before the product claim
  can be made.

No static pose pack, wall-only frame, replay-warmed dictionary, or reduced
resolution may satisfy that integration gate.

## Authentic full-command viewport raster

The diagnostic presentation root now delegates through transparent command
recorders at Mocha's actual indexed draw-function boundary.  Across 192
moving/firing E1M1 player frames, the captured stream contains the original
invocation order for wall columns, visplane spans, masked sprites, and player
weapon columns, plus the authentic prelit Freedoom source bytes.  Pack version
3 binds both the complete 320x200 reference SHA-256 and the 320x168 viewport
SHA-256 for every frame.

Before OCI timing counts:

- the compact TeaVM raster must reproduce all 192 viewport digests in Node;
- OCI must reproduce three distributed viewport digests after database-side
  pack staging and SHA verification;
- any fuzz command is fail-closed until the separately tested fuzz path
  exists; this route contains no sky, fuzz, or translated-column coverage;
- the status bar and patch-based screens are explicitly not included.

The OCI cell measures twelve 192-frame per-call passes and twelve retained
batch passes.  The final-two worst per-call p95 and amortized batch cost are
classified as follows:

- both `<=20.000 ms` promotes integration of the authentic 320x168 viewport;
- either `>30.000 ms` rejects this compact command-raster shape;
- otherwise optimize the measured raster before integration.

Promotion is not the product claim.  It means the real world/sprite/weapon
pixel workload has enough component headroom to add HUD/patch commands,
publication, retrieval, and the deployed browser `>=30 FPS` gate.
