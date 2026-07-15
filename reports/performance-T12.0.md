# T12.0 pulled-forward local renderer acceleration

Date: 2026-07-15

Status: active pulled-forward playability gate. Exact structural improvements
are selected, but P8 remains paused because unique moving frames are still far
outside the 30 FPS budget. This does not replace the final 300-frame local/cloud
T12.1 and T12.2 evidence.

## Baseline

The fixed reviewed spawn pose at `(-416,256)`, angle 0, tic 17 produced:

| Stage | Rows | Signature | Elapsed |
| --- | ---: | ---: | ---: |
| World | 64,000 | palette sum 3,694,320 | 12.11 s |
| Selected masked | 4,738 | palette sum 367,504 | 4.70 s |
| Full presentation | 64,000 | palette sum 4,608,207 | 18.11 s |

The prior clean public `DOOM_API.NEW_GAME(3)` baseline was 121.79 seconds with
a 92,658-byte response, state SHA-256
`3e05a3305cd738a2115b2a233fedad173a6a81f664621d81d0363c46482ab640`,
and frame SHA-256
`1e9b6e40177c1234a87159cdc69cac93e968c7da4f1f54389a8426286f12d90f`.

## Selected implementation

The public API now uses exact bounded set-based staging for:

1. Profile-keyed screen axes and 64×320 precomputed camera rays.
2. Conservative projected seg bounds followed by the canonical determinant,
   `t`, and inclusive `u` intersection predicates.
3. One ordered R1 hit stream, portal walk, and sector-interval stream per frame.
4. World pixels and range-bounded masked pixels from those shared facts.
5. Direct world-to-final composition plus sparse deterministic overlays.
6. Chunked, ordered frame-byte hashing, RLE, JSON, and compression.

The original canonical renderer views and byte-locked
`sql/render/r2/020_pixels.sql` remain unchanged. Direct evaluator calls therefore
remain an independent parity oracle. Global temporary relations are private to
the database session and use fixed shared cardinality statistics. Adaptive plans
and optimizer feedback are disabled only on fixed-shape staging statements to
prevent a slower second-execution cursor.

Successive exact public probes reduced `NEW_GAME` through 26.30, 14.06, 11.35,
10.08, 8.08, 7.67, and 7.63 seconds. A second from-zero 41-file bootstrap ended
with zero invalid objects and its first `NEW_GAME` completed in 8.89 seconds.
Every call returned the same 92,658 bytes and exact baseline state/frame hashes.
The best clean result is about 16 times faster than 121.79 seconds.

The executable moving probe measured one turning command at 8.71 seconds and a
four-command forward batch at 11.35 seconds. The authoritative moving result is
therefore about 0.115 FPS, not real-time playability, and is roughly 262 times
over the 33.3 ms frame budget.

## Rejected attempts

- A local interval derivation inside the canonical world view improved its
  isolated timing but changed a byte-locked reviewed source file. It was reverted
  and its SHA-256 restored exactly.
- Broad CTE materialization hints reduced the plan to 256 operations but
  regressed isolated world/masked stages; rejected.
- Materializing shared R1 camera rays regressed presentation from 18.11 to 23.05
  seconds; rejected.
- A staged/canonical fallback union preserved output but Oracle still expanded
  the fallback and presentation regressed to 52.21 seconds; rejected.
- A leading fallback guard made the staged path fast but caused the canonical
  parity path to spill heavily to TEMP. It was removed and canonical portal view
  names were restored.
- Unpinned temporary-table cursors were fast once and slow on their second
  execution due to cardinality feedback. Shared statistics plus statement-local
  adaptive/feedback controls removed that plan flip.
- Inline world sample staging and indexed world row ranges preserved output but
  regressed the selected plan; both were removed. Full timings and the current
  row-source inventory are in `performance-T12.0-stage-profile.md`.

## Correctness evidence

- T5.2: 1,856,885/1,856,885 declared assertions passed; canonical live frame
  SHA-256 remained exact.
- T5.3: 988/988 declared assertions passed.
- T5.4: 448,566/448,566 declared assertions and all nine reviewed PNG identities
  passed.
- T6.1 through T7.3 all passed, including concurrency, collision, lifts,
  history, branch isolation, combat, monsters, audio, and Chromium playback.
- Fresh bootstrap: 41/41 files, zero invalid objects, exact NEW_GAME hashes.
- Moving API probes: one turn and four forward tics completed with valid payloads.
- Secret audit: ignored runtime credentials remain untracked; only fake example
  templates are visible to Git.

Raw executable probes are in `artifacts/performance/t12.0/`. The final T12 phase
still requires its fixed 300-frame local/cloud replay, complete raw samples,
cursor evidence, and the two-attempt stopping rule.

The independent deep research and JavaBox architecture review are recorded in
`performance-sol-xhigh-deep-research.md`. JavaBox informs BSP ordering, solid
screen-column occlusion, spans, persistent state, texture-column caching, and
publish-on-new-frame sequencing; no GPL code, data, or control flow is copied.
