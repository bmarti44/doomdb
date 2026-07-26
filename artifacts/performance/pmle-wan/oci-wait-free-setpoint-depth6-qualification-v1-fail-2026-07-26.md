# OCI wait-free depth-6 qualification v1 — FAIL

Date: 2026-07-26

Classification: `QUALIFICATION_FAIL`

The 50 +/- 10 ms profile completed its full 90-second warmup and 600-second
scored interval and passed:

- 20,237 / 20,236 sequential unique frames
- cadence p99 35.1 / 35.1 ms
- occupancy p50/p95/min 4/6/0 for both players
- input-to-confirmed p95 273.7 / 280.3 ms
- zero resyncs and zero neutral substitutions
- full database and managed-ADB resource postflight PASS

The subsequent 100 +/- 20 ms profile was stopped by the legacy instantaneous
presentation-buffer assertion when player 2 briefly reached occupancy 85
while visibly draining at 62.4 FPS. That assertion was the sampling companion
of the removed `MAX_CONFIRMED_PRESENTATION_BACKLOG` snapshot-drop path. With
foreground snapshot dropping now prohibited, its result depends on whether a
five-second HUD poll happens to intersect a recoverable burst.

The completed 50 ms evidence demonstrates the defect: its exact trace recorded
maximum occupancies of 104 and 83, but the polling assertion happened not to
sample either excursion and the profile passed with occupancy p95 6. The
instantaneous polling assertion is therefore phase-dependent and cannot be a
valid no-growth gate.

The correction retains the unchanged p95 lag and confirmed-to-presented gates
and replaces the polling assertion with an exact trace-derived maximum
excursion-duration gate. Occupancy above selected depth plus 64 must recover
within 5,000 ms. Maximum occupancy and recovery duration remain recorded.
This matches the reviewed no-snapshot-drop semantics and fails sustained
backlog growth deterministically.

No matrix PASS is claimed. Raw logs remain unmodified:

- `matrix-oci-wait-free-setpoint-depth6-qualification-v1-2026-07-26.log`
- `rtt-50-jitter-10-oci-wait-free-setpoint-depth6-qualification-v1-2026-07-26.log`
- `rtt-100-jitter-20-oci-wait-free-setpoint-depth6-qualification-v1-2026-07-26.log`

Cleanup was independently verified:

`WAN_CLEANUP|active=0|ready=2|assigned=0|long_poll=0|leases=0`
