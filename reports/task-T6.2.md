# T6.2 movement and collision implementation

Status: **COMPLETE — PASS 372/372**

Route: Sol high. The approved and frozen evaluator manifest is
`199b20a2207fb724e8131bf43512fbc195d33e397df04cd07933938b7d4c2251`.
No T6.2 evaluator file was modified.

## Production implementation

`sql/sim/020_movement_collision.sql` provides the reviewed
`DOOM_PLAYER_MOVE(p_session,p_delta_x,p_delta_y)` table SQL macro and the
database-owned `PLAYERS.NOCLIP` constraint/configuration. Its collision core:

- selects every blocking linedef as the conservative exact set, retaining
  BLOCKMAP membership only as a broad-phase hint;
- intersects the moving player circle with the finite segment body and both
  endpoint caps, preventing destination-only tunneling;
- derives one-sided, blocking-bit, step, and cylinder-opening decisions from
  session-current sector heights;
- orders contacts by `(contact_t,linedef_id)`, projects the remainder onto the
  first blocking tangent, and performs exactly one second contact query;
- resolves the destination through `DOOM_BSP_LOCATE`, then owns destination
  floor z, view offset, and absolute eye height relationally;
- reads noclip exclusively from the current database player row and does not
  mutate or commit gameplay state.
- prefers session-current sector heights and safely falls back to immutable map
  heights during the short new-session interval before `SECTOR_STATE` is
  initialized.

Oracle 23.26 does not expand formal macro parameters inside a returned query
whose top-level construct is `WITH` (`ORA-00904` at invocation). The public
interface therefore remains a shallow table SQL macro over a database payload
function. Both exact contact passes remain set-based SQL; orchestration is
fixed at two contacts and contains no collision loop or dynamic SQL.

## Isolated verification

```text
PASS T6.2-EVAL-SELF-CHECK (80/80 fixture-contract assertions)
PASS T6.2-EVAL-MUTATION-SELF-CHECK (18/18 isolated mutations killed)
PASS T6.2-SOURCE-AUDIT (session-bound relational swept collision, openings, sliding, stable contacts)
PASS T6.2-ORACLE-MINI-MAP (10 independent live scenarios)
PASS T6.2-ORACLE-PRODUCTION
PASS T6.2-VISIBLE (22/22 test ids, 372/372 declared assertions)
PASS T0.4 (8/8 assertions)
PASS T0.4-EVALUATOR-SELF-TEST (13/13 attacks rejected)
PASS T6.1-VISIBLE (20/20 test ids, 430/430 declared assertions)
PASS T6.1-CONCURRENCY (4/4 identical and conflicting callers serialized exactly once)
PASS T1.2-static (10/10 assertions)
PASS T3.1-static (24/24 assertions)
PASS secret ignore audit (8 ignored paths, 3 visible templates, no tracked secret-like paths)
```

The frozen sixteen-scenario analytic oracle is covered by the 80/80 self-check
and kills all 18 reviewed semantic mutations. A fresh isolated Oracle volume
loaded all 537 seed files and all 18 ordered production files before the live
production and mini-map probes. The default dashboard database was not reset.
After T4.3 reused the loaded renderer for its approved captures, the isolated
T6.2 container, network, and volume were removed and verified absent.
