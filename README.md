# DoomDB

DoomDB runs Doom simulation and rendering inside Oracle Database. The browser is
a thin static canvas/audio client: it submits live keyboard or touch commands to
generated ORDS AutoREST procedures and displays the indexed frame returned by
Oracle. There is no separate game server and no prerecorded route in the play
path.

Open the local dashboard at <http://localhost:8080/> and the playable client at
<http://localhost:8080/play/> while the Compose stack is running.

## Database-rendered output

These reviewed 320×200 frames are produced from Oracle output and frozen as
visible goldens.

| Gameplay | Automap |
| --- | --- |
| ![Database-rendered pistol gameplay](goldens/t5.4/game-pistol.png) | ![Database-rendered full automap](goldens/t5.4/automap-full.png) |

| Menu | Intermission |
| --- | --- |
| ![Database-rendered menu](goldens/t5.4/menu-selection-2.png) | ![Database-rendered intermission](goldens/t5.4/intermission.png) |

More reviewed views include the [shotgun HUD](goldens/t5.4/game-shotgun.png),
[paused game](goldens/t5.4/game-paused.png),
[normal automap](goldens/t5.4/automap-normal.png), and
[masked/sprite diagnostics](goldens/t5.3/).

## Current status

P0–P7 and the original T8.3 live-play defect closure are complete. P8's
deterministic E1M1 route now reaches the real exit switch in the isolated route
lab. Two clean post-checkpoint replays ended at tic 4,118 with 49 HP, 42 kills,
34 items, one secret, and exact state SHA
`ac5d82cba9ab641192e91e02dc6856dd9210dc57b4b7fad156bab0b40373b7e6`.
The exit command now authors `DONE/INTERMISSION` before canonical capture; the
captured database frame is shown below. Its frame SHA is
`32028078e1db3695ff9b8809641d3dea3a1c458caa25973c4f5a88489ce8e851`.
The next route slice replaces the checkpoint-chain prefix with one uninterrupted
public-command replay. Its clean lineage now reaches tic 2,110 alive; the
exact-radius line-54 door-jamb defect is fixed without changing the canonical
opening route. Remaining work is routing the low-health combat bridge before
running the complete route twice.

![Database-rendered E1M1 completion](artifacts/t8.1-live/exit-intermission.png)

The selected retained worker now supports arbitrary live movement, collision,
weapon selection, common hitscan/melee fire, `USE`/`WALK` triggers, doors,
lifts, switches, carry, blocking, monsters, pickups, and world presentation.
Hitscan barrel damage, ordered recursive splash, player armor/death, same-tic
monster death, and the complete rocket/plasma spawn, sweep, impact, splash, and
removal lifecycle also run there with exact SQL parity. SQL remains an
independently executable differential oracle.

Save/load branch isolation is now enforced end to end. Event ordinals, monster
sound perception, retained worker loads, renderer snapshots, and response audio
all read only the active `save_lineage`; a live regression proves abandoned
events remain auditable without affecting the continued game.

The presentation fixes are deployed. Renderer catalog fallback keeps monsters
visible across authored state transitions, the real Freedoom `BAL1A0` imp
fireball is seeded, and both SQL and retained renderers select the current
database `weapon_state`. Audio loading no longer blocks canvas paint. A fresh
browser regression measured **25.9 ms input-to-submit** and **148 ms
input-to-correlated-paint**, with seven distinct pistol animation frames.

Projectile collision now excludes the owner and includes the separately stored
player. A deterministic SQL fixture proves the missile travels, leaves its
owner at 60 HP, and changes player health from 100 to 97 only on tic 7, which
carries correlated `PROJECTILE_IMPACT` and `PLAYER_DAMAGE` events.

Player hitscan, projectiles, and splash now read live sector heights, matching
monster line-of-sight when doors move. This removes the asymmetric case where
monsters could fire through an open doorway while the player's shots still hit
its original closed geometry; the completed E1M1 route exercises the fix.

The corrected combat path now clears the 30 FPS gate. Two quiescent 300-frame
FIRE-every-8 runs rendered 300/300 distinct frames at **31.95 FPS** and
**30.81 FPS** with exact identical frame chains; paint-gap p95 was 32.14 and
32.28 ms. The database producer itself sustained 31.55 and 30.40 FPS, so the
result does not depend on prebuffering. A compact DMF3 frame envelope reduced
the typical response from about 44 KB to 25.75 KB, explicit synchronous OJVM
compilation removed cold-session compiler contention, and durable commits now
use `IMMEDIATE WAIT`. Rollback/restart fencing and projectile parity still pass.
Post-correction T5.1–T5.3 and T6.1–T7.3 are green. T5.4 source, mutation, and all
nine reviewed golden checks are green; its final live SQL-oracle replay is
reserved for an isolated database because the intentionally brute-force parity
renderer can starve an interactive two-core stack.

The benchmark harness can exercise a deeper throughput window, while the live
client remains latency-oriented at depth two with at most one queued successor.
Every ticcmd—including FIRE—uses the dynamic AutoREST pipeline. The design is
resolution-aware:
visibility and simulation are independent of the 320×200 buffer, and horizontal
plane spans remain planned before enabling the future 640×400 profile.

Full measurements, rejected alternatives, and remaining regression work are in
[PLAN.md](PLAN.md) and [reports/](reports/).

## Architecture

```text
static browser client
        │ generated AutoREST: NEW_GAME / SUBMIT_STEP / POLL_FRAME
        ▼
ORDS connection pool
        ▼
Oracle Database
  durable command ledger + authoritative relational state
        ▼
  bounded resident Scheduler worker (PL/SQL + OJVM retained arrays)
        ▼
  deterministic simulation → exact renderer → codec → SecureFile response
```

ORDS resets request-session package and Java state after every request, so a
bounded long-lived database Scheduler session owns each warm worker. Tables,
hash chains, checkpoints, and response BLOBs remain authoritative and durable;
the browser never simulates or renders the world itself.

## Run locally

Create local-only secrets from the fake templates, install the pinned Node
dependencies, and start the stack:

```sh
cp secrets/oracle_password.txt.example secrets/oracle_password.txt
cp secrets/doom_password.txt.example secrets/doom_password.txt
npm ci
docker compose up -d
```

On a brand-new database volume, wait for Oracle to become healthy and run the
schema/data bootstrap once:

```sh
docker compose wait db
./scripts/bootstrap.sh
docker compose restart ords
```

Then visit <http://localhost:8080/play/>. Controls are W/S to move, A/D to turn,
Ctrl to fire, Space to use, and number keys to select weapons. Touch controls
are shown on mobile.

Real credentials, wallets, private keys, environment files, and Terraform
variable files are ignored by [.gitignore](.gitignore); only explicit fake
`*.example` templates are committed.

## Verify

```sh
./verify.sh env
./verify.sh secrets
./verify.sh task T7.3
./verify.sh evaluator-self-test
```

See [reports/](reports/) for implementation, performance, and review evidence.
