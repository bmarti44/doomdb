# T7.2 source-first implementation handoff

Status: **INTEGRATED — see `reports/task-T7.2.md`**

The frozen T7.2 evaluator and manifest were not modified. This implementation
is intentionally absent from shared bootstrap, drop, verification, routing, and
tic-transaction files while T6.4/T7.1 production acceptance is pending.

## Delivered

- `sql/sim/060_monsters.sql`: definer-rights `DOOM_MONSTERS` package with the
  unique `ADVANCE(session_token,tic)` transaction-participant procedure.
- `sql/sim/staged/t7.2_schema.sql`: constrained relational monster catalog and
  authoritative sector, direction, wake, cooldown, health-observation and
  once-only death state.
- `sql/sim/staged/t7.2_defs.sql`: independent state graphs and behavior rows for
  all five reviewed E1M1 types, plus the database-owned imp projectile.
- `sql/sim/staged/t7.2_tic_hook.sql`: the single owning-transaction delegation,
  parked separately to avoid editing the shared transaction.

The package snapshots actors in stable mobj order before mutation, advances
states through `DOOM_STATE_DEF` joins, traverses the sound-blocked sector graph
with a bounded visited set, applies REJECT as a negative-only LOS filter, orders
exact rational linedef intercepts, chooses collision-tested chase directions,
and implements relational melee/hitscan/projectile attacks, pain, death and
drops using database RNG reads. It contains no transaction boundary, dynamic
SQL, host randomness, wall-clock gameplay or reviewed-type dispatch.

## Source-first evidence

```text
PASS T7.2-EVAL-SELF-CHECK (70/70 fixture-contract assertions)
PASS T7.2-EVAL-MUTATION-SELF-CHECK (24/24 isolated mutations killed)
PASS T7.2-STAGED-SOURCE-AUDIT
PASS T7.2-INTEGRITY (frozen manifest and source-policy hashes unchanged)
```

The source audit was applied to the real production package with the staged tic
hook composed in memory. The shared tic source remains untouched as required.
Frozen hashes remain:

- source policy: `00b7b06ea8aed54a4cc092244bd21f29a7a31443bdf0690a8d6ae0c1bb48c2c3`
- evaluator manifest: `1042e2852498a8127b8bace2d0e6b525579851f76041fa016fd6aea74feff51e`

## Ordered integration

After T6.4 and T7.1 are accepted:

1. Apply the staged T7.2 schema after the staged T7.1 schema.
2. Apply the staged definitions after T7.1 definitions and install the package.
3. Insert the hook exactly once after `DOOM_COMBAT.ADVANCE` and before state
   hashing/snapshot serialization.
4. Extend T6.4 canonical state/save/load serialization with every new mobj
   field before live replay acceptance.
5. Update ordered bootstrap/drop/routing only in the owning integration turn.
6. Run `bash evaluator/t7.2/run-visible.sh` in a fresh isolated Oracle stack and
   require all 25 IDs / 2,565 assertions plus all 24 mutation witnesses.

No Oracle service was started and no live acceptance is claimed in this turn.
