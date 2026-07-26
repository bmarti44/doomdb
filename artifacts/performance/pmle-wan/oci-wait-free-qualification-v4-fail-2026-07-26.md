# OCI wait-free WAN qualification v4 — FAIL

Date: 2026-07-26

Classification: `QUALIFICATION_FAIL`

The first predeclared `50 +/- 10 ms` profile completed its 90-second warmup
and 600-second scored interval on the input-preempts-poll candidate. The
candidate corrected the v3 input/mirror miss but failed the unchanged
presentation-cadence gate, so the matrix correctly stopped before the 100 ms
and 200 ms profiles.

| Metric | Player 0 |
|---|---:|
| Presented frames | 20,335 |
| Confirmed transitions | 20,331 |
| Resyncs | 0 |
| Input/mirror p95 | 505.6 ms (PASS, limit 587.9 ms) |
| Batch count p95 | 13 |
| Presentation interval p99 | 122.5 ms (FAIL, limit 57.143 ms) |

The candidate is rejected. Cancelling an in-flight wait-free transition poll
gave authored input the managed venue's runnable ORDS path, but enlarged the
delivery batches enough to violate smooth confirmed presentation.

The run exposed the underlying lead-policy defect: input targets are scheduled
from `mirror.frontier`, while the adaptive minimum lead was calculated from the
newer transport cursor. The next candidate restores uninterrupted polling and
calculates minimum lead from `committedFrontierTic - mirror.frontier.tic + 1`.
No acceptance threshold changes.

Raw evidence is preserved without modification in:

- `rtt-50-jitter-10-oci-wait-free-qualification-v4-2026-07-26.log`
- `matrix-oci-wait-free-qualification-v4-2026-07-26.log`
