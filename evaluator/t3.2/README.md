# T3.2 independent Spatial evaluator candidate

This directory is evaluator-owned and pending explicit user approval. It fixes
the visible Oracle Spatial contract before any T3.2 production SQL is authored.
It does not authorize changes to this directory during implementation.

## Production interface after approval

T3.2 extends the approved T3.1 schema without renaming its map keys:

- `DOOM_VERTEX(VERTEX_ID, X, Y)` contains the 1,196 E1M1 vertices.
- `DOOM_LINEDEF(LINEDEF_ID, START_VERTEX_ID, END_VERTEX_ID, GEOM, LENGTH,
  DIRECTION_X, DIRECTION_Y)` contains the 1,175 E1M1 linedefs.
- `DOOM_CONFIG(CONFIG_KEY, NUMBER_VALUE)` contains exactly one numeric row for
  each of `FAR_DISTANCE=8192` and `PLAYER_RADIUS=16`.
- the spatial index is named `DOOM_LINEDEF_SIDX`.

`GEOM` is a two-dimensional, null-SRID straight line (`SDO_GTYPE=2002`, element
info `1,2,1`) whose ordinates are exactly `(start.x,start.y,end.x,end.y)`.
Every geometry must validate with tolerance `0.005`.

The stored metric columns are deterministic decimal values:

```text
LENGTH      = ROUND(SQRT(dx*dx + dy*dy), 12)
DIRECTION_X = ROUND(dx / unrounded_length, 12)
DIRECTION_Y = ROUND(dy / unrounded_length, 12)
```

Zero-length linedefs are rejected by a constraint; pinned E1M1 contains none.
The direction is from `START_VERTEX_ID` toward `END_VERTEX_ID`, never an
unoriented slope or an angle.

`USER_SDO_GEOM_METADATA` has one row for `DOOM_LINEDEF.GEOM`, null SRID, X/Y
tolerance `0.005`, and bounds computed at deployment time from `MIN/MAX(X/Y)` in
`DOOM_VERTEX`, expanded on both sides by
`FAR_DISTANCE + PLAYER_RADIUS`. For pinned E1M1 the independently expected
bounds are X `[-8912,11456]` and Y `[-9272,10544]`. Literal use of these values
in production SQL fails the source audit even when the resulting row is equal.

The index is a valid Oracle Spatial R-tree domain index. A successful `CREATE
INDEX` is not enough: `USER_INDEXES.STATUS`, `DOMIDX_STATUS`, and
`DOMIDX_OPSTATUS` must all be valid.

## Exact-predicate rule

`SDO_FILTER` is only an MBR candidate operation. In every production render,
collision, LOS, and spatial candidate query that uses it, the same candidate
must subsequently pass `SDO_RELATE(...,'mask=ANYINTERACT')='TRUE'` or a stricter
exact `SDO_GEOM` predicate. Moving the exact predicate to an unrelated query or
accepting the filtered row first fails.

The visible Oracle mini-map deliberately indexes a diagonal `(0,0)-(10,10)` and
queries a rectangle at the opposite corner of its MBR. `SDO_FILTER` returns the
line, while `SDO_RELATE(...,'mask=ANYINTERACT')` rejects it. It also checks two
true contacts and translated coordinates. The script is evaluator-only and
refuses to run unless `CURRENT_USER` begins `DOOMDB_EVAL`; it creates no
production object.

## Candidate commands

```sh
node evaluator/t3.2/self-check.mjs
# In a disposable DOOMDB_EVAL[_SUFFIX] Oracle schema:
scripts/db_sql.sh evaluator/t3.2/oracle-mini-map.sql
# After implementation/bootstrap in the DOOM schema:
scripts/db_sql.sh evaluator/t3.2/oracle-production.sql
```

The Oracle scripts fail on SQL errors and assertion failures. A timeout,
missing Spatial option, absent object, null aggregate, invalid index, or empty
test discovery is a failure, never a skip. The implementation runner must run
both scripts in their proper schemas and map the assertions to the stable IDs
in `test-ids.json`.

Fourteen semantic mutations are fixed in `mutation-specs.json`. In particular,
removing the exact predicate must leave the database and index healthy and fail
`T32-EXACT-FALSE-POSITIVE` because the false-positive row is returned; a compile
error or invalid index does not count as a kill.
