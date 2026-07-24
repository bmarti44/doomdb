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

The custom TeaVM core fork is reproducible from TeaVM tag `0.13.1`, commit
`b3a245b7d9034ff35cdfab2def057a3d4f256efb`, using the tracked patch and
bootstrap script. The fork removes only `CoroutineTransformation` from the
single-thread headless legacy-Wasm target; class initialization, shadow-stack,
and write-barrier passes remain.

`PMLE_WASM2JS_SPIKE|REJECTED_BEFORE_MLE|reason=binaryen_i64_high_word_loss`
