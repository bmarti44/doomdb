# T12.0 compiled OJVM renderer gate

Date: 2026-07-15

The clean-room Java 11 renderer now runs as a stored procedure inside Oracle
JVM. Oracle remains the runtime and owns all relational assets and game state;
the browser still receives only the compressed indexed frame. The Java class
does not run as an external game server.

## Exactness and data loading

The selected class is `scripts/performance/DoomBspKernelBench.java`. The latest
independent SQL-oracle run retained every accepted primitive and matched all
64,000 tic-zero presentation pixels:

- 57,012 SQL-accepted seg/column pairs, 0 missing;
- 21,050 SQL-visible hits, 0 missing;
- 12,487 active portal hits, 0 missing, extra, or clip mismatch;
- 26,165 opaque wall pixels, 0 missing, extra, or color mismatch;
- 7,106 masked-wall/sprite pixels, 0 missing, extra, or color mismatch; and
- 64,000 final presentation pixels, 0 missing, extra, or color mismatch.

Four deterministic database-native asset packs replace more than three million
row-at-a-time texel reads. Each value is stored as an unsigned big-endian
two-byte `(palette_index + 1)` value, preserving transparent `-1` and palette
index 255 without ambiguity.

| Pack | Elements | Encoded bytes |
| --- | ---: | ---: |
| Wall textures | 1,256,192 | 2,512,384 |
| Flats | 200,704 | 401,408 |
| Sprite patches | 331,474 | 662,948 |
| UI patches | 173,170 | 346,340 |

The external correctness harness's cold relational load fell from 6,899 ms to
1,810 ms. OJVM caches remain session-private, so production pool prewarming is
still required before interactive traffic.

## Algorithmic change

Deep OJVM tracing originally measured plane rasterization at 18.915 ms p95,
making it 70% of the 27.016 ms traced total. The selected implementation
pre-resolves flat/sky asset and light indexes, precomputes sector-row distances
once per frame, and uses compact per-column visible seg/depth lists. It removes
per-pixel string/map lookup, repeated division, a 2.6 MB projected-pair grid,
and a third determinant pass. No Mocha Doom or JavaBox source, table, asset, or
control flow is copied.

The post-change HotSpot parity run was exact and measured the complete renderer
at 1.906 ms p50 / 3.068 ms p95 and renderer plus packed-v2 codec at 3.795 ms
p50 / 5.362 ms p95.

## Compiled OJVM result

The externally compiled Java 11 class was loaded with `loadjava -resolve`.
Five hundred same-session frames provided a bounded native-JIT warmup; every
selected hot renderer method reported `IS_COMPILED=YES`. The first steady-state
sample rendered 1,500 frames through the real caller-owned BLOB entry point at
10.262 ms p95. A clean scripted redeployment and second 1,500-frame sample is
reported conservatively below. The entire repeat SQL-call loop averaged
11.460 ms per frame, including call-spec/getter overhead.

| Stage | p50 | p95 | p99 |
| --- | ---: | ---: | ---: |
| Total renderer + codec + BLOB | 9.188 ms | 10.517 ms | 12.734 ms |
| Renderer | 6.379 ms | 7.313 ms | 9.520 ms |
| BSP/project | 0.274 ms | 0.344 ms | 0.400 ms |
| Solid coverage | 0.572 ms | 0.655 ms | 0.750 ms |
| Portal/walls | 2.553 ms | 2.957 ms | 4.474 ms |
| Planes | 2.392 ms | 2.673 ms | 4.092 ms |
| Sprites/masked | 0.352 ms | 0.426 ms | 0.497 ms |
| Presentation | 0.180 ms | 0.242 ms | 0.285 ms |
| Packed-v2 codec | 2.755 ms | 3.081 ms | 3.598 ms |
| Two-write BLOB handoff | 0.033 ms | 0.061 ms | 0.088 ms |

The payload is 44,112 GZIP bytes. The conservative 10.517 ms p95 passes both the 20 ms
renderer gate and the 33.3 ms 30-FPS frame budget with 23.0 ms of headroom.
This proves the database-resident rendering component is fast enough; it does
not yet prove interactive playability because the subsequently optimized
render-free SQL simulation remains 36.842 ms p50 / 49.503 ms p95.

### Rejected wall-wrap/light-band micro-optimization (2026-07-17)

Replacing power-of-two texture wrapping with precomputed masks, removing hot
texture-name checks, and reusing precomputed sector light bands preserved the
canonical 330-frame chain but regressed the production moving-route render
kernel from the accepted 12.932/15.267 ms p50/p95 after restoration to
20.653/28.971 ms. Portal and plane p95 rose to 9.067 and 16.523 ms. The change
was reverted. Do not retry this combined code shape without method-level native
compilation evidence that explains the regression.

The redeploy also exposed an audit race: Oracle publishes persistent JIT method
status asynchronously after hot calls return. The deployment gate now polls a
bounded 60-second window for the last selected methods instead of failing while
MMON is still compiling them.

## Reproduction

Deploy and warm the stored class:

```sh
scripts/performance/deploy-t12.0-ojvm-renderer.sh
```

Then run the 1,500-frame percentile harness in a connected DOOM SQL session:

```sql
@scripts/performance/ojvm-renderer-benchmark.sql
```

Credentials are read from the ignored Compose secret and never written to a
command argument, report, or repository file.
