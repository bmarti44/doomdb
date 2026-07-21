# T12.2 local optimization ledger — 2026-07-21

Status: local complete; cloud publication remains final-P11 work.

All attempts use the content-addressed 300-frame Mocha fixture and retain the
same state (`a4af25da…e4b3c`), frame (`e14a8f7e…1d19a`), and payload
(`b91ce8c7…a0f2`) chain digests.

| Attempt | Class | Change | p50 / p95 | Effective serial FPS | Result |
| ---: | --- | --- | ---: | ---: | --- |
| 1 | transport | readiness 5 ms → 2 ms | 30.060 / 42.420 ms | 31.248 | accepted, +28.13% |
| 2 | transport | readiness 2 ms → 1 ms | 36.464 / 72.954 ms | 24.159 | rolled back, -21.30%; one host-clock anomaly |
| 3 | index | redundant request/status poll index | 31.237 / 76.008 ms | 26.091 | rolled back, -3.92%; plan unchanged |

Attempts 2 and 3 are consecutive, technically distinct, and below five-percent
improvement. The stop rule therefore fires at attempt 3. The temporary index was
dropped; the selected production source retains the 2 ms bounded waiter.

The selected build also passed two exact browser runs at 31.814 and 31.591 FPS.
After rollback cleanup, the broader live interaction gate measured 32.07 FPS,
32.2/33.0 ms frame-gap p50/p95, and 122.2 ms input-to-correlated-paint while
movement, fire, pointer capture, Tab menu, Escape behavior, and frame ordering
all passed.

`verify.sh task T12.2` revalidates every local evidence envelope and referenced
artifact, recomputes all improvements, checks the first valid stop pair,
requires the selected exact chains and ≥30 FPS browser runs, checks the selected
2 ms production source, and rejects leakage of the temporary index.
