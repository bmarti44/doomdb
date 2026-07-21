# T12.1 selected-Mocha local checkpoint — 2026-07-21

Status: local complete. Managed-cloud repetition remains final-P11 work.

The content-addressed 300-frame fixture (`1ad47bc8…327fe3`) ran through the
production `SUBMIT_STEP`/`POLL_FRAME` surfaces. An independent decoder verified
every DMF3/4 frame digest. A credential-private collector separately enabled
Oracle row-source statistics, captured internal package SQL anchors, and proved
exact 90-call execution deltas for submit, poll, and `M_DOOM` asset retrieval.
Generated AutoREST anonymous blocks are invocation evidence only; the report
does not claim they have row-source plans. Both production and independent
evidence validators pass.

The first run exposed a 50 ms sleep in `POLL_FRAME` as the dominant avoidable
latency. Reducing that bounded readiness quantum to 5 ms changed the serial
selected-route result as follows:

| Metric | Before | After |
| --- | ---: | ---: |
| Effective serial FPS | 15.27 | 25.54 |
| End-to-end p50 / p95 | 78.64 / 82.06 ms | 37.81 / 56.09 ms |
| ORDS/request remainder p50 / p95 | 67.66 / 71.06 ms | 27.16 / 34.44 ms |
| Database p50 / p95 | 6.99 / 10.35 ms | 7.14 / 11.87 ms |

The instrumented pre-commit retained worker is comfortably inside budget:
database 7.14/11.87 ms,
ticker 0.30/1.68 ms,
render 1.02/1.95 ms, codec 0.06/0.16 ms, BLOB 0.24/0.47 ms, and finalize
2.38/4.06 ms p50/p95. Commit timing is currently sampled every 32nd tic to
avoid adding a post-commit update to the hot path (9/270 measured samples,
1.18–2.41 ms); unsampled commits remain in the external request remainder.
The serial number includes two AutoREST round trips and is not the pipelined
display-throughput claim.

The live browser now uses depth-2 submit/presentation queues and bounded
half-period catch-up only when more than two decoded frames accumulate. Its
interaction gate measured 31.36 displayed FPS, 32.1/33.1 ms p50/p95 paint
gaps, and 126.1 ms input-to-correlated-paint while movement, fire animation,
mouse capture, Tab menu, Escape behavior, and tic-zero suppression all passed.
No frame is skipped or reordered.

The exact content-addressed fixture then ran twice through a dedicated browser
driver using the same production API, codec, palette, and canvas modules. The
runs sustained 31.70 and 31.56 FPS. Both browser runs and the private
attribution replay reproduced identical state (`a4af25da…e4b3c`), frame
(`e14a8f7e…1d19a`), and payload (`b91ce8c7…a0f2`) chain digests across all 300
frames. `verify.sh task T12.1` revalidates this local evidence fail-closed.

This Colima/Lima VM can step Oracle's wall clock backward. The collector counts
and clamps impossible negative database substage observations rather than
publishing them as durations; the accepted post-fix run had zero such samples.
Stable-host p99.9/max certification remains final-P11 work.
