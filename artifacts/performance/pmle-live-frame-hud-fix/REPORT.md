# OCI live-frame HUD reprojection fix — 2026-07-29

Classification: production defect fix with live verification.

Coordinator `906f045eb2c5b016f9c1733c3c7546575d0a8e07f591c85181bf38ef56df6306`
restricts confirmed-frame temporal reprojection to the 320x168 world
viewport. The prior coordinator transformed all 200 rows, shifting the
retained 32-row status-bar background on three of every four tics before the
widget-level compositor redrew current values. That caused the torn/cropped
ammo, health, face, armor, and inventory display reported in the public demo.

The authority
`66dd235cde82a8b8fbcac88bb905912bacfd6ea40671d2808e5951ce290ce873`
and renderer
`c60a34dd81d6e184be7262f494ff3070adb1ab2fb926ecaafedc4043b22cf93c`
are unchanged.

## Verification

- The source property test proves stationary frames remain bit-identical and
  moving reprojection cannot write rows 168 through 199.
- A 128-tic Node A/B changed 104 affected temporal frames without changing
  canonical simulation state. Mean pixel disagreement with the exact
  reference over the captured two-POV sequence improved from 60.715% to
  58.503%.
- The live OCI browser passed 300/300 unique, sequential, database-authored
  frames at 34.366 FPS with 32.5 ms p95 presentation cadence, zero confirmed
  drops, zero pixel starvation/resync events, and successful match release.
- The retained screenshot
  `oci-browser-2026-07-29.png` shows an intact status bar during simultaneous
  forward movement and turning.

The remaining visual limitation is explicit: the world raster is sampled at
160x56 and expanded to the 320x168 viewport. It is coarse but no longer
corrupts the full-resolution HUD.
