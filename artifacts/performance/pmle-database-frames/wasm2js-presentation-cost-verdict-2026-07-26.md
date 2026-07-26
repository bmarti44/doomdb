# OCI wasm2js presentation-cost verdict — DVR-only

Date: 2026-07-26  
Classification: `DIAGNOSTIC_NOT_GATE`  
Artifact tier: `PRESENTATION_DIAGNOSTIC_ONLY`

## Verdict

`PMLE_WASM2JS_COST_VERDICT|DVR_ONLY_ON_COST`

The generated linear-memory shape is not a live-frame path. Its deliberately
incomplete 320×200 raster kernel measured **133.341 ms p50 / 140.960 ms p95**
on OCI. That is already 4.93× the entire 28.571 ms tic slot and 55.7× the
2.531 ms p95 raster allowance left after the artifact's measured peak-combat
step.

The kernel omits Doom visibility, BSP traversal, wall/plane/sprite drawing,
status/HUD work, frame transfer, and publication. Repairing `Display()` cannot
make a lower bound smaller, so parity debugging stops here. The prior
marker-zero divergence remains useful localization evidence; marker-one was
removed and was not used in this measurement.

The shipping TeaVM 0.15 de-CPS authority remains
`5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3`.
The standing `REJECT_CURRENT_TRANSLATOR` and `REJECTED_BEFORE_MLE` fences are
unchanged.

## Measured decomposition

| Quantity | Result |
| --- | ---: |
| wasm2js lower-bound raster p50 / p95 | 133.341 / 140.960 ms |
| same kernel in ordinary MLE JS p50 / p95 | 21.418 / 21.478 ms |
| wasm2js/pure-JS raster ratio | 6.56× slower (`structural_speedup=.152`) |
| wasm2js peak authority step mean / p95 | 24.45 / 26.04 ms |
| lower-bound integrated mean / p95 | 157.791 / 167.000 ms |
| implied upper bound before missing renderer work | about 6.34 / 5.99 FPS |
| TeaVM 0.15 exact raster baseline p95 | 207.488 ms |
| TeaVM 0.15 two-RAW egress p95 | 9.287 ms |
| TeaVM 0.15 bounded-ring publication p95 | 2.694 ms |
| artifact bytes | 14,435,019 |
| module creation | 3,651.713 ms |
| first instantiation/lowering call | 2,402.216 ms |
| retained linear memory before/after | 72,876,032 / 72,876,032 bytes |
| clock-suspect samples | 0 |

Rasterization and authority step moved in the **same unfavorable direction**,
although for different reasons: wasm2js peak authority was 3.44× slower than
the shipping authority (40.9 versus 140.845 tics/s), while the Doom-shaped
memory-gather raster kernel was 6.56× slower than ordinary MLE JavaScript.

The 14.4 MB module requires about 6.05 seconds for creation plus first
instantiation before IWAD loading or Doom initialization. Full cold init was
not measured because the marker-zero initialization defect remains and the
cost gate failed first. Per the predeclaration, session-restart and
two-session-cage determinism were not run after a cost rejection.

TeaVM 0.13.1 is required for this experiment: it is the last tested TeaVM
lineage with the legacy linear-memory WebAssembly backend. TeaVM 0.15 uses the
newer WasmGC backend, which Binaryen wasm2js does not translate.

## Split-toolchain evaluation

Keeping the 0.15 authority and using wasm2js only for rasterization does not
rescue this candidate:

- Command replay transfers only the 32-byte authoritative command vector, but
  the renderer context must duplicate the wasm2js step. Its 26.04 ms peak p95
  leaves 2.531 ms for raster; the measured lower bound is 140.960 ms.
- A full canonical-state transfer is 75,818–78,522 bytes on the accepted
  stream, larger than the 64,000-byte framebuffer. It still requires
  renderer-only reconstruction and cannot erase the 140.960 ms lower bound.
- A new render-primitive snapshot interface could avoid duplicate simulation,
  but would be a new specialized renderer contract. Even granting zero
  transfer cost, this candidate's lower-bound raster exceeds the whole frame
  budget by 4.93×.

Separate authority/renderer toolchains remain architecturally legal, but this
wasm2js renderer is not the implementation.

## Evidence lineage and hygiene

Accepted v6:

- `oci-wasm2js-presentation-cost-v6-2026-07-26-pool.log`
- `oci-wasm2js-presentation-cost-v6-2026-07-26-install.log`
- `oci-wasm2js-presentation-cost-v6-2026-07-26-rank.log`
- `oci-wasm2js-presentation-cost-v6-2026-07-26-cleanup.log`

The cost and pure-JS arms returned the identical checksum `1469833290`.
Database staging verified artifact and bridge length/SHA before module
creation. Postflight reported zero diagnostic objects, reverified the shipping
authority SHA, and restarted the retained pool.

Earlier attempts remain void evidence:

- v1: stale local SQLcl path; no database action;
- v2: folded SQL loader terminated before its database SHA marker;
- v3: JDBC verifier used a PL/SQL-only constant in SQL expression context;
- v4: combined 1,600-frame call exceeded the managed client's silent-call
  window;
- v5: the shorter call retained a malformed combined `SET SERVEROUTPUT`
  directive, so terminal output was suppressed.

Every database-touching void run has a passing cleanup/postflight record.

PMLE_WASM2JS_SOURCE_PROVENANCE|PASS|source_patch_sha256=f87a968d9004a236f490e929295a209063c87dfcc977374d04ecf9ff90c4c3f7|adapter_patch_sha256=none

## Consequences

The wasm2js presentation branch is closed as live rendering and retained only
as DVR/audit exploration evidence. The current exact database renderer remains
the TeaVM 0.15 presentation artifact at approximately 4.5 FPS.

Frame compression is suspended. The corrected decomposition shows
rasterization is roughly 94% of the frame path; egress and ring publication
are already small. Compression reopens only if a future renderer approaches
roughly 30 ms.

The released browser-rendered path remains production. Its OCI
`200 ± 40 ms` WAN display-delay p95 baseline is **228.6 ms**.
