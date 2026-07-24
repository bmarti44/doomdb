# wasm2js output policy

The spike's source, pinned patches, build scripts, final conversion recipe, and
dated evidence records are tracked. Maven/TeaVM/Binaryen `target/` trees and
intermediate Wasm/JavaScript products are generated outputs and are ignored.

A generated artifact is promoted only by copying its exact bytes into the
normal pinned authority/presentation artifact path and recording its byte
length, SHA-256, toolchain versions, build flags, input-JAR provenance, parity
result, and direct Oracle MLE rank result. This avoids treating an in-progress
compiler work directory as deployable evidence.
