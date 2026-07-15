# T4.1 live verification status

Status: **evaluator issue resolved and re-frozen; production macro expansion is
the current blocker**.

## Outcome

The approved evaluator-only correction moved `SET CONSTRAINTS ALL DEFERRED`
immediately before `DECLARE`, without changing the statement, fixtures,
expectations, assertions, interfaces, or production source. A fresh isolated
run then completed the full 15-file bootstrap and reached the real T4.1 macro
queries. Oracle now rejects the production nested SQL-macro expansion with
`ORA-00904: "P_SESSION": invalid identifier`.

## Resolved evaluator defect

The prior run failed before any macro query because `SET CONSTRAINTS` was inside
an anonymous PL/SQL block:

```text
set constraints all deferred;
    *
ERROR at line 18:
ORA-06550: line 18, column 7:
PL/SQL: ORA-00922: missing or invalid option
ORA-06550: line 18, column 3:
PL/SQL: SQL Statement ignored
```

`SET CONSTRAINTS` is an Oracle SQL statement and cannot be issued as a static
statement inside an anonymous PL/SQL block. The failure occurs before either
fixture insert and before any call to a T4.1 macro, so it is evaluator
infrastructure failure rather than a production assertion failure.

The user explicitly approved moving the statement on 2026-07-14. The corrected
evaluator source SHA-256 is
`0854616c47f6f27e9813596862ac7e63a6dfc925f1e9718849de950aae215d79`.

## Current production failure

`tests/verify-t4.1-live.sh` now reports after the successful bootstrap:

```text
Constraint set.
ORA-06550: line 8, column 173:
PL/SQL: ORA-00904: "P_SESSION": invalid identifier
ORA-06550: line 13, column 169:
PL/SQL: ORA-00904: "P_SESSION": invalid identifier
ORA-06550: line 14, column 169:
PL/SQL: ORA-00904: "P_SESSION": invalid identifier
```

The failing production expansion paths are the nested calls returned by the
approved macros:

```sql
from table(doom_r1_rays(p_session)) r
from table(doom_r1_hits(p_session)) solid_hits
```

The evaluator invokes the fixed public interfaces with its session fixture as
approved. It made no production edit and stopped at this production failure.

## Applied correction

In `evaluator/t4.1/oracle-production.sql`, move the unchanged statement out of
the anonymous block:

```sql
set constraints all deferred;

declare
  ...
begin
  select min(weapon_id) into l_weapon from doom_weapon_def;
  -- existing fixture inserts continue here
```

Equivalently, add it immediately before `declare` and delete only its current
copy after the `select min(weapon_id)` statement. No interface, fixture,
expectation, assertion count, tolerance, mutation, or production source changes.
The corrected evaluator has been independently verified and re-frozen even
though production remains red. The current manifest SHA-256 is
`158c94e68220bbea4809f8688cb94549b07423655aaa4017b6fcaf3703c28ae6`.

## Evidence already green

```text
PASS T4.1-EVAL-SELF-CHECK (99/99 fixture-contract assertions)
PASS T4.1-EVAL-MUTATION-SELF-CHECK (16/16 isolated mutations killed)
PASS T4.1-SOURCE-AUDIT (1 SQL files)
PASS secret ignore audit (8 ignored paths, 3 visible templates, no tracked secret-like paths)
BOOTSTRAP COMPLETE (15 files)
```

The prior approved evaluator manifest SHA-256 was
`1481cdf6f630be70bb769eee64206821f9c8184e027c84f8a678610f60e2d060`.

## Resolution

The user approved the evaluator-only statement move. The corrected evaluator
was re-frozen at the current hash above, and T4.1 subsequently completed. Final
canonical evidence is recorded in `reports/task-T4.1.md`.
