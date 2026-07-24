# De-CPS authority rank — 2026-07-24

Verdict: **the source-level de-CPS candidate is accepted for full promotion
gating, but is not promoted yet.** Removing the authoritative build's reachable
`Thread.sleep`/`WaitVBL` path changes no canonical state and improves the full
preserved deathmatch route from 6.002 to 19.788 tics/second. Quiet windows now
clear 35 Hz; peak-combat windows do not.

## Candidate and correctness

- candidate JavaScript: 1,081,331 bytes, SHA-256
  `2848ef7a8dc4799de7faa46bcf304f4ac3d351da97be94b144a53f3300607f29`;
- candidate input JAR SHA-256:
  `c6d26633316b7a6251e79b9013bfb16ca877e2d93642ebbaba17bfc66c8861a4`;
- source patch SHA-256:
  `6092f86c9c70a20be9a011db34e1dd75669e7f2f0b0f3da76d702f57c5866e29`;
- TeaVM 0.15.0, JavaScript backend, `ADVANCED`, minification enabled;
- pinned oracle: `e485b9418e5845b78e9e1593918d8bbb6f3c441c41a43cb8f3faf046e595148b`;
- exact stream SHA-256:
  `fa7637570c30d3a33cbf8456e98268890e9f5bd82f5ba39fd7f69b139ddc4085`.

The Node differential compared the complete canonical byte stream at tic zero
and after every one of 5,250 live deathmatch tics. All 5,251 comparisons pass;
the terminal 75,818-byte canonical state has SHA-256
`b3f667c9395455fd42e31586dd79006fc9c091132cb09c8b1f4627a7d93a9907`.
This proves the pacing call was outside authoritative semantics on the accepted
stream. It does not replace the canonical, co-op, membership, ledger, recovery,
and lifecycle batteries required before promotion.

The generated module is 90,565 bytes smaller than pinned `e485…`. The
authoritative native-thread runner disappears and generated suspension call
sites fall from three to two. The two retained runtime sites implement TeaVM
sleep and XMLHttpRequest support; no generated native-thread runner reaches
the authoritative exports.

## Direct Oracle MLE result

Both the historical ADVANCED baseline and this candidate replay the exact same
5,250-tic stream with the retained pool parked and no active match, under the
edition-enforced Oracle Free envelope (`CPU_COUNT=2`, PDB utilization limit
50, running-session limit 2).

| Metric | ADVANCED baseline | de-CPS candidate | Effect |
| --- | ---: | ---: | ---: |
| Whole-route throughput | 6.002 tics/s | 19.788 tics/s | 3.297x |
| Whole-route p50 | 148.208 ms | 36.640 ms | 4.045x |
| Whole-route p95 | 296.126 ms | 142.665 ms | 2.076x |
| Whole-route p99 | 391.336 ms | 196.411 ms | 1.993x |
| Maximum | 591.380 ms | 376.974 ms | 1.569x |
| Cold initialization | 43,800.991 ms | 40,568.874 ms | 1.080x |
| Restored 500-tic prefix p50 | 264.913 ms | 109.791 ms | 2.413x |

The 100-tic window speedup is density-shaped. Tics 1–700 improve 2.35–3.04x.
The late quiet plateau at tics 4,400–5,250 improves 10.64–12.06x: its
candidate windows take approximately 10.0–11.3 ms/tic and therefore clear the
35 Hz slot. Peak windows still take approximately 106–141 ms/tic, so the
candidate does not satisfy the live contract under combat density. No 30 FPS
claim is made.

The clean full-stream log has SHA-256
`61efa443e39dbfc4c9fd5f7a7d78f75d683f49e5aeecc2a9589ca6afb9cc819c`.
The shorter 500-tic preview independently measured 8.703 tics/s and
109.225/213.580 ms p50/p95.

## Hidden compilation

The hidden controls remain diagnostic-only and disabled in production. Two
candidate cells were attempted:

1. immediate + synchronous + fatal compilation;
2. synchronous + fatal compilation with immediate compilation disabled.

Each remained in `MLE park` for more than five minutes without reaching
initialization or a replay terminal marker. Each tagged session was killed by
full SID/serial, the pinned `e485…` database module was restored through its
SHA fence, both warm slots returned to `READY`, and the later full interpreter
cell's alert window contained no new Oracle error. The kill records report
`Result = ORA-00000`, Oracle's success code; the alert scanner now excludes
that code while continuing to fail on every nonzero `ORA-nnnnn`.

These two cells are void diagnostics, not performance evidence. De-CPS solved
the interpreter's ticker wrapper cost but did not make Oracle's undocumented
whole-module compilation path operational.

## Decision

The candidate has crossed the structural-promotion threshold: exact accepted
stream, 3.297x full-route throughput, and more than 10x improvement in quiet
windows. Its Oracle promotion battery now passes:

- four-player 330-tic canonical differential;
- two-player 762-tic co-op differential with deep equality every tic;
- leave/neutral/checkpoint/rejoin membership recovery through tic 100, bound
  to candidate `2848…` and OJVM oracle `2a102…`.

The exhaustive 13,272-tic every-tic ledger, recovery/lifecycle gates, and final
soak still remain before any pin or production deployment changes. The next
performance work must target peak monster AI/movement/sight cost; hidden JIT is
not a usable fallback on this artifact, and the rejected Binaryen 131 wasm2js
output remains closed until its `long` high-word corruption is fixed.
