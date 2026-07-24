# Hidden MLE compilation diagnostic — Oracle 26ai Free

Classification: `DIAGNOSTIC_NOT_GATE`

This probe tests undocumented, session-scoped Oracle MLE compilation controls.
It does not authorize them for production, persist them at system level, or
change the pinned e485 authority.

Oracle's alert log records that the hidden parameters were set without the
diagnostics privilege. That warning is preserved as further evidence that
these switches are unsupported diagnostics, not a production configuration.

The local Oracle AI Database 26ai Free build reports runtime compilation and
separate compilation isolates enabled, while immediate and synchronous
compilation are disabled by default. The previously reported orphaned probe
session (SID 42 / serial 60842) was absent before this matrix. Every matrix
cell used a fresh session, verified cleanup afterward, and the retained
production pool was restored.

## Arithmetic kernel

The exact deterministic integer kernel ran 40 one-million-iteration samples:

| Cell | Settings | Steady p50 | Steady p95 | Result |
| --- | --- | ---: | ---: | --- |
| default async | defaults | 373.169 ns/iteration | 430.130 | interpreted |
| immediate | `_mle_compile_immediately=TRUE` | 372.823 | 419.155 | interpreted |
| immediate + sync + fatal | immediate plus synchronous fatal compilation | 2.792 | 3.472 | compiled |

The compiled cell paid 5,537.552 ms on its first call, transitioned through
58.841 and 258.041 ns/iteration, then stabilized between 2.602 and
3.592 ns/iteration. This is more than 100x faster than the interpreted
steady state and decisively clears the standing 15 ns/iteration threshold.
It proves that this Free build contains a working optimizing MLE compiler;
the former interpreter ceiling is policy/generated-shape dependent rather
than an absolute engine limit.

`_mle_compile_immediately` alone did not compile the kernel. Synchronous
coordination was required in this experiment.

## Full e485 production shape

Two production-shaped attempts were preserved as void diagnostics:

1. Immediate + synchronous compilation spent more than five minutes compiling
   cold initialization without entering the 500-tic stream. Interrupting that
   cell left SID 212 / serial 56005 parked in MLE; it was killed by full
   incarnation and the incident is recorded.
2. Synchronous hot-threshold compilation with
   `compile_immediately=FALSE` passed cold setup but then remained in
   `MLE park` for more than 13 minutes. The tagged Oracle session consumed
   little CPU and compiler-worker processes were sleeping, so this was
   classified as a compilation hang rather than a slow successful sample.
   Tagged cleanup removed the session and both warm slots returned to
   `READY`.

Neither attempt emitted a ticker terminal marker, so neither is performance
evidence for the full engine. The small-kernel JIT result reopens the
acceleration branch, but the current large TeaVM/CPS-generated method shape
cannot yet consume it operationally.

## Decision

The next structural priority is to remove TeaVM CPS/blocking contamination and
split pathological generated methods, then repeat the direct MLE ticker rank
cell. This also aligns with the legacy-Wasm compiler failure in
`BoomLevelLoader.P_LoadSegs`, which currently fails inside TeaVM's
`CoroutineTransformation`. If the reshaped artifact compiles, its exact
quiet and peak command-stream windows—not this arithmetic kernel—decide
whether JIT or wasm2js can satisfy 35 Hz.
