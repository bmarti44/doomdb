# OCI wait-free WAN qualification v3 — FAIL

Date: 2026-07-26

Classification: `QUALIFICATION_FAIL`

The first predeclared profile (`50 +/- 10 ms`, two transport legs) ran its
complete 90-second warmup and 600-second scored interval. The run then failed
the unchanged input-to-confirmed-mirror p95 gate, so the matrix correctly
stopped without running the 100 ms and 200 ms profiles.

The background/refocus scenario passed. Both clients preserved a continuous
confirmed chain with zero resyncs:

| Metric | Player 0 | Player 1 |
|---|---:|---:|
| Presented frames | 20,374 | 20,374 |
| Confirmed transitions | 20,376 | 20,374 |
| Transition batches | 5,962 | 5,875 |
| Resyncs | 0 | 0 |
| Input/mirror p95 | 359.0 ms (PASS) | 574.3 ms (FAIL) |
| Profile limit | 457.8 ms | 463.8 ms |
| Input POST RTT p95 | 114.6 ms | 117.6 ms |
| Accepted-to-confirmed p95 | 226.3 ms | 355.2 ms |
| Batch wall p95 | 113.0 ms | 113.5 ms |

The evidence exonerates authority throughput and confirmed-chain delivery.
It exposes asymmetric request scheduling under the managed-ADB two-running-
session envelope: wait-free transition polls and input posts currently compete,
and the browser transport has no input-priority rule. The next product
candidate gives an authored input precedence over a replaceable wait-free poll.
The latency bar is unchanged.

The runner cleanup was independently queried after the failure:

`WAN_CLEANUP|active=0|ready=2|assigned=0|long_poll=0|leases=0`

Raw evidence is preserved without modification in:

- `rtt-50-jitter-10-oci-wait-free-qualification-v3-2026-07-26.log`
- `matrix-oci-wait-free-qualification-v3-2026-07-26.log`
