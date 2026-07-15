# T12.2 source-first implementation status

Status: **OPTIMIZATION LEDGER, CAPTURE SCHEMA, VERIFY/PUBLISH DRIVER, AND
SYNTHETIC TAMPER UNITS COMPLETE; LIVE PROFILE LOOP INTENTIONALLY PARKED**.

The corrected frozen evaluator manifest is byte-identical at
`3bd2feea88d0c25e6a8c6e87f2b359b5251a1c4c6cc63d27686f92f677b7dc0a`.
This implementation did not edit evaluator sources or manifests, shared
routing, database objects, cloud resources, or unfinished optimized systems.
It performed no database, HTTP, cloud, or network operation and records no
latency or FPS claim.

Delivered production sources:

- `scripts/run-performance-optimization.mjs`: fail-closed publication and
  verify-only driver for externally captured 300-frame attempts and independent
  final local/cloud replays. It derives p50/p95, effective FPS, stage medians,
  dominant bottlenecks, improvement percentages, accept/rollback decisions and
  the exact Section 6.6 stop rather than accepting copied summaries.
- `scripts/performance/t12.2-ledger.mjs`: fixed contract, append-only chained
  journal validation, unique allowed-diff enforcement, schema/golden invariance,
  complete correctness/mutation gates, safe artifact paths, recursive redaction,
  atomic writes and content/provenance verification.
- `scripts/performance/t12.2-capture-plan.schema.json`: finite live input
  contract with approved baseline ancestry, external samples and reviewed
  attempt metadata. Correctness/mutation payloads exclude their digest; the
  driver hashes their finite bytes and stores the external digest in evidence.
- `tests/verify-performance-optimization-unit.mjs`: synthetic statistics,
  stop-rule, journal, invariance, provenance, redaction and artifact-tamper
  tests. Its temporary evidence passes both production verification and the
  corrected frozen evaluator, and is deleted afterward.

Executed evidence:

```text
PASS T12.2-SCHEMA-PARSE
PASS T12.2-PRODUCTION-UNITS (ledger, profiling, stop rule, invariance, provenance, redaction)
PASS T12.2-EVAL-SELF-CHECK (14/14 fixture-contract assertions)
PASS T12.2-EVAL-MUTATION-SELF-CHECK (30/30 isolated mutations killed)
PASS T12.2-SOURCE-AUDIT (optimization driver contract present)
```

Live acceptance remains blocked by design until T12.1 and T11.2 provide the
approved real baseline/replay and working local/cloud stacks. It additionally
requires actual reviewed source changes targeting each measured dominant
bottleneck, full correctness and mutation machine reports after every attempt,
and independent final local/cloud replay samples. The journal must preserve
regressions and stop at the first two consecutive technically distinct reviewed
attempts below five percent. Only that evidence may publish direct local/cloud
p50, p95 and FPS values; synthetic units are never accepted as measurements.
