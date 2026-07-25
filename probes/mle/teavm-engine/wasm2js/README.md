# TeaVM legacy-Wasm to wasm2js spike

This directory is an isolated generated-shape experiment. It does not replace,
deploy, or mutate the pinned TeaVM 0.15 JavaScript authority.

TeaVM 0.14 removed its legacy linear-memory WebAssembly backend. The newest
release that can feed Binaryen `wasm2js` is therefore TeaVM 0.13.1. TeaVM's
current WasmGC backend is not suitable for this experiment: Binaryen
`wasm2js` translates core linear-memory WebAssembly, not WasmGC object and
reference types.

The probe uses:

- the same pinned Mocha revision and authority patches as the production MLE
  module;
- one additional headless-only patch replacing
  `Runtime.availableProcessors()` with `1`, because the legacy Wasm class
  library does not implement that JDK query and the value controls renderer
  tint workers that the authority never starts;
- a primitive/raw-linear-memory bridge rather than JSO typed arrays;
- TeaVM 0.13.1 and Binaryen 131.0.0, both exact-pinned.

Build:

```bash
./probes/mle/teavm-engine/wasm2js/build.sh
```

The intended output chain is:

```text
pinned Mocha Java 8 bytecode
  -> TeaVM 0.13.1 legacy WebAssembly
  -> Binaryen 131.0.0 wasm2js ES module
  -> small Oracle-MLE lifecycle/RAW bridge
```

All acceptance work remains fail-closed:

1. the full authority reachable set must compile;
2. the translated module must execute the captured two-player deathmatch
   command shape under Node;
3. a 100-tic canonical state must match the pinned OJVM oracle;
4. the same artifact must load as an Oracle MLE JavaScript module;
5. direct server-side MLE wall-clock timing must beat the current generated
   JavaScript shape before this path can be considered for promotion.

Build/compiler logs and generated artifacts stay under `target/`. Permanent
measurements belong under `artifacts/performance/pmle-wasm2js/`.

## Current verdict

TeaVM compilation and native-Wasm tic-zero parity pass. Binaryen 131 wasm2js
fails exact parity at tic zero by dropping mobj `long` flag high words, so the
current translator is `REJECTED_BEFORE_MLE` and no Oracle MLE rank run was attempted. See
`artifacts/performance/pmle-wasm2js/REPORT.md`.

## Terminal result

The 2026-07-24 spike is fail-closed rejected before MLE. The complete
authority compiles and native legacy Wasm matches the parity-proven oracle at
tic 0, but Binaryen 131 wasm2js loses Java `long` high words in canonical save
material (236 differences beginning at byte 28,660). Stable/default,
deterministic, Wasm `-O3`, the current 131 nightly, and TeaVM `FULL` variants
all reproduce the same bad canonical SHA. See
`artifacts/performance/pmle-wasm2js/REPORT.md`.

The experimental `0.13.1-doomdb-singlethread` TeaVM core is reconstructed by
`build-teavm-singlethread.sh` from a pinned upstream commit plus the tracked
single-thread patch. It remains spike-only. No Oracle MLE load or production
mutation was performed.

A dated source comparison also found Binaryen `main` and `version_131` use
byte-identical `I64ToI32Lowering.cpp` implementations (SHA-256
`0bfda9dea546dbba608f9abf55ed2c265adef6dec43729524d3872e67e1c2bd9`).
Do not spend another rank cell on a version-only retry until that pass changes;
the next useful spike is a reduced failing operation or a targeted translator
repair, with tic-zero parity still preceding all timing.

The next diagnostic is staged in `run-i64-lowering-diagnostics.sh`. It first
rebuilds legacy Wasm from the accepted de-CPS source patch and records the
complete patch-set and Wasm hashes; stale target output is never accepted as
input. It then runs wasm2js explicitly at `-O0` to distinguish optimizer
reordering from mandatory i64 lowering and preserves a `wasm-dis` view plus a
hash-bound serializer/i64 inspection extract. It begins with the six reduced
high-word exports and tic-zero canonical parity. The script refuses to run
beside a long evidence gate and never loads its output into Oracle.

Each reduced case now emits its own actual/expected marker. If the field-load
case passes while the long-argument call case fails, the diagnostic classifies
the defect as call-boundary high-word loss instead of closing the generated
shape. `run-serializer-workaround.sh` is then the only permitted next step: it
applies the tracked adapter-only patch that reads each mobj long and shifts it
inside an object-taking helper, so only an `int` crosses into
`DataOutputStream.writeInt`. The canonical byte format is unchanged. The
workaround must pass exact tic-zero and every-tic 100-tic parity before its
wasm2js bundle is eligible for a direct Oracle MLE rank; failure closes this
branch without a timing cell.

`mle-rank-wrapper.mjs` is the isolated high-level bridge for that eventual
rank. It never introduces a WebAssembly dependency: it imports the pure
wasm2js module, maps its linear-memory byte arrays to MLE `Uint8Array`
arguments, recreates views after allocation growth, preserves the exact
32-byte command and canonical-state contracts, and rechecks all six i64
reductions inside Oracle before timing. Loading and ranking this bridge remain
forbidden until the serializer workaround reaches its parity terminal.

`install-mle-rank.sh` enforces that terminal, binds the exact bundle hash,
stages both generated engine and bridge through in-database SHA-256 checks,
and installs them under isolated `doom_wasm2js_rank_*` names. Its install
smoke reruns all six lowering reductions in Oracle. The loader refuses every
non-workaround artifact and every concurrent evidence gate; it never replaces
`doom_teavm_simulation` or any production call specification.

`benchmark-mle-rank.sql` then performs an untimed 100-tic Oracle execution
whose canonical SHA must match the Node/OJVM parity record, followed by the
exact 5,250-tic stream with per-tic wall-clock samples. The comparator chooses
the peak and quiet windows from the de-CPS baseline and compares those same
windows: at least 2x in both advances to the full parity battery, below 1.5x
in either rejects the shape, and the 1.5–2x middle escalates without silently
changing the acceptance policy.

`run-mle-rank.sh` is the sole execution path. It requires explicit opt-in,
an inactive match set and quiet host, parks the retained pool, brackets the
run with Oracle alert attribution, proves Node/MLE canonical SHA equality,
and verifies the production `doom_teavm_simulation` metadata is byte-identical
before and after the isolated experiment. Cleanup is verified before the pool
is restored.
