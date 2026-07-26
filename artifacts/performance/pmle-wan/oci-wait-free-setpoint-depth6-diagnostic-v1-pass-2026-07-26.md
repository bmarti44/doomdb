# OCI wait-free setpoint controller, depth 6 — PASS

Date: 2026-07-26

Classification: `DIAGNOSTIC_NOT_GATE_PASS`

The predeclared depth-6 comparison used the same confirmed-only free-running
setpoint controller as depth 12: two-tic acceleration/deceleration margins,
2x maximum acceleration, and 31.4 ms maximum deceleration period.

| Metric | Player 0 | Player 1 | Bar |
|---|---:|---:|---:|
| presentation cadence p99 | 43.2 ms | 36.7 ms | <= 57.143 ms |
| occupancy p50/p95/min | 5 / 13 / 0 | 5 / 16 / 0 | recorded |
| acceleration duty | 13.716% | 14.381% | recorded |
| deceleration duty | 40.975% | 40.778% | recorded |
| presentation lag p95 | 13 tics | 16 tics | <= 19 tics |
| confirmed-to-presented p95 | 244.6 ms | 254.1 ms | <= 542.9 ms |
| input-to-confirmed p95 | 777.1 ms | 742.1 ms | <= 1,171.4 / 1,025.4 ms |
| neutral substitution | 0% | 0% | < 0.5% |

Both clients presented 4,061 sequential unique frames with zero resyncs.
Background/refocus, lease release, checkpoint recovery, transition-chain
continuity, generation ordering, singular authority-session liveness,
managed-ORDS pool bound, worker readiness, and database postflight passed.

The comparison is non-null: selected depth controlled steady occupancy.
Depth 12 measured occupancy p50 10; depth 6 measured p50 5 for both players.
Depth 6 passed cadence with substantially more margin than the depth-12 cell.
The twelve-tic amendment is therefore withdrawn and the six-tic maximum is
the selected release setting.

Nominal presentation latency reclaimed by reducing the selected maximum from
12 to 6 is six tics, or 171.4 ms. The measured median-occupancy change was
five tics, or approximately 142.9 ms, because the depth-12 adaptive selection
had p90 11 rather than a constant 12.

Terminal markers:

- `PMLE_WAN_GATE|PASS`
- `PASS P13.5-MULTIPLAYER-SOAK`
- `PMLE_WAN_PROFILE|PASS|name=rtt-200-jitter-40`
- `PMLE_WAN_MATRIX|PASS|profiles=1`

Cleanup was independently verified:

`WAN_CLEANUP|active=0|ready=2|assigned=0|long_poll=0|leases=0`

Raw logs remain unmodified:

- `matrix-oci-wait-free-setpoint-depth6-diagnostic-v1-2026-07-26.log`
- `rtt-200-jitter-40-oci-wait-free-setpoint-depth6-diagnostic-v1-2026-07-26.log`
