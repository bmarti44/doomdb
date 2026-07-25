# TeaVM legacy-Wasm to wasm2js spike — 2026-07-24

Verdict: **the structural compile succeeded; Binaryen 131 wasm2js is rejected
for authority use because it loses Java `long` high words at tic 0**.

Evidence classification: `binaryen_i64_high_word_loss`.

The isolated TeaVM 0.13.1 legacy-Wasm backend compiled the full reachable
headless authority: 1,278 classes and 8,516 methods. Native WebAssembly
execution initialized against the same IWAD/table pack and produced the exact
tic-zero canonical SHA of the pinned `e485b941…` JavaScript/OJVM oracle:

```
aad29a0b52d80f801ffb24af34cabf46ee1a0c57af9a05b2ea7cf1a0f4cd026a
```

That isolates the failure after TeaVM. Binaryen 131 converted and executed the
module, but its tic-zero canonical state had 236 byte differences. The first
offsets are 28660, 28816, 28972, and so on at an exact 156-byte stride. The
translated values are zero where the oracle carries nonzero high words
(including 15, 7, and 23) for mobj `long` flags. Default and deterministic
translation produced the same invalid state.

Binaryen's own wasm2js pipeline specifies `remove-non-js-ops`, `flatten`, then
`i64-to-i32-lowering`; `flatten` is explicitly required for correctness.
Applying the lowering a second time is therefore not a valid repair. Engine
fields and codecs were not weakened to accommodate a translator defect.

The direct Oracle MLE rank cell was not run. Parity is a prerequisite to
timing, so spending that evidence slot would have produced a meaningless
number. This rejects the current translator, not the broader generated-shape
idea: native Wasm identity proves the de-CPS/linear-memory authority itself is
semantically viable. A future Binaryen version or targeted translator fix must
first pass exact tic-zero and 100-tic Node parity before MLE can be revisited.

On 2026-07-24, the official Binaryen `main` and `version_131` copies of
`src/passes/I64ToI32Lowering.cpp` had the identical SHA-256
`0bfda9dea546dbba608f9abf55ed2c265adef6dec43729524d3872e67e1c2bd9`.
The current upstream pass still specifies paired low/high `i32` values and a
global high half for `i64` returns. A Binaryen version bump is therefore not a
distinct candidate at this point. Reopening this route requires isolating the
failing lowered operation and fixing that operation, or an upstream change to
this exact pass, followed by the existing parity gates.

The next reduction is now fail-closed and queued behind the promotion ledger.
It converts the rebuilt de-CPS Wasm at `-O0`, preserves a `wasm-dis`
serializer extract, and emits separate constant, field, field-copy, array,
call, and flag-OR high-word verdicts. A field-pass/call-fail result unlocks one
tracked adapter-only workaround: mobj long fields are shifted inside
object-taking helpers and only the resulting `int` crosses the serializer
call boundary. That workaround changes no canonical bytes and must pass tic
zero plus every-tic 100-tic parity before any MLE timing is permitted.
The classifier requires exactly six reduction records: constant, field,
field-copy, array, and flag-OR must pass, while call alone must fail. Any
additional or unrelated failure remains `OTHER_I64_OR_SERIALIZER_FAILURE` and
cannot authorize the workaround.

The custom TeaVM core fork is reproducible from TeaVM tag `0.13.1`, commit
`b3a245b7d9034ff35cdfab2def057a3d4f256efb`, using the tracked patch and
bootstrap script. The fork removes only `CoroutineTransformation` from the
single-thread headless legacy-Wasm target; class initialization, shadow-stack,
and write-barrier passes remain.

`PMLE_WASM2JS_SPIKE|REJECTED_BEFORE_MLE|reason=binaryen_i64_high_word_loss`

## Staged call-boundary recovery and Oracle rank

The post-rejection reduction is now executable but remains unrun behind the
active de-CPS ledger. `run-i64-lowering-diagnostics.sh` rebuilds the de-CPS
legacy-Wasm source, runs Binaryen `-O0`, preserves a serializer-focused
`wasm-dis` extract, and distinguishes field-load correctness from i64
call-boundary scratch-state loss. Only the exact
`CALL_BOUNDARY_HIGH_WORD_LOSS` classification permits the tracked
object-to-high-int adapter workaround.

If that workaround passes exact tic-zero and every-tic 100-tic Node/OJVM
parity, an isolated Oracle path is ready:

- `mle-rank-wrapper.mjs` maps the pure wasm2js linear-memory ABI to MLE
  `Uint8Array` call specifications and reruns all six i64 reductions;
- `install-mle-rank.sh` accepts only the hash-bound, parity-approved bundle
  after exactly binding its adapter patch, Wasm input, bundle, tic-zero log,
  and 100-tic parity-log hashes, then verifies both generated engine and bridge
  inside Oracle before module creation;
- `benchmark-mle-rank.sql` proves the 100-tic canonical SHA in Oracle, then
  captures all 5,250 exact-stream tic times plus 53 nonshrinking
  linear-memory windows;
- `compare-mle-rank.mjs` compares the same de-CPS peak and quiet windows:
  at least 2x in both advances, below 1.5x in either rejects, and the middle
  escalates. It independently binds the approved de-CPS parent and unpromoted
  candidate provenance and recomputes the terminal percentiles from all tic
  samples;
- `run-mle-rank.sh` parks capacity, brackets Oracle alerts, proves isolated
  cleanup and production-module byte identity, restores capacity, and only
  then emits PASS.

Cleanup failure or an unclassified Oracle alert holds gameplay capacity
closed; removing the isolated objects is not sufficient permission to reopen
capacity after an alert-window failure.

No generated wasm2js target is tracked, no Oracle object has been installed,
and no production module has been changed by this staged work.
