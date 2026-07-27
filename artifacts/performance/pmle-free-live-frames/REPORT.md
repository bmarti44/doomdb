# Always Free database-authored live frames

Date: 2026-07-26
Venue: Oracle Autonomous Database 26ai Always Free (`doomdb-adb`)
Status: specialized renderer architecture promoted; product integration
remains incomplete.

## Contract

The database must generate every displayed framebuffer. The client may decode,
copy, and nearest-neighbor scale those pixels but may not rasterize world state.
The deployed solo and multiplayer paths must sustain at least 30 unique moving
FPS. Exact Mocha framebuffer parity, DVR persistence, and frame compression are
not release requirements. The current live release still renders authoritative
state deltas in the browser and therefore does not satisfy this amended
contract.

## Real workload capture

`run-real-draw-metrics.sh` expands and SHA-verifies the accepted 5,250-tic
`live-dm-2026-07-23` fixture and drives the real Mocha indexed renderer against
Freedoom E1M1. The measured production shape is 1,505 draw commands and 56,615
drawn pixels per average frame, with observed maxima of 2,325 commands and
77,869 pixels. The accepted pose stream contains all 5,250 real display-player
positions and angles:

`3180d9f7ead6f5309d994bd15bc0d76b357566dcd33cc3d857fc3209671317ce`

## Native compositor result

On Always Free, native `UTL_RAW.TRANSLITERATE` is effectively free at this
cardinality (`0.100 ms` peak p95), but optimistic per-command RAW scatter is
not. Combined peak p95 is `14.007 ms`, already above the complete
`11.330 ms` raster allowance before visibility generation or vertical-column
layout. The `REJECT_COMMAND_SCATTER` verdict therefore closes per-draw-command
PL/SQL/native composition, not native LUT use.

## Specialized renderer result

The promoted diagnostic packs the checked-in E1M1 BLOCKMAP and linedefs plus
the accepted pose stream into typed arrays. A retained, allocation-free MLE
JavaScript module casts 160 rays, traverses BLOCKMAP cells, intersects real
linedefs, and authors a complete 160x100 indexed framebuffer. The first cell
uses flat walls/floor/ceiling to isolate visibility and framebuffer work.

Always Free results:

| Pass | p50 ms | p95 ms | Throughput FPS |
|---:|---:|---:|---:|
| 1 | 3.275 | 4.040 | 304.371 |
| 2 | 2.019 | 3.280 | 437.861 |
| 3 | 1.822 | 2.890 | 513.295 |
| 4 | 3.067 | 3.316 | 346.700 |
| 5 | 2.043 | 2.529 | 460.123 |
| 6 | 1.886 | 2.060 | 520.568 |

The final-two worst p95 is `2.529 ms`, passing the predeclared `<=8.000 ms`
promotion rule. All pass clocks agree, the diagnostic objects were removed,
the production authority SHA remained
`5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3`,
and the warm pool was restored.

This is meaningful headroom, not a release result. The module still needs
portal-aware wall bands, textures and lighting, floors/ceilings, dynamic
objects and sprites, weapon overlays, HUD, authority-state transfer, ORDS
delivery, and browser cadence qualification.

## Preserved diagnostic failures

- `blockmap-flat-160x100-v1` did not reach Oracle because the selected local
  SQLcl lacked a Java runtime.
- `blockmap-flat-160x100-v2` staged successfully but demonstrated that MLE
  module state is session-local: the pack was loaded in the installer session
  rather than the rank session. Its failure is preserved. Version 3 reloads
  the SHA-fenced pack in the measured retained session.
- `real-render-state-v3` failed closed at Java compilation because the Mocha
  adapter initially treated mutable one-element health/armor arrays as scalar
  fields. `v3b` fixes the adapter and is the source of the accepted 32-byte
  render-state records.

## Next decision

Keep the BLOCKMAP layout and spend its measured headroom on presentation
features. Each feature batch is measured directly on Always Free against the
same pose stream. If complete raster p95 exceeds the budget, optimize its
generated shape, caching, state transfer, or transport; do not delete required
presentation features or return world rasterization to the browser.

## Full-resolution and authentic-texture continuation

Brian subsequently clarified that 160x100 and visibly simplified output are
diagnostic-only. The final demo must provide the complete 320x200 Doom
presentation surface, including all in-level layers and title/menu/loading/
intermission/finale states.

The same real-pose cell at 320x200 produced these successive Always Free
results:

| Cell | Final-two worst p95 | Interpretation |
|---|---:|---|
| flat BLOCKMAP visibility | 6.508 ms | full-resolution layout promoted |
| interpreted authentic texture sampling | 41.509 ms | reject pixel gathers |
| scaled/lit column cache | 17.869 ms | improved, cache misses dominate |
| 18-map prelit atlas | 15.998 ms | improved, still over budget |
| recycled cache allocations | 16.188 ms | allocation hypothesis rejected |
| 262K direct cache | 16.229 ms | capacity hypothesis rejected |
| corrected high-bit cache mixer | 9.112 ms | authentic wall layout promoted |

The cache defect was structural: wall height occupied high key bits, while a
power-of-two slot mask observed low bits; multiplication did not fold height
down before masking, so distinct scales replaced one another. The corrected
mixer ends the sampled final frame at 320/320 hits and no replacement. The
renderer retains 22,906,368 bytes of prelit authentic texture data across the
18 light maps actually referenced by E1M1.

The 9.112 ms result is inside the current 11.330 ms raster allowance but has
limited remaining headroom. Portal bands, flats, sprites, weapons and HUD must
therefore share cached native column/span blits, while direct MLE BLOB binding
and transport encoding recover budget from the historical 9.287 ms RAW egress
leg. Cold/new-view cache behavior remains a required gate; only final warmed
passes reached the promotion result.

## Portal-correct continuation

The render-state capture was extended from 12 to 32 bytes per tic without
changing the accepted command stream.  It now carries player view height,
health, armor, ready weapon, and clip ammo in addition to position and angle.
The 5,250-record state SHA is:

`161c1305810211a68ef50805f8ee8690dc52b485c7aa34ea7e00817245a67724`

Pack format 3 retains both sidedefs' upper/lower/middle texture identities and
offsets, front/back sectors, sector heights/lights, linedef flags, and the
checked-in SEGS/SSECTORS/NODES tree.  The renderer now clips upper and lower
wall bands and continues through real two-sided openings instead of treating
every linedef as solid.

Successive Always Free cells:

| Cell | Final-two worst p95 | Final sampled shape |
|---|---:|---|
| per-ray BLOCKMAP portals | 43.377 ms | 8,390 intersections; depth 15 |
| front-to-back BSP | 40.220 ms | 2,181 intersections; 462 subsectors |
| BSP back-child bbox rejection | 40.392 ms | 2,181 intersections; 70 subsectors |
| empty two-sided boundary skip | 36.962 ms | 1,893 intersections; depth 13 |
| lazy texture/light setup | 37.432 ms | same shape; hypothesis rejected |

The front-to-back BSP result is geometrically consistent with the ray cell in
its sampled terminal frame: both produced 1,870 portal and 311 solid column
hits before empty-boundary rejection, maximum portal depth 15, 1,060 cache
hits, six misses, and no replacements.  BSP bounding-box rejection cut visited
subsectors from 462 to 70, while empty-trigger rejection removed 288
portal-column intersections.  Neither change is enough to satisfy the
`11.330 ms` raster share.

The present bottleneck is therefore the interpreted per-column portal/clip
work, not texture gathers, cache capacity, or BSP tree breadth.  Pass-level
throughput remains 35–56 raster frames/s, but 30 FPS cannot be claimed by
component mean: ticker, egress, publication, flats, sprites, weapon, and HUD
are not included, and raster p95 remains 31–43 ms.  The next renderer batch
must replace repeated per-column portal setup with span/incremental work or a
compiled generated shape.  Fidelity is not reduced and the existing browser
delta renderer remains the public release until the complete database-frame
gate passes.

## Incremental and generated-shape results

Two more allocation-free specializations preserved every route-pass checksum:

| Cell | Final-two worst p95 | Effect |
|---|---:|---|
| incremental seg denominator | 34.778 ms | avoids ray/divide on clip-only columns |
| specialized clip-only spans | 34.286 ms | 687 terminal-frame columns bypass general helper |

The identical-window compilation discriminator then repeated poses 500–999.
Its 12-pass plateau held p50 at roughly `20.2–20.9 ms` and p95 at
`25.784–26.553 ms`; the median p95 of passes 9–12 was `25.912 ms`, only
`1.4%` below pass 2 (`26.272 ms`). The plain JavaScript specialized module is
therefore compilation-inert on this Always Free venue.

A separate reproducible TeaVM 0.15.0 `ADVANCED` artifact emitted the same
primitive-array BSP/portal geometry as a 17,696-byte ES module:

- artifact SHA:
  `21d4d942c9b3bdac1f94f1ea1e973c92328a5c14cee11b994e36069d8f56f13d`;
- source SHA:
  `b97e63b090abf89e8bfb98ceb84060b97907a087e8685a13818dcb73e3c7b46f`;
- identical-window final p50: `6.553/7.059 ms`;
- identical-window final p95: `10.077/10.190 ms`;
- throughput: `162–163 geometry frames/s`.

This is a real generated-shape improvement, but the artifact deliberately
omits texture-cache lookup and framebuffer blits, so it lands in the
predeclared `REQUIRE_AMDAHL_PROJECTION` band rather than passing. The next
cell extends this generated artifact with the real prelit texture cache and
64,000-byte framebuffer. Only that full-raster measurement can promote a
generated renderer.

That full generated raster was then measured with the authentic
2,545,152-byte wall pack retained in one MLE session. Its final-two worst p95
was `48.273 ms` (`30.0–31.5 FPS` pass-level throughput), so it hit the
predeclared `REJECT_GENERATED_FULL_WALL_RASTER` branch. The failure is
generated framebuffer/cache shape, not generated visibility: TeaVM's emitted
Java array copies do not behave like the native `TypedArray.set` blits that
made the plain cache effective.

The next measured candidate is therefore a narrow hybrid, not another engine:
TeaVM emits a bounded ordered wall-command tape, and ordinary MLE JavaScript
consumes it in the same module graph with native typed-array cache blits. It
preserves the exact generated portal decisions and authentic wall pixels while
isolating the two independently measured fast shapes.

That hybrid passed byte-for-byte comparison against the generated reference
at poses `0`, `500`, `999`, `2500`, and `5249`, but its final-two worst p95
was `45.415 ms`. The terminal frame contained 1,173 commands, of which 1,133
were cache hits. Moving that many cache/control operations into the
interpreted wrapper erased the geometry gain even though each final copy used
native `Uint8Array.set`.

The next cell therefore leaves cache control in the generated kernel and
changes only the storage/copy primitive: its framebuffer, prelit atlas, and
cached segments are TeaVM JSO `Uint8Array` objects copied with native `set`,
not Java arrays copied through `System.arraycopy`.

The resulting generated native-typed-array cell improved sustained
pass-throughput to `34.8–36.4 FPS`, but its final-two worst p95 was still
`40.670 ms`. The copy primitive helped, yet approximately 1,100 short copy
calls per frame remained the dominant raster shape. The next discriminator
removes those boundaries and directly gathers each authentic prelit texel
into the generated primitive framebuffer.

The direct-pixel discriminator preserved the exact same cumulative checksums
but regressed to `59.556 ms` final-two worst p95 and roughly `20 FPS`.
Consequently, neither interpreted per-pixel sampling nor many short bulk
copies is a viable terminal raster shape.

The remaining database-native composition path is now explicit. Generated
geometry will own the segment-cache keys and emit a compact ordered tape:
cache hits reference retained slots, while only misses carry newly generated
segment bytes. A session-persistent PL/SQL package can then apply those
segments with native `UTL_RAW.OVERLAY`. Existing venue evidence measured
native scatter at about `10.775 ms p95` for 1,505 commands; the specialized
terminal frame has 1,173 commands. This path must measure the real tape,
including MLE egress and parsing, before it can be promoted.

The real-tape native-overlay result was exact but slower than its synthetic
projection: `54.634 ms` final-two worst p95 at 1,173 commands and a
10,551-byte terminal tape. Parsing four binary fields per command in PL/SQL
outweighed native overlay's isolated benefit, so that composition path is
rejected.

The next source-level discriminator targets the direct raster's actual inner
loop. Texture Y is a rational function of screen Y; it does not require
floating-point `Math.floor`, modulo, and accumulated addition for every texel.
The generated loop can advance an integer numerator by 128 and divide by the
wall height, preserving the mathematical sample while producing a much
smaller interpreter/compiler shape.

The rational-step cell improved steady throughput from roughly `20 FPS` to
`27.2 FPS`, with a final-two worst p95 of `44.804 ms`. Its cumulative checksum
changed slightly because integer rational sampling resolves a few texel
boundaries differently from accumulated binary floating point; it therefore
did not satisfy that cell's exact-output prerequisite.

The next candidate removes a separate source of deterministic overdraw.
Front-to-back portal clipping leaves one open interval per screen column.
Writing walls as they are accepted and filling only that final interval
assigns every output pixel once instead of painting a 64,000-byte background
and then overwriting the walls.

That candidate did not improve the raster.  The corrected removed-range
implementation produced the same cumulative checksum as the rational-step
cell, but reported 64,236 writes because boundary pixels shared by adjacent
portal ranges were still assigned twice.  Its first pass was already
`37.401 ms p50 / 49.479 ms p95` (`27.006 FPS`) before the exact-64,000-write
assertion stopped the run.  This is slower than the rational-step baseline,
so removing the remaining 236 duplicate writes cannot plausibly recover the
`16.238 ms` needed to reach 30 FPS p95.  The one-write shape is rejected
without weakening its predeclared invariant.

Taken together, these cells isolate the remaining uncertainty.  The generated
geometry is fast, authentic texture data is not itself large enough to explain
the result, and both roughly 1,100 short bulk-copy calls and an interpreted
frame-sized sampling loop miss the budget.  The next discriminator is a
separate, deliberately small generated raster module fed real E1M1 wall
commands.  Its purpose is to determine whether the integrated artifact's
raster method is too large or structurally complex for the compiled tier.
It does not replace the authoritative engine or relax presentation fidelity.

The small module passed complete 64,000-byte framebuffer comparisons at poses
`500`, `750`, and `999`.  It retained a 7,812,116-byte real-command pack and a
22,906,368-byte authentic prelit atlas.  Across twelve 500-frame passes it
sustained `36.5–37.4 FPS`, with final-two p95 values of `31.506` and
`30.859 ms`.  This is a useful 1.3x improvement over the integrated
native-typed-array cell, but it is still wall-only and leaves no p95 budget
for geometry, flats, sprites, weapon/HUD, or delivery.

A second cell kept all 500 renders inside each long exported invocation,
matching the retained-worker execution shape.  It remained flat at
`26.672–27.152 ms/frame` (`36.8–37.5 FPS`) across all twelve passes; the
final-two worst was `26.970 ms/frame`.  Long invocation did not unlock a
compiled pixel loop.  The module-size and call-spec-return compilation
hypotheses are therefore both closed.

This does not close encoded database-generated frames.  Materializing every
cached span into a server-side 64 KB array is the measured cost center.  A
framebuffer transport codec may instead carry ordered target offsets plus
database-generated literal pixel blocks and retained dictionary references.
The browser's only operation is deterministic decompression/copy into the
indexed framebuffer; it receives no geometry, world state, textures, or
rendering decisions.  That remains a database-generated frame, just as RLE is
a frame, while avoiding the server-side scatter that all three native
composition experiments found expensive.  The next measurement isolates
real-route generation plus egress of that pixel-complete tape before any
additional presentation layer is built.

The pixel-complete tape was exact at poses `500`, `750`, and `999`, but did
not preserve a live-rate margin.  Its cold, never-repeated 500-frame route
measured `35.199 ms p50 / 43.670 ms p95` and `31.769 FPS` sustained.  Repeating
the same route warmed the retained dictionary and raised throughput to roughly
`40 FPS`, but that is not representative of unique movement: the cold route
reported `1,007` misses at p95.  The encoded-frame route is therefore closed
for live presentation.

Oracle 26ai's native Web `Blob` implementation was then tested as a possible
bulk compositor.  An async call-spec smoke proved that
`new Blob([Uint8Array...]).arrayBuffer()` is available in MLE and preserves
bytes.  The production-shaped wrapper assembled ordered pixel spans entirely
inside MLE and passed complete 64,000-byte comparisons at all three reference
poses.  It nevertheless measured `75.740 ms p50 / 95.056 ms p95` cold and
about `90 ms p95` warm, sustaining only `14.0-15.0 FPS`.  Native Blob
materialization is therefore not a raster primitive on this venue.

The small generated raster still contained one full interpreted-looking
operation that none of those composition paths removed: it repainted the
64,000-pixel ceiling/floor background with nested loops before drawing walls.
Replacing that loop with a retained exact background framebuffer and one
TeaVM `System.arraycopy` preserved all sampled frame bytes.  It improved the
per-call result to roughly `19 ms p50 / 25 ms p95` and the retained-batch
result from `26.970` to `20.330 ms/frame`, sustaining about `49 FPS`.

An exact quotient/remainder recurrence was also tested to remove per-pixel
integer division.  An exhaustive host property check covered negative and
positive numerators, heights `1..4096`, and 400 samples per case; the OCI
candidate also passed the three full-frame comparisons.  Its branch-heavy
shape regressed retained rendering to `22.582 ms/frame`, so it was reverted.
This is compiler evidence, not a correctness compromise: the simpler direct
division loop is the selected implementation.

The promoted layout result is the column-major prelit atlas.  The installed
Mocha/Freedoom atlas is row-major; retained initialization transposes every
referenced lit texture column once and rewrites command bases, while leaving
the authoritative asset bytes and output palette indices unchanged.  Complete
frame comparison again passed at poses `500`, `750`, and `999`.  Twelve
per-call passes sustained `65.7-68.0 FPS`, with final p95 values `17.316` and
`17.088 ms`.  Twelve retained-batch passes sustained `66.7-68.0 FPS`; the
final-two worst was `14.812 ms/frame`.

This is the first measured raster shape with credible room for a complete
database presentation pipeline: about `18.5 ms/frame` remains under the
33.333 ms budget before command generation, flats, masked sprites, weapon and
HUD composition, publication, and ORDS delivery.  It is still a wall-only
component and is not itself a 30 FPS product claim.  The next integration gate
must capture the real Mocha low-level column/span/patch command cardinality
from moving and firing E1M1 frames, execute those commands in the small
compiled raster, and include database publication.  No static pose pack or
wall-only result may satisfy that gate.

That real-command integration is now measured.  Transparent delegates around
Mocha's actual indexed draw functions captured 192 moving/firing E1M1
player-frames without changing the canonical renderer.  The p95 workload was
2,474 calls and 60,637 sampled pixels, including walls, visplane
floor/ceiling spans, masked sprites, and the player weapon.  Pack version 3
binds every command stream and prelit Freedoom asset to both the original
320x200 frame digest and a 320x168 viewport digest.

The first compact implementation decoded the 28-byte commands during every
render.  It reproduced all 192 viewport digests in Node and three distributed
digests on OCI, but measured `30.491 ms` final-two worst per-call p95 and
`24.100 ms/frame` retained.  Per its predeclared rule that shape was rejected:
its roughly `41 FPS` throughput did not leave enough room for HUD and
publication.

The promoted implementation resolves the byte tape once into primitive
command arrays during retained-context initialization and uses explicit
column-major output strides.  It remains pixel-identical on all 192 Node
frames and all three OCI samples.  On Always Free it measured:

- final-two worst per-call p95: `17.862 ms`;
- final-two worst retained cost: `16.928 ms/frame`;
- sustained retained throughput: `59.075-59.743 FPS`;
- wall-clock/`GET_TIME` suspects: zero;
- postflight diagnostic objects: zero.

This passes `PROMOTE_FULL_VIEWPORT_INTEGRATION`.  It is the first
production-cardinality component result covering authentic walls, flats,
masked sprites, and weapon animation with enough measured headroom for the
remaining 32-line status bar and publication.  It is not yet a product claim:
sky, fuzz, translated sprites, the status/HUD patch layer, menu/title/loading
surfaces, automap, intermission/finale, live authority-to-renderer command
production, ORDS retrieval, and the deployed `>=30 FPS` browser gate remain.

## Integrated-path verdict and authority/renderer split

The direct OCI bisection closed the object-heavy Mocha presentation traversal
as the live rasterizer:

| Peak-window arm | p50 ms | p95 ms |
|---|---:|---:|
| geometry/visibility/HUD count-only | 139.978 | 155.609 |
| command and prelit-asset capture | 167.140 | 177.973 |
| compact raster only | 19.052 | 21.936 |

The complete candidate still reproduced every sampled 320x200 frame, so this
is a performance classification rather than a correctness failure.
Approximately `156 ms` p95 is paid before compact pixel composition begins.
Optimizing the pixel loop cannot recover the live budget while that traversal
stays on the frame path.

The live architecture therefore keeps the accepted Mocha/TeaVM artifact as
the simulation authority and moves rasterization into the small typed-array
TeaVM module. The authority now exports a fixed 32-byte player presentation
record (`x`, `y`, high angle word, `viewz`, health, armor, ready weapon, and
clip ammo). The renderer accepts that record directly; prerecorded pose
indices are no longer required by its live entry point.

Two executable Node gates establish the boundary:

- fourteen distributed records from the accepted 5,250-pose bank produce
  identical geometry checksums through the pose and snapshot entry points;
- a fresh 96-tic two-player authority run yields 92/90 distinct snapshots and
  92/90 distinct renderer checksums when those live records are passed
  directly between the two generated modules.

This is not yet a product-complete renderer. The compact module currently
draws authentic portal-clipped wall bands. Real flats/skies, masked objects
and sprites, weapon animation, the status bar/HUD, automap, and non-level
screens remain explicit implementation gates. Each layer must be authored
inside MLE and the completed database-to-browser path must still pass the
deployed 30 FPS acceptance gate.
