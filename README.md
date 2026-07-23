# DoomDB

Doom, running *inside* Oracle Database. Not next to it. Not "using it for
saves." The authoritative game engine lives in a retained Oracle MLE
JavaScript session; the browser renders only confirmed state transitions.

![DoomDB gameplay recorded from the local stack](media/doomdb-gameplay.gif)

*Real footage, recorded off the local stack: the title screen and menus are
built from WAD assets served out of Oracle, and the gameplay is presented at
31 FPS — every frame a BLOB the database selected. Full-quality 30 FPS video:
[media/doomdb-gameplay.mp4](media/doomdb-gameplay.mp4).*

## Wait, what?

Here's what happens when you press the fire key:

1. The browser sends a tiny JSON command over REST (ORDS AutoREST — the
   database's own generated HTTP API).
2. Oracle validates it, persists it as a row, and hands it to a pinned
   TeaVM-generated JavaScript build of Mocha Doom running **inside the
   database** in Oracle MLE.
3. The engine advances one tic: the bullet traces, the zombie takes damage,
   monsters think. All of it inside your database session's world.
4. A compact, cryptographically chained DMD1 transition comes back. The
   browser applies that confirmed transition to the same pinned engine artifact
   and renders the 320×200 view.

That round trip — keypress, HTTP, PL/SQL, MLE JavaScript, confirmed delta,
HTTP, canvas — happens at Doom's 35 Hz tic rate. Firing the pistol is a
database transaction. A demon dying is authoritative database state
advancement. Your save file is rows plus an exact checkpoint.

The browser has no authority: it cannot predict, simulate ahead, reorder, or
invent a tic. If you close the tab, the world is still in the database and a
reconnecting client verifies and resumes the confirmed chain.

## The parts I'm proud of

**There are two Doom engines in here, and one grades the other.** Before
porting the real thing, I built a Doom engine in pure SQL and PL/SQL —
visibility, movement, monsters, the works. Frames get converted to
run-length-encoded spans with `MATCH_RECOGNIZE` (the SQL pattern-matching
clause, doing sprite work). The title screen's PSX-style fire effect is
computed by Oracle's `MODEL` clause — a 150-frame animation, 604,369 rows,
bit-identical across independent runs. That SQL engine is now the referee: the
production engine (a pinned GPLv3 build of [Mocha Doom](third_party/mochadoom))
has to match it exactly. The old OJVM adapter remains in repository/dev tooling
only as the permanent differential oracle.

**Everything is deterministic, and I mean forensically.** Every frame and
every game state carries a SHA-256 identity. A full no-cheat playthrough of
E1M1 on skill 3 runs 13,272 tics to the intermission screen — and a fresh
Oracle session replaying the command log reproduces all 13,272 state, frame,
and response hashes exactly. `kill -9` the engine's worker session mid-game
and the database reconstructs the identical frame chain from the command
ledger and carries on.

**It's actually fast.** ORDS wipes session state after every request, so a
long-lived Oracle Scheduler job owns each warm MLE engine and REST calls talk
to it. The final four-player MLE simulation gate sustains 132.9 tics/s on the
edition-capped local stack, with 3.3× headroom over Doom's 35 Hz requirement.
Fresh-context checkpoint recovery takes about 1.8 seconds.

**Multiplayer, where the database is the server.** Two browsers join one
authoritative world living in Oracle. The engine advances once per ordered
command vector and emits one confirmed transition chain. Each browser renders
its own point of view, with per-listener positional audio. Co-op and deathmatch
are both available, survive worker/ORDS recovery, and replay to the exact
terminal hash.

Numbers, measured on the local two-core Oracle Free stack:

| Measurement | Result |
| --- | --- |
| Four-player MLE simulation throughput | 132.9 tics/s |
| Final retained-session soak | 30 min PASS |
| Single-player early authority admission | 110.458 s cold |
| Fresh-context checkpoint recovery | ~1.8 s |
| Full E1M1 MLE/OJVM differential | 13,272/13,272 tics exact |
| Co-op MLE/OJVM differential | 762/762 tics exact |

## Architecture

```text
static browser client
        │ generated ORDS AutoREST: single-player + capability-secured match API
        ▼
ORDS connection pool
        ▼
Oracle Database
  durable commands, checkpoints, hashes, events, and DMD1 transitions
        ▼
  retained Scheduler session per game/match + generation fence
        ▼
  one authoritative TeaVM/MLE Mocha Doom world → confirmed transition chain
        ▼
  browser verifier + renderer → per-player indexed frame
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

Then open <http://localhost:8080/play/>. New Game starts single-player by
default. The right-side **Co-op** and **Multiplayer** buttons open two-player
co-op and deathmatch respectively. Cold MLE construction on Oracle Free takes
about two minutes; the loading screen reports progress while authority starts.

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

- [Mocha Doom](https://github.com/AXDOOMER/mochadoom) (GPLv3, pinned) is
  compiled by TeaVM into the production MLE JavaScript authority and browser
  presentation artifacts.
- [Freedoom Phase 1](https://freedoom.github.io/) (BSD) provides the game
  content.
- Everything else is MIT — see [LICENSE](LICENSE).

id Software made Doom run on everything. This just continues the tradition.
