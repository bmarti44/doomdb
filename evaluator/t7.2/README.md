# T7.2 monster states and perception evaluator

This evaluator freezes an independent database-owned monster contract. Production
implements one non-overloaded `DOOM_MONSTERS.ADVANCE(session_token,tic)` and the
owning tic transaction calls it after world movement and T7.1 combat outcomes.
Callers never supply state, perception, target, direction, hit, damage, pain,
death, drop, random, collision, or event decisions.

Definitions are relational for E1M1 monster types 9, 58, 3001, 3002, and 3004.
They link independently authored see/chase/melee/missile/pain/death states, speed,
pain chance, range, attack math, projectile kind, and optional drop. State
advancement follows `DOOM_STATE_DEF.next_state_id` joins. A graph audit rejects
dangling or unintended dead states.

Sound perception is bounded sector-graph reachability with sound-block lines and
a visited set. Sight checks `DOOM_REJECT_BYTE` first as a negative-only filter,
then orders exact rational linedef intercepts to the target. Chase directions and
collision candidates have stable preferences and identifiers. All actors advance
from one prior-tic snapshot in mobj order; random reads and events are stable.

The fixture/reference covers idle/wake, heard/not-heard, seen/occluded, chase,
melee, hitscan, projectile, pain, death, drop, and deterministic lifecycle replay
for every type. The Oracle path derives the five-type set from live E1M1 data,
checks the relational matrix/state graph and fail-closed production paths, and
rejects type dispatch, evaluator coupling, dynamic SQL, host randomness, wall
time, autonomous transactions, or transaction ownership.

Candidate checks:

```sh
node evaluator/t7.2/self-check.mjs
node evaluator/t7.2/mutation-self-check.mjs
node evaluator/t7.2/source-audit.mjs
```

After T6.4 and T7.1 production acceptance, run:

```sh
bash evaluator/t7.2/run-visible.sh
```

The full path fails closed when `sql/sim/060_monsters.sql` is absent. No mutable
production source is pinned by this candidate.
