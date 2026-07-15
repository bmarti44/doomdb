# T8.2 source-first implementation handoff

Status: **PARKED FOR ORDERED LIVE INTEGRATION**.

The frozen T8.2 evaluator and manifest were not modified. The implementation is
task-owned and intentionally does not edit the shared bootstrap, drop, tic
transaction, REST package, root verification, or routing while T7.3, T8.1, and
T10.1 live integration is unfinished.

## Delivered

- `sql/sim/staged/t8.2_schema.sql` adds authoritative menu selection, GOD,
  FULLMAP, generation, intermission summary/hash state, and relational per-
  session automap discovery.
- `sql/sim/080_workflows.sql` owns exact menu transitions, pause/gameplay
  gating, database automap modes, all four cheats, reserved canonical rewind,
  terminal state detection, and intermission summary capture without a commit.
- `sql/sim/staged/t8.2_tic_hook.sql` freezes the owning transaction placement,
  gameplay gate, damage/collision rules, history branching seam, and terminal
  finalization.
- `sql/rest/staged/t8.2_api_hook.sql` freezes NEW_GAME initialization while
  retaining the exact seven-member DOOM_API boundary and STEP-only controls.
- `client/staged/t8.2/workflows.mjs` is a presentation-only coordinator for the
  seven same-origin procedure paths. It owns exact commands, a monotonic public
  sequence, one-to-four command batches, byte-identical retry, save/load,
  rewind, and independent replay calls; it infers no gameplay or pixels.
- `tests/verify-t8.2-workflows.mjs` checks the independent control-state model
  and client orchestration, including rejected-request frontier atomicity.

## Source-first evidence

```text
PASS T8.2-EVAL-SELF-CHECK (36/36 fixture-contract assertions)
PASS T8.2-EVAL-MUTATION-SELF-CHECK (24/24 isolated mutations killed)
PASS T8.2-SOURCE-AUDIT (fixed public workflow surface, anti-coupling policy)
PASS T8.2-STAGED-SOURCE-AUDIT (SQL ownership, STEP hooks, terminal and persistence seams)
PASS T8.2-WORKFLOW-UNIT (menu, pause, automap, cheats, branches, persistence, retry atomicity)
PASS git diff --check (task-owned sources)
```

Refreshed frozen evaluator manifest:
`cd36b384dc61111914f9e6c05289cff1b02f3c4d73b644b2705a05f8e1ddb791`.
It pins the current T8.1 evaluator lineage
`9d397f036967aa0a62b61177a7d089957f0c3c6e5d6a34c0b3da310c75305b95`.

## Ordered integration

After T7.3 and T8.1 pass, apply the staged schema, install `DOOM_WORKFLOW`, add
its pre-gameplay, terminal-transition, and post-hash seal calls once to the
owning per-command transaction, and include every state-affecting new field in
T6.4 canonical state/save/load/replay (the two derived terminal seals are
excluded from their own hash inputs). Resolve
REWIND and DEAD/RESTART through verified branching while preserving the global
command frontier and every old lineage. Initialize workflow state during
NEW_GAME, integrate database-owned pause/menu/automap/death/intermission pixels,
then update shared bootstrap/drop/routing in the owning integration turn.

Live Oracle/ORDS and Playwright remain mandatory: run all 28 IDs / 323,056
assertions and all 24 mutations with evaluator-provisioned dead/intermission
sessions. No visual golden is created or claimed here.
