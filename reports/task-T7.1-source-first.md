# T7.1 source-first implementation handoff

Status: **INTEGRATED — see `reports/task-T7.1.md`**

The frozen T7.1 evaluator and manifest were not modified.  This source-first
implementation is intentionally absent from shared bootstrap, drop, verification,
routing, and tic-transaction files while T6.3/T6.4 integration is unfinished.

## Delivered

- `sql/sim/050_combat_inventory.sql`: definer-rights `DOOM_COMBAT` package with
  the unique `ADVANCE(session_token,tic)` procedure.
- `sql/sim/staged/t7.1_schema.sql`: constrained ammo/projectile catalogs and
  authoritative player/mobj combat columns.
- `sql/sim/staged/t7.1_defs.sql`: four ammo families, seven exact weapon attack
  definitions, 22 relational pickup grants, and rocket/plasma definitions.
- `sql/sim/staged/t7.1_tic_hook.sql`: the single owning-transaction delegation
  statement, parked separately to avoid editing the shared T6 transaction.

The package implements conditional single pickup consumption, backpack caps,
weapon ownership and no-ammo selection, lower/raise/fire/refire/flash states,
ordered table RNG reads, stable nearest hitscan actors bounded by the reviewed R1
intersection result, swept projectile collision, armor absorption, occluded
distance-falloff splash, and stable once-only barrel chain expansion.  It contains
no transaction boundary, dynamic SQL, host randomness, or wall-clock gameplay.

## Source-first evidence

```text
PASS T7.1-EVAL-SELF-CHECK (93/93 fixture-contract assertions)
PASS T7.1-EVAL-MUTATION-SELF-CHECK (22/22 isolated mutations killed)
PASS T7.1-SOURCE-AUDIT (relational inventory, weapons, hitscan, projectiles, splash, barrels)
PASS T7.1-STAGED-DEFS (4 ammo, 7 weapons, 22 pickups, 2 projectiles)
PASS git diff --check
```

The source audit was run against the real production package and the isolated
`t7.1_tic_hook.sql` in memory.  The shared tic source remains untouched as
required.  Frozen hashes remain:

- source policy: `f69e459eeb0a6a3cc8a7bd6f0b5a33ee4bf658a003565afd810233df3b092d80`
- evaluator manifest: `45be1db5dea63fc4291851ac4e692e9a66bd903096b35bf8b2379a190503f30e`

## Ordered integration

After T6.3 and T6.4 are accepted, integrate in this order:

1. Apply `sql/sim/staged/t7.1_schema.sql` after the T6 schema extensions.
2. Apply `sql/sim/staged/t7.1_defs.sql` after base engine definitions.
3. Install `sql/sim/050_combat_inventory.sql` after R1 rays/hits exist.
4. Insert the staged hook exactly once in the per-command logical-tic path after
   movement/world advancement and before state hashing/snapshot serialization.
5. Extend the canonical T6.4 state document with every new player/mobj combat
   field, then update ordered bootstrap/drop/routing in the owning integration
   turn.
6. Run `bash evaluator/t7.1/run-visible.sh` in a fresh isolated Oracle stack and
   require all 23 IDs / 1,582 assertions plus all 22 mutation witnesses.

No Oracle service was started and no live acceptance is claimed in this turn.
