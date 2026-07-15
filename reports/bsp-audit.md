# BSP behavior source audit

## Scope

This audit grounds only externally observable point-to-subsector behavior. No
source code, lookup table, engine state table, control flow, or generated data
from a Doom engine is included in production. The evaluator reference is an
independent implementation of PLAN Section 1.2 over the pinned Freedoom map
lumps.

## Compared behavior

Chocolate Doom's `R_PointOnSide` identifies side 0 as front and side 1 as back.
Its vertical and horizontal partitions use separate sign-sensitive branches and
put axis equality in the `<=` branch. Its general branch returns front only for
the strict comparison corresponding to the plan's positive cross; equality is
back. `R_PointInSubsector` begins at `numnodes - 1`, repeatedly indexes the child
selected by the side predicate, stops when the subsector flag is set, and masks
that flag from the leaf index.

Primary research source: [Chocolate Doom `src/doom/r_main.c`,
`R_PointOnSide` and `R_PointInSubsector`](https://github.com/chocolate-doom/chocolate-doom/blob/master/src/doom/r_main.c).
The WAD child/subsector layout was cross-checked against the public
[Doom map format specification](https://www.gamers.org/docs/FAQ/DOOM.FAQ.Specs.Chapters.4.html).

## Reconciliation with the project contract

The evaluator implements the plan's integer-coordinate expression directly:

```text
cross = (px - node_x) * node_dy - (py - node_y) * node_dx
side 0 iff cross > 0; otherwise side 1
```

It uses the plan's explicit axis cases before this expression. It deliberately
does not reproduce Chocolate Doom fixed-point sign-bit optimizations because the
project contract defines relational NUMBER arithmetic and observable side
results, not translated engine control flow. The root, high-bit leaf marker,
and leaf masking agree. Sector ownership is independently decoded from the
first seg and its facing sidedef as required by the plan.

## Three-way evidence

1. Fourteen hand-authored cases cover vertical/horizontal positive and negative
   directions, left/right or above/below points, both non-axis cross signs, and
   equality at the origin and elsewhere on a partition.
2. The pinned-WAD reference probes player spawn and all 292 THINGS coordinates.
   Spawn resolves to subsector 115, sector 140, at depth 8. The 292 paths range
   from depth 5 through 25.
3. Live Oracle checks invoke the approved SQL macro with binds and compare the
   canonical ordered result document, plus root-boundary and out-of-bounds
   probes. A source audit separately requires `CONNECT BY` and rejects fixture
   coordinates, expected hashes, procedural loops, recursive WITH, and dynamic
   SQL in production BSP files.

The evaluator self-check recomputes these observations from the pinned WAD; it
does not trust production seed output or implementation reports.
