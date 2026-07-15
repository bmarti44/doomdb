# T12.0 pulled-forward local renderer acceleration

Date: 2026-07-15

Status: accepted as the P8-enabling local optimization after exact parity and a
fresh bootstrap. This does not replace the final 300-frame local/cloud T12.1 and
T12.2 evidence.

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

The public API now uses four bounded set-based materialization statements:

1. Exact R1 analytic hit rows for the selected session.
2. World pixels from staged portal/interval views.
3. Selected masked pixels from the same staged hit stream.
4. Final presentation composition from staged world and masked pixels.

The original canonical renderer views and byte-locked
`sql/render/r2/020_pixels.sql` remain unchanged. Direct evaluator calls therefore
remain an independent parity oracle. Global temporary relations are private to
the database session and use fixed shared cardinality statistics. Adaptive plans
and optimizer feedback are disabled only on the four fixed-shape staging
statements to prevent a slower second-execution cursor.

Two consecutive fixed-pose staging runs retained all row/signature totals. The
observed stage totals were approximately 10.64 and 14.08 seconds; variation was
in R1 hit generation, while masked and presentation plans remained stable.

Two consecutive clean public `NEW_GAME` calls then completed in exactly 26.30
seconds. A fresh 38-file bootstrap completed with zero invalid objects and its
first `NEW_GAME` completed in 28.01 seconds. Every call returned the same 92,658
bytes and the exact baseline state/frame SHA-256 identities. The repeated 26.30
second result is a 78.4% reduction from 121.79 seconds, or about 4.63 times
faster. It is a local first-frame measurement, not an FPS or cloud claim.

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

## Correctness evidence

- T5.2: 1,856,885/1,856,885 declared assertions passed; canonical live frame
  SHA-256 remained exact.
- T5.3: 988/988 declared assertions passed.
- T5.4: 448,566/448,566 declared assertions and all nine reviewed PNG identities
  passed.
- T6.1 through T7.3 all passed, including concurrency, collision, lifts,
  history, branch isolation, combat, monsters, audio, and Chromium playback.
- Fresh bootstrap: 38/38 files, zero invalid objects, exact NEW_GAME hashes.

Raw executable probes are in `artifacts/performance/t12.0/`. The final T12 phase
still requires its fixed 300-frame local/cloud replay, complete raw samples,
cursor evidence, and the two-attempt stopping rule.
