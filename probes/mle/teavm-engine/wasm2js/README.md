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
