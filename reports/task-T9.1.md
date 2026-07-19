# T9.1 — ordered Oracle MODEL fire

Status: complete. Production generation, independent full rerun, deterministic
checks, mutation checks, and visual review are green as of 2026-07-19.

## Accepted identities

- Grid: 150 frames at 160×96, 2,304,000 independently checked cells.
- Canonical storage: 604,369 `DOOM_FIRE_FRAME_RUN` rows.
- Animation SHA-256:
  `b1eac353252af51494cfe4ca77a80ac2bad502761bbaf79dd382f1146cb7e4ba`.
- Database-derived APNG SHA-256:
  `79c27b9755741d90c75d405b3ecb01a3dd676957d5517266acffdbf9c24169b3`.
- Exact review strip (frames 0, 35, 75, 110, and 149) SHA-256:
  `302c4342676f8b193f8d0540db4de6cc7cb406de12e569eca5d30d8d16e4ebb5`.

The production source contains one textual SQL `MODEL` clause with `RULES
SEQUENTIAL ORDER` and the required `frame_no ASC, y DESC, x ASC` rule order.
The TypeScript reference independently visits every cell and matches all 150
frame hashes. The review page presents only the APNG and exact-frame strip; it
contains no cellular simulation.

Two independent full-size database executions reproduced the same 604,369
canonical rows, every frame hash, and the accepted animation SHA. The second
run therefore closes the production determinism gate without relying on the
TypeScript reference or the first run's committed rows.

## Full-size feasibility evidence

The first accepted full insert took 2,857,160 ms (47m 37.160s) on the pinned
two-CPU Oracle Free local stack. A live work-area snapshot reported two ordered
spreadsheet operations with maximum work areas of 68 MiB and 31 MiB. The
operation spilled heavily to TEMP: conservative observed lower bounds before
completion were 531.4 GiB physical reads and 211.4 GiB physical writes. This is
an offline capability artifact, not part of the gameplay hot path.

Oracle Free rejected a 2 GiB PGA target with `ORA-56752`; 512 MiB is the edition
ceiling in this environment. Both 256 MiB and 512 MiB targets still spill, so no
further configuration retries are warranted. The accepted result retains the
fixed full dimensions and never falls back to a smaller animation.

## Commands

```sh
node evaluator/t9.1/self-check.mjs
node evaluator/t9.1/mutation-self-check.mjs
T91_REQUIRE_PRODUCTION=1 node evaluator/t9.1/source-audit.mjs
scripts/db_sql.sh evaluator/t9.1/oracle-production.sql
node scripts/t9.1-render-fire.mjs
```
