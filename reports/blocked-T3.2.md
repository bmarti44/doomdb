# T3.2 blocked report

Status: **RESOLVED after three explicitly approved evaluator-only compatibility corrections**.

Route: `T3.2-IMPL | Terra | medium | attempt 1`.

## Production result

The T3.2 production implementation remains intact in
`sql/spatial/010_linedef_geometry.sql`. A fresh local deployment completed all
of the following before the evaluator failure:

- materialized 1,175 directed two-point geometries;
- stored Euclidean length and normalized direction rounded to twelve decimal
  places from the unrounded norm;
- derived both metadata dimensions from live vertex `MIN/MAX` and the live
  `FAR_DISTANCE + PLAYER_RADIUS` values;
- created `DOOM_LINEDEF_SIDX` as `MDSYS.SPATIAL_INDEX_V2`;
- completed an indexed broad-filter plus exact-predicate health query; and
- completed the ordered twelve-step bootstrap after extending its safe
  directory allowlist to `sql/spatial`.

Equivalent supported Oracle checks passed for metadata values, canonical
geometry shape and directed endpoints, all geometry validity, all stored
metrics, all three domain-index status fields, and the pinned linedef-zero MBR
false positive (`filter=1`, `exact=0`). The approved production source audit
also passed:

```text
PASS T3.2-SUPPORTED-ORACLE-EQUIVALENTS
PASS T3.2-EXACT-FALSE-POSITIVE-EQUIVALENT
PASS T3.2-SOURCE-AUDIT (1 SQL files)
PASS T3.1-static (24/24 assertions)
```

These diagnostic checks do not substitute for the approved evaluator and do
not authorize a T3.2 PASS.

## Immutable evaluator failure

The approved `evaluator/t3.2/oracle-production.sql` fails to compile on the
pinned Oracle Free image before any assertion executes:

```text
ORA-00904: "M"."DIMINFO": invalid identifier
ORA-00904: "GEOM"."SDO_ORDINATES"."COUNT": invalid identifier
PLS-00221: 'SDO_ORDINATES' is not a procedure or is undefined
ORA-00904: "MDSYS"."SDO_GEOMETRY"."SDO_ORDINATES": invalid identifier
```

The three failing expression families are:

1. `m.diminfo(1).sdo_lb` and related SQL-level VARRAY element access;
2. `geom.sdo_elem_info.count` / `geom.sdo_ordinates.count` inside SQL; and
3. `l.geom.sdo_ordinates(1)` and related SQL-level element access.

The same object and collection accesses succeed in PL/SQL variables/records,
which is how the equivalent diagnostics above established that this is an
evaluator-only syntax defect rather than a production data defect.

## Minimal evaluator correction and reapproval boundary

An evaluator-author context should change only
`evaluator/t3.2/oracle-production.sql`:

- select `DIMINFO` into an `MDSYS.SDO_DIM_ARRAY` PL/SQL variable and read its
  two elements in PL/SQL; and
- perform geometry collection count/element checks on `SDO_GEOMETRY` values in
  a PL/SQL cursor loop (or another Oracle-supported equivalent), preserving the
  same counts, endpoints, failures, test ids, and 136 declared assertions.

The currently approved file hash is:

```text
57ca451ecadfd9c43bf5d40d5ba2456db81d1fff9ac6c4f78ef08196700d9792  evaluator/t3.2/oracle-production.sql
```

After that correction, `evaluator/integrity.pending-T3.2.json` must record the
new evaluator file hash and the user must explicitly reapprove the corrected
baseline. Its current hash is:

```text
d037993e10038333e062af1b2bacd90712d417972344768bca2f4a68bf908c0a  evaluator/integrity.pending-T3.2.json
```

Because pending T3.3 chains that integrity document, its still-unapproved
`evaluator/integrity.pending-T3.3.json` must be refreshed before T3.3 review.
No approved evaluator file was modified, and the final immutable audit passed
all thirteen inherited and T3.2 hashes:

```text
PASS T3.2 immutable audit (13/13)
```

No T3.2 root verifier route or PASS report was added.

## Correction attempt and second evaluator defect

After explicit user approval, a separate evaluator context applied only the
collection-access correction above. The corrected
`evaluator/t3.2/oracle-production.sql` has SHA-256
`208828c193b0acba13ba874e984bed4b88aede58124b93d9cf2a3a77c18cf8a2` and
passes both the live production assertions and the unchanged 58/58 evaluator
self-check.

The full runner then exposed a second pinned-Oracle compatibility defect in
the still-frozen `evaluator/t3.2/run-visible.sh`: its setup executes
`GRANT CREATE SESSION, CREATE TABLE, CREATE INDEX`. Oracle has no `CREATE
INDEX` system privilege, so the whole grant fails with `ORA-00990`; the test
user consequently cannot log in. A table owner already has authority to create
ordinary indexes on its own tables, but Oracle Spatial creates an internal
`MDRS_*` sequence while building this R-tree. A manual live run that merely
removed `CREATE INDEX` reached index creation but failed with
`ORA-29855`, `ORA-13249`, and nested `ORA-01031` on `CREATE SEQUENCE`.
The same evaluator mini-map passed all 6/6 assertions when the grant was
instead changed to `GRANT CREATE SESSION, CREATE TABLE, CREATE SEQUENCE`.

The proven minimal correction is therefore the one-token privilege replacement
`create index` -> `create sequence`, preserving every test id, assertion,
fixture, and expected result. The currently approved runner SHA-256 remains
`d41019cc82cef3329f1caf32483cdad3d2a0ca956d4df58d3df5abdb45cff06c`.

That additional runner edit requires explicit approval before the corrected
T3.2 candidate can be completed, rehashed, and propagated into T3.3's chained
pending integrity document.

## Approved privilege correction and third evaluator defect

The user subsequently approved the exact `create index` -> `create sequence`
replacement. It is preserved in `evaluator/t3.2/run-visible.sh`, whose new
candidate SHA-256 is
`c0a70bec8810259891549c93db3c13935a88928457ddf9a1c7495ca7141dd1fb`.
The unchanged corrected production evaluator again passed against the live
database, but the canonical runner still reached the mini-map login with
`ORA-01017`.

The runner's emitted SQL revealed a third pre-existing syntax defect: neither
the `CREATE USER` line nor the `GRANT` line ends with a semicolon. SQL*Plus
therefore buffers the statements rather than executing them before `EXIT`, so
no evaluator user is available for the mini-map login. This explains why the
manual compatibility probe, which used terminated statements, succeeded while
the canonical runner did not.

The minimal correction is to append `;` inside each of those two emitted SQL
strings. It changes no evaluator assertion, fixture, expected value, production
interface, or privilege. Those two line terminators require explicit approval
before application. T3.2 integrity metadata and T3.3's inherited baseline have
not been refreshed while the candidate remains unable to complete its canonical
runner.

## Resolution

The user explicitly approved both SQL statement terminators. With exactly those
characters added, the unchanged canonical runner completed against pinned
Oracle Free:

```text
PASS T3.2-SOURCE-AUDIT (1 SQL files)
PASS T3.2-ORACLE-PRODUCTION
PASS T3.2-ORACLE-MINI-MAP (6/6 assertions)
PASS T3.2 (136/136 assertions)
PASS T3.2-EVAL-SELF-CHECK (58/58 fixture-contract assertions)
```

The corrected and approved frozen hashes are:

```text
208828c193b0acba13ba874e984bed4b88aede58124b93d9cf2a3a77c18cf8a2  evaluator/t3.2/oracle-production.sql
a879e2027da712b1f9e7b4de0c4e8bd4b0038b799ff1e4deb9d35593cdb3ecc9  evaluator/t3.2/run-visible.sh
d617cdd9e5f8a36606d6606d6c61a514f46b3b5545f4526e48361a1c04208050  evaluator/integrity.pending-T3.2.json
```

All nine T3.2 evaluator files and four inherited approved baselines matched the
refreshed manifest (13/13). The generic foundation remained green at 8/8 and
all 13 adversarial evaluator attacks were rejected. Pending T3.3 now inherits
the corrected T3.2 manifest hash; its evaluator logic, fixtures, expectations,
and approval status remain unchanged.
