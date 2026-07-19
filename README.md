# DoomDB

DoomDB runs Doom inside Oracle Database. The browser is a thin static
canvas/audio client: it sends keyboard or touch commands through generated ORDS
AutoREST procedures and displays frames returned by Oracle. There is no external
game server and no prerecorded route in the play path.

Open the local dashboard at <http://localhost:8080/> and the current playable
client at <http://localhost:8080/play/> while the Compose stack is running.

## Current status

The active implementation path is **P12.M: Mocha Doom inside Oracle's JVM**,
and it is playable end to end on the local stack. New `/play/` sessions run the
pinned GPLv3 `AXDOOMER/mochadoom` engine (commit `c0af1322…abe93`) as Java
schema objects inside OJVM, owned by a long-lived Scheduler worker session and
reached only through generated ORDS AutoREST. The previous clean-room SQL/PLSQL
engine (phases P0–P7) remains intact and independently executable as the
differential and visual oracle.

What works today, all verified by repeatable gates:

- **Playable game.** Title screen, WAD-native menus, skill selection, dynamic
  movement/turning/fire/use, doors and lifts, monsters, damage, authored audio
  events, pause/automap/menu, GOD/ALL/NOCLIP/FULLMAP verification cheats,
  save/load with lineage forking, and exact replay
  — every displayed pixel selected inside Oracle, every input a database
  transaction.
- **Determinism and recovery.** Frames and state carry SHA-256 identities; the
  append-only `ticcmd_t` ledger reconstructs a killed or restarted worker to
  the identical frame chain; duplicate requests replay byte-identical
  responses; concurrent sessions are isolated by generation fencing.
- **30 FPS locally.** Repeated 300-frame moving/combat routes through the real
  HTTP/browser pipeline hold 30–32 displayed FPS with paint-gap p95 ≤ 33.3 ms
  and 300/300 unique frames (frame-chain SHA `a1888c88…4be900` reproduced
  across independent runs).
- **Operational resilience (2026-07-19).** Worker claims self-heal when the
  Oracle Scheduler loses an async job dispatch; dead claims are reclaimed;
  when all four worker slots are busy the least-recently-active idle worker is
  evicted (bounded, deterministic, durable-state reconstruct) so a new player
  is never refused; the eleven-gate Mocha regression suite passes from a fully
  occupied pool.
- **Fast new games.** A pre-warmed standby worker constructs the next Mocha
  engine ahead of the claim, cutting a new game from ~17 s cold to ~1.4 s —
  proven byte-exact with a cold construction (identical frame/state/payload
  SHA chains). The skill menu additionally overlaps any remaining
  construction with a speculative default-skill allocation.

Key verified numbers (local two-core Oracle Free stack):

| Measurement | Result |
| --- | --- |
| Engine step + render + BLOB (warm, p95) | 3.2–3.9 ms |
| Durable tic with ledger + synchronous commit (p95) | ~20 ms |
| Displayed FPS, two independent 300-frame routes | 30.75–32.05 |
| New game, standby-claimed vs cold construction | ~1.4 s vs ~17 s |
| Tic-zero frame SHA-256 | `a1c9b037…d3b5` |
| IWAD BLOB (SecureFile, SHA-verified) | 28,795,076 bytes |

What is left (see [PLAN.md](PLAN.md) §7 for the task cards):

- **P8** — finish the remaining reviewed Mocha fixtures (uninterrupted full-
  E1M1 completion replay and browser-visible death/restart/intermission); the
  42-request direct AutoREST workflow is green.
- **P9** — the Oracle `MODEL`-clause title fire animation (T9.1).
- **P11** — the real S3 + Autonomous Database deployment; blocked only on
  cloud credentials, local dry-runs exist.
- **T12.1/T12.2** — the final golden-preserving local *and cloud* 300-frame
  performance protocol (the local 30 FPS evidence does not substitute for it).
- **P13** — database-authoritative multiplayer, planned after the
  single-player matrix is fully green.

Full measurements, rejected alternatives, and acceptance gates are maintained
in [PLAN.md](PLAN.md), the
[P12.M OJVM performance report](reports/performance-P12.M-mochadoom-ojvm-2026-07-18.md),
the [2026-07-19 outage triage](reports/task-T12.M-triage-2026-07-19.md),
and [reports/](reports/).

## Reviewed database output

These 320×200 frames are frozen goldens from the previous Oracle SQL renderer,
which remains the independent visual oracle during migration.

| Gameplay | Automap |
| --- | --- |
| ![Database-rendered pistol gameplay](goldens/t5.4/game-pistol.png) | ![Database-rendered full automap](goldens/t5.4/automap-full.png) |

| Menu | Intermission |
| --- | --- |
| ![Database-rendered menu](goldens/t5.4/menu-selection-2.png) | ![Database-rendered intermission](goldens/t5.4/intermission.png) |

The legacy E1M1 route also reached the real exit at tic 4,118 with an exact,
database-rendered intermission frame:

![Database-rendered E1M1 completion](artifacts/t8.1-live/exit-intermission.png)

## Target architecture

```text
static browser client
        │ generated AutoREST: NEW_GAME / SUBMIT_STEP / POLL_FRAME
        ▼
ORDS connection pool
        ▼
Oracle Database
  durable commands, checkpoints, hashes, events, and response BLOBs
        ▼
  retained Scheduler session + AQ generation fence
        ▼
  headless Mocha Doom in OJVM → indexed frame → response codec
```

ORDS resets request-session PL/SQL and Java state after every request, so a
bounded long-lived Scheduler session owns each warm engine. ORDS remains the
only browser API, Oracle remains the only server runtime, and the browser never
simulates or renders the world itself.

## Run locally

Create local-only secrets from the fake templates, install pinned Node
dependencies, and start the stack:

```sh
cp secrets/oracle_password.txt.example secrets/oracle_password.txt
cp secrets/doom_password.txt.example secrets/doom_password.txt
npm ci
docker compose up -d
```

On a new database volume, bootstrap once and restart ORDS:

```sh
docker compose wait db
./scripts/bootstrap.sh
docker compose restart ords
```

Then visit <http://localhost:8080/play/>. The database-owned title screen leads
to New Game and skill-selection menus before allocating a Mocha Doom game inside
OJVM. Click or press Enter to begin; the game remains windowed.
The visible menus are composed from the pinned Freedoom IWAD's original Doom
patches served by Oracle; browser HTML supplies accessibility targets only.
Controls are W/S or Up/Down to move, A/D or Left/Right to turn, F or Ctrl to
fire, Space to use, Tab for the Doom menu, M for the automap, P to pause, and V
to toggle audio.
Escape is deliberately reserved for the browser so one key never races three
behaviors: a tap releases the captured mouse, and holding it exits fullscreen.
Once gameplay starts, click the game to capture the cursor; horizontal mouse
movement turns and left-click fires. On macOS, rapid double-Control presses
trigger the host's Dictation prompt in a windowed browser. Canvas clicks never
enter fullscreen. Use the dedicated top-right Fullscreen button to explicitly
enter fullscreen Keyboard Lock, which captures both Ctrl keys so firing never
opens that prompt. Leaving fullscreen restores the windowed capture.

Real credentials, wallets, private keys, environment files, WADs, generated
classes/JARs, and Terraform variable files are ignored by
[.gitignore](.gitignore); only explicit fake `*.example` templates are tracked.

## Verify

```sh
./verify.sh env
./verify.sh secrets
./verify.sh task T7.3
./verify.sh evaluator-self-test
```

See [reports/](reports/) for implementation, performance, and review evidence.
