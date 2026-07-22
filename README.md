# DoomDB

Doom, running *inside* Oracle Database. Not next to it. Not "using it for
saves." The game engine itself lives in the database, and the browser is just
a dumb screen.

![DoomDB gameplay recorded from the local stack](media/doomdb-gameplay.gif)

*Real footage, recorded off the local stack: the title screen and menus are
built from WAD assets served out of Oracle, and the gameplay is presented at
31 FPS — every frame a BLOB the database selected. Full-quality 30 FPS video:
[media/doomdb-gameplay.mp4](media/doomdb-gameplay.mp4).*

## Wait, what?

Here's what happens when you press the fire key:

1. The browser sends a tiny JSON command over REST (ORDS AutoREST — the
   database's own generated HTTP API).
2. Oracle validates it, persists it as a row, and hands it to the Doom engine —
   which is 830 Java classfiles loaded **into the database** as schema objects,
   running on the JVM that has quietly shipped inside Oracle since the 90s.
3. The engine advances one tic: the bullet traces, the zombie takes damage,
   monsters think. All of it inside your database session's world.
4. The finished 320×200 frame comes back as a BLOB. The browser applies the
   palette and blits it to a canvas.

That round trip — keypress, HTTP, PL/SQL, Java-in-Oracle, frame BLOB, HTTP,
canvas — happens **30+ times per second**. Firing the pistol is a database
transaction. A demon dying is relational state advancement. Your save file is
just rows.

The browser contains no game logic at all. No simulation, no collision, no AI,
no rendering decisions. If you close the tab, the world is still in the
database, mid-frame, waiting.

## The parts I'm proud of

**There are two Doom engines in here, and one grades the other.** Before
porting the real thing, I built a Doom engine in pure SQL and PL/SQL —
visibility, movement, monsters, the works. Frames get converted to
run-length-encoded spans with `MATCH_RECOGNIZE` (the SQL pattern-matching
clause, doing sprite work). The title screen's PSX-style fire effect is
computed by Oracle's `MODEL` clause — a 150-frame animation, 604,369 rows,
bit-identical across independent runs. That SQL engine is now the referee: the
production engine (a pinned GPLv3 build of [Mocha Doom](third_party/mochadoom))
has to match it exactly.

**Everything is deterministic, and I mean forensically.** Every frame and
every game state carries a SHA-256 identity. A full no-cheat playthrough of
E1M1 on skill 3 runs 13,272 tics to the intermission screen — and a fresh
Oracle session replaying the command log reproduces all 13,272 state, frame,
and response hashes exactly. `kill -9` the engine's worker session mid-game
and the database reconstructs the identical frame chain from the command
ledger and carries on.

**It's actually fast.** ORDS wipes session state after every request, so a
long-lived Oracle Scheduler job owns each warm engine and the REST calls talk
to it. One engine step — simulate, render, encode, persist — takes 3–4 ms warm.
The pipeline holds 30–32 FPS through a real browser, and a pre-warmed standby
worker cuts "New Game" from ~17 seconds of engine construction down to ~1.4.

**Multiplayer, where the database is the server.** Two browsers join one
authoritative world living in Oracle. The engine advances once per ordered
command vector and renders a separate point of view for each player, with
per-listener positional audio. It holds ~35 FPS, survives worker kills and
ORDS restarts mid-match, and replays to the exact terminal hash. Deathmatch
rules, frags, and the scoreboard included.

Numbers, measured on the local two-core Oracle Free stack:

| Measurement | Result |
| --- | --- |
| Engine step + render + encode (warm, p95) | 3.2–3.9 ms |
| Durable tic with ledger + synchronous commit (p95) | ~20 ms |
| Single-player displayed FPS (300-frame browser routes) | 30.8–32.1 |
| Two-player displayed FPS (300-frame gates) | 34.8–35.2 |
| New game: standby worker vs cold construction | ~1.4 s vs ~17 s |
| Full E1M1 replay, fresh session | 13,272/13,272 hashes exact |

## Architecture

```text
static browser client
        │ generated ORDS AutoREST: single-player + capability-secured match API
        ▼
ORDS connection pool
        ▼
Oracle Database
  durable commands, checkpoints, hashes, events, and response BLOBs
        ▼
  retained Scheduler session per game/match + AQ generation fence
        ▼
  one authoritative headless Mocha Doom world → per-player indexed frames
```

ORDS is the only HTTP surface. Oracle is the only server runtime. The client
is static files.

## Run it

You need Docker and Node. Create local-only secrets from the fake templates,
install pinned dependencies, and start the stack:

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

Then open <http://localhost:8080/play/> (or `/play/multiplayer` with a
friend). Press Enter at the title, pick a skill, and give the database a
moment to build you a Doom engine.

**Controls:** W/S or ↑/↓ move · A/D or ←/→ turn · F or Ctrl fire · Space use ·
Tab menu · M automap · P pause · V audio. Click the game to capture the mouse
(horizontal movement turns, left-click fires); Escape releases it. On macOS,
use the Fullscreen button if you want Ctrl-to-fire without double-Ctrl
triggering the Dictation prompt.

## Verify

Nothing here is "it looked right in a demo." Every claim above is enforced by
a repeatable acceptance gate:

```sh
./verify.sh env
./verify.sh secrets
./verify.sh phase P13          # includes two 300-frame FPS runs and a 30-minute soak
./verify.sh evaluator-self-test
```

[PLAN.md](PLAN.md) is the implementation contract — task cards, measurements,
rejected alternatives, and the honest list of what's left (the final
managed-cloud deployment gate is staged and waiting on real Autonomous
Database credentials). Deep-dive evidence lives in [reports/](reports/).

## Credits

- [Mocha Doom](https://github.com/AXDOOMER/mochadoom) (GPLv3, pinned) is the
  production engine, adapted to run headless inside OJVM.
- [Freedoom Phase 1](https://freedoom.github.io/) (BSD) provides the game
  content.
- Everything else is MIT — see [LICENSE](LICENSE).

id Software made Doom run on everything. This just continues the tradition.
