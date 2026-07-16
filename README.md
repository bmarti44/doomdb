# DoomDB

DoomDB renders and simulates Doom inside Oracle Database. Oracle owns the map,
game state, collision, combat, world machines, history, and frame construction;
the browser is a thin canvas/audio client.

The project is under active implementation against the contracts in
[PLAN.md](PLAN.md). The local review dashboard is currently served at
<http://localhost:8080/> when the Compose stack is running.

## Current database output

These are reviewed 320×200 frames produced from database output and frozen as
visible goldens.

| Gameplay | Automap |
| --- | --- |
| ![Database-rendered pistol gameplay](goldens/t5.4/game-pistol.png) | ![Database-rendered full automap](goldens/t5.4/automap-full.png) |

| Menu | Intermission |
| --- | --- |
| ![Database-rendered menu](goldens/t5.4/menu-selection-2.png) | ![Database-rendered intermission](goldens/t5.4/intermission.png) |

Additional reviewed views include the
[shotgun HUD](goldens/t5.4/game-shotgun.png),
[paused game](goldens/t5.4/game-paused.png),
[normal automap](goldens/t5.4/automap-normal.png), and the
[R2 masked/sprite diagnostics](goldens/t5.3/).

## Status

As of July 2026:

| Phase | State | Result |
| --- | --- | --- |
| P0–P3 | Complete | Contracts, reproducible stack, WAD ingestion, schema, geometry, BSP, BLOCKMAP, REJECT, and graph gates pass. |
| P4 | Complete | First-light renderer and three human-reviewed database frames. |
| P5 | Complete | R2 portals, clipping, floors/ceilings, sky, masked textures, sprites, weapon/HUD/menu/pause/automap/intermission; reviewed goldens frozen. |
| P6 | Complete | Deterministic tic transaction, movement/collision, world machines, history, save/load, rewind, and replay gates pass. |
| P7 | Complete | Inventory, weapons, pickups, monsters, projectiles, combat, audio, concurrency, lifecycle, mutation, and Chromium gates pass. |
| P12.0 | Active playability gate | Clean-room BSP/projection/solid/portal clipping passes at 0.729 ms p95 with exact SQL portal parity. OJVM JIT works but cold compilation is resource-heavy; full drawing/codec and simulation remain unselected. |
| P8 | Paused behind P12.0 | The legitimate E1M1 route is preserved at tic 1430 with 46 health and 9 kills, approaching lift 2; it resumes only after the pulled-forward performance gate. |
| P9–P10 | Source ready | MODEL-fire, production AutoREST API, thin TypeScript client, and local E2E harness are authored; live acceptance follows P8. |
| P11 | External target pending | Autonomous Database and S3 scripts are ready; real cloud acceptance requires the deployment credentials and targets. |
| P12.1–P12.2 | Pending | The final fixed 300-frame local/cloud profiling and stopping-rule evidence follows completed cloud acceptance. |

The current public route checkpoint is alive at tic 1430 with 46 health, 9
kills, and 15 shotgun shells. It has legitimately opened the corridor doors,
operated and ridden lift 1, reached the lift-2 approach, and cleared a stronger
combat line without losing health. No noclip, teleport, or direct state mutation
is used.

Route evaluation exposed and fixed four production integration defects: a
portal-free boundary transition, stale MOBJ self-references at commit, command
reads leaking across save/load lineages, and occupied lifts refusing to rise.
Focused regressions and the complete adjacent P6/P7 gates pass after the fixes.
A standalone public 163-tic prefix runs in about 31 seconds. The pulled-forward
T12.0 staging path now completes its best warm clean `NEW_GAME` in 6.97 seconds with
the exact prior state hash, frame hash, and 92,658-byte payload, down from
121.79 seconds. A second from-zero bootstrap completed all 41 files with zero
invalid objects and its first call measured 8.89 seconds. The exact moving-frame
probes now measure 7.10–7.84 seconds for one turn and 7.73–8.30 seconds for four
forward tics. The conservative one-turn figure is about 0.128 FPS. The canonical
reviewed renderer remains unchanged as the independent parity oracle.
An independent Sol/xhigh evaluation rejected MLE JavaScript and `UTL_TCP` for
the production path: neither reduces the dominant relational renderer work,
and `UTL_TCP` cannot replace the required inbound ORDS/AutoREST transport. The
confirmed improvements came from precomputed rays, bounded rasterization,
static opacity metadata, shared portal/interval staging, sparse composition, and
chunked frame hashing. JavaBox informed the next architecture experiments—BSP
front-to-back rejection, solid column occlusion, spans, persistent state, and
publish-on-new-frame sequencing—but no GPL code or data is copied. Final T12
will still measure the fixed 300-frame replay and every post-render stage locally
and in the cloud.

The deeper Sol/max review established a narrow, approved OJVM path as the only
measured architecture in the right performance class. After correcting Docker's
JIT shared-memory mount, an isolated coherent 320x200 generation + GZIP + RAW
return averaged 6.8 ms; that is a feasibility probe, not a game-frame result.
The corrected production-boundary render-free baseline for
`DOOM_TIC_TX.APPLY_BATCH` was 68.1 ms p50 / 168.9 ms p95 over 270 warmed unique
turn tics. Exact relational sound-graph closure removed a 95.6 ms repeated BFS
spike; bulk actor housekeeping, one-pass light-neighbor derivation, and modern
state-document work reduction and packed immutable LOS inputs bring the selected
result to 41.4 ms p50 / 70.6 ms p95. A production-shaped brute OJVM analytic probe was rejected at
1,133.9/1,461.5 ms p50/p95 with a 244 KB compressed payload; it proves that the
Java path also needs BSP/solid-column/span work reduction and smaller separately
compiled hot methods. P12.0 therefore has two mandatory workstreams: an exact array-based
OJVM renderer and profile-guided SQL simulation/history reduction. Neither may
claim playability until local AutoREST/browser p50 and p95 are both at most
33.3 ms.

The first real-map clean-room implementation now loads all 681 BSP nodes, 682
subsectors, and 2,057 segs into primitive Java arrays. Its allocation-free
front-to-back traversal, conservative projection, exact intersections, and
two-pass solid-depth coverage and exact portal clipping measured 0.167 ms p50 /
0.729 ms p95 over 20,000
HotSpot samples. Across 12 spawn directions it omitted none of 57,012 accepted
SQL intersections, then retained all 21,050 SQL-visible hits through the first
solid wall while reducing brute-pair retention to 0.2706%. Its ordered portal
walk then matched all 12,487 production SQL active hits with zero missing/extra
and zero final clip mismatches. This validates clipping, not a complete
renderer. Oracle's trace corrected the initial JIT interpretation: the one-line
method compiled successfully in 59.47 seconds, with the cold compiler heavily
constrained by memory and CPU throttling. Deployment compilation will be warmed
separately; only compiled steady-state calls count toward the frame budget.

## Is it playable yet?

Not interactively yet. The complete R2 presentation renderer is correct and
reviewable, and the best exact clean frame is about 16 times faster than the
original baseline, but the current production path is only about 0.128 FPS and
render-free simulation is independently far over budget. The
dashboard is useful for visual review; P12.0 remains active until unique moving
frames sustain 30 FPS (33.3 ms at both p50 and p95).

## Local review

The repository pins Node, npm, Oracle Free, and ORDS versions. Local credentials
must be created from the deliberately fake examples and remain outside Git:

```sh
cp secrets/oracle_password.txt.example secrets/oracle_password.txt
cp secrets/doom_password.txt.example secrets/doom_password.txt
npm ci
docker compose up -d
```

Then open <http://localhost:8080/>. The database can take several minutes to
become healthy on its first boot.

Run the environment and secret checks with:

```sh
./verify.sh env
./verify.sh secrets
```

Real credentials, wallets, private keys, environment files, and Terraform
variable files are ignored by [.gitignore](.gitignore). Only explicit fake
`*.example` templates are intended to be committed.

## Verification

Task gates use the repository's evaluator contract:

```sh
./verify.sh task T7.3
./verify.sh evaluator-self-test
```

See [PLAN.md](PLAN.md) for the complete acceptance matrix and
[reports/](reports/) for implementation and review evidence.
