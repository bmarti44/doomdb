# OCI wait-free WAN qualification v5 — VOID

Date: 2026-07-26

Classification: `VOID_HARNESS_OBSERVABILITY`

The `50 +/- 10 ms` profile passed all predeclared gates. The
`100 +/- 20 ms` profile completed its full warmup and scored interval and
passed both clients' input/mirror latency bounds:

- player 0: 497.3 ms p95 <= 661.9 ms
- player 1: 540.5 ms p95 <= 654.3 ms
- zero resyncs
- batch p95: 7 transitions

During one observed 4.126-second input-post stall, the authority correctly
neutral-substituted player 0 for 36 tics and then resumed sampled commands when
the pending request completed. The per-player neutral rate was approximately
0.17%, below the unchanged 0.5% WAN fairness bar.

The generic soak assertion nevertheless required a failed-request/reconnect or
checkpoint-resync marker whenever any disconnected-neutral tic existed. A
pending request that eventually succeeds produces neither marker, so the
harness rejected permitted and fully attributed WAN behavior before emitting
the per-player rate verdict.

The harness now accepts that recovery shape only when it is bound to a measured
transport stall of at least the three-second membership-liveness interval. It
emits `PMLE_WAN_STALL_RECOVERY|PASS` with the stall and neutral counts. The
per-player `<0.5%` fairness gate, latency gates, and presentation gates are
unchanged.

Cleanup after the voided run was independently verified:

`WAN_CLEANUP|active=0|ready=2|assigned=0|long_poll=0|leases=0`

Raw logs remain unmodified:

- `rtt-50-jitter-10-oci-wait-free-qualification-v5-2026-07-26.log`
- `rtt-100-jitter-20-oci-wait-free-qualification-v5-2026-07-26.log`
- `matrix-oci-wait-free-qualification-v5-2026-07-26.log`
