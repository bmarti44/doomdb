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
| P12.0 | Complete | Pulled-forward local renderer acceleration keeps canonical goldens intact and reduces repeated clean `NEW_GAME` from 121.79 to 26.30 seconds. |
| P8 | Active | The full legitimate E1M1 route is executing through the public tic transaction. Its current public checkpoint is tic 1430 with 46 health and 9 kills, approaching lift 2; blue key, exit, repeatability, and milestone-frame review remain. |
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
T12.0 staging path now completes repeated clean `NEW_GAME` calls in 26.30 seconds
with the exact prior state hash, frame hash, and 92,658-byte payload, down from
121.79 seconds. A fresh bootstrap's first call measured 28.01 seconds. The
canonical reviewed renderer remains unchanged as the independent parity oracle.
An independent Sol/xhigh evaluation rejected MLE JavaScript and `UTL_TCP` for
the production path: neither reduces the dominant relational renderer work,
and `UTL_TCP` cannot replace the required inbound ORDS/AutoREST transport. The
confirmed improvement came from shared relational staging; final T12 will still
measure the fixed 300-frame replay and every post-render stage locally and in the
cloud.

## Is it playable yet?

Not interactively yet. The complete R2 presentation renderer is correct and
reviewable, and T12.0 made clean first-frame API generation about 4.6 times
faster, but 26.30 seconds per `NEW_GAME` is still far from real time. The
dashboard is useful for visual review; final representative STEP/FPS measurement
and further golden-preserving optimization remain in T12.1–T12.2.

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
