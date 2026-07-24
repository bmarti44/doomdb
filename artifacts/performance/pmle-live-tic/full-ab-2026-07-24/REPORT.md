# TeaVM FULL versus ADVANCED in MLE — 2026-07-24

Verdict: **FULL is rejected**. It does not improve whole-route throughput and
materially regresses the quiet plateau. No deterministic promotion gates are
warranted for this candidate.

## Direct MLE result

Both artifacts came from the same input JAR and diagnostic source, were
loaded through the in-database length/SHA fail-closed staging gate, and
replayed the exact preserved 5,250-tic deathmatch stream on a quiet host with
the worker pool parked.

| Metric | ADVANCED | FULL | FULL effect |
| --- | ---: | ---: | ---: |
| Artifact bytes | 1,167,604 | 1,562,996 | +33.9% |
| Whole-route p50 | 160.768 ms | 188.362 ms | +17.2% slower |
| Whole-route p95 | 326.883 ms | 297.350 ms | -9.0% |
| Throughput | 5.512 tics/s | 4.984 tics/s | -9.6% |
| Windows 1–700 total | baseline | 0.951x | 4.9% faster |
| Windows 4200–5250 total | baseline | 1.367x | 36.7% slower |

FULL improves several peak-combat windows by roughly 3–10%, but peak cost
still remains around 287–313 ms/tic and therefore about 10–11x above the
28.571 ms slot. It makes the late plateau roughly 163–167 ms/tic versus
ADVANCED's 119–126 ms/tic. The small peak improvement cannot compensate for
the plateau regression or lower total throughput.

Node directionality independently agrees: FULL delivered 12,948.8 tics/s
versus ADVANCED's 13,645.1 tics/s on the same stream (5.1% slower). Node is
not used as MLE acceptance evidence.

The restored-origin 500-tic check is noisy and slow for both candidates
(ADVANCED 287.036 ms p50; FULL 271.638 ms p50). It does not overturn the
complete-route and steady-window result.

## Environment

Both cells ran consecutively with:

- Oracle AI Database 26ai Free 23.26.2;
- `CPU_COUNT=2`, `DEFAULT_PLAN`, CPU managed `ON`;
- PDB `CPU_COUNT=2`, `DEFAULT_CDB_PLAN`, utilization limit 50, running
  sessions limit 2;
- stopped worker pool and no active match;
- Mac host scheduler/speed limit 100, 12 CPUs available, no thermal or
  performance warning before or after either cell.

`environment-after.log` records the invariant database configuration. Future
replays emit this metadata directly before each cell.

## Provenance

- Input JAR SHA-256:
  `42b25147133bb5c84c3b19c1511583bbd36219fb2a68996244106f40078f943e`
- ADVANCED artifact SHA-256:
  `4b13332c9726ecf06c8cd897beff6d552e95b79dda5e9a74316a0ca84278f9e6`
- FULL artifact SHA-256:
  `8313e8364f25225bfe3be4e69fa8fb698ceb642a6afe68fbcc7c401a92792969`
- ADVANCED MLE log SHA-256:
  `130f58a8131d6f68db6713657b4db1ad5a2379c372bf0f658f868e4fecc5e207`
- FULL MLE log SHA-256:
  `d903c7fb32cd0271f146fb98fd2913c179a87cf65ce5a3958fc8c1ad6f1b66b3`

The pinned production artifact
`06ac33331d9a9158d63fba2da4688ad5d3ff30c316b4c20c09e38d77d3fdebf0`
was restored through the same database staging gate after the A/B.

