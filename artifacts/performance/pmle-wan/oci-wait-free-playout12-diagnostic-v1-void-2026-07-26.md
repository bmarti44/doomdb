# OCI wait-free playout-12 diagnostic v1 — VOID

Date: 2026-07-26

Classification: `VOID_STALE_HARNESS_FENCE`

The single authorized `200 +/- 40 ms` diagnostic reached confirmed
presentation, then timed out before the background or scored phases. The
startup convergence assertion still required `server - presented <= 8`,
which indirectly encoded the former six-tic playout ceiling plus two. A
legitimate selected depth of 12 cannot satisfy it.

The fence is repinned exactly to 14 and its semantic form is required by the
source verifier. No product or acceptance gate ran in this attempt.

Cleanup was independently verified:

`WAN_CLEANUP|active=0|ready=2|assigned=0|long_poll=0|leases=0`

Raw logs remain unmodified:

- `matrix-oci-wait-free-playout12-diagnostic-v1-2026-07-26.log`
- `rtt-200-jitter-40-oci-wait-free-playout12-diagnostic-v1-2026-07-26.log`
