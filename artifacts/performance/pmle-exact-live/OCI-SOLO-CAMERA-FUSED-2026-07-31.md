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

Two further bounded-buffer experiments were rejected:

- Returning up to eight already-confirmed frames in the fused camera response
  slightly improved cadence (30.213 FPS, 39.2 ms p95, 161 starvations) but
  increased camera latency to 189.6/260.5/707.6 ms p50/p95/max. The larger
  BLOB response made the control path slower. An earlier attempt that reached
  an empty launcher during static replacement is classified VOID; the rerun
  was preceded by a live index/module readiness check.
- Increasing solo's post-batch poll spacing from 35 to 45 ms improved camera
  p95 to 219.2 ms, but throughput fell to 29.131 FPS, cadence p95 rose to
  45.4 ms, and one producer pause reached 3.239 seconds. It violates the 30
  FPS gate and was rejected.

These cells bracket the lane tradeoff: more camera payload hurts response;
less ordinary polling sacrifices source cadence. Production remains the
one-frame fused response with 35 ms batch spacing and manifest
`c8f6f6c6...`.

## Confirmed camera reprojection promotion

The next database-producer change keeps renderer
`51aadc21bcb619928cee3e73217c8150cebf19aa3186dfd273ea3535d88e2edb`
and authority `66dd235cde82a8b8fbcac88bb905912bacfd6ea40671d2808e5951ce290ce873`
unchanged, and promotes coordinator
`cfaa40468edc3f80fa413331717872c94123060edadea8fa7d4d89e97b73926a`.
This differs from the measured `94679de2...` module only in corrected
evidence/comment wording; executable statements are unchanged.
After a camera command becomes authoritative, MLE reprojects the world
viewport of the last exact Mocha frame from the newly confirmed camera. It
retains the complete exact HUD, weapon, status bar, palette, and layout, and
the ordinary interval-three exact raster remains the correction keyframe.
The browser still receives only database-authored indexed pixels and performs
only the canvas copy.

The 120-second repeated-turn public cell produced 3,748/3,748 unique database
frames at 31.179 FPS. Direction latency was 176.5/219.5/274.6 ms p50/p95/max,
with effective-frame-to-canvas at 1.8/4.7 ms p50/p95. Against the prior
promoted repeated-turn cell, p95 improved by 8.7 ms and the maximum improved
by 146.2 ms (34.7%). Four captured route views retained the exact renderer's
walls, sprites, gun, HUD, face, and status bar.

Three follow-up request-path cells were rejected and fully rolled back:

- reducing the pixel-read/input serialization bound to 25 or 50 ms increased
  cancellations and worsened the direction maximum;
- a 20 ms producer yield before the first fused lookup produced
  178.0/219.1/413.9 ms direction latency and two cancellations;
- splitting immediate input commit from framebuffer retrieval improved input
  acceptance to 65.6/109.9 ms but added 123.0/173.9 ms to presentation,
  reduced output to 28.567 FPS, and failed at 193.8/277.4/562.8 ms overall;
- replacing the fused loop with an exact-ring-slot wait was invalid for a tic
  embedded in a temporal bundle and failed at 297.1/372.3/538.7 ms.

The deployed REST package and hosted statics were restored to the original
fused one-request behavior after those cells. The residual 150.2/196.7 ms
fused request p50/p95 is now the measured optimization target; canvas work is
not material.

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
- `solo-camera-batch8-v2-smoke-public-15s-2026-07-31.log`
- `solo-camera-batch8-v2-repeat-turns-public-120s-2026-07-31.log`
- `solo-camera-batch8-reject-static-restore-2026-07-31.log`
- `solo-poll45-repeat-turns-public-120s-2026-07-31.log`
- `solo-poll45-reject-static-restore-2026-07-31.log`
