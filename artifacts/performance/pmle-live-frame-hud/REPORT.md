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

## Transport/ticker hardening deployment — 2026-07-29

The public ADB deployment now also carries:

- a 600-tic retained-context ticker prewarm followed by an exact tic-zero
  restore before a warm slot becomes `READY`;
- 35-ms successful-response microbatch pacing and the measured three-frame
  input catch-up floor;
- a delayed idempotent framebuffer-fetch hedge;
- a dedicated one-second `TOUCH_MATCH_PRESENCE` lifecycle call, leaving
  `POLL_MATCH_PIXEL_BATCH` read-only so primary and hedge requests do not
  serialize on the player's membership row.

The deployed hosted client is
`multiplayer-ffa0bb983cc9.js`, SHA-256
`ffa0bb983cc9ec03f3cdb42977fa524e907bcbd639d94e0026d2ec3d40ee6a40`.
The database static-loader manifest SHA-256 is
`9bbac133daf9655399a819d78c8632ea8d3f01012e5709b59a3f7cfc8711d454`.
The public entry, solo entry, and new generated package endpoint returned
HTTP `200`, `200`, and an expected authenticated `555` respectively; the
latter proves the endpoint is routed and rejected the deliberately invalid
capability rather than returning `404`.

The first exact-deployment two-browser run
(`oci-hud-v8-two-pov-300-v15-presence-split-2026-07-29`) produced 300/300
consecutive unique database framebuffers for both players over tics
301–600. Player 0 measured `32.612` FPS with `33.400` ms p95; player 1
measured `32.440` FPS with `33.200` ms p95. This is playable above the
30-FPS product target and confirms end-to-end operation, but remains a
strict-gate `FAIL` because player 0 exceeded the `33.333` ms p95 cadence bar
by `0.067` ms and both streams retained Free-tier tail spikes. The run is
preserved as measured, not relabeled. Cleanup left zero active matches and
both retained slots `READY`.

## Visual-correction promotion — 2026-07-29

The `61163171…` renderer was withdrawn after a synchronized same-tic
comparison proved that its custom world raster used the camera's opposite
perpendicular and mixed the 160-column horizontal focal length into the
200-row vertical projection. Those defects mirrored and stretched the scene.
It also selected one constant colormap per sector and approximated the
player-weapon placement.

The currently deployed renderer is
`c60a34dd81d6e184be7262f494ff3070adb1ab2fb926ecaafedc4043b22cf93c`
(`48,427` bytes). It retains the 160-column low-detail database raster while
correcting camera handedness, horizontal/vertical focal lengths, wall
denominators, ray and plane steps, sprite projection, Doom's
distance/orientation colormap selection, and `R_DrawPSprite` placement.
Against a canonical-state-identical Mocha frame at tic 32, the old build
differed in roughly 76–82% of pixels; the corrected build differs in 42.780%,
with mean palette-index delta `19.044`. The residual difference is dominated
by the deliberately coarse vertical raster, simplified visplane coverage,
and noncanonical status-face selection rather than mirrored geometry.

A higher-fidelity 160-by-84 candidate (`50835b71…`) passed the production-
shaped OCI database cell at `72.562` FPS (`13.145/18.598` ms p50/p95 over
1,200 complete 64,000-byte frames). It nevertheless measured only `29.76`
and `29.61` FPS in two consecutive public two-browser runs because
managed-ORDS delivery tails, not raster capacity, drained the confirmed
frame reserve. The deployed 160-by-56 build retains more compute margin, but
its first public run measured `29.67` FPS under the same approximately
60-ms p95 delivery tail. A two-staggered-poll client experiment worsened the
result to `28.70` FPS with a 1.247-second stall and was immediately reverted;
the public client is again the prior single-poll manifest
`9bbac133daf9655399a819d78c8632ea8d3f01012e5709b59a3f7cfc8711d454`.

The promotion is therefore classified
`VISUAL_GEOMETRY_FIXED_DATABASE_RENDERER_DEPLOYED_30FPS_TRANSPORT_GATE_OPEN`.
The database module and both warm slots are healthy and SHA-attested; the
remaining release gate is sustained public delivery at or above 30 FPS.

### Two-POV producer reconciliation

Full retained browser traces subsequently showed that the public stream itself
advanced only `29.569–29.886` consecutive tics/s. Increasing the confirmed
playout reserve from 6 to 12 frames did not change that rate, proving that the
approximately 54-ms paint p95 was downstream evidence of a producer shortfall,
not a buffer-starvation defect. The `72.562` FPS OCI result above is a
one-viewpoint production-shaped cell; live co-op renders two independent POVs
per authoritative tic.

A coordinator candidate
(`f98f6e3408ff7d2d57c26aa31b09d572fd73ea98b551f3f0cd322459dce15a0a`)
retains each player's prior database-rendered status bar and skips patch
composition when that player's HUD state is unchanged. Its first two-browser
run measured `29.85` FPS and therefore did not materially improve the limiting
path. It was withdrawn on 2026-07-29; the public deployment is again the
proven coordinator
`59acb671e6e0a03ee89735806c8f0178a53dc792d22b87fb2c22db5f226fdd85`.

The honest current classification is
`VISUAL_GEOMETRY_FIXED_DATABASE_RENDERER_DEPLOYED_TWO_POV_PRODUCER_GATE_OPEN`.
Client polling and buffer-size experiments are no longer the primary
performance path; the next measurement must decompose the actual two-POV
producer before another optimization is promoted.

### Best-fixed public deployment — 2026-07-29

The public ADB deployment now binds authority `66dd235c…`, corrected renderer
`c60a34dd…`, and coordinator `59acb671…`. The hosted client uses a six-frame
confirmed playout ceiling and one-request adaptive refill. In-database staging
verified the length and SHA-256 of all three JavaScript sources, both retained
slots returned `READY`, and the public entry returned HTTP 200 with the
expected no-cache policy.

A pacing candidate that retained monotonic catch-up for up to one second was
rejected after its 600-frame two-POV producer diagnostic measured `26.709`
FPS. The deployed worker was restored to the prior `200/35`-centisecond reset
and source-attested after compilation. The direct producer diagnostic itself
adds an aggressive serial ORDS polling workload and is not comparable with the
browser acceptance harness; after rollback, the same two-browser 300-frame
test measured `30.12` FPS for player zero with 300 unique database
framebuffers and distinct player POVs. It still failed the strict cadence
tail (`52.4` ms p95 versus `33.333` ms), so the honest result is average-rate
PASS-shaped but full 30-FPS acceptance still open.
