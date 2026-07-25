# VOIDED long-flag cast benchmark — v2

Classification: `VOIDED_HARNESS_CLEANUP_PLACEMENT_REPEAT`.

The attempted cleanup move again matched the preflight `end; /` block rather
than the benchmark terminal and therefore still ran before call-spec creation.
The database rejected the missing object before timing. The raw log is
preserved and is not evidence. The corrected source now pins cleanup
immediately after the unique `PMLE_LONG_FLAG_CAST` benchmark block.
