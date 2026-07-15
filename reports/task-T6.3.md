# T6.3 world machines implementation

Status: **COMPLETE — PASS 906/906**

Route: Sol high. The corrected approved and frozen evaluator manifest is
`29a7574575f2fb765d7d4179447d9fb37d465cca823aed7c022f8b74790bfb83`.
No implementation work modified the frozen evaluator.

## Production implementation

`sql/sim/030_world_machines.sql` implements the session-bound
`DOOM_WORLD_MACHINES.ADVANCE(session,tic,previous_x,previous_y)` package. It:

- discovers manual use by nearest exact ray/segment intersection and discovers
  walk triggers by exact front-to-back signed crossing;
- dispatches all reviewed E1M1 line and sector semantics from relational engine
  definitions, with constants read from `DOOM_CONFIG`;
- persists once/repeat state, blue-key denial, movers, button restoration,
  sector damage exposure, secret discovery, and light timing per session;
- derives tagged targets, adjacent floor/ceiling targets, and occupancy from
  relational geometry/state, with stable machine and event ordering;
- consumes `DOOM_RNG_VALUE` for random blinking and owns no transaction boundary.

The dynamic schema now retains mover kind/origin/source and random-light timer
state. The tic package compile order is movement, world machines, then the
dependent transaction body. For initialized gameplay sessions each accepted
tic captures the previous player position, applies `DOOM_PLAYER_MOVE`, and then
advances world machines. Synthetic pre-world sessions remain valid for the T6.1
transaction boundary contract. Machine metadata participates in state hashing.

## Verification

One fresh isolated Oracle stack loaded all 537 seed files and 19 ordered
production files. The default dashboard stack was not changed.

```text
PASS T6.3-EVAL-SELF-CHECK (67/67 fixture-contract assertions)
PASS T6.3-EVAL-MUTATION-SELF-CHECK (20/20 isolated mutations killed)
PASS T6.3-SOURCE-AUDIT
PASS T6.3-ORACLE-PRODUCTION
PASS T6.3-VISIBLE (28/28 test ids, 906/906 declared assertions)
PASS T6.1-VISIBLE (20/20 test ids, 430/430 declared assertions)
PASS T6.1-CONCURRENCY (4/4)
PASS T6.2-VISIBLE (22/22 test ids, 372/372 declared assertions)
PASS T0.4 (8/8 assertions)
PASS T0.4-EVALUATOR-SELF-TEST (13/13 attacks rejected)
PASS T3.1-static (24/24 assertions)
PASS secret ignore audit
```

Two evaluator-only legality defects were corrected and re-frozen independently:
an overbroad source-audit parameter regex and a SQL-only hash function invoked
directly from PL/SQL. The only production correction found by the live gate was
protecting parallel use rays with `NULLIF` before Oracle expression evaluation.
