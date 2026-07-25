# VOIDED de-CPS Node profile build — v2

Classification: `VOIDED_HARNESS_STREAM_HASH_ENCODING`.

The build and typed build-marker validation completed. Before the CPU
profile began, the runner compared the fixture's binary expanded-stream
SHA-256 with a SHA-256 over the SQL export's textual rows. The complete
5,250-row database export therefore failed a comparison between two
different encodings.

The raw build log and generated debug artifact are preserved. Neither is
cited as CPU-profile evidence. The `v3` runner computes the canonical
digest over each membership byte followed by its 32 command bytes and
self-tests malformed rows, tic gaps, membership range, and payload size
before execution.
