# Plain-MLE compiled raster floor predeclaration — 2026-07-26

Classification: `DIAGNOSTIC_NOT_GATE`.

The production-default plateau completed without a compilation step-down:
final passes measured about 20.23 ms p50 and 20.75–21.23 ms p95. This companion
cell uses the standing diagnostic-only hidden-parameter authority and
leak-guard:

- `_mle_compile_immediately=TRUE`
- `_mle_compilation_sync=TRUE`
- `_mle_compilation_errors_are_fatal=TRUE`

The settings apply only to the tagged diagnostic SQL session and never enter
production schema, deployment, worker, or ORDS files. The session is bounded
by a 180-second external timeout; diagnostic objects are isolated and
postflight must reverify zero objects plus the shipping authority SHA before
capacity reopens.

The operation count per pixel is reported two ways:

- one frame-sized pass = 64,000 pixels, two dependent byte gathers, one byte
  store, and integer coordinate/mask arithmetic;
- effective memory passes = three byte-array operations per pixel (two reads,
  one write), or 192,000 byte touches/frame, plus arithmetic.

The venue reference is 91 ns/byte for the earlier one-gather tier probe,
equivalent to 5.824 ms for one 64,000-element gather-only pass.

Predeclared interpretation uses the slower p95 of the final two 500-frame
passes:

- ≤8.000 ms/frame: `COMPILED_FLOOR_PLAUSIBLE`; costing a specialized renderer
  may close the budget, but implementation still requires separate charter
  authorization.
- ≥20.000 ms/frame: `COMPILED_FLOOR_CLOSES_LIVE_RENDERING`; live exact
  database rendering is permanently closed on this OCI venue and exact DVR is
  the database-rendered end state.
- between: `COMPILED_FLOOR_AMBIGUOUS`; report for charter decision.

No specialized renderer starts in this workstream.
