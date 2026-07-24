# DoomDB

Doom, running *inside* Oracle Database. Not next to it. Not "using it for
saves." The authoritative game engine lives in a retained Oracle MLE
JavaScript session; the browser renders only confirmed state transitions.

![DoomDB gameplay recorded from the local stack](media/doomdb-gameplay.gif)

*Real footage from the earlier exact database-frame pipeline. The current MLE
architecture keeps simulation authority in Oracle and renders confirmed state
in the browser. Full-quality video:
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
   browser applies it to a separately pinned TeaVM presentation artifact and
   renders the 320×200 view.

The target round trip is keypress, HTTP, PL/SQL, MLE JavaScript, confirmed
delta, HTTP, canvas at Doom's 35 Hz tic rate. Firing the pistol is a database
transaction. A demon dying is authoritative database state advancement. Your
save file is rows plus an exact checkpoint.

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

**Everything is deterministic, and I mean forensically.** Every authoritative
game state carries a SHA-256 identity. A full no-cheat E1M1 command ledger
runs 13,272 tics, and the current `103e15e9…` MLE authority matches the
preserved OJVM oracle after every one. The 762-tic co-op route and a
leave/neutral/checkpoint/rejoin membership route are also exact. OJVM is not
in the production path; it remains in repository/dev tooling because it is
the differential instrument that makes future MLE changes auditable.

**The performance result is honest, not finished.** ORDS does not preserve
request-local engine state, so a retained Oracle Scheduler session owns each
MLE world and REST calls communicate through durable rows. A sparse
four-player ticker microbenchmark reached 132.9 tics/s, but that number does
not represent real gameplay. The production-shaped two-player deathmatch
stream measures 3.961 tics/s on Oracle AI Database 26ai Free, with
253.6 ms CPU/tic and 244.672/374.710 ms p50/p95. That is below the 35 Hz
simulation requirement and below the 30 FPS presentation goal. Generated-code
shape, hidden compilation controls, wasm2js, and a paid/ADB venue probe are
being investigated; no 30 FPS success is claimed yet.

**Multiplayer, where the database is the server.** Two browsers join one
authoritative world living in Oracle. The engine advances once per ordered
command vector and emits one confirmed transition chain. Each browser renders
its own point of view, with per-listener positional audio. Co-op and
deathmatch are available. The current artifact has passed deterministic
multiplayer comparison; its density-aware recovery, lifecycle, WAN, and final
soak gates are still in progress.

Numbers, measured on the local two-core Oracle Free stack:

| Measurement | Result |
| --- | --- |
| Current authority artifact | `103e15e9…` (1,170,639 bytes) |
| Full E1M1 MLE/OJVM differential | 13,272/13,272 tics exact |
| Co-op MLE/OJVM differential | 762/762 tics exact |
| Production-shaped deathmatch throughput | 3.961 tics/s |
| Production-shaped MLE CPU | 253.6 ms/tic |
| Peak-combat replay cost | ~290.124 ms/tic |
| Last fully qualified soak | 30 min PASS on superseded `a942cd2d…` |
| Current `103e…` lifecycle/final soak | Pending |

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
co-op and deathmatch respectively. Bootstrap warms an authority slot first and
a recovery slot second; New Game restores a hash-fenced clean tic-zero
checkpoint rather than cold-initializing the engine after the click. Oracle
Free admits one live game at a time. The loading screen reports the current
phase or capacity queue state while a slot is unavailable.

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
./verify.sh phase P13          # deterministic, lifecycle, recovery, FPS and soak gates
./verify.sh evaluator-self-test
```

[PLAN.md](PLAN.md) is the implementation contract — task cards, measurements,
rejected alternatives, and the honest list of what remains. The current
critical path is MLE throughput plus the `103e…` recovery/lifecycle/final-soak
battery. The managed-cloud probe is staged and waiting on real Autonomous
Database credentials. Deep-dive evidence lives in
[artifacts/performance/](artifacts/performance/) and [reports/](reports/).

## Credits

- [Mocha Doom](https://github.com/AXDOOMER/mochadoom) (GPLv3, pinned) is
  compiled by TeaVM into the production MLE JavaScript authority and browser
  presentation artifacts.
- [Freedoom Phase 1](https://freedoom.github.io/) (BSD) provides the game
  content.
- Everything else is MIT — see [LICENSE](LICENSE).

id Software made Doom run on everything. This just continues the tradition.
