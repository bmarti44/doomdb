# OCI wait-free depth-6 WAN qualification v2 — PASS

Date: 2026-07-26

Classification: `QUALIFICATION_PASS`

The complete managed-OCI qualification ran from the beginning against the
deployed depth-6 confirmed-state setpoint controller. Every profile used a
90-second warmup followed by 600 scored seconds with two independent browser
processes.

| Profile | Input/mirror p95 | Cadence p99 | Occupancy p50/p95/min | Display-delay p95 |
|---|---:|---:|---:|---:|
| 50 +/- 10 ms | 292.9 / 294.8 ms | 35.4 / 34.5 ms | 4/7/0, 4/7/0 | 200 / 200 ms |
| 100 +/- 20 ms | 379.7 / 381.6 ms | 34.6 / 34.5 ms | 5/7/0, 5/7/0 | 200 / 200 ms |
| 200 +/- 40 ms | 557.7 / 556.1 ms | 36.2 / 35.5 ms | 5/8/0, 5/8/0 | 228.6 / 228.6 ms |

Across all profiles:

- more than 20,100 sequential unique moving frames per player and profile;
- zero mirror poisons, chain discontinuities, generation regressions, or
  presentation resyncs;
- selected maximum depth remained six tics;
- low-RTT depth did not widen;
- cadence stayed comfortably within the 57.143 ms p99 bar;
- exact occupancy excursions above selected depth plus 64 recovered within
  1,456.3 ms worst case, under the 5,000 ms bound;
- background/refocus, lease release, checkpoint recovery, singular authority
  liveness, managed-ORDS pool bound, and database postflight passed.

At 200 ms, a measured 4.045-second transport stall caused 15 disconnected
neutral tics for player 2. The member reactivated without resync and the
per-player substitution rate was 0.0710%, below the unchanged 0.5% gate.
Player 1 remained at zero substitutions.

The selected-depth controller's steady-state behavior is evidenced directly:
depth 6 produced median occupancy four to five tics across all WAN profiles,
with acceleration duty approximately 2.5--7.1% and deceleration duty
approximately 29.9--43.6%.

Terminal marker:

`PMLE_WAN_MATRIX|PASS|profiles=3|duration=600|warmup=90|classification=QUALIFICATION|transport_legs=2|approval_sha256=c0257840d5ec12ea730e8da11d08589c85eef03d989fde6b0533b6da53b2463c`

Cleanup was independently verified:

`WAN_CLEANUP|active=0|ready=2|assigned=0|long_poll=0|leases=0`

Raw logs remain unmodified:

- `matrix-oci-wait-free-setpoint-depth6-qualification-v2-2026-07-26.log`
- `rtt-50-jitter-10-oci-wait-free-setpoint-depth6-qualification-v2-2026-07-26.log`
- `rtt-100-jitter-20-oci-wait-free-setpoint-depth6-qualification-v2-2026-07-26.log`
- `rtt-200-jitter-40-oci-wait-free-setpoint-depth6-qualification-v2-2026-07-26.log`
