# T12.2 independent evaluator

This fail-closed evaluator accepts profile-guided optimization only after the
approved T12.1 baseline is complete. Each attempted change is numbered and
hash-chained in an append-only journal before it is measured. Every attempt must
name the bottleneck identified by the immediately preceding measured result,
carry a technically distinct allowed change class and source-diff digest, retain
the public decompressed schema and approved golden manifest byte-for-byte, and
pass the complete correctness and required-mutation gates. Performance
regressions are evidence, not failed or deleted experiments.

Each attempt repeats the fixed Section 6.6 replay: 300 frames at 320x200, 30 warm
and 270 externally measured. The stopping rule is exact: the final two
technically distinct attempts must each improve median end-to-end latency by less
than five percent against the best accepted state available before that attempt.
Human review must affirm that both changes targeted the measured bottleneck and
were not chosen merely to end the loop. The journal must end at that point.

The selected best revision is then replayed independently on both local and
cloud stacks. The final report publishes p50/p95 latency and the highest directly
verified effective FPS from raw samples for each environment, labels neither as
an estimate, and makes no portable performance claim. Raw samples, attempt
reports, diffs, test results, journal, final verification and report are separate
content-addressed safe-path artifacts. Live execution remains blocked until
T12.1 and the cloud gate pass; evaluator self-tests do not inspect production or
start a database.
