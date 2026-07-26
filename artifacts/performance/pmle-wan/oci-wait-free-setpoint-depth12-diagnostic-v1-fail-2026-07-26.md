# OCI wait-free setpoint controller, depth 12 — FAIL

Date: 2026-07-26

Classification: `DIAGNOSTIC_NOT_GATE_FAIL`

The selected-depth setpoint controller was deployed with independently pinned
two-tic acceleration and deceleration margins, a 2x acceleration ceiling, and
a 31.4 ms deceleration-period ceiling. Player 0 completed the scored interval:

- presentation cadence p99: 34.2 ms <= 57.143 ms
- occupancy p50/p95/min: 10 / 26 / 0 tics
- selected depth p90/max: 11 / 12 tics
- acceleration/deceleration duty: 11.262% / 44.086%
- presentation lag p95: 26 > 24 tics — **FAIL**
- confirmed-to-presented p95: 538.3 <= 685.7 ms
- input-to-confirmed p95: 725.9 <= 973.2 ms
- batch-count p95: 10 tics
- apply-step observed maximum: 7.9 ms
- browser Long Task observation: one 629 ms task

The input evidence included a 3.189-second command-to-confirmed outlier, with
2.967 seconds in accepted-to-confirmed authority time. The setpoint controller
substantially improved cadence margin and moved median occupancy toward the
selected depth, but the unchanged batch-aware visual-lag gate missed by two
tics after that authority stall. The assertion stopped the cell before player
1, fairness, and final postflight verdicts; no overall PASS is claimed.

The explicitly directed depth-6 comparison remains meaningful because the
setpoint now controls median occupancy. It proceeds with the same two-tic
margins and cadence limits.

Cleanup was independently verified:

`WAN_CLEANUP|active=0|ready=2|assigned=0|long_poll=0|leases=0`

Raw logs remain unmodified:

- `matrix-oci-wait-free-setpoint-depth12-diagnostic-v1-2026-07-26.log`
- `rtt-200-jitter-40-oci-wait-free-setpoint-depth12-diagnostic-v1-2026-07-26.log`
