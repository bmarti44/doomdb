# T6.3 doors, lifts, switches, sectors, secrets, and exit evaluator

This frozen evaluator is independent of production implementation. Its oracle
does not import production SQL, geometry, state-machine code, or engine data.
It fixes an internal package boundary:

```sql
DOOM_WORLD_MACHINES.ADVANCE(
  p_session    IN VARCHAR2,
  p_tic        IN NUMBER,
  p_previous_x IN NUMBER,
  p_previous_y IN NUMBER)
```

`ADVANCE` runs inside the already locked T6.1 tic transaction and neither commits
nor rolls back. It reads the current player, the authoritative command at `p_tic`,
and database geometry. The previous coordinates are transaction-internal movement
state, not client input. Use selection is the nearest exact ray/segment intercept
within 64 units and from the actionable front side. Walk triggers require an exact
front-to-back signed crossing. The caller never supplies a linedef, sector, key,
range decision, or crossing decision.

All behavior is relational and session scoped. Line definitions 1/2/11/23/26/62/
88/117 and sector definitions 1/7/9/12 are dispatched from their reviewed engine
semantics. Engine configuration fixes normal/blazing door speed 2/8, door wait
150, lift speed/wait 1/105, button reset 35, damaging-floor amount/cadence 5/32,
and synchronized strobe bright/dark 5/35. Random blink consumes `DOOM_RNG_VALUE`
and advances the session RNG cursor; it never uses host randomness or wall time.

The independent replay model checks every special in isolation and in composition.
It covers exact use boundary and denial, front side, crossing direction, once vs.
repeat, blue-key denial without trigger consumption, tagged sector selection,
door reversal, lift occupancy, button restoration, damage exposure cadence,
secret once, both light machines, stable event ordinals, and exit completion.
Twenty semantic mutations each have a focused witness. Source audit rejects
caller-authored activation, fixture coupling, dynamic SQL, autonomous transactions,
and embedded evaluator identifiers.

Run after production installation with:

```text
bash evaluator/t6.3/run-visible.sh
```
