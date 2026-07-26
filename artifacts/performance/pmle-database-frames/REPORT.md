# Database-generated frame path — 2026-07-26

## Target

Oracle MLE JavaScript must generate every complete 320×200 indexed Doom frame.
Oracle/ORDS delivers those confirmed frame bytes, and the browser only
palette-expands, scales, and writes them to its canvas. The release gate is at
least 30 unique moving client FPS; the database producer is budgeted at 35
frames/s so delivery has margin. Compression is optional.

The deployed client-rendered OCI release remains the rollback baseline until
this replacement passes its full gates.

## Corrected baseline

The earlier de-CPS presentation diagnostic did not separate rendering from
persistence. Its 11.058 ms p95 bucket was the authority step only; its
180.003 ms p95 bucket combined rendering and the BLOB write.

The stage-separated RAW-ring diagnostic on presentation artifact
`118c37717b362d9e7669b5a3a1e73c87b3916479b6e53651f08e85be9ae8f2d3`
measured:

| Stage | p95 |
| --- | ---: |
| authority step | 10.022 ms |
| exact MLE rasterization | 207.488 ms |
| two-RAW frame egress | 9.287 ms |
| bounded-ring publication + `WRITE BATCH NOWAIT` | 2.694 ms |
| full pipeline | 222.569 ms / 4.493 FPS |

All 300 frames were unique and the frame chain matched the Node reference.
This proves transport and publication are already inexpensive enough to fit
inside a 33.333 ms budget; rasterization is the blocking stage.

## Voided lineage cell

Candidate
`b3045361d6907ebfb054f7a5fefcd2f9061097b636147ff576e17dadf88d99ef`
adds a TeaVM `@JSByRef` framebuffer export and caches each immutable status-bar
background. The complete 5,250-frame Node chain remained exactly
`dc0cfe6a9cc79f592e9b04409508c7db29866308d2a886d7f344d1b75294330c`.

OCI measured 206.776 ms raster p95 and 224.532 ms pipeline p95 (4.454 FPS).
The candidate accidentally omitted the required de-CPS source patch, however,
so it is `VOIDED_WRONG_PATCH_LINEAGE` rather than an optimization verdict.
The cell remains useful only as confirmation that exactness fences survive
the transport change. It is not promoted.

## Warmup and current-shape verdict

The ticker compiled on OCI despite containing larger generated functions than
the renderer. Correct de-CPS candidate
`4646503ae1165a6496f2165a1410d36ca49b374c79dc896792718fe43af3c06e`
contains the same by-reference/status-cache changes on the exact
`0c4c97dc…` Mocha patch lineage. Its complete 5,250-frame Node chain matches.

The retained-isolate cell advanced 3,000 real command-stream tics and rendered
every resulting frame. Its 100-call windows remained scene-density-shaped
(approximately 54–181 ms/render) with no sustained compilation step-down. The
following exact 300-frame moving cell measured:

| Stage | p95 |
| --- | ---: |
| authority step | 9.882 ms |
| exact MLE rasterization | 210.643 ms |
| two-RAW frame egress | 7.793 ms |
| bounded-ring publication | 3.997 ms |
| full pipeline | 228.946 ms / 4.368 FPS |

All 300 frames were unique and the frame chain matched. A prior warm attempt
that repeated one static tic produced approximately 13.9 ms calls but is
retained as `VOIDED_NONREPRESENTATIVE_CORPUS`: it did not execute changing
wall, sprite, or status rendering.

Longer warmup, by-reference export, status-background caching, and micro-level
TeaVM tuning are therefore closed for the current object-heavy JavaScript
shape. The fresh exact-lineage Node CPU profile is distributed across column,
wall-loop, masked-column, span, sprite, status, Java-long, array-copy, and GC
work; no isolated site has the roughly 6–8× leverage required.

## wasm2js structural verdict

The TeaVM 0.13.1 legacy-Wasm → Binaryen wasm2js candidate reached exact
5,250-tic Node authority parity after a tracked serializer high-word
workaround, then ran directly in OCI MLE. It is not a shipping-authority
candidate: its slowest peak window was 40.9 tics/s versus 140.845 for the
shipping 0.15 de-CPS authority.

Before further `Display()` debugging, an isolated Doom-shaped 320×200
linear-memory raster lower bound measured 133.341/140.960 ms p50/p95. The
operation-for-operation ordinary MLE JavaScript arm measured 21.418/21.478 ms.
Thus the generated shape is 6.56× slower for raster gathers and stores, not
faster. Combined with its 26.04 ms peak-step p95, the lower-bound pipeline is
167.0 ms before any real Doom visibility, sprite, HUD, transfer, or
publication work.

The candidate is therefore `DVR_ONLY_ON_COST`; the renderer parity branch is
closed without adopting marker-one or changing the shipping wasm2js rejection
fences. Full details:
[wasm2js-presentation-cost-verdict-2026-07-26.md](wasm2js-presentation-cost-verdict-2026-07-26.md).

Frame compression is suspended because the corrected path is raster-bound:
207.488 ms raster versus 9.287 ms egress and 2.694 ms publication. It reopens
only after a future renderer approaches roughly 30 ms.

## Ordinary-MLE pixel-floor discriminator

The follow-on ordinary-JavaScript control resolves the apparent 21.478 ms
versus 5.824 ms floor discrepancy. Its complete pixel loop performs three
effective byte-array passes per pixel: two dependent reads and one retained
write. A 3,000-frame production-default plateau ended at 21.232 ms p95, or
331.750 ns/pixel for the complete loop. Normalized across those three passes,
that is 7.077 ms per frame-sized pass and 110.583 ns/pixel/pass—close to the
same-venue 91 ns one-gather result.

No asynchronous compilation step-down occurred, so the cell is interpreted.
An isolated forced-compilation attempt was fail-closed: both DOOM and ADMIN
were denied the hidden compile control with `ORA-01031`; no compiled sample is
claimed. Cleanup removed every diagnostic object and reverified the shipping
authority SHA.

The normalized interpreted floor is below Brian's approximately 8 ms/pass
costing threshold. This authorizes no implementation, but makes a purpose-built
flat typed-array renderer worth a separate costing decision. The exact Mocha
renderer remains 9.66× slower than the ordinary three-pass pixel kernel
(207.488 / 21.478), which is the principal structural finding. See
[plain-mle-raster-floor-verdict-2026-07-26.md](plain-mle-raster-floor-verdict-2026-07-26.md).
