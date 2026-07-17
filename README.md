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

P0–P7 and the pulled-forward P12.0 playability gate are complete. Work has
resumed on P8's full E1M1 completion route.

The selected retained worker now supports arbitrary live movement, collision,
weapon selection, common hitscan/melee fire, `USE`/`WALK` triggers, doors,
lifts, switches, carry, blocking, monsters, pickups, and world presentation.
Hitscan barrel damage, ordered recursive splash, player armor/death, same-tic
monster death, and the complete rocket/plasma spawn, sweep, impact, splash, and
removal lifecycle also run there with exact SQL parity. SQL remains an
independently executable differential oracle.

Isolated 300-frame moving baselines pass at **30.88 FPS** and **32.06 FPS**.
Three FIRE-every-8 repeats pass at **32.00 FPS**, **30.82 FPS**, and **32.00 FPS**, proving that live
combat no longer drains or serializes the command window. Every run produced
300 distinct frames; the baseline retained the exact 330-frame chain
`4d9a7a22dd8c3d02c37d40523e6f5d9fcec18665a374eccd7a9b63427d49b6fd`.
Both combat repeats produced the identical chain
`0d8475430dd0e40a603e729429659cfbbe5c9a8af14e3e7366be879f9d8ac817`.
Their best paint-gap p50/p95 was 31.22/32.09 ms. The independent renderer oracle,
dynamic special, projectile differential, rollback, restart, worker-fencing,
and complete T5.1–T7.3 gates pass.

The client uses a depth-four command window, two concurrent correlated frame
polls, ordered decode, a 32 ms command clock, a 31.8 ms display clock, and a
ten-frame startup buffer. Every live ticcmd—including FIRE—uses this dynamic
AutoREST pipeline. The buffer currently adds about 320 ms of input-to-display
latency; reducing it without losing sustained cadence is still active work. The design is resolution-aware:
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
