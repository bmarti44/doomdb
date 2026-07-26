# OCI wait-free playout-12 diagnostic v4 — FAIL

Date: 2026-07-26

Classification: `DIAGNOSTIC_NOT_GATE_FAIL`

The single authorized `200 +/- 40 ms` rerun reached the full scored interval
after the batch-aware bound, exact selected-depth test, startup-convergence
fence, and presentation clock-debt correction were deployed.

Player 0 measured:

- input/mirror p95: 830.4 ms <= 984.0 ms
- selected maximum depth: unavailable because the verdict assertion preceded
  the playout observation marker in this run
- batch-count p95: 10 tics
- presentation-lag p50/p95/max: 15 / 30 / 66 tics
- confirmed-to-presented p95: 762.4 ms
- presentation cadence p99: 70.4 ms > 57.143 ms
- exact chain continuity: 4,058 confirmed transitions, zero resyncs
- background/refocus: PASS, lease released, checkpoint resync at tic 1,280

This is a substantive cadence failure, not a bound-calibration failure.
The client presented 4,051 sequential unique frames but recurrent event-loop
or confirmed-replay stalls exceeded the approved two-tic cadence window.
The same run also contained accepted-to-confirmed outliers up to 2.396
seconds, yielding a 66-tic maximum delivery/presentation backlog.

An offline profile of the exact deployed browser artifacts over 5,250 tics
measured the steady per-tic client work as approximately 0.03 ms authority
verification, 0.03 ms presentation stepping, and 1.1--1.5 ms rendering after
warmup. Average browser compute is therefore not the 70.4 ms tail's cause.
The next diagnosis must attribute per-batch apply and presentation stalls,
and must reconcile the playout controller's time-compression boundary with
the batch-aware bound's assumed selected-depth-to-selected-plus-batch
sawtooth before another OCI evidence cell is authorized.

The evidence-order defect is corrected in source: future
`PMLE_WAN_PLAYOUT|OBSERVED` markers precede all verdict assertions and include
the pre-clamp desired depth, selected depth, batch count, cadence, lag, and
confirmed-to-presented measurements.

Cleanup was independently verified:

`WAN_CLEANUP|active=0|ready=2|assigned=0|long_poll=0|leases=0`

Raw logs remain unmodified:

- `matrix-oci-wait-free-playout12-diagnostic-v4-2026-07-26.log`
- `rtt-200-jitter-40-oci-wait-free-playout12-diagnostic-v4-2026-07-26.log`
