# T7.1 inventory, pickups, weapons, hitscan, and projectiles evaluator

This evaluator freezes an independent database-owned combat contract. Production
implements `DOOM_COMBAT.ADVANCE(session_token,tic)` and the owning tic transaction
calls it after movement/world advancement. Callers provide commands, never hit,
pickup, target, damage, random, or trigger decisions.

Definitions are relational: four ammunition families and caps; seven weapons and
state links; all pickup grants; rocket/plasma motion; and barrel/splash behavior.
Authoritative player state includes backpack, owned weapons, pending/selected
weapon, ready/fire/refire/raise/lower and flash states. Mobjs own projectile
momentum/owner and barrel exploded state. Events use stable `(tic,ordinal)` order.

The evaluator independently fixes 23 distinct interactive E1M1 thing types:
key 5, backpack 8, weapons 2001-2005, pickups 2007/2008/2010-2015/2018/2019/
2023/2046-2049, and barrel 2035. Every type requires a focused production replay;
the Oracle path additionally derives the live set from map and category tables.

Hitscan consumes ordered database RNG reads per pellet and terminates at the
nearest exact shootable intercept using the reviewed ray/intersection machinery.
Projectiles use swept movement. Splash uses bounded falloff plus line-of-effect;
barrels chain once in stable mobj order. Useful pickups consume once, while a
pickup granting nothing because of caps/stronger ownership remains.

Run candidate checks before implementation:

```sh
node evaluator/t7.1/self-check.mjs
node evaluator/t7.1/mutation-self-check.mjs
node evaluator/t7.1/source-audit.mjs
```

After dependencies and production are installed:

```sh
bash evaluator/t7.1/run-visible.sh
```

The full path fails closed when production is missing. T6.3 and T6.4 production
acceptance remain upstream gates; this candidate pins no mutable production file.
