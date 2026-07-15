# T10.1 source-first implementation

Status: **PARKED pending the accepted T8/T9 production stack and live Oracle +
ORDS acceptance**.

Implemented the task-owned production sources:

- `sql/rest/010_doom_api.sql` defines the exact seven-member, non-overloaded
  definer-rights package surface. Private helpers own UTF-8/gzip transport,
  canonical 320x200 RLE payload construction, frame hashing, session expiry and
  capacity, crypto tokens, retry-cache bytes, rollback/error mapping, exact
  asset selection, save/load, and bounded replay orchestration.
- `sql/rest/020_ords_enable.sql` defines a non-updatable, secret-free health view
  and publishes exactly `DOOM_API` and `PUBLIC_HEALTH` through object AutoREST.
  It defines no custom module, template, or handler and grants no base table.

Source-first checks passed:

```text
PASS T10.1-SOURCE-AUDIT (exact package/exposure/error/gzip policy)
PASS T8.2-SOURCE-AUDIT (fixed public workflow surface, anti-coupling policy)
PASS T8.1-SOURCE-POLICY-SELF-CHECK (5 present production surfaces)
PASS T10.1-EVAL-SELF-CHECK (38/38 fixture-contract assertions)
PASS T10.1-EVAL-MUTATION-SELF-CHECK (24/24 isolated mutations killed)
PASS git diff --check (task-owned SQL)
```

The sources intentionally reference the final history, audio provenance, R2
pixel, and staged T7 runtime columns. Per the task routing constraint, no
Oracle/ORDS stack was started and no shared bootstrap, drop, verification, or
routing file was edited. Live package compilation, metadata, HTTP, concurrency,
canonical payload, cursor reuse, and asset acceptance remain mandatory after
the upstream stack is integrated. In particular, the integration turn must
verify that the completed T8 frame producer persists per-tic frame hashes for
multi-command batches and replay before running the frozen T10.1 live gate.
