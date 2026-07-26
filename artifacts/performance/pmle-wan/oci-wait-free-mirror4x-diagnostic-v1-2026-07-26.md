# OCI wait-free mirror-4x WAN diagnostic

Date: 2026-07-26

Classification: `DIAGNOSTIC_NOT_GATE`

Candidate changes:

- input lead is derived from the confirmed-mirror backlog rather than the
  newer transport cursor;
- confirmed mirror apply/render preparation may catch up at 4x;
- visible presentation remains capped at 2x;
- no transition is skipped, predicted, reordered, or presented before
  verification.

The deployed candidate passed the 300-frame public T11.2 browser gate before
this diagnostic.

| Profile | Input/mirror p95, players 0/1 | Limit, players 0/1 | Presentation p99 | Result |
|---|---:|---:|---:|---|
| 50 +/- 10 ms | 275.7 / 440.1 ms | 467.4 / 457.6 ms | 33.1 / 33.2 ms | PASS |
| 100 +/- 20 ms | 400.2 / 390.7 ms | 627.9 / 618.1 ms | 33.1 / 33.2 ms | PASS |
| 200 +/- 40 ms | 616.2 ms (player 0 emitted before stop) | 1,021.6 ms | 66.4 ms | FAIL |

At 200 ms, one outstanding wait-free poll delivered batches with p95 count
eleven and p95 wall time 315.8 ms. The implementation's six-tic playout-buffer
ceiling represents 171.4 ms and cannot reliably bridge that delivery interval
plus jitter; the unchanged presentation p99 gate missed by 9.3 ms.

Increasing the confirmed-only playout offset is the minimal technical fix, but
the approved WAN design previously bounded it at six tics and the wait-free
transport amendment explicitly left presentation gates unchanged. A bound
change therefore requires charter authority. No threshold or constant has been
changed.

Cleanup was independently verified:

`WAN_CLEANUP|active=0|ready=2|assigned=0|long_poll=0|leases=0`

Raw evidence:

- `matrix-oci-wait-free-mirror4x-diagnostic-v1-2026-07-26.log`
- three corresponding `rtt-*-oci-wait-free-mirror4x-diagnostic-v1-2026-07-26.log`
