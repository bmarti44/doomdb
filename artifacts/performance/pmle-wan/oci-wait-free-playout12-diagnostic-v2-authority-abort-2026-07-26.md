# OCI wait-free playout-12 diagnostic v2 — authority abort

Date: 2026-07-26

Classification: `ABORTED_BY_CHARTER_AUTHORITY`

Brian Martin directed the in-progress single `200 +/- 40 ms` diagnostic to
stop after startup/background and before its terminal scored verdict. The run
was terminated immediately so the visual-cost gate could be corrected from a
flat `selected + 8` allowance to the batch-aware:

`selected maximum + batch-count p95 + 2`

The startup convergence fence is also repinned from 14 to 25 so its polled
observation cannot miss the one-tic sawtooth trough. No result from this run is
cited as performance evidence.

Cleanup was independently verified:

`WAN_CLEANUP|active=0|ready=2|assigned=0|long_poll=0|leases=0`

Raw logs remain unmodified:

- `matrix-oci-wait-free-playout12-diagnostic-v2-2026-07-26.log`
- `rtt-200-jitter-40-oci-wait-free-playout12-diagnostic-v2-2026-07-26.log`
