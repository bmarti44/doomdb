# Plain-MLE raster plateau predeclaration — 2026-07-26

Classification: `DIAGNOSTIC_NOT_GATE`.

This is the final cheap gate before considering a purpose-built ordinary-MLE
typed-array renderer. It uses only production-default OCI MLE behavior: no
hidden parameters, compiler switches, or engine flags. It does not replace or
modify the shipping TeaVM 0.15 de-CPS authority.

The kernel is operation-for-operation identical to the pure-MLE-JavaScript arm
that measured 21.418/21.478 ms p50/p95 in the wasm2js cost cell: 64,000 pixels,
integer coordinate work, two byte gathers, and one retained framebuffer store.
It is moved into its own small module so default asynchronous compilation is
not obscured by the 14.4 MB wasm2js module.

Protocol:

- five initialization calls;
- six consecutive passes;
- 500 one-frame calls per pass;
- per-pass p50/p95, total throughput, checksum, and SYSTIMESTAMP versus
  GET_TIME disagreement;
- identical checksum across every pass;
- one OCI cell at a time, retained pool parked, production SHA postflight.

Predeclared outcomes use the slower of the final two pass p95 values:

- `COMPILED_RASTER_SHAPE_PROMISING`: ≤5.000 ms. Proceed to a compact
  authority-to-renderer primitive boundary and one exact wall/plane slice.
- `COMPILED_RASTER_SHAPE_AMBIGUOUS`: >5.000 and ≤10.000 ms. Publish the
  plateau and obtain charter review before a renderer rewrite.
- `COMPILED_RASTER_SHAPE_INSUFFICIENT`: >10.000 ms. Close ordinary-MLE
  per-pixel rasterization: the lower bound leaves too little of the 28.571 ms
  slot for the shipping authority, visibility, sprites, HUD, and transfer.

A landing is sustained only when both final passes meet the same band. A
transient faster window is not a landing. The existing exact renderer baseline
remains 207.488 ms p95; the WAN live-path baseline remains 228.6 ms display
delay p95 at the 200 ms profile.
