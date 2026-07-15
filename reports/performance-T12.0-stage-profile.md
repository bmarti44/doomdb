# T12.0 deep stage profile and playable-gate status

Date: 2026-07-15

Status: performance work remains active.  Parity is paused.  The current exact
local first frame is substantially faster but is not interactively playable and
does not pass the 30 FPS (`33.3 ms`) unique-moving-frame gate.

## Initial deep trace

The clean `NEW_GAME(3)` trace at the earlier 26.30-second revision used
`SQL_TRACE`/TKPROF with binds omitted.  The temporary `DBMS_MONITOR` grant was
revoked immediately after collection.

| Stage | SQL ID | Elapsed | Share of 30.27 s traced SQL |
| --- | --- | ---: | ---: |
| Selected masked pixels | `bwh53um32gq8j` | 17.00 s | 56.2% |
| World pixels | `afvrdp0gy5sv3` | 4.92 s | 16.3% |
| R1 hits | `as2d5qya5hrfw` | 3.22 s | 10.6% |
| Final presentation pixels | `0ftgjs8x7x22g` | 3.03 s | 10.0% |
| Frame-byte XML/hash input | `djd68rcbm86v1` | 1.01 s | 3.3% |
| RLE and JSON | multiple | <0.50 s | <2% |

The masked row-source plan exposed two concrete explosions: 495 sprite bounds
were scanned against the 64,000-pixel Cartesian relation 31.68 million times,
and the static first-opaque lookup scanned roughly three million `AT` texels and
spilled approximately 12,000 TEMP blocks every frame.

## Selected structural reductions

1. `DOOM_SCREEN_COLUMN` and `DOOM_SCREEN_ROW` are indexed and keyed by the
   explicit `CANONICAL_320X200` render profile.  Masked walls/sprites range-join
   those axes before forming pixel pairs.  The isolated masked stage fell from
   17.00 seconds to as low as 1.36 seconds with identical row and palette sums.
2. `DOOM_ASSET.FIRST_OPAQUE_X/Y` is derived once after seed load.  Runtime
   masked rendering no longer scans/ranks all opaque texels for an off-screen
   witness.
3. Sixty-four orientations times 320 exact ray rows are seeded in
   `DOOM_RENDER_RAY`.  A conservative perspective interval is materialized for
   each front-plane seg before the existing determinant, `t`, and inclusive `u`
   predicates.  At the spawn pose, 2,018 bounds materialize in 0.08 seconds and
   the same 12,558 hits materialize in 0.77 seconds versus the prior 3.22
   seconds.  A two-way full-row `MINUS` against the canonical R1 view returned
   zero differences.
4. GAME/DEAD presentation copies the complete world once, composes masked
   pixels inline, and ranks only sparse weapon/HUD/key/pause overlays.  It no
   longer builds and ranks a second full candidate canvas.
5. The staged world path removed its unused 128,000-row horizon fallback from
   the selected branch.  Wall plus plane candidates still cover exactly 64,000
   pixels and retain the reviewed frame identity.
6. Frame hash input is aggregated into ordered 1,900-pixel hex chunks before
   XML-to-CLOB conversion.  This replaces 64,000 XML elements with 34 while
   retaining the identical column-major 64,000-byte frame and SHA-256.
7. The ordered portal walk and sector intervals are now materialized once per
   frame into exact session-scoped GTTs.  World and masked rendering share those
   rows instead of repeating `MATCH_RECOGNIZE` and interval analytics.  On a
   second clean bootstrap, first `NEW_GAME` improved from 9.86 to 8.89 seconds,
   one moving turn from 9.87 to 8.71 seconds, and four forward tics from 11.76
   to 11.35 seconds, with identical output.
8. The world and masked views now derive the session as the exact single
   aggregate row held by the frame GTT, and world rays come from the seeded
   320-row orientation profile rather than `DISTINCT` over thousands of hit
   rows.  This removes optimizer estimates of 16,000 sessions, a 12-million-row
   pose/ray join, and redundant hash-unique work.  Controlled clean-instance A/B
   measurements improved the moving shapes by 5-8%; main observations reached
   7.10-7.84 seconds for one turn and 7.73-8.30 seconds for four tics.

Across successive exact public probes, `NEW_GAME(3)` fell from 26.30 seconds to
14.06, 11.35, 10.08, 8.08, and finally 7.67 seconds.  Every selected probe
returned 92,658 bytes, state SHA-256
`3e05a3305cd738a2115b2a233fedad173a6a81f664621d81d0363c46482ab640`,
and frame SHA-256
`1e9b6e40177c1234a87159cdc69cac93e968c7da4f1f54389a8426286f12d90f`.
After shared portal/interval staging and cardinality repair, the best repeated
clean probe reached 6.97 seconds.  That is about 3.77 times faster than the prior
26.30-second revision and 17.5 times faster than the original 121.79-second
baseline.  The conservative one-turn frame is 7.84 seconds (about 0.128 FPS),
roughly 235 times above a 33.3 ms frame budget.

## Updated trace at the eight-second shape

The second trace was captured after bounded R1, sparse presentation, and masked
axis work.  Its temporary tracing grant was also revoked immediately.

| Stage | SQL ID | Elapsed | Rows | TEMP/physical reads |
| --- | --- | ---: | ---: | ---: |
| World pixels | `afvrdp0gy5sv3` | 4.03 s | 64,000 | 11,487 |
| Selected masked pixels | `bwh53um32gq8j` | 1.98 s | 7,106 | 0 |
| Frame-byte construction/hash input | `djd68rcbm86v1` | 0.93 s | 1 | 0 |
| Bounded R1 hits | `cw276y3b2qunv` | 0.79 s | 12,558 | 0 |
| Final base-frame insert | `c50bbdt8xp63d` | 0.42 s | 64,000 | 0 |
| RLE | `ans0rrdtddwk3` | 0.28 s | 45,317 | 0 |
| Sparse presentation overlay | `cngx9bk9ff4zn` | 0.27 s | 12,302 | 0 |
| JSON columns | `64hzdn9uq93nz` | 0.15 s | 1 | 0 |
| Seg bounds | `ga6rvqjqud3n1` | 0.06 s | 2,018 | 0 |

This makes world sample selection and its TEMP spill the next primary target.
The final 7.67-second probe includes the subsequently selected chunked hash
construction, so the 0.93-second trace value is an upper bound for that stage.

## Rejected experiments

- Merely placing a conservative angular predicate inside the expanded R1 view
  regressed 3.22 seconds to 4.6-4.8 seconds because Oracle full-scanned the ray
  table and repeatedly evaluated the expanded bound expressions.  Explicit
  bounded GTT materialization was selected instead.
- Forcing the segment-bound CTE to materialize caused a severe regression and
  was terminated.
- Replacing the presentation window sort with four `KEEP (DENSE_RANK FIRST)`
  aggregates preserved output but regressed 10.08 seconds to 10.63 seconds.
- Splitting world geometry samples and texel lookup into two 64,000-row GTT
  statements isolated 3.36 seconds versus 0.59 seconds but added an insert and
  regressed end to end; it was removed.
- Indexed row-range generation for world walls/planes caused a worse Oracle join
  shape (3.79 seconds isolated versus approximately 3.3 seconds) and was
  reverted.  The same shape remains selected for masked sprites because its
  measured improvement there is large and repeatable.
- Materializing projected portal clip windows and interval windows into two
  additional indexed GTTs changed the world insert to a pathological UGA-heavy
  plan.  It exceeded 60 seconds (versus approximately 4 seconds for the selected
  world stage), continued server-side after the client interrupt, and was killed
  and fully removed.  Redeploying the selected revision immediately restored
  the exact hashes in 6.97 seconds with zero invalid objects.

## Remaining acceptance work

This report does not claim all-frame playability.  Cold moving probes now cover
one-command turn and four-command translation, and the second 41-file fresh
bootstrap ends with zero invalid objects and exact public hashes.  Sector motion
and combat samples, post-database ORDS/browser timing, complete T5-T7
correctness/mutation gates, and the 270-frame p50/p95 playable-gate replay remain.
Exact render caches must be reported separately from cache-miss moving frames.

The independent primary-source research and ranked next steps are in
`reports/performance-sol-xhigh-deep-research.md`.

## Regression evidence for the selected revision

The selected production revision passed the complete frozen adjacent sweep:
T5.2 `1,856,885/1,856,885`, T5.3 `988/988`, T5.4
`448,566/448,566` plus all nine reviewed PNG identities; T6.1 `430/430`, T6.2
`372/372` plus thin-door/opening-route checks, T6.3 `906/906` plus lift carry,
T6.4 `848/848`, T7.1 `1,582/1,582`, T7.2 `2,565/2,565` plus lifecycle/history/
integrity/branch isolation, and T7.3 `684/684` plus Chromium and audio checks.
Every evaluator mutation self-check passed.  The main database ended with zero
invalid production objects and the live dashboard served the updated status.
