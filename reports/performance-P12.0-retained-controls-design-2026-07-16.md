# P12.0 retained controls design

Date: 2026-07-16

## Measured blocker

The public moving-frame gate passes, but unsupported controls still stop the
resident owner, execute the complete SQL renderer, and reconstruct the worker.
One fresh local sequence measured:

| Command | AutoREST wall time |
| --- | ---: |
| retained movement before fallback | 564.529 ms (includes worker claim) |
| fire | 8,173.207 ms |
| use | 8,417.954 ms |
| weapon slot | 8,010.033 ms |
| retained movement after each fallback | 491–615 ms (reconstruction) |

These are correctness fallbacks, not a playable control path.

## Selected order

1. **Weapon selection/state.** It changes bounded player fields and emits
   `WEAPON_LOWER`/`WEAPON_RAISE`; it does not require a ray, target, projectile,
   line, sector, or mover mutation.
2. **Fire.** Add the complete retained combat order: pickup, weapon selection,
   weapon-state advance, fire, projectile advance, then monster logic. Preserve
   exact RNG, damage, ammo, flash/refire, spawn/removal, event, and renderer
   parity.
3. **Use.** Add retained line/sector/mover/switch state, the exact use ray and
   dispatch rules, subsequent mover ticks, actor carry, and renderer geometry
   deltas.

## Protocol decision

DMSC/v2 remains byte-locked: its action/reserved bytes continue to reject any
nonzero value. DMSC/v3 keeps the fixed 24-byte envelope and assigns bytes
21–23 to `fire`, `use`, and `weapon`; byte 24 remains reserved. Action-bearing
DCTC/DTIC results are independently versioned. The exact packed command remains
the retry identity, while the command-chain hash remains the canonical public
command JSON.

The ledger-side v3 decoder and rejection/command-SHA acceptance are implemented
first. Public selection stays off until the retained owner, strict relational
applier, canonical state codec, renderer accept/discard path, recovery, and
differential gates all support the same version.

## Weapon selection gates

- owned, unowned, already-selected, insufficient-ammo, and slots 1–9;
- at least five following neutral/movement tics across LOWER→RAISE→READY;
- exact player row, events, RNG, tic/sequence, command SHA, delta bytes/SHA,
  canonical state BLOB/SHA, history chain, and frame pixels/SHA;
- prepare invisibility, discard, accept, and worker restart during lower/raise;
- no JDBC/SQL reads on the warm Java path and no more than 2 ms added database
  p95;
- a repeated 300-frame AutoREST route with periodic valid switches, at least
  270 unique frames, and the existing 30 FPS paint-gap gate.

## Implementation reconciliation

Weapon selection is now selected and public. The implementation preserves
DMSC/v2 and adds strict DMSC/v3 plus DTIC/v2 weapon state, ammo, flash/refire,
and nullable `WEAPON_LOWER`/`WEAPON_RAISE` events. Canonical JSON, DWCP/v4
recovery, SQL delta apply, renderer/HUD staging, accept/discard rollback, and
projectile-bearing entrypoints carry the same state.

The nine-tic acceptance switches PISTOL→SHOTGUN, observes exactly one LOWER and
one RAISE event, runs eight DTIC/v2 transition tics, returns to DTIC/v1 at
`WEAPON_SHOTGUN_READY/1`, and records nine in-worker SQL parity passes. The
public selector waits for earlier pipelined commands before choosing v2/v3, so
a neutral request cannot freeze an in-flight transition by reading stale player
state. Retry matching remains sequence/action exact while intentionally ignoring
only the transport version byte.

Matched hot measurements reject v3 overhead as a blocker: v3 is
20.883/28.527 ms p50/p95 and adjacent v2 is 20.332/28.284 ms. The earlier
27.015/54.168 ms result was cold-code evidence; worker readiness now exercises
the actual movement, valid weapon action, renderer, and codec paths. The final
weapon-switching public route produced 300/300 unique frames at 31.065 FPS,
32.181/32.977 ms paint-gap p50/p95, and 49.303/81.127 ms request-to-decode
p50/p95 with a depth-three window. Depth two was measured twice and is retained
as a rejected borderline configuration because one repeat fell to 29.462 FPS.

## Fire F1 checkpoint

The retained hitscan/melee kernel is implemented for all five catalog-defined
non-projectile weapons without a DTIC format change. It reuses the canonical
renderer ray table, consumes three RNG values per pellet in SQL order, applies
ammo/flash/refire and monster health before monster advancement, and emits the
strict DAMAGE, HITSCAN_HIT, HITSCAN_MISS, and DRY_FIRE records. A two-tic
AutoREST gate and an independent SQL session agree exactly on health 94, RNG
cursor 4, bullets 49, event order/values/text, durable owner state, and frame
construction.

That differential also found the next required dependency: special-1 sector
light timers in `doom_world_machines.advance` consume RNG before combat. The
isolated combat gate pins those timers, so it proves F1 itself but does not
authorize unrestricted public fire routing. Retained world-machine state must
land first. Barrels with recursive splash and player rocket/plasma spawn plus
same-tic advancement remain F2; these cases and use continue through SQL.
