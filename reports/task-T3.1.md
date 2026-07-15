# T3.1 implementation report

Status: **PASS**.

Route: `T3.1-IMPL | Terra | medium | attempt 1`.

## Delivered

- Constrained static map, asset, engine-definition, configuration, and dynamic
  ownership tables from PLAN Section 5, with deterministic keys and explicit
  primary, foreign, unique, range, and not-null constraints.
- Ordered, manifest-hash-verified seed loading for all 537 generated SQL files.
  The dense `AT(A,X,Y,C)` relation retains null/range checks during ingestion;
  its primary and asset foreign keys are bulk-built and validated after load.
- Strict deterministic decoding of checked `AT` seed rows to set-based
  `JSON_TABLE` inserts. Checked seed bytes remain unchanged, every decoded row
  is counted, and a complete rerun drops and rebuilds the owned schema.
- Configuration, engine definitions, grants, the T3.2-facing vertex/linedef
  interface, bounded schema drop, and ordered bootstrap integration.
- Static and fresh-volume Oracle checks for exact manifest counts, two
  intentional invalid references, constraint validation, forbidden production
  object names, and complete-process idempotence.

## Verification

Canonical command:

```text
./verify.sh task T3.1
```

Result on a fresh isolated Oracle volume, including two complete bootstraps:

```text
PASS T3.1-static (24/24 assertions)
PASS T3.1-live (13/13 assertions)
PASS T3.1 (37/37 assertions)
```

The exact loaded fingerprint was
`292|1196|1175|1829|182|2057|682|681|4141|7528|566|854|3040239`
on both runs. Both deliberate bad foreign keys failed with `ORA-02291`; all
production constraints were enabled and validated, and no evaluator,
reference, or golden object existed in the production schema.

The final stable-tree verification also included the subsequently added T3.2
Spatial bootstrap entry, proving that the T3.1 rebuild remains idempotent after
the next ordered migration.
