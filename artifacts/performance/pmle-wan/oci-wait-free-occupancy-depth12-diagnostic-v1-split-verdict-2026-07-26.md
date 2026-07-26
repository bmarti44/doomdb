# OCI wait-free occupancy controller, depth 12 — split verdict

Date: 2026-07-26

Classification:
`DIAGNOSTIC_PRESENTATION_PASS_POSTFLIGHT_SESSION_COUNT_FAIL`

The authorized `200 +/- 40 ms` depth-12 cell completed its full scored
interval. The reworked free-running, confirmed-only occupancy controller
passed every presentation and WAN product gate for both clients:

| Metric | Player 0 | Player 1 | Bar |
|---|---:|---:|---:|
| presentation cadence p99 | 55.3 ms | 46.9 ms | <= 57.143 ms |
| occupancy p50/p95/min | 5 / 11 / 0 | 5 / 10 / 0 | recorded |
| presentation lag p95 | 11 tics | 10 tics | <= 24 / 25 |
| confirmed-to-presented p95 | 314.6 ms | 284.2 ms | <= 685.7 / 714.3 |
| input-to-confirmed p95 | 584.5 ms | 600.3 ms | <= 946.8 / 987.8 |
| neutral substitutions | 0 | 0 | < 0.5% |

Both clients presented more than 4,050 sequential unique frames with zero
resyncs. Background/refocus, lease release, checkpoint catch-up, transition
chain continuity, generation ordering, and authority health passed.

Steady-state interpretation: in this tested controller,
`MAX_PLAYOUT_TICS` did not determine occupancy after startup. The 35 Hz
consumer and batched confirmed delivery produced a reflected sawtooth from
empty to approximately one batch; the `<2` deceleration floor only perturbed
the empty boundary, and the exceptional catch-up threshold was rarely active.
The measured 5/11/0 occupancy is therefore not a twelve-frame reserve. A
depth-6 run of that controller would have been a null comparison and was held
before build or deployment.

The post-presentation managed-ADB resource assertion then failed because the
total `DOOM` session count grew from 18 to 20. That metric includes managed
ORDS pooled REST sessions; it does not identify worker-session growth, and the
authority worker itself remained singular and `READY`. The presentation PASS
therefore activates the predeclared depth-6 comparison, while this complete
cell is not represented as an overall diagnostic PASS.

Cleanup was independently verified:

`WAN_CLEANUP|active=0|ready=2|assigned=0|long_poll=0|leases=0`

Raw logs remain unmodified:

- `matrix-oci-wait-free-occupancy-depth12-diagnostic-v1-2026-07-26.log`
- `rtt-200-jitter-40-oci-wait-free-occupancy-depth12-diagnostic-v1-2026-07-26.log`
