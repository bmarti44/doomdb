# OCI solo camera-input fusion — 2026-07-31

## Outcome

The camera-only fused input/pixel path is the deployed incremental winner.
It keeps simulation and raster authority in Oracle MLE and returns the exact
effective framebuffer in the same authenticated ORDS exchange that accepts a
camera-changing command. Fire, use, weapon, menu, and cheat revisions remain
on the compact input endpoint so frequent non-camera input cannot force pixel
work onto every input request.

The production pair is renderer `51aadc21bcb619928cee3e73217c8150cebf19aa3186dfd273ea3535d88e2edb`
and coordinator `15f1664cb9f3e65a60f13a69aa3f4376c612484918b87998431ffacbac2db60a`.
Both retained slots were rebuilt from that pair and reached `READY` before
admission reopened.

## Measured comparison

| Cell | FPS | Direction p50 / p95 / max | Effective frame to canvas | Verdict |
|---|---:|---:|---:|---|
| Interval-3 control, repeated turns | 28.555 | 175.6 / 248.3 / 367.0 ms | 113.0 ms (first motion) | superseded |
| Interval-4 renderer scheduling | 25.597 | 185.7 / 305.8 / 1562.8 ms | 122.1 ms | rejected |
| Exact endpoint + camera fusion, repeated turns | 30.103 | 165.9 / 228.2 / 420.8 ms | 4.0 ms | promoted incrementally |
| Temporal parent + camera fusion | 30.820 | 169.0 / 244.4 / 593.5 ms | 4.0 ms | rejected on latency tail |
| Exact endpoint + camera fusion, normal route | 33.309 | 191.0 / 212.4 / 212.4 ms | 4.5 ms | PASS |
| Camera request bypasses active pixel poll | 30.015 | 169.9 / 235.5 / 646.6 ms | 2.7 / 5.0 ms p50/p95 | rejected |

The normal 60-second route returned 1,999 unique database frames, made
999/999 successful pixel exchanges, and had no cancelled or failed exchange.
The repeated-turn cell exercised 81 direction transitions over 120 seconds,
returned 3,609 unique frames out of 3,613 presentations, and made 1,897/1,897
successful exchanges.

## Honest residual

The repeated-turn p95 improved by 20.1 ms and average presentation crossed
30 FPS, but its 420.8 ms maximum does not pass the existing 350 ms strict
direction-tail assertion. That isolated maximum is not called a gate pass.
Session evidence attributes the remaining sparse 350–470 ms events to the
single-threaded MLE authority/raster producer running on CPU, not browser
buffering, SQL row locks, commits, or ORDS cancellation. The client now adds
about 4 ms after the effective framebuffer exists; further tail improvement
must come from the database producer.

A subsequent scheduling A/B let camera input bypass an in-flight read-only
pixel request. It worsened p95 and maximum latency despite zero HTTP failures,
so concurrent ORDS work is not a priority lane under the Always Free session
cage. Its explicit decomposition put input-to-effective at 165.7/232.8 ms
p50/p95 and effective-to-canvas at 2.7/5.0 ms. The candidate was rejected and
the hosted static manifest was restored byte-for-byte to `c8f6f6c6...`.

## Evidence

- `solo-interval3-repeat-turns-public-120s-2026-07-31.log`
- `solo-interval4-repeat-turns-public-120s-2026-07-31.log`
- `solo-camera-fused-v2-repeat-turns-public-120s-2026-07-31.log`
- `solo-camera-fused-temporal-repeat-turns-public-120s-2026-07-31.log`
- `solo-camera-fused-v2-normal-public-60s-2026-07-31.log`
- `solo-camera-fused-v2-static-deploy-2026-07-31.log`
- `solo-camera-fused-v2-exact-coordinator-restore-2026-07-31.log`
- `solo-camera-lane-bypass-repeat-turns-public-120s-2026-07-31.log`
- `solo-camera-lane-bypass-reject-static-restore-2026-07-31.log`
