# T12.1 source-first implementation status

Status: **SOURCE, COLLECTOR CONTRACT, SCHEMAS, AND SYNTHETIC ARTIFACT UNITS
COMPLETE; LIVE ACCEPTANCE BLOCKED BY UPSTREAM T11.2 AND REAL REPLAY/STACKS**.

The frozen evaluator manifest remains byte-identical at
`2fcdd0f204ea7a248f29970be8a6ce56f6a18b3e3f4ff4bd2c10a9c5a7d1cd93`.
No evaluator, manifest, shared routing, database, cloud deployment, or live
benchmark was changed or started by this implementation task.

Delivered production sources:

- `scripts/verify-performance-baseline.mjs`: independent external 300-frame
  HTTP timing, transport decode/blit timing, payload identity/size ledger,
  database-observation merge, report derivation, atomic publication, and
  verify-only artifact validation.
- `scripts/performance/t12.1-evidence.mjs`: fixed Section 6.6 contract,
  programmatic schema validation, p50/p95/FPS derivation, cursor/shape checks,
  recursive redaction, safe paths, hashes, and atomic writes.
- `scripts/performance/t12.1-collector.mjs`: bounded stdin/stdout adapter for
  credential-private collection of `ALLSTATS LAST`, redacted `V$SQL`, bound
  shapes, and out-of-band stage timers.
- JSON schemas for the evidence envelope and collector output, plus adapter
  documentation.
- `tests/verify-performance-baseline-unit.mjs`: temporary synthetic evidence
  and artifact tests. Synthetic data is never published as T12.1 evidence.

Executed evidence:

```text
PASS T12.1-PRODUCTION-UNITS (replay, observations, artifacts, redaction, collector protocol)
PASS T12.1-EVAL-SELF-CHECK (15/15 fixture-contract assertions)
PASS T12.1-EVAL-MUTATION-SELF-CHECK (24/24 isolated mutations killed)
PASS T12.1-SOURCE-AUDIT (baseline driver contract present)
```

The production unit fixture also passes the frozen evaluator's
`validate-evidence.mjs`, then proves rejection of shape drift, a payload timer
leak, a secret-bearing key, a changed artifact digest, and a credential-bearing
collector argv.

Live work remains intentionally parked. It requires the accepted T11.2 S3 and
Autonomous Database browser gate, the reviewed replay with the frozen identity,
live local and cloud endpoints, and credential-private collector adapters. Only
those real systems can produce the accepted baseline; this task records no FPS,
latency, plan, cursor, payload, or stage measurement claim.
