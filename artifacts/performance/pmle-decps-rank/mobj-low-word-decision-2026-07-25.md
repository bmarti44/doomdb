# Mobj low-word decision — 2026-07-25

Verdict: **REJECT_BELOW_5_PERCENT**. The candidate is not promoted and does
not consume the full differential battery.

The emitted-shape microbenchmark proved that hoisting a Java `long` flag value
to an `int` can be worthwhile in isolation: repeated casts measured
1,306.257/1,407.471 ms p50/p95, versus 399.238/436.645 ms for the hoisted
shape (3.2719x p50), with identical checksums. The source candidate preserves
the `long` fields and all checkpoint/codecs. Its 1,000,012-case boundary
property test passed, including bit-38/high-word cases, and its exact
5,250-tic Node differential matched the pinned `5ec18cbe…` authority after
every tic.

The direct Oracle MLE paired A/B on that exact stream is the promotion
decision:

| Metric | Improvement |
| --- | ---: |
| whole-route p50 | 1.035% |
| whole-route p95 | 4.122% |
| monotonic throughput | 2.707% |
| median matched high-awake window | 1.401% |
| best matched high-awake window | 5.230% |

The standing rule requires at least 5% in a promotion metric; a single best
window does not outweigh the 1.401% high-awake median. The broad profile's
14.042% `Long_*` category therefore does not translate into a sufficient gain
from this narrow two-site rewrite. Raw arms are preserved unchanged, and
`compare-mobj-low-word-rank.mjs` regenerates the terminal verdict from them.
The hidden-JIT final-artifact closeout is next.

Evidence:

- `long-flag-cast-5ec18cbe-2026-07-25-v4.log`
- `mobj-low-word-build-2026-07-25.log`
- `mobj-low-word-node-parity-2026-07-25.log`
- `interpreter-5ec18cbe4cff-5250-mobj-low-word-baseline-2026-07-25.log`
- `interpreter-c3d490fde9dd-5250-mobj-low-word-candidate-2026-07-25.log`
- `mobj-low-word-rank-2026-07-25.log`
