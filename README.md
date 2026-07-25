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
game state carries a SHA-256 identity. The final reproducible authority
`5ec18cbe…` matches the preserved OJVM oracle after every one of the 13,272
no-cheat E1M1 ledger tics. It also passes the 330-tic canonical, every-tic
762-tic co-op, and leave/neutral/checkpoint/rejoin membership differentials.
OJVM is not
in the production path; it remains in repository/dev tooling because it is
the differential instrument that makes future MLE changes auditable.

**The performance result is honest, not finished.** ORDS does not preserve
request-local engine state, so a retained Oracle Scheduler session owns each
MLE world and REST calls communicate through durable rows. A sparse
four-player ticker microbenchmark reached 132.9 tics/s, but that number does
not represent real gameplay. Removing TeaVM's reachable coroutine/pacing shape
raised the exact 5,250-tic production deathmatch stream from 6.002 to 19.788
tics/s on Oracle AI Database 26ai Free. Quiet windows now clear 35 Hz, while
20-awake-monster peak windows remain about 7–9 tics/s (106–141 ms/tic).
A fresh peak-weighted Node profile on the final `5ec18cbe…` lineage assigns
23.6% of ticker work to sight/BSP, 14.0% to mobj long/flag handling, 9.3% to
action dispatch, and 8.4% to movement/AI after excluding profiler-control
overhead. A property-tested narrow flag optimization was exact but improved
real MLE throughput by only 2.7% (1.4% median in high-awake windows), so it was
rejected under the predeclared 5% rule. The final-artifact hidden-JIT closeout
then found one default-configuration matched window improving 25.5% by
corrected wall median and 41.1% by monotonic throughput. That is a localized
compiler landing signal awaiting independent reproduction, not a 30 FPS
success. OCI Always Free 26ai measured
171–189 ns per warmed
arithmetic iteration and 91 ns per gathered byte. That permanently closes the
ADB-JIT and exact live database-rendering branches under the approved 100 ns
rule; its 1.7–2.5x venue uplift is capacity evidence, not a 35 Hz claim.

The hidden-compilation investigation proved that this Free build contains an
optimizing MLE compiler: a deterministic integer kernel improves from roughly
373 ns/iteration interpreted to 2.792 ns/iteration compiled. Those controls
are undocumented and remain diagnostic-only. The first measured de-CPS
authority, `2848ef7a…`, removes the reachable pacing/sleep root and matches
pinned `e485…` after every tic of the preserved 5,250-tic deathmatch stream.
In direct interpreted MLE it improves whole-route throughput
from a comparable ADVANCED artifact's 6.002 to 19.788 tics/s (3.30x), with
36.640/142.665 ms p50/p95. Quiet late-route windows now run in 10–11 ms/tic;
peak combat remains 106–141 ms/tic. No 30 FPS success is claimed.

Post-ledger hardening found that `2848ef7a…`'s timestamp-bearing input JAR was
not retained and could not reproduce that exact minified byte sequence. The
build now pins its archive timestamp. Two consecutive builds produced the same
1,081,335-byte successor, `5ec18cbe…`, which matches `2848ef7a…` across 5,250
tics and 5,251 full canonical-state comparisons. Its fresh 13,272-tic every-tic
Oracle differential passed, source promotion and database deployment completed,
and the dashboard remains fail-closed on the recovery/final-soak gates that
still must be rerun for this artifact. Evidence is never inherited across
artifact SHAs. The generated
`client/dist/mle-status.json` is the authoritative live
source/deployment/lifecycle state after those transitions, avoiding a prose
claim that can silently outlive a deployment. Both immediate and hot-threshold
synchronous compiler cells still spend more than five minutes in `MLE park`
without reaching the ticker.

The first de-CPS/linear-memory spike compiled and is byte-exact when executed
as native WebAssembly, but Binaryen 131's wasm2js translation loses mobj
`long` high words at tic zero. That translator is rejected and was not timed
in MLE. The queued reduction now distinguishes optimizer effects, field
loads, and i64 call-boundary loss; only a confirmed call-boundary failure may
try the tracked int-high-word serializer workaround, and exact tic-zero plus
100-tic parity still precedes any rank cell.

Exact live database rendering is closed on both measured Free venues. Exact
MLE rendering remains the asynchronous audit/DVR tier. Live presentation is a
confirmed-only browser renderer consuming chained authoritative deltas; it
does not simulate ahead, reorder, or reinterpret database state.

**Multiplayer, where the database is the server.** Two browsers join one
authoritative world living in Oracle. The engine advances once per ordered
command vector and emits one confirmed transition chain. Each browser renders
its own point of view, with per-listener positional audio. Co-op and
deathmatch are available. Deterministic multiplayer gates are bound to their
recorded artifact SHA; the pre-de-CPS `e485…` authority passed the
maximum-distance high-density recovery gate, while every promoted replacement
must rerun recovery, lifecycle, and final-soak qualification. The WAN matrix
is still in progress.

Numbers, measured on the local two-core Oracle Free stack:

| Measurement | Result |
| --- | --- |
| Current database authority | `5ec18cbe…` (1,081,335 bytes) |
| Full E1M1 MLE/OJVM differential | 13,272/13,272 tics exact on current `5ec18cbe…` |
| Current co-op MLE/OJVM differential | 762/762 tics exact on `5ec18cbe…` |
| Pre-deCPS maximum-distance recovery | 57.337 s estimated total at 20 awake monsters |
| Production-shaped deathmatch throughput | 19.788 tics/s whole-route on de-CPS; peak windows ~7–9 tics/s |
| De-CPS current build | `5ec18cbe…`, promoted and deployed after every-tic ledger PASS |
| Pre-de-CPS production-shaped MLE CPU | 253.6 ms/tic on `a942cd2d…` (historical) |
| De-CPS quiet / peak windows | ~10–11 ms/tic / ~106–141 ms/tic |
| Last fully qualified soak | 30 min PASS on superseded `a942cd2d…` |
| Pre-deCPS `e485…` lifecycle/final soak | Not reusable as de-CPS cutover evidence |

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
reproducible `5ec18cbe…` every-tic ledger and source/database promotion have
passed. The current critical path is a fresh de-CPS Node profile, Amdahl
ceiling, and one directly ranked peak-combat batch, followed by the remaining
lifecycle/final-soak and WAN qualification on that exact artifact. The OCI
Always Free probe is complete and interpreter-tier; cloud qualification now
uses OCI CLI and the existing `doomdb-adb` target. Deep-dive evidence lives in
[artifacts/performance/](artifacts/performance/) and [reports/](reports/).

## Credits

- [Mocha Doom](https://github.com/AXDOOMER/mochadoom) (GPLv3, pinned) is
  compiled by TeaVM into the production MLE JavaScript authority and browser
  presentation artifacts.
- [Freedoom Phase 1](https://freedoom.github.io/) (BSD) provides the game
  content.
- Everything else is MIT — see [LICENSE](LICENSE).

id Software made Doom run on everything. This just continues the tradition.
