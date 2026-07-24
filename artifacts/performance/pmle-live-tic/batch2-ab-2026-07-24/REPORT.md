# Batch 2 screen: FixedDiv + low-word flag hoist — 2026-07-24

Verdict: **reject and shift to generated shape**. The batch is exact but its
measured gain is below the 5% promotion threshold and does not track toward
the density-dependent 4–10x requirement.

## Correctness and shape prerequisites

- FixedDiv boundary/random differential:
  `PASS`, 3,835,751 cases, checksum `-1130136517`.
- TeaVM cross-runtime FixedDiv checksum: `PASS`.
- FixedMul regression property: `PASS`, 1,000,529 cases.
- Runtime `Math.*` allowlist: `PASS`.
- Long low-word cast MLE microbench: `PASS`; hoisted p50 451.006 ms
  versus repeated-long p50 1,467.633 ms for 200,000 iterations, a 3.2541x
  shape speedup.
- Candidate artifact:
  1,169,459 bytes,
  SHA-256 `92d3468e6c92b1c67d14860ed33916cd3b2af4e7ebceead5ebd65e3ec438448c`.

The FixedDiv property gate caught and preserved the legacy
`MIN_VALUE / -65536` wrap and `MIN_VALUE / 0` exception before measurement.

## Exact-stream MLE screen

The candidate and the immediately preceding ADVANCED control replayed the
same first 500 tics of `live-dm-2026-07-23` on the same Free-edition resource
configuration and quiet host:

| Metric | ADVANCED control | Batch 2 | Effect |
| --- | ---: | ---: | ---: |
| mean | 293.167 ms | 291.685 ms | 0.51% faster |
| p50 | 290.801 ms | 286.852 ms | 1.36% faster |
| p95 | 434.106 ms | 439.052 ms | 1.14% slower |
| p99 | 503.529 ms | 502.450 ms | 0.21% faster |

The batch also regressed Node exact-stream throughput by about 12%, which is
directional only and not used as the MLE verdict.

The direct MLE improvement is too small to justify a full 5,250-tic
differential/promotion battery or bisection of the two spot changes. Under
the approved decision checkpoint, work moves to the wasm-to-JavaScript
generated-shape spike and the ADB venue probe.

The pinned production module
`06ac33331d9a9158d63fba2da4688ad5d3ff30c316b4c20c09e38d77d3fdebf0`
was restored through the in-database SHA gate after the screen.

