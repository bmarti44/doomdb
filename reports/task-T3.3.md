# T3.3 BSP location implementation report

Status: **PASS**.

## Delivered

- `sql/bsp/010_bsp_location.sql` defines standalone scalar
  `DOOM_BSP_SIDE` and table `DOOM_BSP_LOCATE` SQL macros with the reviewed
  interfaces.
- The scalar macro implements all explicit vertical and horizontal sign/tie
  branches and selects non-axis side zero only for a strictly positive cross.
- The table macro uses call-time parameters and relational `CONNECT BY`, starts
  at `MAX(DOOM_MAP_NODE.NODE_ID)`, follows the selected normalized child, and
  returns exactly one leaf row.
- Leaf ownership follows the subsector first seg and that seg's facing sidedef.
  The observable path is a root-to-leaf `node_id:side` `LISTAGG` ordered by
  traversal depth.
- Ordered bootstrap, its safe directory allowlist, and `verify.sh task T3.3`
  include the BSP deployment without removing inherited entries or routes.
- Fresh local initialization grants the fixed production owner direct
  `SYS.DBMS_CRYPTO` execution for canonical SHA-256 documents. The Autonomous
  bootstrap documents and verifies the same capability before publishing ORDS
  objects. Credentials remain secret-file/stdin based and ignored by Git.

## Fresh Oracle evidence

The implementation was loaded through all thirteen ordered bootstrap entries
in a new `doomdb-t33` Compose project on port 15233. Before bootstrap, the fresh
application owner successfully executed the mounted DBMS_CRYPTO capability
check, proving the grant was applied by first-volume initialization rather than
manually added to the test database.

Canonical acceptance after the approved evaluator correction:

```text
PASS T3.3 integrity (14/14)
PASS T3.3-EVAL-SELF-CHECK (61/61 fixture-contract assertions)
PASS T3.3-SOURCE-AUDIT (1 SQL files)
PASS T3.3-ORACLE-PRODUCTION
PASS T3.3-VISIBLE (15/15 test ids, 455/455 declared assertions)
```

This covers the fourteen hand-authored side cases, spawn subsector 115 and
sector 140, every one of 292 THINGS, root boundaries, arbitrary outside
coordinates, the fractional bind, and deterministic complete path signatures.

## Mutation and regression evidence

All fifteen approved semantic mutations are killed. The evaluator correction
preserves the real execution evidence for M01-M11 and M13-M15 because none of
their fixtures or assertion paths changed. M12 was freshly executed against
the corrected frozen evaluator by installing the exact rounding mutant into the
isolated production schema. It failed specifically at `T33-BIND-SAFETY` with
`fractional bind subsector expected 157 got 558`; canonical SQL was immediately
restored and re-passed 455/455.

Regressions and isolation checks:

```text
PASS T3.2 (136/136 assertions)
PASS T3.1-static (24/24 assertions)
PASS T1.3 (12/12 assertions)
PASS secret ignore audit (8 ignored paths, 3 visible templates, no tracked secret-like paths)
PASS T3.3 production isolation audit
```

No production BSP or deployment source reads evaluator, report, golden, test,
caller-stack, or process-state artifacts. The corrected evaluator manifest and
all inherited baselines matched their frozen SHA-256 values. The isolated
container, network, and volumes were removed after verification.

