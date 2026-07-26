# OCI wait-free WAN diagnostic — 2026-07-26

Classification: `DIAGNOSTIC_NOT_GATE`.

This record does not amend the approved managed-ORDS long-poll contract and is
not release qualification. It measures the ADB-safe alternative after the
qualified long-poll shape exceeded its requested hold by more than an order of
magnitude under Autonomous Resource Manager.

## Compared transport shapes

Held long poll, 50±10 ms:

- requested hold: 500 ms;
- observed hold p95: 7,575 ms;
- batch wall p95: 7,774.9 ms;
- input-to-confirmed p95: 7,903.3 ms;
- 717 sequential moving frames in 20 seconds after buffering.

Source log:
`rtt-50-jitter-10-oci-cloud-smoke-v17-2026-07-26.log`
(`ba846128bb6f4f7882a29cc348c92712ba56e3cd6caf20ca2d8854ca7fff7873`).

Wait-free batching sets the database hold to zero. The latency budget is
topology-explicit: two measured HTTP RTT legs (input POST and subsequent
transition retrieval), the selected input-lead window, and one authoritative
processing tic. The existing chain, confirmed-only, cadence, per-player
neutral-substitution, hidden/refocus, and presentation gates are unchanged.

## Diagnostic matrix

| Injected profile | Frames, players 0/1 | Input→mirror p95 ms | Presentation p99 ms | Neutral rate | Resyncs |
| --- | ---: | ---: | ---: | ---: | ---: |
| 50±10 ms | 678 / 679 | 319.6 / 293.9 | 33.2 / 33.7 | 0 / 0 | 0 / 0 |
| 100±20 ms | 684 / 684 | 569.9 / 596.6 | 52.1 / 33.3 | 0 / 0 | 0 / 0 |
| 200±40 ms | 673 / 673 | 554.8 / 540.4 | 33.7 / 33.4 | 0 / 0 | 0 / 0 |

Every profile also passed the prolonged-hidden-tab lease release, confirmed
checkpoint resync on focus, 40-frame sequential post-focus tail, generation
and chain continuity, input-lead hysteresis, and per-player fairness checks.

Evidence:

- matrix:
  `matrix-oci-cloud-immediate-diagnostic-v24-2026-07-26.log`
  (`f35ce8d30516b05d9fbb8728721b11996802565af8cff543df24d8b62440300b`);
- 50±10:
  `rtt-50-jitter-10-oci-cloud-immediate-diagnostic-v24-2026-07-26.log`
  (`5464b90227f1f550f55bb1ccc9be5defda7ddfc20742522275dccbd59000fa96`);
- 100±20:
  `rtt-100-jitter-20-oci-cloud-immediate-diagnostic-v24-2026-07-26.log`
  (`35e10c754880cd9162d1d59723eb849b40de4d38d875a6e13b7b2ee0c625f7d9`);
- 200±40:
  `rtt-200-jitter-40-oci-cloud-immediate-diagnostic-v24-2026-07-26.log`
  (`bf6ba78449dc07f3dbdd4d2be9a576c8468ba4d59eff51a5ae5077ec5e4cf472`).

## Product and harness corrections covered by the diagnostic

- network acquisition overlaps serialized TeaVM verification/presentation;
- confirmed apply work yields and is paced at the existing 2× catch-up ceiling;
- visual debt is bounded without skipping canonical mirror state;
- an initial authored neutral command and visible-client heartbeat prevent
  `NEUTRAL_INITIAL` from being mistaken for a paced client;
- one in-flight input plus one coalesced unsent latest state bounds recovery
  after an ORDS outlier;
- two client devices are modeled by two Chromium processes;
- fairness is measured per player from that player's scored frontier;
- p95 input-effect evidence ends when the target tic is applied to the
  confirmed mirror, not at later visual playout.

## Decision still required

Charter authority must either:

1. approve wait-free immediate batching as the managed-ADB production
   transport and authorize the two-leg latency budget before the full
   3×10-minute qualification; or
2. select another managed-ADB-safe delivery mechanism that does not depend on
   prompt resumption of a held database session.

Until then the production WAN gate remains open.

## Prepared fail-closed qualification

The qualification runner cannot promote this diagnostic implicitly.
`DOOMDB_WAN_QUALIFICATION=YES` is accepted only when all of the following are
true:

- long polling is disabled and the requested database hold is zero;
- the topology is recorded as two HTTP legs;
- each profile runs 600 scored seconds after a 90-second warmup; and
- a nonsymlink approval artifact contains exactly:

```text
WAN_TRANSPORT_AMENDMENT|APPROVED|authority=Brian Martin|transport=WAIT_FREE_IMMEDIATE_BATCHING|transport_legs=2
```

The approval artifact's SHA-256 is bound into both the transport and terminal
matrix records. Without that artifact, a wait-free run remains
`DIAGNOSTIC_NOT_GATE`; held polling cannot be selected as qualification. The
offline preflight kills absent approval, wrong approval, held-poll topology,
and shortened-duration mutations.

After approval is recorded, the prepared qualification command is:

```bash
DOOMDB_WAN_LONG_POLL_ENABLED=0 \
DOOMDB_WAN_HOLD_MS=0 \
DOOMDB_WAN_QUALIFICATION=YES \
DOOMDB_MLE_WAN_SECONDS=600 \
DOOMDB_MLE_WAN_WARMUP_SECONDS=90 \
PMLE_EVIDENCE_TAG=oci-wait-free-qualification-2026-07-26 \
probes/mle/teavm-engine/run-wan-matrix.sh
```
