# T5.3 masked textures and world sprites evaluator candidate

Status: approved and re-frozen under standing user authorization on 2026-07-15.
This directory contains evaluator work only and does not modify production SQL,
existing evaluator behavior, or root verification.

The dependency-only refresh pins final T5.1, final accepted T5.2, and the
human-reviewed actual T5.2 visible-golden manifest. The subsequent T5.3 visual
checkpoint accepted three actual 320x200 database frames after independent SQL
recapture, byte-for-byte indexed-PNG decoding, and original-resolution inspection.
`goldens/integrity-T5.3.json` freezes those reviewed artifacts. This changes no
T5.3 masked or sprite behavior, fixtures, expectations, test IDs, assertions,
mutation witnesses, Oracle semantics, source policy, or production interface.

## Fixed production interface

T5.3 supplies two session-bound table SQL macros:

- `DOOM_R2_MASKED_CANDIDATES(p_session VARCHAR2)` exposes every opaque projected
  two-sided middle-texture or world-sprite sample. Columns are `SESSION_TOKEN`,
  `COLUMN_NO`, `ROW_NO`, `SOURCE_KIND`, `SOURCE_ID`, `DEPTH`, `SECTOR_ID`,
  `ASSET_NAME`, `ASSET_X`, `ASSET_Y`, `PALETTE_INDEX`, `ROTATION_NO`, `FLIP_X`,
  `SCREEN_VISIBLE`, `SECTOR_VISIBLE`, `WALL_VISIBLE`, and `IS_SELECTED`.
- `DOOM_R2_MASKED_PIXELS(p_session VARCHAR2)` exposes exactly the selected rows
  from the same contract, at most once per `(COLUMN_NO,ROW_NO)`.

Only opaque patch texels become candidates; absence is transparency and palette
index zero is opaque. Screen bounds are 320x200. Sector clipping comes from the
active per-column R2 interval/window. A solid wall wins at equal depth using the
inherited epsilon. Eligible overlays sort by `(depth, source-class, source-id,
asset-y, asset-x)`, with `MASKED` before `SPRITE` at equal depth.

Directional selection divides viewer-relative object bearing into eight 45-degree
bins centered on rotations 1..8. A rotation-zero lump is used only for a state
declared rotation zero. Dual-name WAD sprite lumps carry an explicit horizontal
mirror flag. Current session `MOBJS`, not immutable map spawn rows, own object
position, angle, state, and stable id.

The production catalog must classify and resolve every world-renderable state,
including decoration, pickup, monster, barrel, projectile, and effect states.
The current reviewed E1M1 closure contains 44 renderable placed thing types, 66
non-weapon world states, and 123 seeded sprite-patch assets; all declared state
rotations resolve. Projectile/effect rows spawned by engine actions must remain
explicit catalog rows rather than being inferred from weapon-overlay frames.

## Independent oracle

`reference.mjs` imports no production parser or renderer. Five hand-authored
scenes cover transparent grates, solid-wall occlusion, nearer sprites, equal-depth
masked/sprite and sprite/sprite ties, and narrow sector windows. An asymmetric
patch covers all rotations and mirror behavior. Further probes cover half-sector
boundaries, screen clipping, wall-depth equality, translation invariance, the
pinned E1M1 spawn plus two diagnostic poses, and a direct engine-definition to
seeded-asset closure walk.

The manifest declares 17 stable ids and 988 assertions. Eighteen mutations cover
transparency, rotation, mirror flags, all clip stages, nearer/equal-depth order,
world closure, projectile classification, early rounding, stale map things,
masked sidedef offsets, procedural loops, and evaluator coupling.
