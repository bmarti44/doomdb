# T4.2 implementation blocked by frozen evaluator syntax

Status: **RESOLVED on 2026-07-14 by the explicitly approved evaluator-only
statement move**.

The approved evaluator manifest remains byte-for-byte unchanged:

```text
5ca1b511b7ebefddee3169a3485248d76afb07325ae7a271d790565842747155  evaluator/integrity.pending-T4.2.json
6759d51f5be4972954566811583827c50ed866ecc22a8a5025d675fd7ec7fe6e  evaluator/t4.2/oracle-production.sql
```

## Exact failure

The frozen live runner puts transaction-control SQL after a PL/SQL statement on
line 27:

```sql
select min(weapon_id) into l_weapon from doom_weapon_def;set constraints all deferred;
```

Oracle parses `SET CONSTRAINTS` as PL/SQL static SQL and exits before the first
production assertion:

```text
ERROR at line 27:
ORA-06550: line 27, column 64:
PL/SQL: ORA-00922: missing or invalid option
ORA-06550: line 27, column 60:
PL/SQL: SQL Statement ignored
```

This is the same statement-placement defect already approved and corrected in
the inherited T4.1 evaluator. It is evaluator-only; it does not describe a
production failure.

## Minimal correction requested

Move the unchanged statement immediately before `DECLARE`, leaving every test
id, fixture, expected pixel, hash, and production interface unchanged:

```sql
set constraints all deferred;

declare
  ...
begin
  select min(weapon_id) into l_weapon from doom_weapon_def;
```

A temporary copy with exactly that move passes the statement itself (`Constraint
set.`) and reaches production execution. The frozen evaluator was not edited.

## Completed evidence before the gate

```text
PASS T4.2-EVAL-SELF-CHECK (139/139 fixture-contract assertions)
PASS T4.2-EVAL-MUTATION-SELF-CHECK (18/18 isolated mutations killed)
PASS T4.2-SOURCE-AUDIT (1 SQL files; canonical order; no procedural pixel loop or dynamic SQL; no expected frame)
```

The general relational `DOOM_R1_PIXELS` implementation compiles as a valid
Oracle table SQL macro and is included in bootstrap order. No frame artifact or
dashboard visual was published because the database pixels are not yet accepted
by the immutable live evaluator.

## Resolution record

The unchanged `SET CONSTRAINTS ALL DEFERRED` statement now appears immediately
before `DECLARE`, and its in-block copy was removed. All assertions, ids,
fixtures, expectations, hash oracles, interfaces, and production files remain
unchanged. The correction passes evaluator self-check 139/139, mutation
self-check 18/18, production-source audit, integrity 19/19, and the inherited
T0.4 foundation 8/8 plus adversarial self-test 13/13. Exact corrected hashes:

```text
b58d3423a5a4b7b67bd8ff5e776cbee590421fd5c80ee5af3d0da810d192f57e  evaluator/t4.2/oracle-production.sql
1cd2021266edea250fd11f9d285a5cdeb3d1fe826c5b557a3d95408d4cd70429  evaluator/integrity.pending-T4.2.json
```

The corrected runner also passed the relocated statement and entered the real
production macro. The first dense-frame aggregate was still CPU-bound after
513 seconds, while an abandoned predecessor had accumulated about 1,890
seconds on the same SQL id. The shared-stack run was therefore rolled back at
orchestrator direction. Full live acceptance remains an implementation
performance responsibility and must be rerun after optimization; it does not
reopen this resolved evaluator syntax defect.

That responsibility is now complete. The optimized implementation passed the
full corrected live suite in 587.08 seconds total, including every repeated
dense/gap/probe/hash query; the formerly 513-second single dense aggregate is no
longer the limiting plan. See `reports/task-T4.2.md`.
