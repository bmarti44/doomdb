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

P0–P7 are complete. P12.0 was pulled ahead of the full E1M1 route to make the
dynamic game playable before continuing P8.

The selected retained worker now supports arbitrary live movement, collision,
weapon selection, common hitscan/melee fire, `USE`/`WALK` triggers, doors,
lifts, switches, carry, blocking, monsters, pickups, and world presentation.
Barrel-chain recursion and the complete player rocket/plasma lifecycle remain
the main retained-gameplay gaps; unsupported actions preserve the complete SQL
fallback and SQL remains an independently executable differential oracle.

Two fresh 300-frame moving runs after front-to-back solid-column BSP rejection
passed at **31.04 FPS** and **32.06 FPS**. Both produced 300 distinct frames and
the exact 330-frame chain
`4d9a7a22dd8c3d02c37d40523e6f5d9fcec18665a374eccd7a9b63427d49b6fd`.
The second run had zero stalls and 31.16/32.05 ms paint-gap p50/p95. The
independent 12-pose SQL oracle matched 57,012 accepted intersections, 21,050
visible hits, 12,487 active portal hits, and all 64,000 final pixels with no
differences. Dynamic special, lifecycle, rollback, restart, and worker-fencing
gates also pass.

The client uses a depth-four command window, ordered decode, a 32 ms command
clock, a 31.8 ms display clock, and a ten-frame startup buffer. That buffer
currently adds about 320 ms of input-to-display latency; reducing it without
losing sustained cadence is still active work. The design is resolution-aware:
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
