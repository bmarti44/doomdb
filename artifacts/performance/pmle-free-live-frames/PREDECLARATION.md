# Always Free live database-frame path — predeclaration

Date: 2026-07-26
Venue: Oracle Autonomous Database 26ai Always Free
Goal: database-generated live pixels at least 30 browser-observed unique
moving FPS; the client is limited to framebuffer decode/copy/presentation.

## Frozen budget

- Browser cadence: `p95 <= 33.333 ms`, sustained.
- Current authority step p95: `10.022 ms`.
- Current two-RAW egress p95: `9.287 ms`.
- Current bounded publication p95: `2.694 ms`.
- Complete same-call raster allowance at 30 FPS: `11.330 ms`.
- The current generated exact raster is `207.488 ms p95`; that artifact shape
  is rejected, but it does not close a specialized live renderer.
- DVR persistence and compression are outside this goal.

## Real workload, not a synthetic projection

`probes/mle/run-real-draw-metrics.sh` expands and SHA-verifies the accepted
`live-dm-2026-07-23` 5,250-tic fixture, installs the canonical table pack, and
executes the actual Mocha indexed draw functions over real Freedoom E1M1.
The diagnostic Java process is workload instrumentation only and never enters
the production database path.

The first canonical-stream result is:

- 1,058 columns and 447 spans per frame on average (1,505 commands);
- 2,325 commands at the observed maximum;
- 56,615 drawn pixels per frame on average and 77,869 maximum, including
  overdraw;
- 17 distinct colormap arrays per frame on average and 29 maximum;
- 581 distinct source arrays per frame on average and 890 maximum.

These numbers supersede the production-cardinality synthetic tape as the input
to native-bulk costing.

## Native cardinality floor

`benchmark-oci-free-native-raster-cardinality.sql` measures three components
at both average and peak real cardinality:

1. `UTL_RAW.TRANSLITERATE` with the observed number of LUT groups;
2. optimistic native RAW substring/overlay scatter with the observed command
   and pixel counts;
3. both operations combined.

The scatter cell is deliberately optimistic: vertical column scatter and
visibility/tape generation are not yet included. Therefore:

- `combined_peak p95 >= 11.330 ms` rejects this native compositor route;
- `combined_peak p95 <= 6.000 ms` promotes capture and execution of the exact
  real draw tape;
- between `6.000` and `11.330 ms`, promotion requires a separately measured
  visibility/tape stage that keeps the complete raster at or below
  `11.330 ms p95`;
- no synthetic or component result can itself pass the release gate.

The final gate remains a deployed Always Free browser session producing real
moving/firing database frames at 30 FPS or better with bounded backlog.

## Specialized 160x100 BLOCKMAP renderer cell

The first promoted architecture after native-scatter rejection is an
allocation-free MLE JavaScript renderer at 160x100 indexed pixels, nearest-
neighbor scaled by the client. Its diagnostic input is the accepted route's
5,250 actual player poses plus the checked-in E1M1 BLOCKMAP and linedefs.
The initial cell deliberately renders flat walls/floor/ceiling so it isolates
visibility plus framebuffer authorship before texture, sprite, weapon, and HUD
work.

Predeclared interpretation:

- raster-only `p95 <= 8.000 ms` promotes the layout to presentation-layer
  implementation;
- `p95 >= 15.000 ms` rejects this BLOCKMAP ray layout before feature work;
- between those bounds requires profiling and one measured optimization;
- this component cell cannot pass the release gate. The complete deployed
  authority + raster + ORDS + browser pipeline must still sustain at least
  30 unique moving FPS.
