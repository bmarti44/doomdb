# T6.2 independent movement and collision evaluator candidate

This evaluator is pending explicit user approval. It adds no production SQL,
does not modify an earlier evaluator or the root verifier, and must become
read-only to the T6.2 implementation context after approval.

## Reviewed production interface

T6.2 provides one session-bound table SQL macro:

```sql
DOOM_PLAYER_MOVE(p_session VARCHAR2, p_delta_x NUMBER, p_delta_y NUMBER)
```

It reads the current player row and returns exactly one row with:

```text
SESSION_TOKEN, PLAYER_ID,
START_X, START_Y, START_Z,
DEST_X, DEST_Y, DEST_Z, DESTINATION_SECTOR_ID,
VIEW_HEIGHT, EYE_Z,
CONTACT_COUNT,
FIRST_BLOCKER_ID, FIRST_FRACTION,
SECOND_BLOCKER_ID, SECOND_FRACTION
```

The macro computes a proposal; the approved T6.1 tic transaction consumes that
row in set-based DML. It does not commit or mutate state itself. `P_DELTA_X` and
`P_DELTA_Y` are bind references in the returned relational query. Noclip is not
a caller flag: the macro reads constrained `PLAYERS.NOCLIP`, added by T6.2, so a
browser cannot bypass collision by changing a display/request parameter.

Reviewed configuration rows are `PLAYER_RADIUS=16`, `PLAYER_HEIGHT=56`,
`PLAYER_STEP_HEIGHT=24`, `PLAYER_VIEW_HEIGHT=41`, and
`PLAYER_MAX_CONTACTS=2`. The macro reads them relationally rather than embedding
fixture coordinates. `VIEW_HEIGHT` is the view offset; `EYE_Z` is destination
floor plus that offset.

Candidates come conservatively from `DOOM_BLOCK_CELL`/`DOOM_BLOCK_LINE` and/or
`SDO_FILTER`, followed by evaluator-observable exact swept-circle contact with
the finite segment body and endpoint caps. A candidate reduction may never
change the exact complete-line result. A line blocks when it is one-sided,
carries flag bit 1, or the current `SECTOR_STATE` portal cannot admit the player
cylinder. Portal bottom is the greater current floor; portal top is the lesser
current ceiling. A rise of exactly 24 passes, 25 blocks, and the full 56-unit
height must fit above the adopted floor.

The earliest blocker order is `(fraction, linedef_id)`. After contact, only the
remaining displacement is projected onto the blocking line tangent. This is
repeated for a fixed maximum of two contacts; if still blocked, the last valid
point is retained. Destination sector is resolved through `DOOM_BSP_LOCATE` and
determines destination z and eye height. All geometry and state decisions stay
in set-based SQL; PL/SQL geometry loops and dynamic SQL are forbidden.

## Independent oracle and visible coverage

`reference.mjs` is a separately authored analytic point-versus-capsule sweep. It
does not import production SQL, the WAD parser, geometry helpers, or engine
definitions. Sixteen hand-authored scenarios freeze head-on and oblique contact,
two-contact corner sliding, open portal, exact and excessive step, closed door,
low opening, blocking flag, translated geometry, long-motion tunneling, noclip,
endpoint cap, earliest-fraction order, and exact-fraction id ties. Candidate
order and joint-translation metamorphic checks are also frozen.

The manifest declares 22 stable ids and 372 assertions. Eighteen isolated
semantic mutations cover dimensions, every blocking reason, fraction/id order,
sliding, current openings, continuous/endcap contact, conservative candidates,
noclip, destination floor/eye height, and the two-contact bound. Source and
anti-cheat audits require relational ownership and reject procedural collision,
fixture answers, evaluator coupling, dynamic SQL, or caller-authored noclip.

Candidate checks:

```sh
node evaluator/t6.2/self-check.mjs
node evaluator/t6.2/mutation-self-check.mjs
```

After approval and implementation, `evaluator/t6.2/run-visible.sh` adds the
production-source and live Oracle paths. Missing objects, compile failures,
empty results, timeouts, or incidental infrastructure failures fail closed and
never count as killed mutations.
