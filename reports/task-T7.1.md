# T7.1 inventory, pickups, weapons, hitscan, and projectiles

Status: **PASS — 23/23 IDs, 1,582/1,582 assertions**

Route: `T7.1-IMPL | Sol | high | attempt 1`.

The approved frozen evaluator manifest remained byte-identical at
`45be1db5dea63fc4291851ac4e692e9a66bd903096b35bf8b2379a190503f30e`.
No evaluator source, fixture, expectation, mutation, or test-ID file changed.

## Production implementation

`sql/sim/050_combat_inventory.sql` installs the definer-rights
`DOOM_COMBAT.ADVANCE(session_token,tic)` transaction participant.  It provides:

- conditional, once-only relational pickup consumption for all 22 reviewed
  E1M1 grants, including normal/backpack ammo caps, health and armor ceilings,
  non-downgrading armor, keys, berserk, and weapon ownership;
- seven relational weapons with ownership/ammo-gated selection, lower/raise,
  ready/fire/refire/flash timing, exact ammo costs, and fixed ordered database RNG
  reads;
- nearest actor hitscan bounded by the reviewed exact R1 ray/intersection result;
- deterministic rocket/plasma spawn and swept collision with owner authority;
- armor absorption, bounded distance-falloff splash with exact blocking-line
  occlusion, and stable once-only barrel chain expansion by mobj ID.

The integrated schema/definition files add four ammo families, two projectile
types, the complete 22-row pickup catalog, and constrained authoritative player
and mobj fields.  Bootstrap installs those files before T6.4 history, installs
combat after world machines, and invokes combat exactly once after movement and
world advancement but before state hashing and snapshot capture.

T6.4 canonical state/save/load now includes every combat inventory, weapon,
projectile, owner, and explosion field.  A dedicated live probe proves these
fields survive save/load.  Legacy short lineages continue to produce the reviewed
T6.1 transport digest, while production SHA-256 lineages hash the full combat
closure.  No T7.3 audio behavior was preempted or changed.

## Acceptance evidence

```text
PASS T7.1-EVAL-SELF-CHECK (93/93 fixture-contract assertions)
PASS T7.1-EVAL-MUTATION-SELF-CHECK (22/22 isolated mutations killed)
PASS T7.1-SOURCE-AUDIT
PASS T7.1-ORACLE-PRODUCTION
PASS T7.1-VISIBLE (23/23 test IDs, 1582/1582 declared assertions)
PASS T7.1-HISTORY-CLOSURE (player inventory/weapon and projectile fields)
```

The frozen live suite completed in 2.8 seconds on the isolated stack.  The second
clean bootstrap loaded all 537 seed files and all 24 ordered SQL entries in
142.45 seconds; `DOOM_COMBAT` compiled valid on its first install.  Performance
has no numeric acceptance threshold, and these complete timings were reviewed as
suitable for this simulation stage.

Regression and hygiene evidence:

```text
PASS T6.1-VISIBLE (20/20 IDs, 430/430 assertions) plus concurrency
PASS T6.2-VISIBLE (22/22 IDs, 372/372 assertions)
PASS T6.3-VISIBLE (28/28 IDs, 906/906 assertions)
PASS T6.4-VISIBLE (28/28 IDs, 848/848 assertions)
PASS T1.2-static (10/10 assertions)
PASS T3.1-static (24/24 assertions)
PASS secret ignore audit
PASS T0.4 (8/8 assertions)
PASS T0.4-EVALUATOR-SELF-TEST (13/13 attacks rejected)
PASS final schema validity (0 invalid objects)
PASS exact one DOOM_COMBAT.ADVANCE delegation
PASS catalogs (4 ammo / 7 weapons / 22 pickups / 2 projectiles)
```

The disposable `doomdb-t71-test` container, network, and volume were removed.
A redundant disposable schema-test stack was stopped and removed as well.  The
default dashboard database and ORDS were never reset; dashboard health remained
`DOOMDB_ORDS_READY` after teardown.
