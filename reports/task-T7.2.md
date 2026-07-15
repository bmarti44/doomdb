# T7.2 monster state advancement and perception

Status: **COMPLETE — PASS 2,565/2,565**

Route: `T7.2-IMPL | Sol | max | attempt 1`. The approved evaluator manifest is
`764dda2fbf89bcb02511e6ffc9e3ba877757cfedb9b2d5a8981bb37b444e82e5`.
No implementation work modified the frozen evaluator or its source policy.

## Production implementation

`sql/sim/060_monsters.sql` installs the unique transaction-participant
`DOOM_MONSTERS.ADVANCE(session_token,tic)`. The ordered bootstrap now applies
the staged monster schema and definitions after T7.1, installs the package, and
delegates exactly once after `DOOM_COMBAT.ADVANCE`.

The implementation provides:

- five relational E1M1 monster definitions with independent see, chase, attack,
  pain, death and terminal-corpse state graphs;
- one immutable prior-tic actor snapshot with ascending mobj advancement and
  database-table RNG consumption;
- bounded sound propagation over directed sector edges with sound-block and
  visited-cycle handling;
- REJECT negative filtering followed by exact rational linedef intercept order;
- deterministic diagonal/axis chase preference with exact wall and stable actor
  collision checks;
- relational melee, hitscan and imp-projectile attacks, pain chance, once-only
  death/kill credit, non-solid corpses, and configured drops;
- canonical tic hashes and T6.4 save/load closure for sector, direction, awake,
  cooldown, observed health and death-processing authority.

Teardown drops the package and monster definition relation before their
dependencies. `verify task T7.2` owns the visible evaluator, history closure,
and independent live lifecycle replay.

## Verification

Two complete 537-seed / 28-entry bootstraps succeeded on a fresh isolated
Oracle 23ai stack. The second bootstrap exercised the expanded teardown and
idempotent reconstruction. The default dashboard/database stack was untouched.

```text
PASS T7.2-EVAL-SELF-CHECK (70/70 fixture-contract assertions)
PASS T7.2-EVAL-MUTATION-SELF-CHECK (24/24 isolated mutations killed)
PASS T7.2-SOURCE-AUDIT
PASS T7.2-ORACLE-PRODUCTION
PASS T7.2-VISIBLE (25/25 test ids, 2565/2565 declared assertions)
PASS T7.2-HISTORY-CLOSURE
PASS T7.2-LIFECYCLE (wake, death, drop and kill credit)
PASS T7.1-VISIBLE (23/23 test ids, 1582/1582 declared assertions)
PASS T7.1-HISTORY-CLOSURE
PASS T6.4-VISIBLE (28/28 test ids, 848/848 declared assertions)
PASS T6.3-VISIBLE (28/28 test ids, 906/906 declared assertions)
PASS T6.2-VISIBLE (22/22 test ids, 372/372 declared assertions)
PASS T6.1-VISIBLE (20/20 test ids, 430/430 declared assertions)
PASS T6.1-CONCURRENCY (4/4)
PASS T1.2-static (10/10 assertions)
PASS secret ignore audit
PASS production object audit (0 invalid objects)
```

The independent lifecycle test executes the compiled package on an actual E1M1
monster coordinate and proves visible wake, lethal transition, one configured
drop, and one kill credit. All writes are rolled back by the test.

## Combined-combat correction

The T8.1 full-map lab exposed an integration defect not isolated by the focused
T7 suites. Three visible zombiemen each landed 29 guaranteed attacks during
tics 4–200, for 825 raw damage, because `DOOM_MONSTERS.ATTACK` treated clear LOS
as a guaranteed hitscan hit. At the same time player former-human weapon spread
was configured as 0.003–0.006 radians per random-table delta (up to roughly
44–88 degrees), rather than Doom's `<<18` BAM scale.

Production now consumes two ordered database RNG values for monster hitscan BAM
spread, then the damage value, and tests the resulting exact perpendicular miss
against the 16-unit player radius. Pistol, shotgun, and chaingun definitions use
`2*pi/16384` radians per delta. LOS-rejected attacks still consume no RNG and all
behavior remains relational and deterministic.

The independent 27-branch lab changed from every branch dead by sequence 151 to
all branches alive at 97–100 health. A cumulative ordinary-input replay then
finished at 76 health with one kill, seven player hits, 34 monster misses, and
successful post-fight movement from x=-32 to x=93.5405. Monster cadence did not
need adjustment.

Post-correction production hashes:

- `sql/sim/060_monsters.sql`: `dd852b7adb7d0b99156727339301f2b9d11a9428231e496897a12bb211e5346d`
- `sql/sim/staged/t7.1_defs.sql`: `eceb4e7b6afb987fdae02843340778d52f49fe390a37a409174f141f1c3567be`

The complete T7.2 2,565-assertion/24-mutation gate, T7.1 1,582-assertion gate,
T6.1–T6.4 regressions, concurrency, history, lifecycle, frozen integrity, and
production validity all passed again on the preserved isolated T8.1 stack.
