# OCI wait-free playout-12 diagnostic v3 — FAIL

Date: 2026-07-26

Classification: `DIAGNOSTIC_NOT_GATE_FAIL`

The single `200 +/- 40 ms` diagnostic completed its scored interval for
player 0 and reached the newly approved visual-cost gate:

- input/mirror p95: 571.4 ms <= 987.0 ms
- selected maximum depth: 12 tics
- batch-count p95: 11 tics
- presentation-lag p95: 25 tics, exactly the batch-aware bound
- confirmed-to-presented p95: 725.8 ms
- confirmed-to-presented bound: 714.3 ms

The 11.5 ms failure is sub-tic scheduling debt. After a late callback, the
client waited a fresh 28.6 ms even when confirmed frames were buffered. The
next candidate retains the approved 2x visible ceiling but uses a 14.3 ms
minimum while recovering the original presentation clock.

The pre-clamp observation marker was still emitted after assertions in this
run and is therefore absent; that instrumentation-order defect is corrected
before the next diagnostic so every failed cell remains diagnosable.

Cleanup was independently verified:

`WAN_CLEANUP|active=0|ready=2|assigned=0|long_poll=0|leases=0`

Raw logs remain unmodified:

- `matrix-oci-wait-free-playout12-diagnostic-v3-2026-07-26.log`
- `rtt-200-jitter-40-oci-wait-free-playout12-diagnostic-v3-2026-07-26.log`
