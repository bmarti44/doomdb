# OCI wasm2js presentation-cost predeclaration — 2026-07-26

Classification: `DIAGNOSTIC_NOT_GATE`.

This cell does not promote wasm2js, amend its standing
`REJECT_CURRENT_TRANSLATOR` / `REJECTED_BEFORE_MLE` verdict, or mutate the
shipping TeaVM 0.15 de-CPS authority. It answers the cost question before any
more `Display()` parity debugging.

## Workload

The isolated TeaVM 0.13.1 legacy-Wasm → wasm2js presentation candidate exports
a retained 320×200 indexed-raster lower-bound kernel. Every frame performs
integer coordinate work, two byte gathers, and one framebuffer store for all
64,000 pixels with no per-frame allocation. A pure MLE JavaScript control
performs the same operations and must return the same checksum.

The terminal protocol uses 20 compiled single-frame samples and five
interpreter-control single-frame samples. The originally predeclared 800-frame
arms exceeded the managed SQL client's approximately three-minute silent-call
window in v4/v5 before any terminal could be emitted; those attempts are
void. Twenty samples give a direct p95 (sample 19) and are sufficient for this
lower-bound rejection test. Both arms first compare the exact one-frame
checksum. SYSTIMESTAMP is primary and GET_TIME disagreement above 30 ms is
reported per sample.

The cell records:

- wasm2js and pure-MLE-JS p50/p95 per frame after warmup;
- the structural speed ratio;
- MLE module creation/load time for the approximately 14.4 MB artifact;
- first-call/warmup time and retained linear-memory bytes;
- the already measured wasm2js authority peak mean/p95 step costs,
  24.45/26.04 ms;
- the TeaVM 0.15 exact-render baseline: 207.488 ms p95 raster, 9.287 ms
  p95 two-RAW egress, and 2.694 ms p95 bounded-ring publication.

This lower-bound kernel is not an exact frame. A PASS can only justify
continuing parity work; it cannot prove live rendering.

## Predeclared interpretation

The 28.571 ms tic budget leaves 4.121 ms at the measured peak mean and
2.531 ms at peak p95. Therefore:

- `UNIFIED_LIVE_COST_ELIGIBLE_FOR_PARITY_WORK`: wasm2js kernel p95 ≤ 2.531 ms,
  both arms return an identical checksum, postflight is healthy, and retained
  memory remains below the documented MLE heap ceiling.
- `SPLIT_RENDER_COST_ELIGIBLE_FOR_PARITY_WORK`: kernel p95 is above 2.531 ms
  but below 28.571 ms. This cannot make the slower wasm2js engine a live
  authority. It only justifies investigating a separate wasm2js rasterizer
  fed by the shipping 0.15 de-CPS authority.
- `DVR_ONLY_ON_COST`: kernel p95 ≥ 28.571 ms. This is decisive because the
  kernel omits Doom visibility, wall/plane/sprite traversal, status rendering,
  frame transfer, compression, and persistence. More `Display()` debugging is
  stopped.

The split architecture has two concrete transfer shapes:

1. replay the 32-byte authoritative command vector in the rasterizer. The
   crossing is sub-millisecond, but the rasterizer must also pay its measured
   24.45/26.04 ms peak step cost, leaving the same 4.121/2.531 ms raster
   budget;
2. transfer a full canonical snapshot (75,818–78,522 bytes in the accepted
   stream). That exceeds a frame and requires reconstruction of renderer-only
   structures, so it is not presumed cheap. A render-primitive snapshot would
   be a new interface and must be measured rather than assumed.

The evidence must say whether raster cost and authority-step cost move in the
same direction. They exercise different generated shapes and may not.

Cold Doom initialization and exact frame parity are measured only after a
cost-eligible result. If the current marker-zero initialization defect
prevents cold init, it is reported as unmeasured—not bypassed with marker-one.
Session-restart and two-session-cage determinism likewise follow only after
cost eligibility.

The artifact tier is explicitly `PRESENTATION_DIAGNOSTIC_ONLY` until and unless
all later exact-frame and integrated 35 Hz gates pass. It is never an authority
candidate: its measured peak authority window is 40.9 tics/s versus the
shipping authority's 140.845 tics/s.

The current released browser path remains the baseline. At the OCI
`200 ± 40 ms` WAN profile its authoritative display-delay p95 is **228.6 ms**.
