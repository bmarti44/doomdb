# OCI wait-free WAN qualification v6 — FAIL

Date: 2026-07-26

Classification: `QUALIFICATION_FAIL`

The full `50 +/- 10 ms` profile passed. Its per-player neutral substitution
rates were 0.4292% and 0.2733%, both below the unchanged 0.5% gate, and 149
neutral tics were bound to an observed 4.838-second successful transport stall
followed by member reactivation.

The `100 +/- 20 ms` profile completed its full warmup and 600-second scored
interval. Player 0 passed input-to-confirmed-mirror latency at 576.1 ms p95
against a 638.3 ms bound. Player 1 failed at 711.9 ms against 672.5 ms.
Both clients delivered more than 20,269 sequential confirmed presentations
with zero resyncs; batch count p95 was six.

The run therefore fails qualification without running the 200 ms cell.
The remaining delay is in confirmed-mirror catch-up: the client deliberately
yields up to 14.3 ms after every verified/rendered transition, limiting apply
catch-up to the same 2x ceiling used for visible presentation. The next
candidate permits mirror apply to catch up at 4x while retaining the visible
2x presentation ceiling. It does not skip, predict, reorder, or present an
unconfirmed transition.

Cleanup after the failed run was independently verified:

`WAN_CLEANUP|active=0|ready=2|assigned=0|long_poll=0|leases=0`

Raw logs remain unmodified:

- `rtt-50-jitter-10-oci-wait-free-qualification-v6-2026-07-26.log`
- `rtt-100-jitter-20-oci-wait-free-qualification-v6-2026-07-26.log`
- `matrix-oci-wait-free-qualification-v6-2026-07-26.log`
