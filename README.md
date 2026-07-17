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

P0–P7 are complete. P8's completion route is preserved while T8.3 closes four
defects found during live `/play/` testing: actor blinking, absent weapon
animation, delayed input, and unexplained-looking health loss.

The selected retained worker now supports arbitrary live movement, collision,
weapon selection, common hitscan/melee fire, `USE`/`WALK` triggers, doors,
lifts, switches, carry, blocking, monsters, pickups, and world presentation.
Hitscan barrel damage, ordered recursive splash, player armor/death, same-tic
monster death, and the complete rocket/plasma spawn, sweep, impact, splash, and
removal lifecycle also run there with exact SQL parity. SQL remains an
independently executable differential oracle.

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

The 30 FPS combat gate is reopened. Earlier 30.88–32.06 FPS baselines were
invalidated because the owner-collision bug deleted imp fireballs immediately.
The first corrected, JIT-quiescent 300-frame FIRE-every-8 soak rendered 300
distinct frames at **20.79 FPS**, with a 31.7 ms median and 93.8 ms p95 paint
gap. Warm averages are 23.4 ms rendering and 10.1 ms durable relational apply;
projectile simulation is now only 0.44 ms. The active work overlaps rendering
with authoritative apply in a separately fenced resident database worker while
preserving rollback, restart, parity, and exact response-correlation semantics.

The benchmark harness can exercise a deeper throughput window, while the live
client remains latency-oriented at depth two with at most one queued successor.
Every ticcmd—including FIRE—uses the dynamic AutoREST pipeline. The design is
resolution-aware:
visibility and simulation are independent of the 320×200 buffer, and horizontal
plane spans remain planned before enabling the future 640×400 profile.

Full measurements and rejected alternatives are recorded in the
[AutoREST 30 FPS report](reports/performance-P12.0-autorest-split-gate-2026-07-17.md),
with the complete execution contract in [PLAN.md](PLAN.md).

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
