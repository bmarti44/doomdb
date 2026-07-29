# OCI Always Free checkpoint cadence decision — 2026-07-29

Status: **PASS — 497–512 tic production cadence approved by measured recovery
evidence and crossed by the terminal two-player database-pixel browser gate.**

The earlier fixed-128 decision remains historical local-Free evidence. It was
not silently reinterpreted. The deployed OCI 26ai engine is materially faster,
so the recovery arithmetic was measured again on the actual hosted topology
before changing the constants.

## Predeclared contract

- authoritative venue: OCI Always Free Oracle AI Database 26ai;
- recovery hard bound candidate: 512 tics;
- kill window: 497–511 tics after the latest durable checkpoint;
- recovery phase budget: 45,000 ms;
- separately reserved detection budget: 15,000 ms;
- end-to-end recovery SLA: 60,000 ms;
- production cadence remained 113–128 throughout the diagnostic;
- diagnostic source used a production-inert committed-frontier pause whose
  checked-in value is zero.

## Accepted measurement

Evidence:
`oci-recovery-cadence-512-2026-07-29-v15.log`

The incarnation-fenced managed-ADB stop occurred at committed frontier tic
511 with the durable tic-0 checkpoint. One hosted database-pixel client
remained online and triggered recovery through its ordinary ORDS pixel
exchange; the peer was isolated so no second trigger contaminated the run.

- restore: 482.635 ms;
- replay of 511 authoritative tics: 3,674.282 ms;
- final database-frame publication: 73.437 ms;
- retained-worker total: 4,230.354 ms;
- browser/ORDS-observed recovery: 22,377 ms;
- observed recovery plus reserved detection: 37,377 ms;
- 45-second phase verdict: PASS;
- 60-second end-to-end verdict: PASS.

The production policy therefore uses:

- `c_checkpoint_min_tics = 497`;
- `c_checkpoint_max_tics = 512`;
- `c_checkpoint_probe_tics = 16`;
- `c_checkpoint_low_awake = 16`.

Absolute 16-tic probes yield an actual interval of 497–512 tics for every
prior checkpoint offset. Recovery never requires a checkpoint older than the
hard maximum interval. Checkpoint pruning continues to retain two full hard
intervals.

## Checkpoint-crossing promotion gate

The recovery result authorizes the constants but does not prove presentation
cadence by itself. The terminal gate subsequently completed the required
sequence:

1. deploying the exact production source with the diagnostic pause pinned to
   zero;
2. observing a durable production checkpoint at distance 497–512;
3. running a database-pixel browser sample that deliberately crosses that
   checkpoint;
4. preserving at least 30 FPS average, the existing frame-interval tail bar,
   ordered unique moving frames, and healthy postflight;
5. rerunning the standard recovery/lifecycle source gates.

Evidence:
`../pmle-live-frame-authority/oci-two-pov-native35-input20-standby5-terminal-2026-07-29-v37.log`.
Both player views crossed checkpoint tic 512 while presenting 300 sequential
unique database frames at 34.182 and 34.133 FPS, with 33.0 and 32.8 ms p95
cadence and zero confirmed-frame drops. Checkpoint serialization ran
asynchronously on the passive standby; the authority's largest observed
publication gap was 62.666 ms.
