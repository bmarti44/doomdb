# Ordinary-MLE raster floor verdict — OCI 26ai, 2026-07-26

Classification: `DIAGNOSTIC_NOT_GATE`.

## Headline

The exact generated Mocha renderer's 207.488 ms raster p95 is **9.66×** the
21.478 ms p95 of the operation-for-operation ordinary-MLE JavaScript control.
The experiment therefore localizes most current raster cost to the generated,
object-heavy renderer shape rather than to the minimum indexed-pixel work.

This does not authorize or implement a specialized renderer.

## Production-default cell

The isolated 1,718-byte MLE module performs, for each of 64,000 pixels:

- one dependent texture-byte gather;
- one dependent colormap-byte gather;
- one retained framebuffer-byte store; and
- integer coordinate, mask, and checksum arithmetic.

Six consecutive 500-frame passes under production-default settings ended at:

| Measurement | Result |
| --- | ---: |
| final pass p50 | 20.228 ms/frame |
| slower p95 of final two passes | 21.232 ms/frame |
| full-kernel p50 | 316.063 ns/pixel |
| full-kernel p95 | 331.750 ns/pixel |
| effective byte-array passes | 3/frame |
| normalized p50 per effective pass | 6.743 ms, 105.354 ns/pixel |
| normalized p95 per effective pass | 7.077 ms, 110.583 ns/pixel |

There was no sustained asynchronous step-down across 3,000 measured frames.
The module is therefore classified as **interpreted/default**, not compiled.
The earlier same-venue tier probe measured 91 ns/byte, or 5.824 ms for one
64,000-element gather pass. Three such passes predict 17.472 ms; the measured
21.232 ms is 1.215× that memory-operation floor after adding coordinate,
mask, call, and checksum work. The two measurements reconcile.

Under Brian's predeclared per-frame-sized-pass rule, the interpreted/default
floor is below the approximately 8 ms plausibility threshold. A specialized
renderer is consequently **worth costing**, but is not authorized to start.
The raw three-pass kernel itself is not a 7 ms renderer.

## Compilation discriminator

The companion forced-compilation cell was attempted exactly once after its
predeclaration. Both the DOOM application user and an ADMIN control probe were
denied `_mle_compile_immediately` with `ORA-01031`. The application cell
stopped before samples, cleaned all diagnostic objects, restored the pool,
and reverified shipping authority SHA
`5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3`.

Accordingly, there is **no honest compiled ns/pixel result for this kernel on
managed OCI ADB**. The compiled value is recorded as `UNAVAILABLE_PRIVILEGE`,
not inferred from the compiled ticker or substituted from another venue.
The default cell and the 91 ns gather probe establish the interpreted floor;
the platform does not expose the control needed to manufacture a compiled
comparison for this isolated shape.

This means the `>=20 ms per pass` permanent-closure branch does not fire:
21.232 ms is the complete three-pass kernel, not one pass. Nor does this prove
that an exact specialized renderer will fit 28.571 ms—the real renderer must
perform visibility, clipping, wall, visplane, masked-sprite, colormap, HUD,
and composition work in addition to byte-array passes.

## Exact-renderer cost estimate

Reproducing Mocha-exact rasterization in a deliberately flat typed-array MLE
kernel is estimated at **6–12 engineer-weeks**, followed by the full evidence
battery. The estimate includes:

1. extracting a compact render snapshot from the shipping de-CPS authority;
2. typed-array BSP traversal, clipping, wall-column and visplane raster;
3. masked sprites, colormaps, palette effects, status bar/HUD, and automap;
4. a bounded state-transfer contract and database frame publication;
5. differential frame-chain parity across the accepted 5,250-tic stream; and
6. OCI unique-moving-frame, restart, memory, and two-session-cage gates.

The principal risk is exactness, not basic drawing. Java `int` overflow,
fixed-point multiply/divide truncation, unsigned angle/table indexing,
64-bit intermediates, draw ordering, and clipping edge cases must reproduce
the accepted Node frame chain byte-for-byte. A visually correct rewrite that
changes even one indexed pixel is not acceptable. The existing Mocha
presentation artifact remains the exact oracle and DVR renderer.

## Evidence

- `oci-plain-mle-raster-default-async-v1-2026-07-26-rank.log`
- `oci-plain-mle-raster-default-async-v1-2026-07-26-cleanup.log`
- `oci-plain-mle-raster-forced-sync-v1-2026-07-26-rank.log`
- `oci-plain-mle-raster-forced-sync-v1-2026-07-26-cleanup.log`
- `plain-mle-raster-plateau-predeclaration-2026-07-26.md`
- `plain-mle-raster-compiled-floor-predeclaration-2026-07-26.md`

PMLE_PLAIN_RASTER_FLOOR|PLAUSIBLE_COSTING_ONLY|interpreted_p95_ns_per_pixel=331.750|effective_passes=3|normalized_pass_p95_ms=7.077|compiled_ns_per_pixel=UNAVAILABLE_PRIVILEGE|specialized_renderer=NOT_STARTED
