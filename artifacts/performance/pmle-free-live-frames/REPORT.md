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

## Next decision

Keep the BLOCKMAP layout and spend its measured headroom on presentation
features. Each feature batch is measured directly on Always Free against the
same pose stream. If complete raster p95 exceeds the budget, reduce texture,
floor, sprite, or HUD fidelity while retaining database authorship; do not
return world rasterization to the browser.
