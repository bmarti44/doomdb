# T3.3 independent BSP-location evaluator candidate

This evaluator-owned directory is pending explicit user approval. It fixes the
visible BSP oracle before any T3.3 production SQL is authored. Approval makes
these files read-only to the T3.3 implementation context.

## Reviewed production interface

T3.3 provides a standalone table SQL macro and its scalar side-predicate macro:

```sql
DOOM_BSP_LOCATE(p_x NUMBER, p_y NUMBER)
DOOM_BSP_SIDE(p_x NUMBER, p_y NUMBER,
              p_node_x NUMBER, p_node_y NUMBER,
              p_node_dx NUMBER, p_node_dy NUMBER)
```

The caller uses binds, for example:

```sql
select ssector_id, sector_id, depth, path_signature
from table(doom_bsp_locate(:x, :y));
```

`DOOM_BSP_SIDE` returns numeric side 0 or 1 and lets the evaluator run the
hand-authored predicate table through the exact production predicate. The
location macro must use this scalar macro for its node decisions rather than
maintain a second expression. `DOOM_BSP_LOCATE` returns exactly one row.
`PATH_SIGNATURE` is the root-to-leaf sequence
`node_id:side` joined with `/`; this makes every side decision independently
observable rather than validating only the final sector. The macro starts at
`MAX(DOOM_MAP_NODE.NODE_ID)`, uses `CONNECT BY`, applies the explicit four axis
branches and strict non-axis cross predicate from PLAN Section 1.2, recognizes
the 0x8000 leaf flag, and resolves a leaf sector through the subsector's first
seg and that seg's facing sidedef.

The macro may produce its SQL text as Oracle requires, but it may not execute
dynamic SQL. Pose inputs remain `p_x`/`p_y` references in the returned query;
production cannot embed fixture coordinates or all-THINGS answers.

## Independent expectations

`reference.mjs` is an evaluator-only structured decoder written from the plan
and binary map layout. It validates the pinned WAD hash, confines lookup to the
E1M1 map-lump window, traverses from the last node, and derives sector ownership
from raw seg/linedef/sidedef fields. It does not import the production parser,
seed manifest, SQL generator, or BSP implementation.

The visible baseline includes fourteen hand-authored side cases covering both
signs of each axis, both cross signs, and equality; player spawn sector 140;
all 292 THINGS coordinates; root equality and adjacent points; and large
coordinates outside map bounds. The all-THINGS oracle compares one canonical
document hash only after requiring exactly 292 ordered rows and the exact
document length, so missing/extra probes fail closed.

## Candidate commands

```sh
node evaluator/t3.3/self-check.mjs
# After an approved implementation and loaded schema:
evaluator/t3.3/run-visible.sh
```

The live command intentionally fails until `sql/bsp` and `DOOM_BSP_LOCATE`
exist. A compile error, null/duplicate macro row, absent test, hash mismatch,
timeout, or source-audit violation is a failure, never a mutation kill or skip.

Fifteen isolated semantic mutations are fixed in `mutation-specs.json`. A
mutation is killed only by its named real assertion path while the macro remains
valid and unrelated evaluator checks remain healthy.
