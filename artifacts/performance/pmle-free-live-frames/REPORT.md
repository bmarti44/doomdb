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
