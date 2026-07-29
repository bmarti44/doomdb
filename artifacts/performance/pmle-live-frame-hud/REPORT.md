# HUD-complete OCI database-pixel deployment — 2026-07-29

## Deployment

The HUD-complete live-frame artifact is installed on the public Oracle
Autonomous Database Always Free instance:

- authority: `66dd235cde82a8b8fbcac88bb905912bacfd6ea40671d2808e5951ce290ce873`
  (`1,090,790` bytes);
- renderer: `61163171b77421fc01a96359903fc1bc5fbbc17c639177c77e48f4973b4a0f12`
  (`48,097` bytes);
- coordinator:
  `59acb671e6e0a03ee89735806c8f0178a53dc792d22b87fb2c22db5f226fdd85`
  (`46,231` bytes);
- compositor/UI packs:
  `e31962b3a177d397783a1e2c369155ae78ab9bdae595a4588d102eb3dc054d37` /
  `8961a242c674c7c3e6f74da2e7c09670c8ad3567996c7ead454fa616df2150b7`.

Database-side length/SHA attestation passed for every artifact and all ten
tic-zero checkpoint-bank entries are bound to the new authority SHA. The
public endpoint is:

<https://G53C2244DAB9063-DOOMDB.adb.us-ashburn-1.oraclecloudapps.com/ords/doom/app/>

## Correctness

The selected authority completed the exact 5,250-tic Node parity stream
against the previously accepted `c613bb51…` authority with identical
canonical state at every tic. The attempted 13,272-tic local OJVM runs are
preserved as failed/void diagnostics: the first exposed a stale hard-coded
predecessor pin, the second restored the dev-only oracle but was stopped
because interpreted OJVM throughput made it unsuitable for this promotion
window. They are not cited as PASS. The dashboard therefore reports the
`c613bb51…` 13,272-tic result as historical and the current 5,250-tic parity
result separately.

## Performance

The OCI server-side production-shaped diagnostic generated 1,200 complete
64,000-byte frames at `84.334` frames/s, with `11.546` ms p50 and `15.557` ms
p95 amortized database time. The renderer has ample compute headroom.

The strict two-browser gate has not yet been requalified:

- warmed unqualified window: `33.254 / 32.944` FPS and `36.4 / 33.1` ms p95;
- qualified tics 301–600: `32.978 / 32.723` FPS and `42.7 / 34.6` ms p95,
  with all 300 tics consecutive for both players;
- a separate unqualified run exposed a 2.938-second ORDS response tail that
  advanced beyond the 64-frame retained ring and correctly failed the
  no-unaccounted-skip fence.

The remaining issue is transport/playout reserve under Always Free ORDS
tails, not MLE rasterization. Until a clean terminal gate lands, the deployed
HUD build is classified
`OCI_HUD_DATABASE_PIXELS_DEPLOYED_REQUALIFICATION_PENDING`; the earlier
`c613bb51…` two-browser PASS remains historical evidence only.

