# DoomDB

DoomDB runs Doom inside Oracle Database. The browser is a thin static
canvas/audio client: it sends keyboard or touch commands through generated ORDS
AutoREST procedures and displays frames returned by Oracle. There is no external
game server and no prerecorded route in the play path.

Open the local dashboard at <http://localhost:8080/> and the current playable
client at <http://localhost:8080/play/> while the Compose stack is running.

## Current status

The active implementation path is **P12.M: Mocha Doom inside Oracle's JVM**.
The previous clean-room SQL/PLSQL engine remains intact as the differential
oracle. New `/play/` sessions now use the Mocha engine; the SQL implementation
remains independently executable for parity and recovery diagnostics.

The Mocha Doom feasibility gate is green:

- Upstream `AXDOOMER/mochadoom` is pinned at commit
  `c0af1322ee5fd168b5cf8aaaf504cab2d1aabe93` as a GPLv3 submodule.
- All 442 upstream sources plus the adapter compile to 822 classes; the DOOM
  schema reports 852 valid Java classes including 30 preserved legacy helpers.
- Oracle stores and verifies the 28,795,076-byte Freedoom IWAD as a SecureFile
  BLOB; its SHA-256 is `7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d`.
- A bounded headless engine initializes E1M1, accepts dynamic `ticcmd_t` input,
  advances exactly one game tic, and renders a deterministic 320×200 indexed
  framebuffer entirely inside the database.
- The tic-zero frame SHA-256 is
  `a1c9b0378eed9e82425cae593b82dfa44715627d8aa635562b450e4c1af3d3b5`.
  A caller-owned Oracle BLOB receives all 64,000 frame bytes in 1.431 ms.

This path is playable and selected locally. The initial interpreted trace
isolated `Display()` at about 193 ms, but synchronous native compilation of the
actual renderer/action classes reduced stable rendering to 2.8–4.9 ms while
preserving frame hashes. Cold initialization is retained in the Scheduler
worker rather than repeated in ORDS request sessions.

A second evidence-driven gate compiles 26 additional classes touched only by
movement/combat. The resulting 300-sample moving/FIRE-every-8 route produced 299
unique frames at **1.323 ms p50 / 3.927 ms p95 / 8.236 ms p99 / 14.239 ms max**
internally. Ticker and renderer p95 are 2.080 and 1.876 ms. This leaves about
29.4 ms of the 33.3 ms frame budget for persistence and delivery; it is strong
30 FPS feasibility evidence, not yet an end-to-end browser claim.

The first production-shaped command bridge is also green. Oracle maps the
existing live `turn/forward/strafe/run/fire/use/weapon` controls with vanilla
walk/run speeds and the six-tic turn ramp, advances Mocha, renders, and writes
the 64,000-byte frame BLOB in one bounded call. A 300-tic moving/FIRE-every-8
clean rerun measured **1.704 ms p50 / 3.191 ms p95 / 6.025 ms p99 / 22.047 ms max**
with 300 unique frames. Every call returns the exact executed eight-byte
`ticcmd_t`; the new lineage-aware, append-only Oracle ledger stores those bytes
and their command/frame hashes for exact restart replay. A turn-bearing durable
bridge test committed `3228fec000000017`, disposed the JVM, rebuilt from Oracle,
and reproduced frame SHA
`c426186759cd917ce9465ea0ad93bbb180b0b5f498e3a4804e3bbe048709c7d8`.
That gate also found and fixed an upstream low-byte sign-extension defect in
`ticcmd_t.unpack`. The schema's `GAME_ENGINE` selector is now `MOCHA` after the
worker, recovery, persistence, gameplay, presentation-control, and native-code
gates passed.

The existing client-compatible gzip/DMF3 response codec is now part of the same
call. Its component path measured **4.900 ms p50 / 12.797 ms p95**. The next
300-sample gate additionally included both command-ledger inserts, the
authoritative session-frontier update, and `COMMIT WRITE IMMEDIATE WAIT` on
every tic. It measured **8.290 ms p50 / 19.560 ms p95 / 38.798 ms p99 / 69.414
ms max**, then disposed the engine and replayed all 330 committed commands to
the identical final frame SHA. At p95 this durable encoded database core has
13.773 ms left in the 33.3 ms frame budget for AQ/ORDS, wire, decode, and paint.

The unchanged generated AutoREST contract now drives the same path through a
generation-fenced Scheduler/AQ worker. Synchronous STEP plus byte-identical
retry passed, as did asynchronous SUBMIT_STEP/POLL_FRAME with a four-command
burst. The real localhost HTTP/browser-decode harness then rendered **300/300
unique frames at 32.03 displayed FPS** with movement and FIRE-every-8: 31.215 ms
p50 / 32.058 ms p95 paint gaps, 32.795 ms max, and zero presentation stalls.
A depth-2/two-frame-buffer probe was correctly rejected at 27.93 FPS; the
selected depth-4/buffer-10 shape absorbs ORDS tail latency without changing game
semantics. This is the first green Mocha end-to-end 30 FPS gate.

An immediate independent rerun produced the identical frame-chain SHA
`a1888c88d8fa779b9b90e8e650a8a5324f3085c21fe4b44f8e810b26b84be900`
at 32.04 FPS, again with 300 unique frames and zero stalls. Its paint gaps were
31.219 ms p50 / 31.976 ms p95 / 32.777 ms max. The two-run deterministic
AutoREST frame-chain gate is therefore green.

Bounded caller-selected new-game and deterministic disposal calls now pass. All
18 upstream `System.exit` sites are mechanically fenced into catchable OJVM
errors, and deployment fails if an unfenced exit remains. Mocha's native vanilla
save stream was measured and rejected because it diverges at the frame and
continued-branch seam. Exact reconstruction now replays the durable packed
`ticcmd_t` ledger: a fresh 70-command run reproduced tic, RNG index, player
pose, and frame SHA exactly.

The remaining worker fault gates are now green as well. Two simultaneous games
owned separate Scheduler/OJVM sessions, matched after identical commands, then
diverged correctly after opposite turns with no cross-session rows. A forced
worker stop at tic 50 now advances the generation, replays Oracle's ledger, and
produces the same tic-51 frame as an uninterrupted twin with 102 total commands.
If a fresh heartbeat temporarily masks the dead job, the aged correlated poll
performs the exceptional Scheduler check and migrates the exact stored command
to the reconstructed generation. Owner rows and jobs whose game session is gone
are reclaimed without touching active games, and worker map/engine identity is
derived from the immutable session lineage instead of a mutable global selector.

Audio, persistence, and the reported gameplay defects now have
production-shaped gates. Oracle imports all 69 IWAD sound lumps, records a
lineage-hashed authored-audio ledger, and serves observed sounds through
AutoREST. A 330-tic route has continuous visible monsters, weapon and muzzle
animation, no one-frame sprite dropouts, and no health loss without a correlated
damage event. New game returns the exact retained Mocha tic-zero frame.
Save/load forks an exact command lineage, continues the monotonic public command
sequence, and replays every frame across the branch. Crash reconstruction,
concurrent sessions, tic-zero, gameplay, audio, save/load, and replay all pass.
The gates preserve the engine selector they found, so running verification can
no longer switch the live `/play/` page back to the legacy SQL engine.

The current local gate is green. Mocha returns raw binary DMF3 while the client
remains backward-compatible with gzip SQL frames, and Jetty compresses only the
outer AutoREST JSON. ORDS keeps exactly six physical connections for the
four-submit/two-poll pipeline. Most importantly, asynchronous submission now
skips a synchronous response-AQ probe that could never produce a message and
cost about 16 ms per command. Two consecutive warm 300-frame moving/FIRE routes
passed at **30.75 and 32.05 FPS**, each with 300 unique frames. Their paint-gap
p95 values were 32.08 and 32.05 ms; the second run had zero stalls and a 33.02 ms
maximum. A newly restarted or redefined stack still reports that the database
pipeline is warming until its retained OJVM/AutoREST caches settle.

The previous SQL/retained-worker implementation did pass two corrected-combat
qualifications at 31.95 and 30.81 displayed FPS. Those results remain valid for
that engine, but they must not be presented as Mocha Doom performance.

Full measurements, rejected alternatives, and acceptance gates are maintained
in [PLAN.md](PLAN.md), the
[P12.M OJVM performance report](reports/performance-P12.M-mochadoom-ojvm-2026-07-18.md),
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

Then visit <http://localhost:8080/play/>. The database-owned title screen waits
for Enter or a click before allocating a new Mocha Doom game inside OJVM.
Controls are W/S or Up/Down to move, A/D or Left/Right to turn, either Ctrl or
F to fire, Space to use, Tab for the automap, Escape for the menu, and P to
pause. On macOS, F avoids any system Dictation shortcut assigned to Ctrl.

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
