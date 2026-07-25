# VOIDED de-CPS Node profile build

Classification: `VOIDED_HARNESS_EXTRACTOR_KIND`.

The unminified profile artifact build completed, but the runner passed the
numeric `bytes` field to a SHA-256-only extractor mode. The extractor
correctly rejected the value before the artifact copy, command-stream
capture, or CPU profile began. The raw build log is preserved unchanged
and is not profile evidence.

The parser now has an adversarially self-tested positive-integer field
kind, and immutable profile evidence tags permit a clean `v2` rerun.
