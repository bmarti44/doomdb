# OCI exact-frame input-tail investigation — 2026-07-31

Classification: measured diagnostic and negative A/B evidence. The production
tuple was restored after every rejected cell.

Production tuple after postflight:

- authority `66dd235cde82a8b8fbcac88bb905912bacfd6ea40671d2808e5951ce290ce873`
- renderer `51aadc21bcb619928cee3e73217c8150cebf19aa3186dfd273ea3535d88e2edb`
- coordinator `afbe04722b3a5db03e3a73c834b5ff7600c8c7f4ca73d8296b9f04d6f6135c3e`
- two retained slots `READY`; zero active matches

## Solo result retained

The bounded Free-tier API-lane grace remains promoted. Two clean public runs
produced 32.209/32.166 FPS and direction input-to-canvas p95 of 189.9/248.5
ms, with unique changing database frames and no failed pixel exchanges.

The previous seconds-long stall was a separate checkpoint-owner defect. A
standby restore/replay at tic 512 consumed 13.225 seconds. Solo now serializes
its checkpoint from the already-current authority context; co-op retains the
standby path.

## Renderer-tail attribution

A held solo match (`d840690fa01127fb9b033ae64e7c68c4`) stayed healthy:
authority `READY`, standby `READY/IDLE`, and checkpoint save/publish around
88–94/21–26 ms. Sparse calls instead localized pauses to `MLE_FRAME`:

| tic | process step | MLE step | post-MLE | frame render |
|---:|---:|---:|---:|---:|
| 418 | 440.154 ms | 3.905 ms | 435.897 ms | 429.170 ms |
| 532 | 122.424 ms | 5.174 ms | 116.912 ms | 109.543 ms |
| 979 | 478.715 ms | 4.677 ms | 473.644 ms | 466.654 ms |
| 1726 | 430.293 ms | 2.872 ms | 425.727 ms | 418.782 ms |

ASH samples inside those windows classified the retained renderer either
`ON CPU` or waiting on `User I/O / db file parallel read`; there was no slot
promotion, standby replay, match-row lock, or input-acceptance defect. This is
renderer residency/venue I/O variance, not the back-to-back assignment path.

## Rejected mitigations

1. Cancelling an in-flight pixel exchange on input caused 49 cancellations,
   30.888 FPS, and 905.9 ms direction p95. Aborting HTTP did not promptly
   release Oracle work.
2. A fixed 12-frame solo reserve still exposed a 1.201-second producer stall
   and reduced the run to 30.314 FPS. Buffering cannot cover an unbounded
   producer pause without unacceptable display delay.
3. Exact-effective multiplayer seeking broke the confirmed schedule before
   explicit drop instrumentation; with honest drops it still measured 27.70
   FPS, 77.0 ms cadence p95, and 514.2 ms input p95.
4. A three-frame multiplayer reserve on interval five measured 30.86 FPS and
   37.6 ms cadence p95, but renderer tails left 175.1 ms p99 / 588.4 ms max
   gaps and 1,033.1 ms input p95.
5. The exact interval-four/ring-128/moving-prewarm coordinator passed Node
   parity. Its clean OCI cell improved multiplayer input p95 from 964.2 to
   327.9 ms and max paint gap from 648.6 to 147.0 ms, but still missed the
   50 ms cadence-p95 and 250 ms input bars. Its reserve-three combination hit
   a renderer tail and regressed to 90.6 ms cadence p95 / 782.9 ms input p95.
   It was rejected and rolled back.

## Next viable experiment

Client buffering and seeking are exhausted at the measured gate. The next
candidate is an input-aware database endpoint scheduler: pass the already
computed effective-input player mask into the coordinator and move (rather
than add) the next expensive exact endpoint to the affected player. Preserve
one-render-at-a-time staggering, bound starvation/fairness for the other view,
and retain variable-interval native EPT1 materialization. It requires Node
parity, canonical authority invariance, two-POV moving/firing coverage, and a
direct OCI A/B before promotion.
