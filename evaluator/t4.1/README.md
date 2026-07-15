# T4.1 independent ray/frustum/intersection evaluator candidate

This evaluator-owned directory is pending explicit user approval. It freezes the
R1 geometry oracle before any T4.1 production SQL is authored. Once approved,
the implementation context may execute but not edit these files.

## Reviewed production interface

T4.1 supplies three standalone table SQL macros, each taking a bound session
token and reading that session's current player row:

```sql
DOOM_R1_RAYS(p_session VARCHAR2)
DOOM_R1_HITS(p_session VARCHAR2)
DOOM_R1_NEAREST(p_session VARCHAR2)
```

`DOOM_R1_RAYS` returns one row for each `COLUMN_NO` 0..319 plus player pose,
angle radians, direction, camera plane, `CAM_X`, and unnormalized `RAY_X/RAY_Y`.
`DOOM_R1_HITS` returns every accepted seg intersection with determinant,
`HIT_T`, `HIT_U`, linedef/seg ids, facing side and sidedef, opposite sidedef,
solid flag, and `HIT_ORDINAL`. `DOOM_R1_NEAREST` has the same identifying and
numeric hit columns but exactly one nearest solid row per column. Ordering is
`(hit_t, linedef_id, seg_id, facing_side)`.

The implementation constructs a pose/FOV/far-distance frustum geometry, uses
the existing `DOOM_LINEDEF_SIDX` through `SDO_FILTER` only as an MBR candidate
stage, joins candidates to E1M1 segs, and applies Appendix B analytically.
`ABS(D)<1e-12`, `t<=1e-9`, and `u` outside inclusive `[0,1]` are rejected.
Rays are not normalized or rounded. A line is solid when one side is absent or
the static vertical opening between its two sectors is non-positive.

## Independent oracle and fixtures

`reference.mjs` reads the pinned WAD directly with evaluator-local structured
binary decoding. It imports no production parser, seed, manifest, BSP, Spatial,
or renderer implementation. It generates all 320 half-pixel rays and evaluates
all 2,057 segs using the plan equations.

The candidate covers hand perpendicular/oblique/parallel/behind/endpoint and
vertex-tie geometry; a jointly translated mini-map; a mirrored mini-map and
reflected view; and three E1M1 poses at east, north, and west headings. Numeric
diagnostics use absolute `t <= 1e-6`, `u <= 1e-9`, and ray-component `1e-12`
tolerances. Counts, columns, ids, facing, solid selection, canonical documents,
and SHA-256 values are exact.

Sixteen isolated semantic mutations are named in `mutation-specs.json`. The
source audit rejects fixture-specific poses, expected hashes, evaluator reads,
procedural ray/wall loops, dynamic SQL, early rounding, or caller inspection.
The live runner intentionally remains red until approved production macros exist.

## Candidate commands

```sh
node evaluator/t4.1/self-check.mjs
node evaluator/t4.1/mutation-self-check.mjs
# after implementation:
evaluator/t4.1/run-visible.sh
```
