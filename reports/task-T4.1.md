# T4.1 rays, frustum, candidates, and intersections report

Status: **PASS**.

## Delivered

- `sql/render/r1/010_rays_intersections.sql` provides the approved
  `DOOM_R1_RAYS`, `DOOM_R1_HITS`, and `DOOM_R1_NEAREST` table SQL macros.
- Shared relational views keep camera and hit behavior single-sourced while
  each public macro applies its bound session parameter directly. This avoids
  unsupported nested Oracle SQL-macro formal-parameter expansion.
- Exactly 320 half-pixel, unnormalized rays derive from the current session
  player. Oracle `BINARY_DOUBLE` camera trigonometry matches the approved
  TypeScript double oracle at endpoint boundaries without early rounding.
- A pose/FOV/configured-distance polygon drives `SDO_FILTER` against the Spatial
  index. Candidate linedefs expand to WAD segs, then exact determinant, strict
  positive `t`, and inclusive `u` predicates determine every accepted hit.
- Facing sidedefs derive from player position and directed linedefs. Static
  solids are one-sided lines or two-sided lines with non-positive vertical
  opening. Hit order is `(t, linedef_id, seg_id, facing_side)`.
- Bootstrap and teardown include the R1 objects and preserve all earlier routes.
- `sql/render/r1/diagnostics/010_dashboard_rays.sql` supplies a bounded,
  read-only dashboard payload from real database rays and hits. Its contract is
  documented in `reports/t4.1-dashboard-diagnostic.md`.

## Canonical evidence

The final verification used a fresh isolated Compose project, the pinned Oracle
image, a new volume, and production 2 CPU/2 GiB limits. It loaded all 537 seed
files and completed the 15-entry bootstrap.

```text
BOOTSTRAP COMPLETE (15 files)
PASS T4.1-EVAL-SELF-CHECK (99/99 fixture-contract assertions)
PASS T4.1-EVAL-MUTATION-SELF-CHECK (16/16 isolated mutations killed)
PASS T4.1-SOURCE-AUDIT (1 SQL files)
PASS T4.1-ORACLE-PRODUCTION
PASS T4.1-VISIBLE (18/18 test ids, 1296/1296 declared assertions)
PASS T4.1-LIVE-ISOLATED (1296/1296 declared assertions; 16/16 mutation witnesses)
```

The exact pose totals are spawn east 12,558 hits, spawn north 4,141, and central
west 4,552, with 320 nearest solids at each pose. All twelve nearest-hit
numeric/id/facing probes met the frozen tolerances.

## Regression, integrity, and policy evidence

```text
PASS T3.2 (136/136 assertions)
PASS T3.3-VISIBLE (15/15 test ids, 455/455 declared assertions)
PASS T3.4-VISIBLE (17/17 test ids, 3300/3300 declared assertions)
PASS T3.1-static (24/24 assertions)
PASS T1.3 (12/12 assertions)
PASS secret ignore audit (8 ignored paths, 3 visible templates, no tracked secret-like paths)
PASS production isolation audit
```

The corrected evaluator remained immutable during the final run:

```text
158c94e68220bbea4809f8688cb94549b07423655aaa4017b6fcaf3703c28ae6  evaluator/integrity.pending-T4.1.json
0854616c47f6f27e9813596862ac7e63a6dfc925f1e9718849de950aae215d79  evaluator/t4.1/oracle-production.sql
```

The isolated container, network, temporary credentials, and volume were removed
after success. No secret value was written to source or verification output.
