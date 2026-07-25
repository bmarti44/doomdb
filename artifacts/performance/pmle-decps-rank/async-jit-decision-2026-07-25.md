# Final-artifact default-async JIT decision — 2026-07-25

Verdict: **LANDING_SIGNAL**, not production qualification.

The pinned `5ec18cbe…` authority completed two consecutive 5,250-tic passes
in one fresh default-configuration MLE session. No unsupported engine
parameter was set. The warm pool was parked, no match was active, the host
was quiet, the Oracle alert window closed with zero incidents, the production
module was restored, and both retained slots returned `READY`.

Window 701–800 crossed the predeclared landing threshold on both clocks:

- corrected SYSTIMESTAMP per-tic median: 86.748 -> 64.626 ms, **25.501%**;
- authoritative 100-tic GET_TIME throughput: **41.079%** improvement.

No other window crossed 20% on both clocks. Compiler-thread census samples
found no thread name matching `mle|graal|truffle|compiler`; that is secondary
evidence only and does not refute compilation in unnamed or transient
threads.

Four of 10,500 tic samples were clock suspects (0.038%). They were excluded
symmetrically, below the predeclared 0.5% cap. The raw pair is unchanged.
The runner's original comparison failed closed because its regex omitted
negative SYSTIMESTAMP values. Two subsequent offline comparator iterations
also failed their own self-tests or used per-tic quantized GET_TIME values;
their empty/diagnostic outputs are retained as `comparison-void-*`. The
accepted `comparison-v5.log` uses the shared SQLcl wrap normalizer, validates
all 10,500 tic rows and 106 monotonic windows, checks the recorded
`clock_suspect` classification, and requires a >=20% result on both corrected
wall median and window GET_TIME throughput.

This result reopens the local default-async compiler branch for a
reproducibility/persistence experiment. It does not authorize hidden
parameters, claim 35 Hz, or replace the OCI arithmetic verdict.

Primary evidence:

- `default-async-pair-5ec18cbe4cff-5250-final-artifact-2026-07-25.log`
- `default-async-pair-5ec18cbe4cff-5250-final-artifact-2026-07-25-comparison-v5.log`
- `default-async-pair-5ec18cbe4cff-5250-final-artifact-2026-07-25-compiler-threads.log`
