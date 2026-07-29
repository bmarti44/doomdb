# DoomDB

Doom, running *inside* Oracle Database. Not next to it. Not "using it for
saves." The authoritative engine lives in a retained Oracle MLE JavaScript
session. The active target is for Oracle Autonomous Database 26ai Always Free
to generate every live framebuffer and deliver at least 30 unique moving FPS;
the browser only copies the completed pixels to canvas.

**Public demo:** [Play DoomDB on Oracle Autonomous Database Always Free](https://G53C2244DAB9063-DOOMDB.adb.us-ashburn-1.oraclecloudapps.com/ords/doom/app/)

The hosted release now uses the database-pixel path: Oracle MLE advances the
authoritative world and produces each complete 320x200 indexed framebuffer.
ORDS returns compressed batches of those pixels; the browser only decompresses,
applies the palette, and copies them to canvas. The terminal two-browser OCI
gate produced 300 sequential, unique database frames per player at 34.182 and
34.133 FPS, with 33.0 and 32.8 ms p95 presentation cadence, zero confirmed
frame drops, distinct player viewpoints, dynamic input, and a checkpoint
crossing. Always Free may stop after an idle period; retry after the database
has resumed if the link is temporarily unavailable.

![DoomDB gameplay recorded from the local stack](media/doomdb-gameplay.gif)

*Real footage from an earlier exact database-frame pipeline. The current
public architecture again generates the final framebuffer in Oracle; the
browser is a framebuffer consumer. Full-quality video:
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
4. MLE rasterizes the player-specific view into a complete indexed
   framebuffer and publishes it through the bounded database pixel ring. ORDS
   returns compressed batches; the browser decodes and copies the pixels to
   canvas. The compact DMD1 state chain remains the authority and recovery
   record, not the live rasterizer.

The target round trip is keypress, HTTP, PL/SQL, MLE JavaScript simulation and
rasterization, completed pixels, HTTP, canvas. The hard demo gate is sustained
browser-observed 30 FPS on Always Free. Firing the pistol is a database
transaction and the resulting wall, sprite, weapon, and HUD pixels are
database output. A demon dying is authoritative database state advancement.
Your save file is rows plus an exact checkpoint.

The renderer program moved through deliberately disposable floor and layout
probes before reaching the deployed integrated candidate. It emits a complete
64,000-byte indexed framebuffer with real E1M1 portal geometry, textures and
flats, dynamic state, sprites, weapon animation, and the Doom status display.
The current public two-POV producer sustains 25.701 tics/s with no client
pixel polling; the 30 FPS gate is therefore still open. A prior 300-frame
browser sample averaged just over 30 FPS by spending startup backlog, but it
was not sustained producer evidence and is no longer described as a pass.
Visual and gameplay fidelity also remain separately reviewable—the
specialized renderer is not a byte-for-byte Mocha rasterizer.

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

**The performance result is honest and venue-qualified.** ORDS does not preserve
request-local engine state, so a retained Oracle Scheduler session owns each
MLE world and REST calls communicate through durable rows. A sparse
four-player ticker microbenchmark reached 132.9 tics/s, but that number does
not represent real gameplay. Removing TeaVM's reachable coroutine/pacing shape
raised the exact 5,250-tic production deathmatch stream from 6.002 to 19.788
tics/s on Oracle AI Database 26ai Free. Quiet windows now clear 35 Hz, while
20-awake-monster peak windows remain about 7–9 tics/s (106–141 ms/tic).
Those local numbers are development/capacity evidence, not the release venue:
the same pinned `5ec18cbe…` artifact ran two complete passes on OCI Autonomous
Always Free 26ai at 317.029 and 302.419 tics/s. Its slowest preselected
awake-20 peak window was 140.845 tics/s, more than 4x the 35 Hz requirement,
with zero clock suspects. A full canonical digest chain matched Node at every
500-tic checkpoint and at the terminal, binding the venue result to the exact
authority and command stream. No further local engine optimization is on the
release path.
A fresh peak-weighted Node profile on the final `5ec18cbe…` lineage assigns
23.6% of ticker work to sight/BSP, 14.0% to mobj long/flag handling, 9.3% to
action dispatch, and 8.4% to movement/AI after excluding profiler-control
overhead. A property-tested narrow flag optimization was exact but improved
real MLE throughput by only 2.7% (1.4% median in high-awake windows), so it was
rejected under the predeclared 5% rule. The final-artifact hidden-JIT closeout
then found one default-configuration matched window improving 25.5% by
corrected wall median and 41.1% by monotonic throughput. That is a localized
compiler landing signal awaiting independent reproduction, not a 30 FPS
success. OCI Always Free 26ai's earlier isolated arithmetic probe measured
171–189 ns per warmed iteration and 91 ns per gathered byte, but the complete
ticker result demonstrates that isolated-kernel timing did not predict the
compiled full workload. A separate on-venue exact-frame persistence diagnostic
still failed the live-render bar: the best 300-frame arm measured 212.095 ms
p95 for 300/300 unique, Node-chain-identical frames. That result closed the
general Mocha rasterizer shape; the public database-pixel release instead uses
the specialized renderer described below.

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
and the dashboard remains fail-closed on any artifact-specific gate that has
not been rerun. Evidence is never inherited across artifact SHAs. The selected
live-frame authority is now `c613bb51…`; its generated
`client/dist/mle-status.json` binds the terminal 13,272-tic ledger, deployed
database-pixel renderer/coordinator hashes, two-player browser result, and
session-cleanup evidence. TeaVM did not reproduce the selected authority bytes,
so the lock records exact-SHA selection and the non-reproducible emission
instead of claiming a reproducible build. Both immediate and hot-threshold
synchronous compiler cells still spend more than five minutes in `MLE park`
without reaching the ticker.

The first de-CPS/linear-memory spike compiled and is byte-exact when executed
as native WebAssembly, but Binaryen 131's wasm2js translation loses mobj
`long` high words at tic zero. That translator is rejected and was not timed
in MLE. The queued reduction now distinguishes optimizer effects, field
loads, and i64 call-boundary loss; only a confirmed call-boundary failure may
try the tracked int-high-word serializer workaround, and exact tic-zero plus
100-tic parity still precedes any rank cell.

The original de-CPS OCI presentation report measured a 191.276 ms p95
pipeline over 100 exact unique frames on the locator arm, versus 33.333 ms,
with exact Node-chain identity and zero clock exclusions. A subsequent
stage-separated 300-frame RAW-ring diagnostic corrected its attribution:
the earlier 11.058 ms bucket was the authority step only, while the reported
180.003 ms bucket combined rendering and persistence. On the same pinned
presentation artifact, exact MLE rasterization measured 207.488 ms p95,
two-RAW egress 9.287 ms p95, and bounded-ring publication 2.694 ms p95.
The renderer—not ORDS or durable publication—is therefore the current
database-frame bottleneck. The active target is to make complete 320×200
frames in MLE, deliver them through ORDS, and sustain 30+ unique moving FPS
with a framebuffer-only browser. Compression remains an optional transport
optimization, not the architecture or acceptance goal.

The subsequent legacy-Wasm → wasm2js structural experiment is also closed for
live frames. On OCI, a deliberately incomplete 64,000-pixel raster kernel
measured 140.960 ms p95 in the generated linear-memory shape versus 21.478 ms
for the identical ordinary-MLE-JavaScript operations. The candidate is 6.56×
slower on raster gathers/stores and was already 3.44× slower than the shipping
authority in peak combat. It is classified `DVR_ONLY_ON_COST`; the 0.15
de-CPS authority remains historical evidence, while the generated wasm2js
rasterizer is not part of the public live path. The deployed path combines the
selected MLE authority with a separate specialized framebuffer renderer.
Compression is a transport implementation detail, not a substitute for
database-side rasterization.

A final ordinary-MLE pixel-floor cell explains the remaining synthetic
discrepancy. The 21.478 ms control performs three effective byte-array passes
per pixel (two dependent reads plus one write); its final plateau normalized
to 7.077 ms per frame-sized pass, close to the earlier 5.824 ms one-gather
probe. It did not asynchronously compile, and managed ADB denied the isolated
hidden forced-compilation control even to ADMIN, so no compiled pixel number
is claimed. The exact 207.488 ms renderer is 9.66× slower than the ordinary
three-pass kernel. Per the predeclared rule, that result authorized the
specialized renderer costing summarized next.

That costing subsequently produced the disposable v84 integrated result:
authority step, reduced world raster, sprites, weapon, HUD and persistent BLOB
ring publication completed at 25.272 ms p50 and 32.025 ms p95 across 300
unique frames on OCI Always Free. The result proves a database-internal
single-view route can cross 30 FPS at p95, but it does not supersede the
product gates: p99 was 38.451 ms, one frame stalled for 268.892 ms, the
world raster was 106x56, two-player rendering is unmeasured, and neither ORDS
  nor browser canvas delivery was inside the cell. The preserved c613 authority
  candidate passed its full 13,272-tic differential, but its required patched
  rebuild did not reproduce the same bytes. Two same-input unpatched rebuilds
  also differed from each other. Promotion therefore remains closed on build
  identity rather than simulation determinism.

**Multiplayer, where the database is the server.** Two browsers join one
authoritative world living in Oracle. The engine advances once per ordered
command vector and emits one confirmed transition chain. Each browser renders
its own point of view, with per-listener positional audio. Co-op and
deathmatch are available. Deterministic multiplayer gates are bound to their
recorded artifact SHA; the pre-de-CPS `e485…` authority passed the
maximum-distance high-density recovery gate, while every promoted replacement
must rerun recovery, lifecycle, and final-soak qualification. Held
`DBMS_ALERT` polls requested for 500 ms resumed at 7,575 ms p95 under
Autonomous Resource Manager and were rejected. Brian approved the
`WAIT_FREE_IMMEDIATE_BATCHING` two-leg transport instead. Its final
depth-6 confirmed-state setpoint controller passed the complete OCI WAN
qualification: two browser processes at each of 50±10, 100±20, and 200±40 ms,
with 90-second warmup plus 10 scored minutes per profile. Each player produced
more than 20,100 sequential unique moving frames per profile; cadence p99 was
34.5–36.2 ms, median buffered occupancy was 4–5 tics, and there were no chain
poisons, generation regressions, or presentation resyncs. One 4.045-second
transport stall caused 15 neutral tics for one player (0.0710%, below the
0.5% gate), followed by exact reactivation without resync.

Numbers, measured on the local two-core Oracle Free stack:

| Measurement | Result |
| --- | --- |
| Current database authority | `5ec18cbe…` (1,081,335 bytes) |
| Current database-frame authority | Exact-SHA-selected `c613bb51…`; 13,272/13,272 exact; TeaVM emission is recorded as non-reproducible |
| Full E1M1 MLE/OJVM differential | 13,272/13,272 tics exact on current `c613bb51…` |
| Current co-op MLE/OJVM differential | 762/762 tics exact on `c613bb51…` |
| Pre-deCPS maximum-distance recovery | 57.337 s estimated total at 20 awake monsters |
| OCI production-shaped deathmatch throughput | 302.419 tics/s slower full pass; 140.845 tics/s slowest selected peak |
| OCI correctness binding | 5,250-tic full canonical digest chain PASS vs Node |
| OCI hosted browser (historical state-rendered release) | Post-push depth-6 recheck: 300/300 sequential unique frames; 34.319 FPS; 32.2 ms p95 |
| OCI database-internal live-frame diagnostic | v84: 300/300 unique; 25.272 ms p50; 32.025 ms p95; single POV and reduced 106x56 world raster |
| OCI production database-pixel browser | PASS: two POVs × 300 unique frames; 34.182/34.133 FPS; 33.0/32.8 ms p95; zero drops; tic-512 checkpoint crossing |
| OCI wait-free WAN qualification | PASS; 3 profiles × 2 clients × 10 scored minutes; cadence p99 34.5–36.2 ms |
| OCI production Java-removal audit | PASS; zero Java objects/specs/dependencies and zero legacy API objects |
| Local production-shaped throughput | 19.788 tics/s whole-route; development/capacity evidence only |
| Historical exact frame persistence diagnostic | Final de-CPS arm: 191.276 ms p95; 100/100 exact unique; superseded as a performance shape by v84 |
| Historical reproducible de-CPS build | `5ec18cbe…`, superseded by the selected live-frame authority |
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
is static files. On OCI those files are themselves database-resident BLOBs
served by a dedicated managed-ORDS PL/SQL module with explicit stored MIME,
class-specific cache policy, strong SHA-256 ETags, and empty-body conditional
304 responses. The page and game API share one `oraclecloudapps.com` origin
without a storage bucket, proxy, or CORS bridge.

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
rejected alternatives, and the honest list of what remains. The reproducible
`5ec18cbe…` authority has passed its every-tic ledger, OCI digest-bound
throughput gate, and lifecycle race battery. T11.1's clean/idempotent managed
schema gate, T11.2's database-hosted browser gate, the complete OCI WAN
qualification, and the production Java-removal catalog audit are green. The
post-push hosted recheck presents 300 sequential unique frames at 34.319 FPS.
Local throughput is no longer on the release path. The remaining release
bookkeeping is to freeze, commit, push, and reverify this evidence unit. The
artifact-specific 30-minute soak and unfinished HUD/automap/intermission/finale
surfaces remain explicitly separate open work. Once the release unit is
terminal, the authorized frame-compression/batched-persistence investigation
begins for the asynchronous DVR tier. Cloud qualification uses OCI CLI and the
existing `doomdb-adb` Autonomous Database. Deep-dive evidence lives in
[artifacts/performance/](artifacts/performance/) and [reports/](reports/).

## Credits

- [Mocha Doom](https://github.com/AXDOOMER/mochadoom) (GPLv3, pinned) is
  compiled by TeaVM into the production MLE JavaScript authority and browser
  presentation artifacts.
- [Freedoom Phase 1](https://freedoom.github.io/) (BSD) provides the game
  content.
- Everything else is MIT — see [LICENSE](LICENSE).

id Software made Doom run on everything. This just continues the tradition.
