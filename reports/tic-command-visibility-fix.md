# Appendix F current-command visibility correction

Status: **PASS — production public replay equals reviewed route lab through sequence 163**

## Defect

`DOOM_TIC_TX.APPLY_BATCH` validated and simulated each logical tic before it
appended that tic's `TIC_COMMANDS` row.  Movement used cursor fields directly,
but `DOOM_COMBAT.ADVANCE` and other database-owned gameplay consumers query the
command table.  They therefore observed no current `fire` or `weapon` command.

The exact public replay in `artifacts/t8.1-live/current-prefix-163.json` exposed
the divergence: movement positions matched the route lab, while production had
HP/kills `100/0`, `85/0`, `61/0`, and `0/0` instead of the reviewed combat state.

## Correction

After envelope/domain/range/conflict/gap validation and under the existing
`GAME_SESSIONS FOR UPDATE` lock, each per-tic loop now:

1. computes the lineage-qualified command hash and appends the validated command
   with zero state/frame placeholders;
2. advances controls, movement, world machines, combat, monsters, and audio with
   that current command visible;
3. computes the authoritative state hash and replaces only that row's
   state/frame/blob placeholders; and
4. captures history and builds the response as before.

The append and finalization remain in the caller-owned transaction.  A gameplay
exception removes both automatically.  Retry identity, conflicting-range and gap
rejection, unique sequence ordering, the session lock, command hash chaining,
event chaining, snapshots, and response-cache atomicity are unchanged.  There is
exactly one production `TIC_COMMANDS` insert.

## Exact semantic replay

The production replay test now asserts every frozen prefix checkpoint, including
movement, health, kills, mover count, and linedef 593 trigger:

```text
sequence 30:  x=48, y=480, HP=100, kills=1
sequence 60:  x=149.01933598375617, y=298.98066401624383, HP=97, kills=1
sequence 98:  x=435.4112549695428, y=304, HP=91, kills=1
sequence 131: x=640, y=304, HP=46, kills=3
sequence 163: x=640, y=304, HP=43, kills=4
PASS T6.2-OPENING-ROUTE (public prefix semantic equivalence through sequence 163)
```

These are exact route-lab expectations from
`artifacts/t8.1-live/current-prefix-163.json`, now reached exclusively through
the public production tic transaction.

## Regression evidence

```text
PASS T7.1-VISIBLE (23/23 IDs, 1582/1582 assertions; 22/22 mutations)
PASS T7.1-HISTORY-CLOSURE
PASS T6.1-VISIBLE (20/20 IDs, 430/430 assertions)
PASS T6.1-CONCURRENCY (4/4)
PASS T6.2-VISIBLE (22/22 IDs, 372/372 assertions)
PASS T6.2-THIN-DOOR
PASS T6.3-VISIBLE (28/28 IDs, 906/906 assertions)
PASS T6.4-VISIBLE (28/28 IDs, 848/848 assertions)
PASS T7.2-VISIBLE (25/25 IDs, 2565/2565 assertions)
PASS T7.2-HISTORY-CLOSURE
PASS T7.2-LIFECYCLE
PASS T7.3-VISIBLE (20/20 IDs, 684/684 assertions)
PASS T7.3 Playwright, history closure, and audio unit gates
PASS final schema validity (0 invalid objects)
```

The correction was installed and verified on the preserved
`doomdb-t81-live` stack handed off by T6.2.  No second database was started and
the preserved stack remains running for T8 continuation.

## SHA-256

```text
c5ad31508796522188896a8820599dbd969d7e3e3c2d1f72acc627d6fa9f667d  sql/sim/tic/010_tic_transaction.sql
d297e77aa0056d024fd993ce9fb24f75924b9fdf5d8f674e650b5fa99d20f6ee  tests/verify-t6.2-opening-route.mjs
45be1db5dea63fc4291851ac4e692e9a66bd903096b35bf8b2379a190503f30e  evaluator/integrity.pending-T7.1.json
```
