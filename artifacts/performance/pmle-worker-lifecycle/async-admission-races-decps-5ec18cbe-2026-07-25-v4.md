# VOIDED async-admission run — v4

Classification: `VOIDED_HARNESS_CONTENTION`.

The aggregate runner began while the immediately preceding focused
dispatch-death test was still rebuilding the retained warm pool. Both
harnesses attempted pool lifecycle work under the edition-enforced
two-running-session limit, invalidating the host-quiescence claim. The
raw log is preserved unchanged. No result from this run is used as gate
evidence; the clean `v5` rerun is authoritative.
