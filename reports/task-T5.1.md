# T5.1 portal and sector timeline implementation

Status: **PASS**

Route: `T5.1-IMPL | Sol | max | attempt 1`.

The approved evaluator manifest remained byte-identical at
`9f917fa0d9557a3a27540ce8184de66feea9860e68ffea592a8b99b3d4db407a`.
No evaluator source, fixture, expectation, mutation, test ID, or reviewed golden
was changed.

## Implementation

`sql/render/r2/010_portal_timeline.sql` adds the two reviewed session-bound table
SQL macros:

- `DOOM_R2_PORTAL_HITS` retains every inherited analytic R1 intersection and
  classifies active, incompatible, transitioning, closed, and post-termination
  rows in exact `(hit_t, linedef_id, seg_id, facing_side)` order.
- `DOOM_R2_SECTOR_INTERVALS` emits contiguous zero-based active-sector intervals,
  including deliberate zero-length tie intervals and the configured final far
  interval for unterminated rays.

Facing and opposite live heights come from `SECTOR_STATE`, with immutable
`DOOM_MAP_SECTOR` heights as the initial-session fallback. Scalar
`GREATEST`/`LEAST` produce portal openings; directed height differences produce
lower and upper pieces. `MATCH_RECOGNIZE` performs the set-based state walk with
no procedural wall loop, recursive render CTE, dynamic SQL, early hit-depth
rounding, or evaluator coupling.

The first fresh compile exposed pinned Oracle's `ORA-64630` prohibition on a
table SQL macro inside a `WITH` clause. Production was corrected without touching
the evaluator: the per-ray start sector is now the stable first-facing sector in
the already ordered all-hit stream. The replacement is analytic, avoids nested
macro expansion, and preserves overlap and vertex-tie semantics.

Bootstrap installs R2 after R1. Teardown drops R2 macros and dependent views
before R1. `./verify.sh task T5.1` routes the frozen suite plus a five-assertion
live dynamic-height probe. Because dynamic schema installation invalidates the
already-created R1 pixel view through Oracle dependency metadata, the final R2
render stage explicitly recompiles that unchanged view; the final clean bootstrap
ended with zero invalid schema objects.

## Acceptance evidence

```text
PASS T5.1-EVAL-SELF-CHECK (97/97 fixture-contract assertions)
PASS T5.1-EVAL-MUTATION-SELF-CHECK (18/18 isolated mutations killed)
PASS T5.1-SOURCE-AUDIT (1 SQL files; complete hits, dynamic heights, analytic ordering)
PASS T5.1-ORACLE-PRODUCTION
PASS T5.1-VISIBLE (20/20 test ids, 674/674 declared assertions)
PASS T5.1-DYNAMIC-SECTOR-HEIGHTS (5/5 assertions)
```

The isolated `doomdb-t51-test` stack used host port 25351 and a fresh named
volume; the dashboard database and ORDS remained untouched. The successful full
bootstrap loaded all 537 deterministic seed files and completed 21 ordered SQL
entries in 138.75 seconds. The frozen visible suite completed in 18.63 seconds;
the full routed suite including dynamic-height mutation completed in 22.99
seconds. Performance has no numeric acceptance threshold, and these complete
external timings were reviewed as suitable for the current renderer stage.

Regression evidence:

```text
PASS T4.1-VISIBLE (18/18 test ids, 1296/1296 declared assertions)
PASS T6.4-VISIBLE (28/28 test ids, 848/848 declared assertions)
PASS T1.2-static (10/10 assertions)
PASS T3.1-static (24/24 assertions)
PASS secret ignore audit (8 ignored paths, 3 visible templates, no tracked secret-like paths)
PASS T0.4 (8/8 assertions)
PASS T0.4-EVALUATOR-SELF-TEST (13/13 attacks rejected)
PASS T5.1 frozen manifest identity
PASS final schema validity (0 invalid objects)
```
