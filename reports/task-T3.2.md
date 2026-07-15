# T3.2 implementation report

Status: **PASS**.

Route: `T3.2-IMPL | Terra | medium | attempt 1`.

## Deliverables

- `sql/spatial/010_linedef_geometry.sql` materializes every directed linedef as
  a canonical null-SRID two-point `SDO_GEOMETRY`.
- `LENGTH`, `DIRECTION_X`, and `DIRECTION_Y` are stable Oracle `NUMBER` values
  rounded to twelve decimal places after calculating the unrounded Euclidean
  norm.
- `USER_SDO_GEOM_METADATA` is regenerated after seed load from live vertex
  `MIN/MAX` values expanded by the live `FAR_DISTANCE + PLAYER_RADIUS` values.
- `DOOM_LINEDEF_SIDX` is an `MDSYS.SPATIAL_INDEX_V2` domain R-tree and the
  deployment verifies the broad-filter plus exact-predicate query path.
- The ordered bootstrap runs Spatial deployment after T3.1 seed finalization;
  its safe path allowlist includes `sql/spatial`.
- Root verification now exposes only the approved `task T3.2` route. Existing
  T2.4, P2, and T3.1 routes are unchanged.

## Verification

The corrected evaluator baseline was explicitly approved and frozen with
manifest SHA-256
`d617cdd9e5f8a36606d6606d6c61a514f46b3b5545f4526e48361a1c04208050`.
All thirteen inherited and T3.2 approved hashes matched before and after the
implementation run.

```text
PASS T3.2 approved integrity (13/13)
PASS T3.2-EVAL-SELF-CHECK (58/58 fixture-contract assertions)
PASS T3.2-SOURCE-AUDIT (1 SQL files)
PASS T3.2-ORACLE-PRODUCTION
PASS T3.2-ORACLE-MINI-MAP (6/6 assertions)
PASS T3.2 (136/136 assertions)
PASS T3.1-static (24/24 assertions)
PASS T3.1-live (13/13 assertions)
PASS T3.1 (37/37 assertions)
```

The approved evaluator provides fourteen semantic mutation specifications and
checks their fixed contracts in its self-check and live assertion paths. It
does not prescribe a separate implementation-side mutation runner, so none was
invented for this task.

The production-isolation audit found no evaluator, golden, expected-output,
mutation-specification, or test-id references in the Spatial SQL or its
bootstrap integration. No evaluator file was modified during implementation.
