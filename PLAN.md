# DoomDB v2 - Doom rendered and simulated by Oracle Database

Execution plan for Codex CLI. The orchestrator is Sol at medium effort. It routes
bounded tasks to Luna, Terra, or Sol using Section 3, but it may not alter the
charter, acceptance matrix, evaluator, or approved goldens.

This document is the implementation contract. A task is not complete because a
demo looks plausible or because a subset passes. It is complete only when its
listed acceptance command succeeds without weakening an existing check.

## Status summary (updated 2026-07-21)

Orientation only; the task cards and dated checkpoints in Section 7 are the
authoritative record.

- **Complete:** P0–P7 (SQL engine, frozen as the differential/visual oracle),
  P12.0 (pulled-forward 30 FPS enabling gate), T12.M1–T12.M4 (pinned Mocha
  Doom build, bounded OJVM adapter, deterministic command/audio/persistence
  bridge, resident worker + AutoREST cutover). T10.1/T10.2 shipped the public
  package and thin client for the SQL engine and carry forward under Mocha.
- **Complete:** T12.M5 gameplay/performance selection. Single-player local 30 FPS is
  requalified (two independent 300-frame routes, identical frame-chain SHA);
  the 2026-07-19 checkpoints added worker-admission self-healing, bounded
  eviction, the canonical presentation contract, collision-free key bindings,
  speculative skill-menu game allocation, and a byte-exact pre-warmed standby.
  The complete eleven-gate Mocha core suite, the P8.2 direct AutoREST workflow,
  and all four P8.2 browser workflows are green. The complete uninterrupted
  no-cheat skill-3 E1M1 command stream and its fresh-session replay reach
  authentic intermission with all 13,272 state/frame/response identities exact;
  P8.1 is complete. P9 is complete: two independent
  full-size Oracle MODEL runs produced the same 604,369 RLE rows, all 150
  frame hashes, and canonical animation SHA.
- **Complete locally:** P13 database-authoritative multiplayer. Co-op completion, exact
  worker/ORDS recovery, deathmatch rules, per-listener audio, bounded storage,
  browser play, paced-input linearization/idempotency, sampled-ledger identity,
  forced paced-worker recovery, and the co-op two-browser 300-frame performance gate
  are green. Two consecutive enforced runs reached 35.18/34.80 and
  35.18/34.85 FPS; paint p95 stayed at 32.2--32.7 ms and input p95 at
  145.3--181.9 ms.
  The real two-browser canonical co-op route now presents all 762 consecutive
  tics and reaches its exact terminal state hash; per-player sprite colors and
  HUD values are independently rendered from the one retained world. A
  30-minute paced soak advanced both clients from tic 136 to 59,904 with a
  bounded Java heap, 258 retained frame rows, and two checkpoints. Resource,
  chain, lease, and session-soak acceptance is closed; the stable-host
  extreme-tail sample is retained for final P11 cloud certification. The
  verified v1 production cap is two players; three/four-player transport is
  explicitly deferred.
- **Active/last:** P11 real S3 + Autonomous Database deployment. The finished
  single-player + multiplayer build has passed the local T12.1/T12.2 protocol;
  the final stable-host tails travel with the identical managed-ORDS sample.
  Deterministic dry-runs, source/evaluator mutation gates, the fresh 24-domain
  local seed observation, and the approved 13,272-command completion ledger are
  ready. Live execution requires the external Autonomous wallet/target,
  managed ORDS origin, pinned SQLcl, and target S3 bucket. The production gate
  now also builds and content-addresses the complete 830-class Java 8 OJVM
  artifact, verifies JAVAVM/JDK availability before mutation, loads the classes
  and pinned IWAD client-side, and finalizes runtime call specs only afterward.
  A full local Java 8 reload passed the eleven-gate core suite and identical
  300-frame browser chains at 32.39/35.51 FPS.
- **Admission repair (2026-07-21):** `/play/` fresh-game admission is green
  after reproducing a dead Scheduler session whose fenced owner row survived.
  Expiry cleanup now force-stops and reclaims only expired owners after a
  bounded graceful-stop fence and confirmed job absence. Local/fresh stacks
  reserve eight Scheduler job slaves (four retained workers plus dispatch and
  maintenance headroom). The stale-owner live regression and warm browser
  movement/fire gate pass.
- **Local timer qualification (2026-07-21):** a Sol xhigh audit correlated
  98.7% of 865 Oracle `Time stalled` alerts with Lima's 10-second guest-clock
  corrections on this Colima host. Both VZ and an isolated native-x86 QEMU
  profile repeated the drift, so tail-sensitive FPS evidence from a window
  containing an alert is provisional. The retained match cadence uses
  `DBMS_UTILITY.GET_TIME` rather than wall time; the local database now uses a
  two-vCPU cpuset instead of CFS quota and grants only `SYS_NICE` so VKTM/LGWR
  start without ORA-00800. Final local tail acceptance requires a stable-clock
  native Linux/OCI rerun with max/p99.9 evidence; correctness hashes remain
  valid here. The live single-player gate is green after these changes.
- **Known cost:** cold Mocha engine construction in a fresh worker session is
  ~10–20 s depending on host load. The selected pre-warmed standby worker
  (2026-07-19 checkpoint) reduces a standby-claimed new game to ~1.4 s,
  byte-exact with a cold construction; the first game after a quiet stack and
  a fully occupied pool still pay the cold cost.

## 0. Charter

### 0.1 Mission

Build a complete, playable Freedoom Phase 1 E1M1 experience in which Oracle
Database hosts and owns the game service:

- WAD geometry, render assets, engine definitions, live objects, player state,
  sector machines, saves, replays, and audio events are relational data.
- The production game engine is the pinned GPLv3 Mocha Doom Java source port,
  adapted to run headlessly inside a long-lived Oracle JVM Scheduler session.
  Oracle persists accepted commands, save/checkpoint material, hashes, events,
  worker generations, and response BLOBs. The existing SQL simulation and
  renderer remain independently executable migration/regression oracles until
  each affected acceptance gate is explicitly replaced.
- Thin PL/SQL procedures lock a game session, validate input, execute set-based
  statements, persist the result, and return a frame. They do not contain a
  second procedural game engine.
- The canonical frame is 320x200 palette indices. The database also renders the
  weapon, HUD, menu, pause overlay, automap, and intermission into that frame.
- MATCH_RECOGNIZE converts each completed canonical SQL-oracle column into
  constant-color RLE runs. The OJVM production codec must match those runs
  exactly but does not execute MATCH_RECOGNIZE on every moving frame.
- A core title-screen effect uses Oracle's MODEL clause to generate a
  deterministic PSX-style fire animation.
- ORDS AutoREST is the only dynamic HTTP surface.
- The browser collects controls, sends tic commands, decodes the returned frame,
  applies the palette, plays database-issued audio events, and blits to canvas.
  It contains no simulation, collision, AI, visibility, or render decisions.

The desired story is: firing the pistol is a database transaction, monster
thinking is relational state advancement, replay is ordered tic-command data,
and every displayed game pixel was selected by Oracle.

### 0.2 Required capabilities

All of the following are core scope:

1. Full 320x200 textured world rendering at fixed resolution.
2. Floors, ceilings, height transitions, sky, lighting, animation, masked wall
   textures, decorations, monsters, pickups, projectiles, weapon sprite, HUD,
   menus, pause screen, automap, and intermission.
3. Movement, running, turning, strafing, collision, sliding, step-up, use, and
   death/restart.
4. Every linedef and sector special present in Freedoom 0.13.0 E1M1.
5. Keys, doors, lifts, switches, damage sectors, secrets, exit, and completion.
6. Every player-usable weapon and inventory item placed in E1M1.
7. Every monster and interactive object type placed in E1M1, including AI,
   hitscan and projectile attacks, damage, death states, drops, and barrels.
8. Database-authored sound events and E1M1 music playback in the client.
9. Save/load, arbitrary-tic rewind, deterministic recording, and replay.
10. Cheats needed for verification and demonstration: god, all keys/weapons,
    noclip, and full automap.
11. Local Oracle Free + ORDS deployment and a real S3 + Autonomous Database
    deployment using managed ORDS.
12. Deterministic visible and held-back verification, mutation testing, and
    Playwright canvas validation.

Multiplayer is a planned post-core workstream after all single-player rows above
are green. It cannot compensate for a missing required single-player capability,
and selection may not weaken the single-player performance or recovery gates.

### 0.3 Non-goals

- No byte-for-byte vanilla framebuffer, state, savegame, or .lmp compatibility.
- No claim that the project reproduces vanilla bugs or integer overflow.
- No MLE JavaScript, WebAssembly, native extproc, or engine process outside
  Oracle Database in the simulation or render path. The approved Mocha Doom
  engine executes as Java schema objects inside OJVM, reached through the
  resident database worker and generated AutoREST procedures.
- No custom ORDS modules, templates, or handlers.
- No client-side prediction, interpolation, gameplay, collision, ray casting,
  sprite sorting, or reference implementation.
- No maps beyond E1M1 in core scope.
- No pre-authorized lower resolution, flat-color mode, removed effects, or
  smaller game as a substitute for a failed requirement.
- No silent mixing of incompatible licenses or unpinned third-party engine
  revisions. Mocha Doom-derived code and its OJVM adapter are distributed under
  GPLv3-compatible terms with complete provenance and corresponding source.
  Oracle Database itself remains a separately obtained runtime governed by
  Oracle's applicable Free Use Terms; release packaging must not imply that the
  Oracle binaries are relicensed by this project.

### 0.4 Charter reconciliation rule

Before asking or accepting an answer that changes scope, the orchestrator must
compare it with Sections 0.1-0.3. If the answer conflicts, it must surface the
contradiction and obtain an explicit charter amendment. Latest-answer-wins is
forbidden for charter changes. A charter amendment invalidates affected
goldens and requires renewed human approval before implementation continues.

#### Approved P12.0 OJVM amendment — 2026-07-15

The user's explicit instruction to implement every confirmed JavaBox-informed
optimization and reach 30 FPS approves this narrow amendment. Oracle, relational
state/assets, AutoREST, the 320x200 frame, public payload, state/frame hashes,
audio semantics, and the thin browser contract remain authoritative and
unchanged. A clean-room Java 11 stored procedure may own only production render
and codec work inside OJVM, using same-transaction internal JDBC. The canonical
SQL renderer and MATCH_RECOGNIZE codec remain independently callable parity
oracles. No JavaBox, Mocha Doom, id Doom, or other engine code, tables, data,
constants, or translated control flow may be copied. Selection requires exact
byte/hash/RLE/schema parity and the complete T5-T7 suite.

#### Approved P12.0 database-worker simulation amendment — 2026-07-16

The user's explicit instruction to approve all remaining work without further
approval prompts, continue fully autonomously, use Sol Max when blocked, and
reach 30 FPS approves this evidence-triggered amendment. The measured SQL
simulation p95 is 36.939 ms before rendering, and the exact live-state worker
boundary is 42.373 ms p95 before simulation/ORDS; the prior charter is therefore
in direct conflict with the required 33.3 ms end-to-end gate.

A clean-room, array-resident Java 11 simulation loop may run only inside a
long-lived `DBMS_SCHEDULER` worker session in Oracle Database. ORDS AutoREST
records authenticated commands in the durable worker ledger and returns only
committed correlated results; AQ remains the synchronous compatibility path.
Oracle relational tables remain authoritative durable state: every
tic writes deterministic changed-row deltas, command/state/frame hashes, events,
history/checkpoints, and the response BLOB before completion is signaled. The
accepted SQL simulation and SQL renderer remain independently executable
differential oracles; no evaluator/golden is weakened. Selection requires exact
300-frame state/frame/payload parity, duplicate/idempotent request behavior,
worker generation fencing and restart reconstruction, the full T5-T7 suite,
and <=33.3 ms p50/p95 end-to-end. No GPL engine code, control flow, constants,
or tables may be copied or translated; the implementation remains independently
designed from this project's SQL contracts and public behavior documentation.

#### Approved Mocha Doom OJVM engine amendment — 2026-07-18

The user's explicit instruction to pivot the implementation to Mocha Doom
inside Oracle Database supersedes the earlier clean-room/no-GPL restrictions
for the production game engine. Pin upstream
`AXDOOMER/mochadoom` commit
`c0af1322ee5fd168b5cf8aaaf504cab2d1aabe93`, retain its GPLv3 license and source
notices, publish all project modifications and adapters under GPLv3-compatible
terms, and record the exact build input and output hashes.

Mocha Doom must run as Java schema objects inside OJVM, not in ORDS, the browser,
or an adjacent application process. A long-lived `DBMS_SCHEDULER` worker owns
each live engine instance because generated AutoREST requests cannot retain Java
heap state. The existing durable AQ request/response ledger, session/lineage/
generation/sequence fencing, idempotency rules, response BLOB transport, and
thin static client remain the public architecture. ORDS AutoREST remains the
only dynamic HTTP surface.

The adapter must replace desktop window, host keyboard, audio-device, filesystem,
wall-clock loop, and `System.exit` behavior with bounded database entry points:
`new_game`, `step`, `frame`, `save`, `load`, `reconstruct`, and `dispose`. The
pinned Freedoom IWAD is stored as an Oracle BLOB or database-resident Java
resource and is never read from an untracked host path. Every Java entry point
has a catch-all that returns a fenced failure and forces clean reconstruction;
no throwable may escape and silently invalidate retained state.

The existing SQL engine is frozen as a legacy regression oracle during the
migration; Mocha Doom is not required to reproduce project-specific SQL state
hashes or non-vanilla simulation behavior. Replacement goldens require explicit
reviewed fixtures, deterministic command replay, save/load and restart hash
continuity, complete public workflow coverage, and two quiescent 300-frame
moving/combat runs at at least 30 unique displayed FPS with paint-gap p50/p95
no greater than 33.3 ms. Resolution remains data-driven with 320x200 selected
and a 640x400 follow-on profile that does not require another engine rewrite.

## 1. Grounded facts and corrected contracts

### 1.1 Pinned WAD facts

Use Freedoom 0.13.0 Phase 1 only:

- Release archive SHA-256:
  `3f9b264f3e3ce503b4fb7f6bdcb1f419d93c7b546f4df3e874dd878db9688f59`
- `freedoom1.wad` SHA-256:
  `7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d`
- E1M1: 1,196 vertices; 1,175 linedefs; 1,829 sidedefs; 182 sectors;
  292 things; 2,057 segs; 682 subsectors; 681 nodes.
- Bounds: x from -704 through 3248; y from -1064 through 2336.
- Player 1 spawn: thing 157 at (-416, 256), angle 0 degrees, flags 7.
- 521 one-sided and 654 two-sided linedefs.
- Linedef specials present: 1, 2, 11, 23, 26, 62, 88, and 117.
- Sector specials present: 1, 7, 9, and 12.
- Interactive monsters present: types 9, 58, 3001, 3002, and 3004.
- Map lumps include REJECT and BLOCKMAP and both are required inputs.

The parser must reproduce these numbers before any schema or renderer task may
start. Do not search past the next map marker when locating E1M1 lumps.

### 1.2 BSP side contract

Let:

```
cross = (px - node_x) * node_dy - (py - node_y) * node_dx
```

For the non-axis case, side 0 is selected when `cross > 0`; otherwise side 1 is
selected, including equality. Side 0 follows the WAD's first child and side 1
the second. Axis-aligned partitions must reproduce the explicit sign and tie
cases of `R_PointOnSide`, not rely on the generic expression:

```
if node_dx = 0 and px <= node_x: side = (node_dy > 0 ? 1 : 0)
if node_dx = 0 and px >  node_x: side = (node_dy < 0 ? 1 : 0)
if node_dy = 0 and py <= node_y: side = (node_dx < 0 ? 1 : 0)
if node_dy = 0 and py >  node_y: side = (node_dx > 0 ? 1 : 0)
```

The root is the last node. A child with bit 0x8000 set is a subsector and the bit
is removed to obtain its id. A subsector's sector is resolved from its first seg
and the seg's facing sidedef. The known spawn sector is 140.

This contract must be validated three ways before use:

1. A hand-authored table of axis, non-axis, sign, and equality cases.
2. Live probes against the pinned E1M1 spawn and every THINGS coordinate.
3. A source-behavior audit documented in `reports/bsp-audit.md`.

### 1.3 Numeric determinism

- Set `NLS_NUMERIC_CHARACTERS='.,'`, `NLS_TERRITORY='AMERICA'`,
  `NLS_LANGUAGE='AMERICAN'`, and `TIME_ZONE='UTC'` in every SQL entrypoint.
- Never use default `TO_CHAR(number)`. Use an explicit `FM` format and explicit
  NLS third argument, or serialize a quantized integer.
- Canonical hashes use `DBMS_CRYPTO.HASH_SH256` by name.
- Hashed documents contain no timestamps, SCNs, sequence values, session ids,
  elapsed times, or unordered object members.
- JSON aggregates specify an explicit column ORDER BY and `RETURNING CLOB`.
- Gameplay randomness uses a project-owned, checked-in 256-entry table and a
  persisted cursor. It is independently authored and is not Doom's P_Random
  table. Every random read increments the cursor in the ordering specified in
  Appendix F.

### 1.4 Spatial contract

`USER_SDO_GEOM_METADATA` bounds are generated from `MIN/MAX(VERTEXES)` plus
`FAR_DISTANCE + PLAYER_RADIUS`, never from a literal map extent. `SDO_FILTER`
is a primary MBR candidate filter only. Every accepted render, collision, or LOS
result must pass the exact geometry predicate that follows it.

### 1.5 RLE and LOB contract

MATCH_RECOGNIZE emits constant-color runs `(column, y0, length, palette_index)`.
This is a Doom-inspired transport, not Doom's patch-post encoding.

ORDS LOB behavior is established by an executable P0 contract test. The target
wire payload is a gzip BLOB containing canonical compact JSON. ORDS returns the
BLOB using its documented AutoREST JSON representation. The client decodes the
outer representation, gunzips it, and parses the JSON. If the contract test does
not prove this exact shape on pinned local ORDS, stop local implementation for a
charter-level transport decision. The same test must pass on the target
Autonomous Database before P11 begins. Do not invent a fallback.

### 1.6 Reuse boundary

Reuse the WAD's native data structures and acceleration data directly: lumps,
BSP nodes, segs/subsectors, BLOCKMAP, REJECT, palettes, COLORMAP, textures, and
sprites become relational inputs. Reuse public mathematical and behavioral
ideas as independently specified SQL stages: BSP location, ray/segment
intersection, portal clipping, state machines, and tic commands.

Do not refactor, transpile, wrap, embed, or mechanically translate the Doom C
renderer or game loop. A C-to-PL/SQL, C-to-Java, C-to-JavaScript, MLE, WASM, or extproc port
would make the database a host for the old engine rather than the engine itself,
would inherit GPL obligations, and would defeat the Oracle-specific design. The
id source is used only to audit externally observable semantics such as the BSP
side predicate. Every production implementation is written from this plan,
public format documentation, hand calculations, and project-owned fixtures.

### 1.7 MODEL priority

The MODEL fire is a core Oracle capability showcase, not a presumed rendering
speedup. Renderer performance comes first from closed-form intersections,
Spatial/BLOCKMAP candidate reduction, set-based projection, stable cursor reuse,
and compact RLE transport. Do not force MODEL into the world renderer. It may be
used there only if an isolated benchmark with all render goldens green proves a
measured end-to-end improvement. T9.1 remains mandatory regardless.

### 1.8 MLE and UTL_TCP performance decision

MLE JavaScript is not a renderer, simulation, RLE, JSON, LOB, compression, or
tic-batching fallback. A measured local evaluation found renderer SQL
materialization to dominate production frame latency before RLE, JSON, hashing,
or compression begins. Wrapping that SQL in MLE does not change its plan;
fetching its rows into JavaScript adds a language boundary, and moving render
decisions into JavaScript violates Sections 0.1, 0.3, and 1.6.

UTL_TCP is outbound-only and is not an HTTP response transport. It may not be
used to bypass AutoREST or send dynamic game data to a relay. All public dynamic
traffic remains the Section 5.4 `DOOM_API` AutoREST contract.

The local renderer-materialization slice of T12 runs immediately after P7 and
before the remaining P8 replay work. It optimizes the measured relational
renderer first because every public replay batch pays that cost. It separately times RLE,
JSON aggregation, frame hashing, UTF-8 conversion, `UTL_COMPRESS`, ORDS
marshaling, browser decode, and blit before proposing a codec change. Any future
MLE experiment requires a charter amendment, fresh independent evaluation,
local and Autonomous capability probes, and all existing goldens.

## 2. Non-negotiable implementation rules

1. All dynamic browser traffic uses objects enabled by `ORDS.ENABLE_OBJECT`.
2. No `ORDS.DEFINE_MODULE`, handler, application server, or alternate API.
3. SQL and set-based DML own simulation decisions. The approved P12.0 OJVM
   exception may own production render/codec decisions while the SQL renderer
   remains the exact independent oracle.
4. PL/SQL may orchestrate a bounded list of statements per tic but may not loop
   over pixels, walls, or live objects to implement a shadow engine.
5. No recursive WITH in the render path. `CONNECT BY` is allowed for trees.
6. No dynamic SQL in simulation, rendering, transport, or verification.
7. Pose and input values are binds or table rows; never inline them into SQL.
8. No unapproved dependency, image, WAD, engine source, or remote asset.
9. No production code may read evaluator inputs, expected hashes, screenshots,
   reference output, test names, test environment flags, or caller stack state.
10. No production code may replace clocks, comparison functions, hash functions,
    browser APIs, SQL wrappers, or evaluator processes.
11. A failed correctness gate blocks the task. It is never informational.
12. P12.0 performance passes only at 30 unique moving FPS: no more than 33.3 ms
    at both p50 and p95 after warmup. Complete external evidence is mandatory.
13. Resolution and required capabilities may not be reduced for performance.
14. Generated SQL and manifests are byte-stable and checked in.
15. Bootstrap runs from a fresh volume and is idempotent as a complete process.
    Individual seed INSERT files do not need to be independently re-runnable.
16. All licenses, attributions, and source origins are recorded before ingestion.
17. A test passes only through its real assertion path. A timeout, crash, compile
    failure, missing test, empty result, or evaluator infrastructure error fails.
18. Implementation agents never approve their own fixture, golden, snapshot,
    mutation result, visual baseline, or performance stopping decision.

## 3. Orchestrator protocol

### 3.1 Routing rubric

| Task profile | Starting route |
|---|---|
| Mechanical files with exact acceptance: compose, DDL, seed batching, scripts | Luna medium |
| Standard implementation from a closed contract: parser, client, AutoREST, test harness | Terra medium |
| Math, query design, simulation ordering, R2 clipping, MODEL rules | Sol high |
| Architecture or a Sol-high task failing twice for different technical reasons | Sol max |

The orchestrator records `task | model | effort | attempt | rationale | result`
in `reports/routing.log`. Model cost is not a reason to weaken acceptance.

### 3.2 Task execution protocol

Every behavior-producing task after T0.4 is executed as two separately routed
work items under the same task id:

1. `<task>-EVAL` authors independent visible expectations, mutation patches, and
   test ids. It starts Terra high, or Sol high for math/simulation oracles.
2. The user reviews and approves that evaluator work.
3. `<task>-IMPL` starts in a new context with evaluator paths read-only and uses
   the implementation route printed on the task card.

The evaluator item may not add production code. The implementation item may not
add, delete, regenerate, or modify evaluator code or data. Mechanical tasks that
introduce no runtime behavior still require evaluator approval but may use a
single implementation item after T0.4 supplies their generic checks.

For every implementation item:

1. Read this charter, the task card, dependencies, and existing report files.
2. Confirm that the task's EVAL item and expected artifacts are already approved.
3. Record the route before editing.
4. Implement only the task's deliverables.
5. Run its focused check, all earlier phase checks, and the immutable-source audit.
6. Record commands, results, changed files, and measured behavior in a task report.
7. If blocked, write `reports/blocked-<task>.md` with evidence and stop that task.

After two failed approaches, escalation changes model/effort, not requirements.
Evaluator-authoring and implementation work for the same phase run as separate
Codex tasks with separate context. Only the evaluator task receives held-back
inputs. The implementation task may see the public contract and visible tests,
but receives neither held-back fixtures nor expected held-back outputs.

### 3.3 Scope-change protocol

An implementation agent may propose a scope or acceptance change only in a
blocked report. It may not edit Sections 0, 2, 6, evaluator code, approved
goldens, or the capability matrix. The user must approve the change in a separate
turn before affected work resumes.

## 4. Deployment topology and repository contract

### 4.1 Pinned baseline

Resolve platform-specific digests during P0 and write them to `versions.lock`:

- `gvenzl/oracle-free:23.26.2-full`
- `container-registry.oracle.com/database/ords:26.2.0`
- Node.js 24 LTS
- `@playwright/test` 1.61.0 and
  `mcr.microsoft.com/playwright:v1.61.0-noble`
- Freedoom 0.13.0 with the hashes in Section 1.1
- Exact TypeScript, AWS CLI, SQLcl/deployment tool, and build dependency versions

Tags remain beside digests for readability, but Compose deploys digests. Do not
use `latest`, unversioned `npx`, or network installs during verification.

### 4.2 Local topology

- `db`: Oracle Free, persistent named volume, 2 CPU and 2 GB memory limits.
- `ords`: pinned ORDS, configured against FREEPDB1, health-gated on the database.
- `client`: compiled static output mounted as ORDS `standalone.doc.root`, so the
  page and `/ords/doom/...` API are same-origin.
- `evaluator`: test-only Playwright/Node container. It has read-only evaluator
  inputs, network access only to ORDS, and no mount in production containers.

### 4.3 Cloud topology

- Static client files are uploaded to an S3 bucket.
- All dynamic state and assets live in Autonomous Database 23ai or later.
- Managed ORDS exposes the same AutoREST package and object names as local.
- The public demo uses opaque 128-bit game-session tokens and stores no sensitive
  user data. Authentication is not part of v1.
- A browser launched from the actual S3 origin must pass CORS, preflight, API,
  BLOB transport, audio fetch, and canvas checks.
- No Lambda, API Gateway, EC2 service, CloudFront requirement, or middle tier.
  The S3 verification URL may be the explicit HTTPS object URL for index.html.

Cloud completion requires credentials supplied outside the repository as
`AWS_*`, `ADB_*`, and wallet/connection environment variables. They must never be
written to reports or committed files. Their absence before P11 does not block
local P0-P10 work; it makes `./verify.sh cloud-preflight` report `NOT RUN`, never
PASS. P11 and final completion remain blocked until the real cloud gates pass.

### 4.4 Repository layout

```
compose.yaml
versions.lock
.nvmrc
package.json
package-lock.json
deploy/
  local/
  cloud/
vendor/
  freedoom-0.13.0.zip
  COPYING-freedoom.txt
tools/
  wad/
  reference/
  mutations/
sql/
  bootstrap/
  seed/
  schema/
  engine/
  render/
  rest/
client/
  src/
  public/
evaluator/
  visible/
  playwright/
  fixtures/
  snapshots/
goldens/
scripts/
reports/
verify.sh
```

The production image and S3 artifact include only compiled client files. They do
not include `tools/reference`, `evaluator`, `goldens`, reports, or WAD tooling.

## 5. Data and interface design

### 5.1 WAD parser outputs

The TypeScript parser uses Node standard APIs and structured binary readers. It
emits deterministic SQL plus `seed-manifest.json` for:

- E1M1 `THINGS`, `LINEDEFS`, `SIDEDEFS`, `VERTEXES`, `SEGS`, `SSECTORS`,
  `NODES`, `SECTORS`, `REJECT`, and `BLOCKMAP`.
- Palette 0 from PLAYPAL and COLORMAP maps 0 through 31.
- TEXTURE1/TEXTURE2, PNAMES, required patches, composed wall textures, flats,
  sky, animations, sprites and rotations, UI patches, font glyphs, weapon
  frames, monster frames, decorations, sounds, and E1M1 music inputs.
- A closure manifest explaining why each non-map lump is required.
- Source lump offset, size, occurrence index, and SHA-256. Duplicate-name lookup
  follows WAD last-occurrence semantics.
- Independently authored `engine-defs.json` mapping every E1M1 THING type,
  linedef special, sector special, weapon, state, sprite, sound, and pickup to a
  documented project behavior. No present id may remain `unknown`.

Texture parsing handles negative patch origins, transparent posts, overlapping
patches, tall-patch top-delta continuation, sidedef x/y offsets, texture widths
that are not powers of two, and missing pixels. Missing required pixels are a
parser failure, not palette index 0 substitution.

Audio tooling decodes Doom-format sound lumps to PCM assets and converts the
E1M1 music lump into a browser-playable, reproducible asset using a pinned,
license-approved build tool. The converted assets are seeded into Oracle BLOBs.

### 5.2 Static schema

Create constrained tables for map lumps, asset metadata, texels, patches,
sprites, palette, colormap, sounds, music, engine definitions, state transitions,
weapons, thing types, linedef specials, sector specials, configuration, and the
sector property graph edge relation.

Store dense texels as palette indices with `(asset_id, x, y)` primary keys.
Store original encoded asset BLOBs as provenance, not as render-time truth.
Foreign keys must make invalid WAD references fail during load.

### 5.3 Dynamic schema

Use these ownership groups:

- `GAME_SESSIONS`: token, mode, skill, tic, RNG cursor, map status, paused state,
  menu state, automap state, current player, and current save lineage.
- `PLAYERS`: position, momentum, angle, view height/bob, health, armor, keys,
  ammo, weapons, selected weapon, powers, kills, items, and secrets.
- `MOBJS`: stable id, type, state, state tics, position, momentum, radius, height,
  health, flags, target/tracer, reaction time, and spawn reference.
- `SECTOR_STATE`, `LINE_STATE`, `ACTIVE_MOVERS`, `ACTIVE_SWITCHES`: dynamic
  heights, light, timers, direction, speed, target height, and trigger status.
- `TIC_COMMANDS`, `GAME_EVENTS`, `AUDIO_EVENTS`: append-only ordered inputs and
  outputs keyed by session/tic/event ordinal.
- `STEP_RESPONSES`: canonical command-batch hash, sequence range, state/frame
  hashes, and cached response BLOB for deterministic retry without re-execution.
- `STATE_HISTORY` and `SAVE_SLOTS`: canonical periodic snapshots plus the command
  range needed to replay from the nearest snapshot.
- `FRAME_*` work tables or global temporary tables scoped to the current request.

Every table has an explicit deterministic key. No ordering relies on rowid,
insertion accident, sequence timing, or hash-table iteration.

### 5.4 Public AutoREST contract

Expose a single package, `DOOM_API`, with `ORDS.ENABLE_OBJECT` and these public
procedures:

```
NEW_GAME(
  p_skill       IN  NUMBER,
  p_session     OUT VARCHAR2,
  p_payload     OUT BLOB)

STEP(
  p_session     IN  VARCHAR2,
  p_commands    IN  CLOB,
  p_payload     OUT BLOB)

SAVE_GAME(
  p_session     IN  VARCHAR2,
  p_slot        IN  NUMBER,
  p_state_sha   OUT VARCHAR2)

LOAD_GAME(
  p_session     IN  VARCHAR2,
  p_slot        IN  NUMBER,
  p_payload     OUT BLOB)

START_REPLAY(
  p_session     IN  VARCHAR2,
  p_from_tic    IN  NUMBER,
  p_to_tic      IN  NUMBER,
  p_replay_id   OUT VARCHAR2)

STEP_REPLAY(
  p_replay_id   IN  VARCHAR2,
  p_payload     OUT BLOB)

GET_ASSET(
  p_asset_name  IN  VARCHAR2,
  p_payload     OUT BLOB,
  p_media_type  OUT VARCHAR2)
```

Only this package and a non-updatable `PUBLIC_HEALTH` view are AutoREST-enabled.
Do not AutoREST-enable base state tables.
AutoREST exposes every public subprogram in the enabled package, so helper
subprograms are private to the body. Public names are unique case-insensitively
and are not overloaded. Every call is HTTP POST with `application/json`.

`p_commands` is compact JSON with version 1 and one or more ordered tic commands:

```
{"v":1,"commands":[
  {"seq":1,"turn":0,"forward":1,"strafe":0,"run":0,
   "fire":0,"use":0,"weapon":0,"pause":0,"automap":0,
   "menu":"NONE","cheat":""}
]}
```

All numeric controls are integers. `turn`, `forward`, and `strafe` are -1, 0,
or 1; booleans are 0 or 1; `weapon` is 0 for unchanged or a valid owned slot.
Commands must have consecutive sequence values. Malformed or repeated commands
with different canonical content raise an application error and do not mutate
state. An exact retry of the last accepted `(session, first_seq, last_seq,
command_sha)` returns the cached response BLOB without advancing state or
duplicating events. Older or gapped sequences fail.

`NEW_GAME` creates a session token from 16 `DBMS_CRYPTO.RANDOMBYTES` bytes encoded
as 32 lowercase hex characters. Public procedures enforce exact JSON keys, a
64-KiB request limit, at most four commands per STEP, session expiry, a configured
global active-session cap, one in-flight STEP per session, and an asset allowlist.
Expired sessions are reclaimed inside bounded NEW_GAME maintenance DML. Limits
are database configuration rows and are covered by direct and concurrent tests.

The decompressed response is canonical JSON:

```
{"v":1,"tic":123,"w":320,"h":200,"mode":"GAME",
 "state_sha":"...","frame_sha":"...",
 "cols":[[[0,12,4],[12,3,17]],...],
 "audio":[[123,0,"DSPISTOL",255,128]],
 "complete":0}
```

Columns are present for 0 through 319 and runs cover rows 0 through 199 exactly.
Audio tuples are `(tic, ordinal, asset, volume, separation)`. Frame and state
hashes cover canonical decompressed representations, never compressed bytes.

## 6. Deterministic evaluator and anti-reward-hacking controls

### 6.0 Verification command contract

Every task has exactly one entrypoint:

```
./verify.sh task T4.2
./verify.sh phase P4
./verify.sh final
```

Successful task output ends with `PASS T4.2 (passed/total assertions)` where
`passed = total` and `total` equals the approved test-id manifest. Phase and final
commands run the union of their task manifests and print one terminal PASS line.
Unknown ids, duplicate ids, zero discovered tests, a count mismatch, missing
JUnit/JSON result, timeout, signal, or nonzero child status fails closed. Shell
entrypoints use `set -euo pipefail` and preserve the first failing status.

### 6.1 Evaluator lifecycle

The separate evaluator is a test-only local/CI harness, not a deployed service
and not a second game server. It owns expected results, expands frames, queries
test state, runs mutations, drives browsers, times requests, and decides pass or
fail. Production code only receives normal AutoREST calls and normal database
rows; it never calls or links to the evaluator.

For each phase that introduces new behavior:

1. The task first adds visible fixtures, independent expectations, mutations,
   and Playwright assertions without adding the implementation.
2. The user reviews the fixture intent and any visual baseline.
3. The user explicitly approves the evaluator baseline.
4. The implementation task begins. From this point the agent may run but not
   modify that phase's evaluator, fixtures, approved goldens, or snapshots.

This is an ordinary review boundary, not a cryptographic seal. SHA-256 detects
output differences and accidental fixture edits; it is not treated as a security
guarantee.

Final evaluation is launched by the user from a fresh evaluator container built
from the evaluator-controlled checkout. Its evaluator and held-back mounts are
read-only. It deploys the unchanged production artifact into a fresh database
volume and recomputes every observation itself. It does not trust implementation-
supplied PASS files, reports, timings, hashes, test counts, or screenshots.
Production containers have no evaluator mount, reference code, expected outputs,
workspace write access, environment marker, privileged host access, or Docker
socket. The implementation container cannot inspect evaluator processes or
network traffic. Held-back failure details are visible to the user, not returned
to the implementation task as expected values.

Before it is trusted, the evaluator self-test deliberately attempts to delete a
test, rename an id, add `.only`, add skip/fixme, remove an assertion, edit a
fixture, edit a golden, replace a child check with `exit 0`, forge a PASS result,
return zero discovered tests, make production read an expected-output path, and
make unapproved network egress. Every attempt must make the evaluator fail for
the intended guard. These are evaluator tests, not optional audit advice.

### 6.2 Visible and held-back coverage

Visible tests include all documented requirements. Additional deterministic
scenario seeds and transformed mini-maps are supplied outside the implementation
worktree for final evaluation. Held-back cases must be similar to visible cases,
not surprise requirements.

Production code is scanned for:

- Reads of evaluator, golden, snapshot, report, or test-result paths.
- Embedded expected hashes, full expected frames, or fixture-specific poses.
- Branches on CI, test name, user agent, Playwright, environment, or caller.
- Process/stack inspection, monkey-patching, timer replacement, and shell exec.
- Imports or binaries from a Doom engine or evaluator implementation.
- Disabled assertions, caught-and-ignored errors, or unconditional success.
- Reference/golden tables or packages inside the production database schema.

The evaluator also runs metamorphic checks whose expected relationship does not
come from the implementation: translating/rotating a mini-map and pose together,
splitting versus batching identical command sequences, save/load continuation
versus uninterrupted play, RLE decode versus canonical pixels, and local versus
cloud seed/state hashes. A source-behavior audit and live WAD probes ground BSP
and placed-object behavior so two implementations cannot validate the same
incorrect prose contract by agreeing with each other.

### 6.3 Mutation suite

The evaluator must prove it detects at least these mutations:

1. Reverse BSP child selection.
2. Change a vertex coordinate.
3. Flip the ray/segment determinant sign.
4. Remove the exact predicate after SDO_FILTER.
5. Reverse a facing sidedef.
6. Ignore x/y texture offsets.
7. Ignore upper/lower pegging.
8. Break a portal height transition.
9. Draw a sprite behind a wall in front.
10. Change a colormap band.
11. Drop or duplicate one pixel.
12. Alter one RLE length.
13. Advance the RNG cursor in a different order.
14. Skip one monster state transition.
15. Shorten a door or lift timer.
16. Ignore a key requirement.
17. Disable damage or pickup consumption.
18. Reorder two simultaneous events.
19. Corrupt one save/replay command.
20. Change one client palette lookup.

Each mutation is applied in an isolated temporary checkout and must make its
named test fail. A mutation is counted as killed only when the baseline was green,
the patch applied, the mutated production build and deployment succeeded, the
named assertion failed for its intended semantic reason, and unrelated evaluator
health checks remained green. Compile errors, startup failures, timeouts, empty
test discovery, or a different incidental failure do not count. The runner has
positive and negative canary mutations proving both killed and surviving paths.
The suite fails if any required mutation survives.

### 6.4 Golden policy

- Parser and schema goldens are independently known counts, checksums, and
  hand-built binary fixtures.
- Geometry goldens combine hand-calculated mini-maps, live WAD probes, and an
  independent TypeScript implementation.
- Render goldens are canonical palette-index hashes plus human-reviewed PNGs.
- Simulation goldens are complete state rows/hashes after scripted scenarios and
  a full E1M1 completion replay.
- Client goldens are raw `canvas.getImageData()` RGBA hashes. Browser screenshots
  are a second presentation check, not a substitute for canvas bytes.
- The implementation never generates its own expected value during a test run.
- Snapshot update flags and `gen_goldens` commands are absent from agent tasks.
- After a human approves a candidate image or replay, an evaluator-author task,
  not the implementation task, records the baseline and test-id manifest.

### 6.5 Playwright policy

Use one pinned Chromium project with:

- `updateSnapshots: 'none'`
- `forbidOnly: true`
- `retries: 0`
- `workers: 1`
- fixed viewport, device scale factor, locale, timezone, color scheme, and font
- animations disabled during screenshots
- failure on console error, page error, failed request, skip, fixme, or missing id

The result validator reads Playwright's machine report and requires the approved
test ids and assertion counts; a green process exit alone is insufficient.

Tests cover desktop and mobile layout, raw canvas hashes, title fire, new game,
movement, use, shooting, monster interaction, pickup, automap, menu/pause,
save/load, replay, exit, audio-event scheduling, and S3-origin cloud operation.

### 6.6 Performance protocol

Correctness and required scope are fixed. Performance measurement is mandatory
but has no machine-independent FPS threshold.

- Use a fixed 300-frame representative replay at 320x200.
- Warm 30 frames, then externally measure at least 270 frames.
- Report p50/p95 end-to-end latency, database time, ORDS time, payload bytes,
  decode/blit time, effective FPS, R1/R2 stage time, and cursor parse/execution
  counts.
- The evaluator owns wall-clock timing outside production processes.
- Optimize only with all goldens green.
- Continue until two consecutive, technically distinct optimization attempts
  improve median end-to-end latency by less than 5 percent each.
- Human review confirms attempts targeted the measured bottleneck and did not
  deliberately choose ineffective work to satisfy the stopping rule.

The performance check passes only when the complete report and raw samples exist;
it does not claim a minimum FPS.

## 7. Execution phases and task cards

Execution order is P0-P7, the completed local T12.0 acceleration evidence, the
active P12.M Mocha Doom migration, P8-P10 against the selected engine, P13
multiplayer, the full T12.1/T12.2 performance re-verification against that
finished architecture, and finally P11 S3 + Autonomous Database deployment.
Phase numbers are stable contract identifiers, not execution priority. Earlier
T12.0 evidence may guide the migration but may not relax or replace the final
300-frame local/cloud evidence.

### P0 - Contract and evaluator foundation

#### T0.1 Versions and host preflight

- Route: Luna medium.
- Deliver: `versions.lock`, `.nvmrc`, package lock, host preflight, license ledger.
- Verify Docker Compose, Node 24, jq, curl, unzip, SHA-256 tool portability,
  available disk, architecture, and credential presence without printing secrets.
- Resolve and record image digests. Verification must run with network disabled
  after dependencies and images are cached.
- Accept: `./verify.sh env` reports exact versions and rejects any floating tag,
  unlocked package, missing license entry, or unexpected network fetch.

#### T0.2 Oracle capability probes

- Route: Terra medium.
- Deliver a temporary probe schema and SQL checks for SDO_GEOMETRY/index,
  CONNECT BY, MODEL, MATCH_RECOGNIZE, JSON RETURNING CLOB, SQL Property Graph,
  DBMS_CRYPTO, UTL_COMPRESS, and ORDS.ENABLE_OBJECT.
- Run against local Oracle Free. Package the identical cloud probe for P11.
- Drop the probe schema afterward.
- Accept: every required local feature executes a result-bearing example and the
  cloud probe is byte-identical to the reviewed script. An unsupported local
  capability blocks local work; there is no feature fallback.

#### T0.3 AutoREST transport contract

- Route: Terra medium.
- Deliver a disposable AutoREST package with IN number/CLOB and OUT
  VARCHAR2/CLOB/BLOB parameters plus a curl contract suite.
- Assert exact URL, method, body names, output JSON, BLOB base64 representation,
  gzip decode, error status, transaction rollback, and public CORS behavior.
- Exercise the maximum expected frame payload and largest seeded asset because
  ORDS documents base64 LOB expansion and memory risk. Record response size and
  ORDS memory behavior; an out-of-memory or truncated response blocks the contract.
- Run locally; preserve the same suite for the P11 entrance gate.
- Accept: `./verify.sh transport` proves the Section 5.4 representation exactly.
  Record captured redacted responses in `reports/transport-contract.md`.

#### T0.4 Evaluator foundation and approval

- Route: Terra high.
- Deliver evaluator container, test-id manifest, read-only mount design, static
  production audit, hidden-seed input hook, mutation runner, and Playwright config.
- Author it in an evaluator-only task context, then start implementation in a new
  context with no held-back inputs or expected held-back values.
- Add deliberate dummy good/bad implementations to prove pass and fail paths.
- Pause for user approval before P1. No implementation work starts first.
- Accept: missing tests, skips, modified fixtures, production reads of evaluator
  paths, forged results, zero assertions, unapproved egress, and a dummy mutation
  all fail for the intended reason.

### P1 - Reproducible local and cloud bootstrap

#### T1.1 Local stack

- Route: Terra medium.
- Deliver Compose, database health check, ORDS install/configuration, secrets via
  environment/files, and ORDS static document root.
- Apply CPU/memory limits matching Oracle Free's 2-core/2-GB constraints.
- Accept: fresh volume reaches healthy state; SQL and ORDS health endpoints work;
  the static page and API share one origin; no credential appears in process args
  or logs.

#### T1.2 Ordered bootstrap and idempotence

- Route: Luna medium.
- Deliver `scripts/bootstrap.sh`, `scripts/db_sql.sh`, schema drop limited to the
  evaluator project name, and exact SQL ordering.
- SQL wrapper accepts either a filename or stdin, prepends SQLERROR/OSERROR exits,
  and pins NLS/session settings.
- Accept: fresh bootstrap passes, second complete bootstrap makes no semantic
  change, and a failed seed statement aborts rather than continuing.

#### T1.3 Cloud skeleton

- Route: Terra medium.
- Deliver deterministic S3 upload and Autonomous SQL deployment scripts with dry
  run, secret redaction, artifact allowlist, and teardown instructions.
- Accept without credentials: dry-run manifests contain only the allowlisted
  placeholder client, health DDL, explicit S3 HTTPS URL, and managed ORDS URL;
  secret fixtures redact correctly. With credentials, the real placeholder smoke
  may run, but it does not substitute for P11.

### P2 - WAD ingestion and independent engine definitions

#### T2.1 Freedoom vendor and license

- Route: Luna medium.
- Deliver pinned archive, WAD extraction verifier, Freedoom license/credits, and
  source ledger.
- Accept: both Section 1.1 hashes and IWAD header match offline.

#### T2.2 Binary parser and mini-WAD fixtures

- Route: Terra high.
- Deliver structured readers for directory and every required lump plus synthetic
  WADs exercising endian, bounds, duplicate names, malformed sizes, node child
  flags, BLOCKMAP, REJECT, patches, tall posts, transparency, and sprites.
- Parse and test THING skill, ambush, single-player, and multiplayer flags without
  conflating file-format bits with project engine behavior.
- Reject out-of-range references and malformed post streams with stable errors.
- Accept: fixture expectations are hand-authored; parser mutation tests fail;
  parsing twice produces byte-identical JSON.

#### T2.3 E1M1 asset closure and engine definitions

- Route: Sol high.
- Deliver `engine-defs.json`, asset-closure report, animation groups, thing and
  special registries, weapon/pickup/state definitions, project RNG table, and
  documentation for every independently authored behavior.
- No registry row may cite copied GPL code/data as its source.
- Include exact support for every type/special present in Section 1.1 and every
  required UI/audio asset.
- Pause for user review of behavior scope and license ledger.
- Accept: closure contains no missing referenced asset or unknown type; a graph
  walk from each placed thing through its state/sprite/sound transitions resolves.

#### T2.4 Deterministic SQL seed generation

- Route: Terra medium.
- Deliver batched SQL, manifest, expected counts, asset hashes, spot texels, and
  provenance rows. Batches are at most 500 rows and output uses LF/ASCII.
- Seed only the E1M1 closure, not unrelated WAD assets.
- Accept: two generations in temporary directories have identical tree hashes;
  manifest matches Section 1.1 and every output hash.

### P3 - Schema, geometry, BSP, BLOCKMAP, REJECT, graph

#### T3.1 Constrained schema and load

- Route: Terra medium.
- Deliver all Section 5 tables with primary, foreign, unique, range, and not-null
  constraints; grants; configuration; and ordered seed loader.
- Accept: all counts match manifest; intentional bad references fail; production
  schema contains no evaluator/reference/golden object.

#### T3.2 Spatial geometry and index

- Route: Terra medium.
- Build linedef SDO geometry and metadata from calculated bounds; create and
  validate the R-tree; precompute stable length/direction data.
- Accept: every geometry is valid, index is valid, calculated bounds enclose WAD
  plus margin, and exact predicates remove known SDO_FILTER false positives.

#### T3.3 BSP location

- Route: Sol high.
- Deliver an inlineable SQL macro or view implementing Section 1.2 with binds and
  CONNECT BY. Do not call it "zero functions" if it is a SQL macro.
- Accept: hand cases, spawn sector 140, all THINGS probes, boundary cases, and
  independent TS results agree exactly.

#### T3.4 BLOCKMAP, REJECT, and sector property graph

- Route: Sol high.
- Materialize block cells/line membership, sector reject bits, and a SQL Property
  Graph over passable two-sided sector connections with sound-block attributes.
- Accept: binary round-trip checks, known reject-bit probes, block-cell mini-map
  goldens, and symmetric graph reachability scenarios pass.

### P4 - R1 first-light renderer

#### T4.1 Rays, frustum, candidates, intersections

- Route: Sol high.
- Implement Appendix A/B with player rows, a 320-column row generator, SDO frustum
  candidate filter, exact closed-form intersections, stable tie-breaks, facing
  sidedef, and nearest solid hit.
- Accept: hand geometry, mirrored/translated mini-maps, three E1M1 poses, and an
  independent TS reference meet stated numeric tolerances.

#### T4.2 Solid wall, floor, ceiling, texture, light

- Route: Sol high.
- Generate exactly 64,000 `(session,col,row,cidx)` rows using relational texels and
  COLORMAP. R1 may treat the nearest hit sector as the floor/ceiling sector, but
  this limitation is not accepted for final gameplay.
- Accept: no gaps/duplicates; palette range valid; spot pixels independently
  calculated; frame hash stable across sessions and reruns.

#### T4.3 First-light human checkpoint

- Route: Terra medium.
- Render spawn and two diagnostic poses through a test-only decoder, write PNGs,
  and provide column/pixel diagnostics.
- Pause for user visual approval before accepting visible R1 goldens.
- Accept after approval: SQL frame, RLE round-trip, independent decoder, raw RGBA,
  and PNG all describe the same palette pixels.

### P5 - Complete R2 renderer

#### T5.1 Portal and sector timeline

- Route: Sol max.
- Keep all ordered ray hits. Determine facing sector transitions, closed portals,
  upper/lower wall pieces, solid termination, and sector intervals using stable
  analytic ordering. Do not leave this approach for a later model to design.
- Accept: purpose-built mini-maps cover windows, steps, doors, overlapping hits,
  vertex ties, and nested portals; independent interval goldens match.

#### T5.2 Clip windows, floors, ceilings, sky, animation

- Route: Sol high.
- Derive visible vertical spans with running analytic clip bounds. Sample each
  interval's sector floor/ceiling; apply sky policy, texture/flat animation by
  tic, light, x/y offsets, and upper/lower pegging flags.
- Accept: height-step, window, sky, animation, offset, and pegging poses produce
  exact approved hashes and 64,000 unique pixels.

#### T5.3 Masked textures and world sprites

- Route: Sol high.
- Project transparent two-sided middle textures and billboard sprite rotations;
  clip by screen, sector, wall distance, and nearer sprites with deterministic
  tie-breaking. Support every decoration, pickup, monster, projectile, and effect
  sprite reachable from E1M1 engine definitions.
- Accept: occlusion mini-scenes, rotations, transparency, equal-depth ordering,
  and E1M1 diagnostic poses match independent spot checks and approved goldens.

#### T5.4 Weapon, HUD, menu, pause, automap, intermission

- Route: Sol high.
- Compose WAD patch assets and database-generated text after world rendering.
  Automap lines come from relational geometry and database-owned automap state.
- Accept: each mode has exact canvas/PNG goldens, text stays within 320x200, and
  hidden variations in health/ammo/keys/menu selection alter expected regions.

### P6 - Player simulation and world machines

#### T6.1 Deterministic tic transaction

- Route: Sol high.
- Implement Appendix F ordering, session row lock, consecutive command validation,
  fixed 35-Hz logical tics, event ordinals, rollback, and state hashing.
- Accept: identical duplicate/concurrent batches apply once and return the same
  response; conflicting duplicate, old, gapped, or malformed batches apply none;
  identical initial state/input produces identical rows/events/hash.

#### T6.2 Movement and collision

- Route: Sol high.
- Implement player radius/height, blocking flags, swept candidates, exact contact,
  stable earliest blocker, sliding, step height, vertical opening, noclip, and eye
  height from destination sector.
- Accept: head-on, oblique, corner, portal, step, too-high step, closed door,
  translated geometry, tunneling, and noclip cases pass independent checks.
- Exact-jamb hardening (2026-07-17): an open paired portal whose opposite jamb
  is exactly two player radii away now admits non-inward endpoint tangency. The
  E1M1 line-54 regression crosses `(880,512)` to `(880,528)` without weakening
  inward-jamb, closed-door, finite-portal, or canonical opening-route gates.

#### T6.3 Doors, lifts, switches, sectors, secrets, exit

- Route: Sol high.
- Implement all E1M1 line specials 1/2/11/23/26/62/88/117 and sector specials
  1/7/9/12 as table-driven machines with fixed speeds/timers from engine defs.
- Include blue-key denial, use range, crossing direction, repeatability, button
  reset, lift occupancy, damage cadence, light timing, secret-once, and completion.
- Accept: one focused replay per special plus combined interactions and mutation
  tests; no present special remains ignored.

#### T6.4 History, save/load, rewind, replay

- Route: Terra high.
- Append commands/events, snapshot at fixed intervals and save points, reconstruct
  from nearest snapshot plus commands, and validate state hashes during replay.
- Accept: save/load and rewind continue identically; corrupted or reordered command
  fails; replay from new game reaches the same final state/frame hashes.

### P7 - Weapons, pickups, monsters, and audio

#### T7.1 Inventory, pickups, weapons, hitscan, projectiles

- Route: Sol high.
- Implement table-driven ammo, weapon ownership/selection, refire, spread/damage
  draws, muzzle/weapon states, hitscan using the intersection query, projectiles,
  splash damage, pickups, keys, health, armor, powers, and consumption.
- Accept: every interactive item/weapon placed in E1M1 has a focused replay;
  inventory caps, no-ammo selection, deterministic random reads, occlusion, and
  barrel chain damage pass.

#### T7.2 Monster state advancement and perception

- Route: Sol max.
- Advance independently authored states by joins; acquire targets via graph sound
  reachability and LOS using REJECT negative filtering plus exact intercepts;
  implement deterministic direction choice, collision, attacks, pain, death, and
  drops for monster types 9/58/3001/3002/3004.
- Accept: idle/wake, heard/not-heard, seen/occluded, chase, melee, hitscan,
  projectile, pain, death, drop, and replay-determinism scenarios for every type.
- Completed correctness hardening (2026-07-17): every production GAME_EVENTS and
  AUDIO_EVENTS consumer is fenced to the current save lineage. The live branch
  regression preserves an abandoned `DRY_FIRE` event while proving it neither
  shifts the new branch's event ordinal nor wakes REJECT-hidden monsters after
  LOAD; retained Java owners and renderer/audio snapshots use the same fence.

#### T7.3 Audio events and browser assets

- Route: Terra high.
- Emit stable sound/music event tuples from database state transitions. Cache
  decoded audio assets fetched through GET_ASSET. Client scheduling is presentation
  only and may not infer gameplay.
- Accept: event timelines match state scenarios, duplicate/reordered events fail,
  browser requests only AutoREST assets, and Playwright observes scheduled playback
  after a user gesture without console errors.

### P12.0 - Pulled-forward local renderer acceleration gate

- Route: Sol high for SQL changes and Terra medium for measurement.
- Parity work after P7 is paused behind a playability gate.  The selected local
  implementation must target 30 presented FPS: no more than 33.3 ms per unique
  moving 320x200 frame at both p50 and p95 after a 30-frame cursor/buffer warmup.
  Measure at least 270 unique moving frames with application render caches cold;
  cached spawn, menu, pause, retry, replay, rewind, or load responses are reported
  separately and cannot satisfy this gate.  If the architectural attempts below
  cannot approach the target on Oracle Free's two-core/2-GB limit, report the
  charter-versus-hardware feasibility conflict rather than calling the result
  playable or resuming parity.
- Run after P7 and before continuing P8. Start from the reviewed T5 renderer
  goldens and the measured T8.1 production profile. Capture representative local
  world, masked, presentation, one-command STEP, and four-command STEP timings
  outside production payloads.
- Optimize the confirmed renderer-materialization bottleneck first. Evaluate a
  shared-portal/single-derivation relational shape, earliest legal session
  predicates, and removal of repeated SQL-macro expansion. Do not change the
  320x200 output, canonical RLE/JSON, public API, simulation, WAD data, or SQL
  ownership, and do not use MLE or UTL_TCP.
- Maintain a row-source inventory for NEW_GAME plus one- and four-command moving
  STEP frames.  Isolate simulation/state hashing, frustum candidates,
  ray/segment pairs, portal/window analytics, world sampling, masked sampling,
  presentation, frame hashing, RLE/JSON/LOB/gzip, ORDS, browser decode, and blit.
  The first deep trace identified the initial-frame database share as masked
  rendering 17.0 s (56%), world pixels 4.92 s (16%), R1 hits 3.22 s (11%),
  presentation 3.03 s (10%), frame hashing 1.01 s (3%), and RLE/JSON below 2%.
- Execute structural work reduction in this order, retaining canonical views as
  independent oracles: indexed resolution-profile axes and bounded sprite/wall
  rasterization; immutable first-opaque/sprite/animation/segment metadata;
  conservative exact screen-column pruning before determinant/t/u intersection;
  one shared materialized portal/interval/clip stream; direct world-to-final
  pixels plus sparse deterministic overlays; then WAD BSP front-to-back subtree
  rejection, solid column occlusion ranges, and floor/ceiling span generation if
  the preceding slices remain materially above budget. JavaBox and Mocha Doom
  are architectural evidence for persistent runtime state, BSP bounding-box
  rejection, solid screen-column ranges, indexed byte buffers, fixed-point
  lookup tables, preallocated draw instructions, visplane horizontal spans,
  cached texture columns, and publish-on-new-frame sequencing only. Mocha Doom
  was inspected at `c0af1322ee5fd168b5cf8aaaf504cab2d1aabe93` (2026-01-14);
  its renderer explicitly keeps BSP traversal serial and partitions the stored
  draw work. It is GPLv3, while DoomDB is MIT and Section 1.6 requires an
  independently designed Oracle-native implementation, so its code, tables,
  data, and control flow may not be copied, translated, or directly embedded.
- Implementation ledger (2026-07-15): profile-keyed axes and 64-orientation ray
  tables, immutable first-opaque metadata, exact bounded R1 candidates, shared
  portal/sector-interval staging, bounded masked rasterization, direct
  world-to-final composition, sparse overlays, and chunked frame hashing are
  selected and exact.  The second clean 41-file bootstrap ended with zero
  invalid objects.  The best exact clean `NEW_GAME` is 6.97 s.  Replacing the
  optimizer's 16,000-session estimate with one aggregate session fact and the
  seeded 320-ray profile passed a controlled same-instance A/B: moving turn and
  four-tic observations are now 7.10-7.84 s and 7.73-8.30 s respectively (use
  7.84 s, about 0.128 FPS, as the conservative current moving figure).
  SQL `MATCH_RECOGNIZE` alone measured 280 ms, so this row/GTT architecture is
  mathematically outside the 33.3 ms budget. The approved next implementation
  is a clean-room Java 11 OJVM renderer derived from the existing project-owned
  SQL equations. The brute analytic shape is no longer an implementation stage:
  independently authored BSP front-to-back rejection, conservative child
  bounding boxes, per-column solid/vertical portal clips, wall columns, and
  plane boundary arrays/spans are mandatory work reduction. The SQL renderer
  and MATCH_RECOGNIZE remain exact differential oracles, not production hot-path
  stages. JavaBox supplies architectural evidence only; no implementation is
  copied or translated.
- OJVM feasibility ledger (2026-07-15): disposable 100-frame probes measured
  16.0 ms/frame for unique 64,000-byte computation, 29.7 ms for temporary-BLOB
  return, 32.0 ms for coherent frame generation plus GZIP/BLOB, and 6.8 ms for
  coherent generation plus GZIP returned as RAW. These are synthetic means, not
  a game-frame claim. Compose now supplies a 256 MiB executable `/dev/shm`; JIT
  is enabled and a disposable class reached `USER_JAVA_METHODS.IS_COMPILED=YES`.
  The realistic kernel and caller-created-BLOB versus bounded-RAW transport
  benchmark must pass at no more than 20 ms p95 before full renderer selection.
  The first production-shaped brute analytic probe is rejected: 320x2,057
  intersections, 64,000 samples, SHA-256, per-run JSON, GZIP, and a caller-owned
  244,435-byte BLOB measured 1,133.882 ms p50 and 1,461.524 ms p95 over 30
  warmed samples. Explicit `COMPILE_CLASS` of its monolithic method stalled and
  was killed without residue. This triggers the planned work-reduction branch:
  small separately compilable methods, front-to-back BSP/bounding-box rejection,
  solid screen-column occlusion, wall columns, plane spans, and a payload corpus
  matching the actual 92,658-byte response before production integration.
- First clean-room BSP/projection implementation (2026-07-15): the real
  681-node/682-subsector/2,057-seg map is loaded into primitive Java arrays and
  traversed front-to-back with conservative child-box rejection and bounded seg
  projection. An independent SQL determinant/t/u audit across 12 spawn
  directions found all 57,012 accepted seg-column pairs in the Java candidate
  bitmap with 0 missing while retaining only 0.7218% of the brute pairs. The
  allocation-free Java 11 HotSpot kernel measured 0.043718/0.222975/0.272980 ms
  p50/p95/p99 over 20,000 samples, passing the <=3 ms algorithm gate. This is
  algorithm evidence only: it has no wall/plane/masked drawing or codec yet.
- Exact two-pass nearest-solid-depth coverage now evaluates only the bounded
  ranges, retains SQL hits through the first solid wall, and avoids relying on
  subsector seg storage order. Across the same 12 poses it retained 21,050
  SQL-visible hits with 0 missing and reduced brute-pair retention to 0.2706%.
  Allocation-free traversal, projection, determinant acceptance, and solid
  coverage measured 0.096178/0.447939/0.514542 ms p50/p95/p99 over 20,000
  samples. The next renderer slice is vertical portal clips plus exact opaque
  wall columns; solid coverage alone is not portal-safe.
- Ordered sector portal walk and upper/lower screen clips now match 12,487
  production SQL `MATCH_RECOGNIZE` active hits with 0 missing, 0 extra, and 0
  final clip mismatches across 12 poses. The complete allocation-free
  traversal/projection/solid/portal-clip kernel measures
  0.167218/0.728709/0.859567 ms p50/p95/p99 over 20,000 samples. Exact opaque
  wall columns are the next slice.
- Exact opaque wall columns now sample the real 1,256,192 relational wall
  texels and 8,192 colormap entries into one reusable indexed buffer. At spawn
  east, all 26,165 production SQL wall pixels match with 0 missing, 0 extra,
  and 0 palette mismatches. A fail-closed integer-boundary snap reconciles SQL
  exact-number flooring with binary-double values immediately below an integer.
  The complete traversal-through-wall path measures
  1.060739/1.435519/1.651697 ms p50/p95/p99 over 20,000 samples, inside the
  <=8 ms opaque-world gate before planes. Row-by-row immutable loading is 4.369
  seconds and must be replaced by revision-keyed primitive BLOB packs. Exact
  floor/ceiling boundary arrays and horizontal spans are next.
- Exact interval-bounded floors, ceilings, and sky now use the stored 20,480 ray
  components and database-computed binary-double projection constant. All
  64,000 production SQL world pixels match with 0 missing, 0 extra, and 0
  palette mismatches. The complete allocation-free world path measures
  2.730063/4.794134/5.348201 ms p50/p95/p99 over 20,000 samples, passing the
  <=8 ms opaque-world gate. Current plane work is direct indexed-array raster;
  horizontal span coalescing remains mandatory before 640x400 activation but
  does not block the 320x200 masked-fragment slice. Cold row loading including
  1,256,192 wall texels, 200,704 flat texels, and stored rays is 4.999 seconds,
  further confirming the packed relational BLOB requirement.
- Exact masked composition now resolves symbolic state IDs to primitive catalog
  indices and applies the production rotation, flip, bounds, interval/solid
  visibility, transparency, and depth/source/asset tie rules. At tic zero, all
  4,702 globally selected masked-wall pixels and 2,404 sprite pixels match SQL:
  7,106 total with 0 missing, 0 extra, and 0 palette mismatches. Complete
  world+masked timing is 3.060035/5.389510/5.942101 ms p50/p95/p99 over 20,000
  samples; the masked increment is about 0.60 ms p95, passing the <=3 ms stage
  gate. Row loading including 331,474 sprite texels is 5.714 seconds. Exact
  first-person presentation is next.
- Exact tic-zero `GAME` presentation now composes the real `PISGA0` weapon,
  `STBAR`, and ammo/health/armor digits over the world+masked buffer. All 64,000
  final indexed pixels match `DOOM_API_PRESENTATION_ROWS` with 0 missing, 0
  extra, and 0 palette mismatches. Complete presentation timing is
  2.884442/5.132537/5.736680 ms p50/p95/p99 over 20,000 samples. Cold row
  loading including 173,170 UI texels is 6.899 seconds,
  reinforcing the packed-BLOB requirement. Exact frame hash/RLE/canonical
  JSON/GZIP/BLOB codec parity is next; dynamic weapons/HUD values and the
  pause/menu/automap/intermission modes remain after the tic-zero slice.
- The codec spike proved the legacy v1 schema is algorithmically hostile:
  45,317 runs expand 64,000 indexed bytes to 481,989 JSON bytes. V1 level 1
  measured 10.465499 ms p95 and 137,333 bytes; Huffman-only measured 8.917733
  ms and 192,338 bytes; level 0 met CPU at 3.636932 ms but emitted 482,047
  bytes. The selected narrow v2 contract carries the same column-major indexed
  bytes as allocation-free base64 in canonical JSON, then level-1 GZIP. Its
  isolated p95 is 1.993562 ms at 44,112 bytes. The full exact run measures
  1.430147/1.800499 ms codec p50/p95, emits 42,140 bytes for the final sampled
  frame, and measures 4.476119/6.811515 ms renderer+codec p50/p95. The legacy
  decompressed document still matches `DOOM_API.NEW_GAME` byte-for-byte, the v2
  GZIP/base64 round trip is exact, and the TypeScript client accepts both
  versions with SHA-256 verification. V2 is selected; caller-owned BLOB handoff
  must keep codec+BLOB <=5 ms p95 before OJVM integration.
- Caller-owned BLOB handoff passes. A disposable OJVM matrix wrote the real
  42,140-byte measured payload size after 200 warmups over 1,500 samples per
  path. Direct locator `setBytes` measured 0.085/0.252 ms p50/p95, two bounded
  locator writes measured 0.093/0.232 ms, and `setBinaryStream` measured
  0.159/0.434 ms. All paths preserved length and SHA-256, and cleanup left zero
  probe/invalid objects. Select two locator writes (32,767 bytes plus remainder)
  because they have the best p95 and remain inside the internal-driver bound.
  Codec+BLOB component sum is 2.032499 ms p95; renderer+codec+BLOB component
  sum is 7.043515 ms. The real combined compiled-OJVM call is next.
- The real combined compiled-OJVM gate passes (2026-07-15). Four deterministic
  relational BLOB packs encode 1,256,192 wall, 200,704 flat, 331,474 sprite,
  and 173,170 UI texels as exact unsigned big-endian `(palette_index + 1)`
  values. External cold loading fell from 6.899 s to 1.810 s. Deep OJVM tracing
  first isolated plane rasterization at 18.915 ms p95 of a 27.016 ms total.
  Pre-resolved plane assets/light bands, per-frame sector-row distances, compact
  visible seg/depth lists, removal of per-pixel map/string/division work, and
  removal of the third determinant pass preserved every independent SQL oracle
  result while reducing plane work to 2.697 ms p95. After a bounded 500-frame
  native warmup, every selected hot method reports `IS_COMPILED=YES`; a clean
  repeat of 1,500 stored-procedure frames measured 9.188/10.517/12.734 ms
  p50/p95/p99 for exact renderer + packed-v2 codec + two-write BLOB. The full
  SQL-call loop averaged 11.460 ms (about 87 FPS), with renderer 7.313 ms, codec
  3.081 ms, and BLOB 0.061 ms p95.
  This passes the <=20 ms renderer gate and leaves about 23 ms of the 33.3 ms
  frame budget. Renderer micro-optimization is no longer the critical path;
  implement a <=5 ms exact dynamic state snapshot and continue simulation/
  history reduction before integrated AutoREST/browser measurement.
- Local native-method evidence correction (2026-07-15): Oracle's foreground
  trace proves the disposable one-line `(I)I` method compiled successfully in
  59,470 ms; the client cutoff landed at completion. JIT, the descriptor, and
  the executable 256 MiB `/dev/shm` are valid. Sol/max inspection instead found
  cold single-worker self-hosting JIT bootstrap at 99.4% cgroup memory, 675.2
  MiB PGA versus a 256 MiB target, about 148.5 MiB MZ00 PGA, and 17.68 seconds
  of CPU throttling. Treat this as deployment warmup, not frame latency: use
  externally compiled Java 11 classes, a bounded 5-10 minute cold deployment
  window, and require every hot method to report `IS_COMPILED=YES` before timing.
  Interpreted OJVM timings still may not select the renderer.
- Fresh 10046/TKPROF triage (2026-07-15): two consecutive exact frames measured
  11.14 and 10.57 s with stable plan hashes and 92,658-byte payloads. The warm
  frame is world pixels 6.53 s (5.62 s CPU, 14,685 TEMP/physical blocks), masked
  pixels 1.21 s, R1 hits 1.18 s, base/sparse composition 0.66 s, and
  RLE/JSON/hash 0.51 s. World ownership forms a 4,762,030-row intermediate and
  spills five major hash workareas; masked rendering spends about 1.08 s in
  ranking and scans `DOOM_SCREEN_COLUMN` 3,505 times; R1 performs 2,018 repeated
  ray range scans plus a per-column window sort. Removing all spill wait would
  still leave 5.62 s of world CPU, while 240 ms production RLE alone is 7.2x the
  complete budget. Further SQL join/index, PGA, DOP, or relational-pixel tuning
  is stopped as a 30 FPS route.
- OJVM implementation gates: use 6-10 cohesive primitive-array methods and
  synchronously call `DBMS_JAVA.COMPILE_METHOD` for traversal, projection,
  opaque columns, plane spans, masked fragments, presentation, codec, and BLOB
  output. Permit one measured 5-10 minute cold deployment bootstrap; after the
  compiler is warm, each hot method must compile within 60 s and report
  `IS_COMPILED=YES`. Kill the route if the no-JDBC composite kernel exceeds
  12 ms p95, BSP traversal/projection exceeds 3 ms p95 or retains more than 25%
  of ordinary brute seg-column pairs, opaque world exceeds 8 ms p95, masked
  composition exceeds 3 ms p95, warm snapshot plus render exceeds 17 ms p95,
  or renderer+codec+handoff exceeds 20 ms p95. Any missing SQL-winning primitive
  or unexplained pixel/RLE/payload mismatch fails immediately.
- OJVM data architecture: load selected deterministic revision-keyed relational
  BLOB packs into exact-width primitive arrays through internal JDBC; do not
  fetch 3,040,239 `AT` rows per request and do not embed a WAD.  The 2026-07-16
  ORDS probe disproved retained session caches: 240 consecutive requests used
  the same SID/AUDSID, while both a Java static and PL/SQL package global reset
  to `1` on every request because ORDS reinitializes package/JVM state during
  cleanup.  Pool pinning prevents connection churn but cannot preserve Java
  statics.  Therefore a selected renderer must rebuild from one bounded
  immutable kernel-pack BLOB plus one packed dynamic-state buffer on every
  request, with no relational row walking.  Immutable decode plus dynamic
  snapshot remains capped at 5 ms p95; reuse within one call is allowed, but
  cross-request correctness or performance dependence is forbidden.
- Exact production composition writes opaque world, planes, masked fragments,
  weapon, HUD, and overlays into that single indexed framebuffer, then performs
  one pass for frame hash, canonical Java RLE/JSON, GZIP, and caller-owned BLOB.
  SQL pixel GTTs and `MATCH_RECOGNIZE` remain mandatory independent parity
  oracles only. A future packed indexed-frame public schema is likely necessary
  for efficient 640x400 scaling, but is deferred and requires its own explicit
  charter amendment; it is not part of the current 320x200 selection.
- Render-free simulation gate (2026-07-15): the first rollback-only 270-call
  probe was rejected because one giant transaction accumulated undo/version
  chains. The corrected public-boundary baseline, with one commit per unique
  tic after 30 warmups, measured 68.070 ms p50 and 168.871 ms p95. Line-level
  profiling isolated 95.594 ms of an outlier in repeated per-monster procedural
  sound-graph searches. Exact bootstrap-time non-blocked sound reachability,
  bulk actor housekeeping, one-pass special-light neighbors, and omission of a
  redundant modern-lineage JSON rewrite all passed their adjacent gates. The
  selected result after replacing array DML with common set operations and
  packing immutable REJECT/line-of-sight inputs was 41.410 ms p50 / 70.581 ms
  p95. A fresh line trace then isolated canonical state JSON, swept collision,
  full state-BLOB history, and a redundant state-document lineage parse. The
  selected exact lineage flag, 1,175-row immutable collision geometry with a
  conservative swept-circle AABB and 182-row immutable sector-light facts all
  pass adjacent P6/P7 gates. Native PL/SQL is rejected at only 1.789 ms p95
  improvement after a restart-safe comparison, below its 3 ms gate. A
  correlated zero-motion SQL-macro fast path is rejected after an Oracle
  `ORA-07445` restart failure. The current restart-safe 270-tic result is
  36.842 ms p50, 49.503 ms p95, 58.123 ms p99, and 76.197 ms maximum.
  Simulation/history remains a
  mandatory bottleneck; continue reducing state serialization/hash, actor
  advancement, world machines, combat, history, command bookkeeping, and audio
  to <=10 ms p95. P12.0 remains active and P8 remains paused.
- State/history and real-route checkpoint (2026-07-16): canonical SQL/JSON now
  emits AL32UTF8 BLOB directly; command history writes through the persistent
  SecureFile locator; interval snapshots wrap the state BLOB without a CLOB
  round trip; zero-motion work is bounded; hitscan combat uses one collision
  ray instead of expanding all 320 renderer columns; and monster perception
  batches REJECT with BLOCKMAP-bounded exact LOS.  Modern state bytes/hashes,
  the complete P6/P7 gates, and every 163-command opening-route checkpoint are
  unchanged.  The best clean turn-only run is 21.260/30.856 ms p50/p95, while a
  conservative later restart repeat is 24.162/36.939 ms with one background
  outlier.  The moving/firing route fell from more than nine minutes before the
  hitscan repair, to 9.5 seconds, then to 5.5 seconds after set-based LOS (about
  29.6 simulation tics/s including setup and assertions).  The compiled
  10.517-ms-p95 renderer remains a complete tic-zero parity kernel, not yet a
  dynamic STEP integration.  No integrated 30 FPS claim is permitted.  The next
  structural work is the dynamic actor/sector snapshot plus production OJVM
  STEP integration; canonical SQL remains the differential oracle.
- Reconciled P12.0 handoff (2026-07-16): the exact OJVM state serializer is a
  measured rejection at 69.286/106.270 ms p50/p95.  It proves that OJVM is for
  compute over packed arrays, not repeated internal-JDBC row walks.  Do not
  retry it.  The remaining SQL simulation work is checkpoint-cadence state
  serialization only if the per-tic `state_sha` contract can remain exact,
  plus an actor split that reserves visibility/LOS work for awake, near actors
  at its documented cadence.  Assemble a narrow array-resident OJVM simulation
  amendment and differential gates as evidence only; simulation remains SQL
  unless the user separately approves that charter amendment.
- ORDS transport correction (2026-07-16): pinned ORDS 26.2 generated package
  procedure paths are case-sensitive (`DOOM_API/NEW_GAME`, `DOOM_API/STEP`,
  and peers), while lowercase procedure paths return 404.  The client may
  perform one startup casing probe/fallback, then must reuse the discovered
  casing without a second request per frame.  A one-connection pool returned
  500 during AutoREST discovery; the smallest viable fixed local pool is
  `InitialLimit=MinLimit=MaxLimit=2`, with high reuse, long inactivity timeout,
  and `RECYCLE` cleanup.  This does not override the stateless-cache result.
- ORDS/OJVM architecture correction (2026-07-16): rebuilding immutable
  renderer state in every AutoREST request is measured and rejected. The
  4,587,043-byte exact pack required 93.076 ms even after decoder/JIT warmup;
  a byte-palette/opacity-bitset pack retained exact tic-8 parity and shrank to
  2,872,196 bytes, but a decisive fresh session still took 167.014 ms pack +
  268.258 ms snapshot + 42.201 ms render + 3.531 ms codec. Oracle shares OJVM
  code/JIT, not application arrays, and ORDS exposes no supported AutoREST
  switch that skips `MODIFY_PACKAGE_STATE(REINITIALIZE)`. Do not retry pool
  pinning, per-request relational loads, or per-request immutable-pack decode.
  The next bounded architecture probe is a persistent-AQ command/completion
  pair with a long-lived `DBMS_SCHEDULER` database worker. AutoREST remains the
  sole HTTP surface and waits for a correlated committed result; SQL remains
  authoritative; the worker session owns the warm OJVM renderer and one packed
  dynamic-state buffer. Select only if 300 unique echo messages meet <=5 ms
  p95 database queue round-trip, worker restart/idempotency/fencing gates pass,
  and the subsequent warm render+codec+BLOB path remains <=20 ms p95. See
  `reports/performance-P12.0-ords-ojvm-worker-2026-07-16.md`.
  The first disposable persistent-AQ echo passed: 300 unique correlated
  messages, one worker generation/SID, zero mismatches, 2.122 ms p50, 3.843 ms
  p95, and 54.740 ms maximum. Proceed to restart/idempotency/fencing and warm
  renderer coupling; retain the maximum outlier in integrated evidence.
  The 300-frame warm-worker follow-up used one generation/SID and persistent
  response BLOBs: request-through-commit was 28.040/32.414 ms p50/p95 with a
  330.654 ms maximum; fill p95 was 28.216 ms, comprising renderer 22.105,
  codec 3.069, and BLOB 0.640 ms p95. The worker architecture is viable, but
  this renderer misses the <=20 ms slice and leaves no simulation/transport
  budget, so it is not selected. A 500-frame JIT bootstrap inside the worker
  was stopped with its job slave after 2:22, and `COMPILE_CLASS` returned 0.
  Keep the bounded foreground JIT warmup plus post-race compiled-method audit;
  workers perform only cache load and a small settling loop.
  Stage tracing then found an accidental per-plane-pixel animated-asset
  HashMap/string lookup (planes alone 21.607 ms p95). Hoisting two animation
  resolutions per sector retained exact tic-8 SQL payload parity and changed
  the repeated 300-frame worker result to 15.671/17.590 ms p50/p95
  request-through-commit, 13.643 ms fill p95, 7.471 renderer, 3.168 codec, and
  0.639 BLOB ms p95. The <=20 ms renderer slice now passes. Keep the 208.068
  ms maximum as cold-settling evidence and never route traffic before warmup
  plus the post-race compiled-method audit succeeds.
  The live-state follow-up rejected the remaining boundary rebuilds. One
  internal-JDBC UNION snapshot was 95.343 ms p95; a procedural 21,834-byte
  binary pack was 23.9 ms average after chunking. Native SQL/JSON generated a
  14,099-byte snapshot in about 2 ms average and retained exact frame SHA, but
  the 300-frame worker composite was still 29.265/42.373 ms p50/p95: SQL pack
  4.031, Java snapshot/geometry 10.874, renderer 16.088, codec 5.511, and BLOB
  0.987 ms p95. Do not bootstrap either snapshot experiment. This establishes
  the charter-versus-hardware conflict for the narrow array-resident worker
  amendment: simulation and rendering share retained primitive state, SQL
  persists authoritative per-tic deltas/checkpoints and remains the parity
  oracle, and no request rebuilds Java state by relational row walking.
- Array-resident simulation slice 1 (2026-07-16): the retained OJVM worker now
  has a no-JDBC player/frontier kernel and a versioned packed command/delta
  boundary. It passed 270/270 exact SQL-oracle turn results, 4/4 packed batch
  results, and atomic rejection with no partial state mutation. Every public
  Java entry catches `Throwable`, and a session token fence prevents retained
  state from leaking between games. The interpreted/JIT-visible internal
  ten-million-turn reproducible diagnostic measured 286.749 ns/tic; this measures only the
  arithmetic kernel and does not count persistence, rendering, AQ, ORDS, or
  browser work. Extend this same boundary with array-resident collision and
  player movement next; do not introduce per-tic JDBC or JSON reconstruction.
- Sol Max retained-state correction (2026-07-16): production state is
  double-buffered and transaction-fenced: `prepare` builds pending state and
  dirty deltas, SQL persists and commits, then `accept` publishes; a pre-commit
  failure calls `discard`, while commit-success/accept-failure kills and reloads
  the worker. The live slice now passes prepare invisibility, discard, accept,
  atomic invalid-batch rejection, and session/lineage/generation fencing. Its
  packed path uses retained scalar scratch/output buffers with no per-request
  `ByteBuffer` or temporary arrays. Exact `oracle.sql.NUMBER` feasibility also
  passes 1,152/1,152 SQL movement values and the representative quadratic root
  byte-for-byte. Preloaded lookup+NUMBER add measured 0.54–0.69 us/op and exact
  quadratic entry 9.7–15.0 us/op; runtime trig is not selected. See
  `reports/performance-P12.0-sol-max-resident-simulation-2026-07-16.md`.
- Retained simulation catalog (2026-07-16): a SQL-built, SHA-verified 200,699
  byte BLOB now carries all 681 BSP nodes, 682 subsector-sector owners, 1,175
  collision lines, 182 sector baselines, and 1,152 raw Oracle `NUMBER` movement
  pairs. The worker loads/decodes it once; relational row walking exists only in
  the offline pack builder. The decoded catalog matches `DOOM_BSP_LOCATE` for
  270/270 deterministic map points and preserves all 1,152 movement encodings
  byte-for-byte. Extend this retained catalog with exact collision NUMBER bytes
  and dynamic double-buffered sector heights before selecting movement.
- Retained collision/movement gate (2026-07-16): the catalog now also packs raw
  Oracle `NUMBER` line length/directions and the 864-cell/2,064-reference
  BLOCKMAP. The independently authored swept-circle/two-contact/portal kernel
  matches `DOOM_PLAYER_MOVE_PAYLOAD` for 270/270 sequential real-session moves,
  including 124 contact samples. A full 1,175-line scan measured
  9.966/16.746/25.070 ms p50/p95/max and was rejected; BLOCKMAP candidate
  enumeration retained exact parity and measures 0.165/0.734/2.079 ms. Select
  the BLOCKMAP route and wire it into pending state; the thin-portal tangent
  exception remains fail-closed until its dedicated adversarial corpus passes.
- Transactional movement integration (2026-07-16): version-2 packed commands
  now advance turn plus exact Oracle `NUMBER` position in pending state and emit
  fixed-width raw NUMBER deltas. The real-session differential passes 270/270
  tics and 270/270 prepare-invisibility checks before explicit fenced accept;
  the collision-heavy companion corpus retains its 124 contacts. The complete
  packed `prepare+accept` boundary measures 0.261/0.762/5.821 ms p50/p95/max.
  This slice is selected. Implement dynamic double-buffered sector heights and
  the complete quiet/common actor tick next, then write canonical state directly
  from arrays; do not spend more time on ordinary movement micro-tuning.
- Retained common-actor slice (2026-07-16): an independently authored
  array-resident kernel now matches all 53 SQL-oracle monster rows for the
  provably quiet housekeeping phase (`monster_health_seen` plus cooldown),
  preserves every other actor field and the RNG cursor, and passes pending
  load/accept/discard/session/lineage/generation/request fences. After five
  warmups its 300 retained `prepare+accept` calls measured
  0.783/1.241/2.290 ms p50/p95/max after retained eligibility lookup. This is
  a bounded component, not yet a
  production actor loop: its entry requires explicit no-sound and all-REJECT-
  hidden proofs and fails closed otherwise. The next actor slice must compute
  those proofs inside retained state, preserve prior-snapshot mobj-id order and
  old-cooldown attack semantics, then add pain/wake/state/action behavior with
  adversarial differential cases before routing real tics through it.
- Retained actor eligibility and audible wake (2026-07-16): the one-time
  simulation catalog now includes compact directed REJECT and sound-reach
  matrices and matches SQL for all 33,124 sector pairs. With live player
  coordinates and retained actor sectors, the worker matches 53/53 SQL actor
  wakes plus 53/53 ordered `MONSTER_WAKE`/`HEARD` events from a frozen
  `DRY_FIRE` sound input; RNG and relational state remain untouched before
  persistence/accept. The follow-up BLOCKMAP LOS kernel matches 270/270 SQL
  rays, including 132 REJECT-open cases, and a warmed 53-actor batch measures
  0.074/0.245/0.476 ms p50/p95/max. With that kernel folded into classification,
  53/53 `SEEN` wakes and events now also match SQL. The next pain slice retains
  all 256 canonical RNG bytes, matches 53/53 actor and RNG transitions, and
  emits 36/36 ordered `MONSTER_PAIN` events for successful rolls. Next add
  death and active state/action phases. The transitional sound bit must ultimately come from the retained
  current-tic event buffer, not a per-tic SQL scalar.
- Retained active-state countdown (2026-07-16): awake live actors whose old
  `state_tics` is greater than one now decrement in retained state and stop at
  the same prior-snapshot boundary as SQL. The controlled differential matches
  53/53 actor rows with zero events and no RNG movement; the HEARD, SEEN, and
  pain corpora remain green. `state_tics <= 1` still fails closed until the
  next-state/action graph and CHASE/attack dispatch are retained.
- Retained state graph and no-action transition (2026-07-16): catalog version 4
  now packs the complete database-defined state graph rather than hardcoding a
  route or fixed actor sequence. All 151 state timers, next-state indices, and
  action classifications match SQL. When an awake actor timer expires, the
  retained worker follows an ordinary no-action edge with 53/53 row parity,
  zero events, and unchanged RNG; CHASE, melee, hitscan, and projectile actions
  remain explicitly fail-closed until their differential slices land. The
  catalog is extended below; its v4 fingerprint is retained as historical
  evidence rather than the current production candidate.
- Retained processed-corpse transition (2026-07-16): dead actors whose initial
  death bookkeeping is already durable now advance through the same retained
  state graph with 53/53 SQL parity, zero events, and unchanged RNG. Unprocessed
  deaths still fail closed; kill credit, first-death events, flags/target
  cleanup, and drop creation remain one atomic differential slice.
- Retained fresh death/drop gate (2026-07-16): the frozen actor pass matches all
  53 fresh-death mutations, 25 resolved drop spawns, and 78 ordered
  `MONSTER_DEATH`/`MONSTER_DROP` events. Kill credit, sequential MOBJ allocation,
  cleanup fields, pending accept/discard, malformed-drop rejection, and repeat-
  death fences pass together; death and drop are never split across commits.
- Retained no-attack CHASE gate (2026-07-16): a variable-radius/height monster
  movement helper uses the retained BLOCKMAP, exact Oracle `NUMBER` coordinates,
  live sector heights, and the immutable prior-actor snapshot. Diagonal,
  horizontal, vertical, and blocked preferences match 212/212 SQL results over
  four target quadrants. This is a pure movement helper, not an independently
  authoritative frontier.
- Unified-world prerequisite (2026-07-16): before melee/hitscan/projectile work,
  merge the player, actor, RNG, next-MOBJ, event, tic, and command frontiers into
  one committed/pending retained state and one fenced prepare/persist/commit/
  accept coordinator. Independent player and actor statics are differential
  prototypes only and may not be routed to production attacks.
- Unified retained-world structural gate (2026-07-16): one owner now captures
  all 280 MOBJ rows, the physical player row, exact Oracle `NUMBER` bytes,
  RNG/ID/event/tic/command frontiers, and the complete state/monster mappings.
  Its 70,999-byte canonical pack and SHA match across committed and pending
  round trips; session, lineage, generation, mapping, frontier, request,
  accept, and discard fences pass. The pack is strictly restart/checkpoint
  material and must not be serialized every tic.
- CHASE allocation repair (2026-07-16): the first exact retained implementation
  measured 9.686/61.016/324.997 ms p50/p95/max and was rejected. Cached invariant
  exact values plus conservative double broad phases with exact boundary
  fallback preserve 212/212 parity. A fully warmed 300-call corpus rotating four
  targets measures 0.227/0.623/0.989 ms; cold/JIT-transition evidence remains
  separately visible and the worker must warm before admission.
- Unified transaction/restart probe (2026-07-16): the production-shaped
  AQ/Scheduler coordinator passes strict RAW magic/version/count/exact-length
  checks, idempotent duplicate replay, pre-commit rollback plus discard, stale
  frontier/generation rejection, post-commit accept-failure reconstruction, and
  Scheduler stop/restart continuation. The bounded probe recorded 3 commits,
  6 intentional failures, 4 discards, and 1 reconstruction, then removed every
  probe object/job. Production integration must return exact-length deltas; it
  may not expose the legacy 104-byte capacity buffer.
- Exact hitscan spread catalog (2026-07-16): catalog version 6 precomputes all
  511 possible `(rng_a-rng_b)*2*pi/4096` spreads, their sine values, and the
  exact `TM9` event text. Every raw Oracle `NUMBER` and string matches SQL,
  avoiding per-attack trigonometric/text conversion without changing RNG order.
  The current catalog is 247,103 bytes with SHA-256
  `6b267e35b08c017d57bc51bc8f74ca9c44245d31f89c0e991f761da2fc3fe51b`.
- OJVM deployment-memory guard (2026-07-16): repeated iterative
  `loadjava -force` cycles eventually drove the 2 GiB local instance's MMAN to
  fatal `ORA-00822`; the alert trace identifies MMAN, not an uncaught game
  entry point. Production loads each class revision once and restarts/warmups
  the worker. The local probe supports `DOOMDB_SKIP_LOADJAVA=1` for repeat
  measurements after one successful compile/load, preventing class-metadata
  churn from contaminating performance or availability evidence.
- Fable/ORDS reconciliation (2026-07-16): Fable independently confirmed that
  ORDS cleanup has no supported off switch and OJVM application arrays are
  session-private. Its unmeasured DBMS_PIPE proposal is archived as fallback,
  not selected: persistent AQ already passed 3.843 ms p95/300 with transactional
  semantics. The live `DBA_SERVICES.RESET_STATE` value for `FREEPDB1` is NULL,
  proving ORDS cleanup—not service `LEVEL1`—causes the observed reset. Production
  adds an exclusive `DBMS_LOCK` worker singleton; global application context is
  permitted only for <=4 KB heartbeat/revision metadata, never game state.
  Keep log-file-sync/commit as a distinct timing stage as dirty volume grows,
  and require a worker-kill/reconstruction test that resumes the exact state and
  frame SHA chain mid-lineage before the public gate.
- Retained-scene renderer gate (2026-07-16): the worker now loads one exact
  21,792-byte scene at reconstruction and applies compact dynamic deltas directly
  to its primitive arrays. Ordinary camera/presentation updates are 145 bytes;
  the adversarial 301-byte gate also changes a sector, updates and adds MOBJs,
  and removes a MOBJ. All 64 changing angles, A-B-A owner isolation, and the
  sector/MOBJ mutations match the SQL/JDBC oracle. After 500 varying warmups,
  300 varying frames measured 0.070/0.116/0.162 ms update and
  7.135/9.505/10.875 ms render+codec+BLOB p50/p95/max. The warm path performs
  no JDBC or table reads. DRS2 remains reconstruction/parity material only.
- Multi-session worker-pool gate (2026-07-16): four fixed Scheduler slots now
  provide exclusive session ownership, slot-correlated request AQ consumption,
  request-ID response correlation, independent generations/SIDs/heartbeats, and
  a public AutoREST `claim(session)` entry for arbitrary valid game sessions.
  Exact terminal requests replay across worker restarts while stale new work is
  rejected. A live two-session gate passes default-off rollout, rollback
  isolation, response correlation, independent restart/generation behavior,
  cross-generation terminal replay, and stale-generation fencing. The installed
  worker remains rollback-only until the unified retained tic and durable delta
  writer replace the scaffold.
- Unified all-MOBJ actor-tic gate (2026-07-16): the executable retained owner
  now captures all 280 MOBJs and every runtime MOBJ column, not only the 53
  monster behavior rows. Its 27,548-byte full-owner checkpoint is fenced by
  session, lineage, state-map SHA, generation, tic/command/RNG/ID/event
  frontiers, and retained player combat/position/sound state; restore validates
  before atomically publishing and rebuilding the movement cache. Stable ID
  lookup, arbitrary removal, and inbound target/tracer/owner cleanup pass.
  One frozen MOBJ-order pass now performs fresh and processed death, pain,
  HEARD/SEEN wake, state transitions, melee, hitscan, projectile spawn, drop,
  and CHASE exactly once. The mixed SQL differential matches 53 actors, two
  spawned MOBJs, seven ordered events, five RNG draws, exact player/frontier
  values, and the accepted 282-row world in one 5,640-byte delta.
- Actor-tic allocation rejection and repair (2026-07-16): the first correct
  full-owner prepare deep-cloned 28 arrays and rebuilt a boxed ID map, measuring
  10.066/14.693/18.370 ms p50/p95/max; it was rejected. Reusable committed/
  pending buffers, capacity-backed append, retained scratch/masks, selective
  movement, shared exact output, and deferred publish encoding preserve parity.
  A cold-after-load 300-unique-tic run measures 3.439/4.160/11.128 ms and the
  warmed repeat measures 0.316/0.747/5.662 ms, ending at exact tic/command
  frontier 320/320. The next production slice integrates the already-selected
  DMSC/v2 player command/movement into this same pending owner; component modes
  remain differential oracles and may not be composed as separate tic phases.
- Unified command/direct-render gate (2026-07-16): one DMSC/v2 movement command
  now advances the same pending all-MOBJ owner before its ordered actor pass.
  The 270-command differential matches player and world state, prepare
  invisibility, restart, and exact 270/270 tic/sequence frontiers. Cold
  prepare+accept is 2.400/3.087 ms p50/p95 and warm is 2.300/2.969 ms. Separate
  tracing attributes warm p95 primarily to the moving-player actor pass
  (1.921 ms); portal/location movement is 0.104 ms and DCTC encoding is 0.016
  ms p95, so further ordinary movement tuning is stopped.
- The renderer now consumes an allocation-free ordered UPSERT/REMOVE diff
  directly from the unified pending arrays, including state, x/y/z, angle, and
  player camera/presentation fields. It remains request/generation fenced and
  rollback-capable until the SQL commit is accepted. Direct application is
  0.111/0.624/1.082 ms p50/p95/max; render+codec+BLOB is
  9.982/10.872/14.269 ms. Direct, strict-DTIC, and fresh DRS2 frames match; the
  measured 1.103 ms DTIC parse p95 is restart/parity-only, never the warm path.
- Durable command-delta gate (2026-07-16): the 24-byte DMSC/v2 command and
  5,745-byte DUOP/DCTC v1 result now receive strict outer/nested frontier,
  length, reserved-byte, canonical NUMBER, and exact BSP-sector validation.
  Atomic SQL apply matches mixed movement, player, 53 actors, drops,
  projectiles, events, RNG, and resulting-tic semantics; malformed, stale,
  discard, and accept gates pass. Canonical command/history/state hashing and
  production worker cutover remain before the public 30 FPS measurement.
- Durable delta-apply optimization (2026-07-16): immutable catalog maps,
  memoized world-reference checks, ordered actor-ID bulk validation, `FORALL`
  writes, and fixed-layout canonical decoders preserve exact actor/DCTC bytes,
  SHAs, malformed-input rejection, and atomic rollback. Two independent warm
  300-tic runs measured strict apply at 5.114/6.612/8.685 ms and
  5.590/7.868/13.034 ms p50/p95/max, versus the 11.331/14.033/33.548 ms
  baseline. The improvement is selected, but the observed tail variability is
  retained in projections; this is not an end-to-end 30 FPS result.
- Production retained-worker gate (2026-07-16): one default-off Scheduler/OJVM
  owner now performs DMSC/v2 prepare, strict durable apply, canonical
  state/history, direct render, commit, post-commit accept, and correlated AQ
  response. Live acceptance passes exact result hashes/bytes, terminal replay,
  precommit rollback/discard, generation-advancing reconstruction after discard
  or accept failure, restart fencing, and two simultaneous sessions on distinct
  slots/SIDs. A 500-warm/300-unique-tic database-caller run measures
  35.041/44.091 ms p50/p95 (28.5/22.7 FPS) before ORDS/browser work, so the
  30 FPS gate remains open and `DOOM_API.STEP` is not cut over. Detailed p95
  stages are render 12.088 ms (kernel 6.800, codec 1.938), canonical state
  11.326, strict apply 7.680, finalization 6.940, and prepare 2.396 ms.
  Replacing direct Java-to-SecureFile output with Java temporary BLOB plus one
  PL/SQL copy reduced the Java BLOB stage from 13.715 to 0.063 ms p95. The next
  selected slice is an exact retained canonical-state codec: cache the missing
  static session/player and sector/line/mover/switch fragments at recovery,
  serialize pending player/all-MOBJ arrays without JDBC row walking, and require
  300-tic byte/SHA parity plus mid-route recovery before worker selection.
- Retained state/geometry follow-up (2026-07-16): the exact state codec now
  reuses immutable canonical JSON fragments for unchanged MOBJ rows and
  re-encodes only changed/new actors. Its 300-tic mixed command/plain/recovery
  gate is byte- and SHA-identical to `DOOM_CANONICAL_STATE`. The worker state
  stage is now 3.755/4.745 ms p50/p95. Detailed tracing isolated moving-camera
  decimal construction; lazy visible-segment evaluation plus compensated
  primitive products preserves the moving SQL pixel oracle and reduces retained
  scene update to 0.044/0.141 ms. After the OJVM compiler queue drained, the
  integrated 300-frame worker measured 31.181/39.376 ms (32.1/25.4 FPS)
  p50/p95. Render is 11.147/14.505 ms, apply 6.828/8.947, state 3.755/4.745,
  and prepare 1.698/2.791. The remaining regular p95 blocker is the reviewed
  four-tic history checkpoint: 5.322/8.114 ms versus 0.459/0.741 ms for normal
  finalization. Preserve its cadence and snapshot bytes; optimize construction
  rather than hiding checkpoints from the sample. Public cutover remains barred.
- SecureFile/strict-durability correction (2026-07-16, supersedes the prior
  four-tic-cadence direction): worker 10046 trace attributed 5,135 waits and
  3.12 seconds directly to the three hot NOCACHE/CACHE-READS LOB segments. The
  selected storage is `SECUREFILE (CACHE LOGGING RETENTION NONE)` for response,
  per-tic state, and history; temporary locators are freed per request; local
  USERS storage is presized to 4 GiB with 512 MiB growth and redo uses three
  1 GiB groups. Plain PL/SQL commits produced only one `log file sync` at worker
  shutdown, so the authoritative commit is now explicit `BATCH WAIT` and traced
  separately. Response copy is 0.731/1.160/2.971 ms p50/p95/max over 1,000
  stationary frames. The reviewed interval is now 32 tics: per-tic deltas stay
  authoritative and strict-durable, snapshot bytes remain exact, and recovery
  is bounded to 32 delta applications. The clean stationary 300-frame database
  gate passes at 27.465/32.287 ms p50/p95; 1,000 frames are 27.821/34.005 ms.
  The real dynamic 300-frame path remains 28.875/35.271 ms because spawned
  projectiles are not yet advanced/removed in retained arrays. Implement and
  parity-lock that lifecycle before public cutover or an end-to-end claim. See
  `reports/performance-P12.0-securefile-tail-research-2026-07-16.md`.
- Dynamic retained-worker 30 FPS gate (2026-07-16, supersedes the open
  projectile/state blocker above): projectile lifecycle mutations now cross the
  SQL/OJVM boundary as validated world operations; the applier writes only an
  ordered changed-actor subset and bulk-merges world changes. Canonical JSON is
  persisted at exact 64-tic checkpoints, while domain-separated lineage/tic/
  command/delta hashes cover intermediate tics. A fresh active 300-frame run
  passed at 20.065/26.008 ms p50/p95 (49.8/38.4 FPS), with five exact checkpoint
  BLOB/SHA validations, a recomputed event chain, retained-owner/SQL parity at
  tic 330, stable world cardinality, and strict BATCH WAIT commits. One 435 ms
  OJVM JIT pause remains in max latency. This passes the database p95 gate only:
  default-off public cutover, full action controls, and fixed AutoREST/browser
  p50/p95 remain mandatory before P12.0 completes.
- Public AutoREST integration checkpoint (2026-07-16): `DOOM_API.STEP` now
  selects the retained worker for one dynamic DMSC/v2 movement command and
  preserves the complete SQL path for unsupported actions/batches. Deterministic
  request IDs make lost-response retries immutable across an advanced frontier.
  Repeated `CLAIM` had leaked the ready worker-control row lock, making the
  resident worker wait 10--30 seconds despite only 23 ms of measured work; the
  ready path now commits before returning and its regression passes at 45.082 ms
  for a reconstructed worker. A reused-connection 20-frame HTTP run measures
  58.699/83.536 ms p50/p95 while its database requests measure 20.323/25.109 ms.
  Moving worker selection ahead of the legacy SQL canonicalization reduces the
  active 20-frame HTTP path to 47.919/52.925 ms and reduces an
  immutable full-frame AutoREST replay to 23.109/39.131 ms over 100 requests;
  the scalar AutoREST floor is 19.521/25.316 ms. The remaining public gate is
  therefore transport scheduling/serialization plus fire/use/weapon parity, not
  an unidentified renderer slice. Bound the next experiments to ORDS pool
  configuration, a one-frame asynchronous throughput pipeline, and a smaller
  retained response/delta codec; separately report corresponding-input latency
  and displayed-frame throughput. Alternate non-AutoREST transports remain out
  of scope.
- AutoREST pipeline experiment (2026-07-16): the fixed pool is now four warm
  connections and the client uses a hard depth-four command window, a 32 ms
  deadline scheduler, ordered decode, and a six-frame server-frame presentation
  buffer. The best 300-frame cadence-only run reached 30.350 displayed FPS with
  32.135/33.083 ms paint-gap p50/p95 and 70.417/169.555 ms input-to-decode
  latency. A fresh-session run reached 31.039 FPS and 32.197/33.103 ms gaps but
  only 112 unique frame hashes; a more active command pattern produced 113
  unique frames and missed cadence at 28.921 FPS. Therefore this is feasibility
  evidence, not the final public gate: the fixed replay must produce at least
  270 unique moving frames while preserving the cadence result, and full
  fire/use/weapon parity remains open. Depth two (22.666 FPS) and depth three
  (28.099 FPS) were measured and rejected for this local two-core stack.
- Exact movement boundary correction (2026-07-16): a long pipelined run reached
  `x=-192`, where double BSP traversal selected sector 141 but Oracle NUMBER
  tie semantics selected sector 99. The worker rolled the tic back. Final
  movement location now uses the exact NUMBER BSP cross product after the
  established portal traversal; the failing command commits and all 270 SQL/
  Java movement parity cases pass.
- Public unique-moving-frame gate (2026-07-16): after the deployment-grade OJVM
  warmup and exact boundary fix, the depth-four AutoREST client completed a
  bounded dynamic spawn-room route with 300/300 unique frame hashes at 30.799
  displayed FPS. Paint gaps are 32.209/33.138 ms p50/p95; corresponding
  input-to-decode latency is 120.487/148.256 ms and remains a separate metric.
  One AQ empty-poll boundary produced a 96.191 ms maximum gap. The frontier now
  uses the bounded worker deadline and clients retry the same deterministic
  sequence after transient ORDS failures, preserving exactly-once state. This
  closes the public movement cadence gate. Retained fire/use/weapon parity and
  the complete T5--T7 regression remain before P12.0 completion.
- Retained-control execution order (2026-07-16): measured SQL fallbacks are
  8,173 ms fire, 8,418 ms use, and 8,010 ms weapon selection; the next retained
  movement then spends 491--615 ms reconstructing. Implement weapon selection
  first, fire second, and use/world machines last. Preserve DMSC/v2 exactly and
  use the fixed-length DMSC/v3 action envelope plus independently versioned
  DCTC/DTIC results. Public v3 routing remains off until strict delta, canonical
  state, renderer rollback, restart, differential, and repeated 300-frame gates
  pass. See `reports/performance-P12.0-retained-controls-design-2026-07-16.md`.
- Retained weapon and warm-public cutover (2026-07-16): DMSC/v3, DTIC/v2,
  canonical state, durable SQL apply, renderer/HUD rollback, checkpoint v4,
  restart state, and LOWER/RAISE events are integrated. A nine-tic acceptance
  proves eight exact v3 transition tics, automatic quiescent return to DTIC/v1,
  nine in-worker SQL parity checks, and distinct weapon frames. Version
  selection is recomputed only after pipelined predecessors commit. Matched hot
  300-frame results are 20.883/28.527 ms for v3 versus 20.332/28.284 ms for v2;
  the apparent cold regression was incomplete OJVM warmup, so READY now warms
  the production movement/action/render call graph. The smallest reliable
  public window is depth three: a weapon-switching route produced 300/300
  unique frames at 31.065 FPS, 32.181/32.977 ms paint gaps, and
  49.303/81.127 ms request-to-decode latency. Depth two was borderline and
  missed one repeat at 29.462 FPS. Retained fire is next, then use/world
  machines; both continue to use the complete SQL fallback until their own
  strict parity gates pass.
- Retained fire F1 checkpoint (2026-07-17): the catalog-driven retained kernel
  now covers FIST/PISTOL/SHOTGUN/CHAINGUN/CHAINSAW ammo, READY/REFIRE gating,
  flash/refire state, exact three-draw pellet order, reviewed renderer rays,
  wall/nearest-target selection, DAMAGE/HITSCAN/DRY_FIRE events, and same-tic
  monster processing. Its isolated AutoREST differential matches SQL exactly
  at health 94, RNG 4, ammo 49, ordered event JSON, two durable owner/SQL parity
  checks, and renderer output. This gate deliberately pins special-1 light
  timers: it exposed that `doom_world_machines.advance` consumes RNG before
  combat and the retained owner does not yet carry those machines. Therefore
  F1 is parity-proven but not generally selected. Integrate retained world
  machines first, then remove the guard; barrel recursion and player rocket/
  plasma lifecycle remain F2 and continue through the complete SQL fallback.
- Retained USE split-phase correction (2026-07-17): the first post-tic SQL
  world-machine bridge was rejected before deployment. The retained Java path
  had already run weapons/monsters, so applying USE/WALK/movers afterward would
  change canonical event ordinals, RNG, LOS, collision and hashes; synchronizing
  the final rows cannot repair the wrong same-tic order. Production therefore
  continues to reject retained `use != 0` and routes it through the complete SQL
  oracle. The selected implementation order is now movement-only Java staging,
  a no-frontier SQL movement apply, SQL world machines, transactional geometry/
  player/actor synchronization, then Java weapons/combat/monsters and the final
  delta/render/commit. Selection requires generic (no fixed linedef) coverage of
  specials 1/11/26/62/88/117, key denial/allow, WALK, full door/lift/switch
  timelines, carry/blocking, world-before-combat event/hash order, switch pixel
  changes, rollback and mid-mover restart. See
  `reports/performance-P12.0-retained-use-split-draft-2026-07-17.md`.
- Split AutoREST 30 FPS gate (2026-07-17): a combined `STEP` request was proven
  to serialize ORDS response work with the next tic on the two-core stack. The
  public package now exposes idempotent `SUBMIT_STEP` and immutable
  `POLL_FRAME` AutoREST procedures while retaining `STEP` compatibility. The
  first pipeline harness had an artificial ~29 FPS ceiling because 0--4 ms
  pump lateness was accumulated into every subsequent deadline; absolute
  32 ms deadlines remove that drift. The selected shape is depth-four command
  submission, exactly one result waiter, ordered decode, and a ten-frame
  startup buffer. Two fresh 300-frame moving runs passed at 31.064 and 30.924
  displayed FPS with 32.154/33.040 and 32.274/33.110 ms paint-gap p50/p95.
  A third run with an abandoned worker present passed at 30.333 FPS and
  33.262 ms p95. The selected post-index 31.8 ms presentation-clock run passed
  at 31.083 FPS with 31.214/32.357 ms paint-gap p50/p95 and the same exact
  330-frame chain. Correlated response AQ is rejected at 23.775 FPS and a 30 ms
  table-poll cadence is rejected at 27.838 FPS; do not retry either without new
  evidence. Idle workers now back off and self-release after 60 seconds. The
  live browser uses the selected dynamic protocol; the ten-frame buffer is a
  measured throughput solution, not the final latency target, so shrinking it
  through further renderer/submit-tail reduction remains active P12.0 work.
  A six-frame follow-up failed at 22.908 FPS/119 stalls. Eight frames passed one
  exact-chain run at 31.596 FPS and 31.222/32.191 ms paint-gap p50/p95, but the
  client stays at ten until that result repeats after retained world machines.
  A separate restart defect is fixed: committed orphan AQ wakeups whose request
  row was cascade-deleted are consumed rather than terminating the Scheduler
  worker on `NO_DATA_FOUND`; a focused next-request regression covers it.
- Dynamic USE plus renderer-headroom selection (2026-07-17): generic retained
  specials 1/11/26/62/88/117, key denial/allow, WALK, door/lift/switch
  timelines, carry/blocking, rollback, restart, and SQL parity now pass with
  `UNIFIED_WORKER_SPLIT_USE_ENABLED=1`. Ordinary movement uses its retained
  BLOCKMAP decision and avoids a complete relational geometry rebuild; genuine
  triggers and active movers retain the exact split SQL-world path. Detailed
  moving-route tracing isolated 7.650 of 8.126 ms average portal time in ACTIVE
  portal/wall sampling, not sorting or buffer reset. The selected clean-room
  renderer now traverses the near BSP child first and rejects a far child only
  when every column touched by its complete bounding box already has a strictly
  nearer dynamically-solid hit. Near-plane crossings fail open, exhaustive
  audit mode remains unchanged, and moving sector heights recompute solidity
  before render and rollback. Matched exact routes reduced average kernel time
  from 16.506 to 12.617 ms. Two fresh 300-frame runs passed at 31.036 and
  32.064 displayed FPS with 300 unique frames and the unchanged 330-frame chain;
  the second had zero stalls and 31.159/32.048 ms paint-gap p50/p95. The
  independent 12-pose SQL oracle retained all 57,012 accepted and 21,050
  visible intersections, matched 12,487 active portal hits, and matched all
  64,000 final pixels. This selects the optimization without reducing
  resolution; horizontal plane spans remain the next renderer architecture
  slice before the future 640x400 profile.
- Retained fire F2 barrel checkpoint (2026-07-17): catalog-driven hitscan now
  applies exact depth-first barrel recursion in retained arrays, including
  stable ID-ordered victims, splash occlusion/falloff, player armor/death,
  same-tic monster pain/death, final ID-ordered world operations, and rollback.
  The differential chain fixture matches the independent SQL path byte-for-byte
  across 11 ordered events and final player/world state, and in-worker SQL
  parity passes. The fixture also exposed and fixed a pre-existing engine-data
  defect: type 2035 had null dimensions and therefore instantiated at radius
  zero; fresh and upgraded databases now use radius 10/height 42. Retained
  removals detach weak target/tracer/owner references in bulk on both sides and
  compact Java arrays once per removal set. Player rocket/plasma spawn, swept
  advance, impact, splash, and transient same-tic ID reuse were the final F2
  protocol slice and are now complete.
- Retained projectile and live-FIRE gate (2026-07-17): DMSC/v4 carries dynamic
  FIRE ticcmds and DTIC/v3 carries exact canonical spawn angle, nullable sector,
  and transient projectile lifecycles. Rocket and plasma survivor/impact paths,
  splash, same-tic monster death/drop ID reuse, malformed fencing, public
  `SUBMIT_STEP`/`POLL_FRAME`, and SQL differential parity pass. All future
  ticcmds are predecessor-independent at submit time; the ordered resident
  worker remains the sole state-transition authority. Removing the former FIRE
  wait restored the 300-frame combat route from 12.92 to 27.58 FPS, and two
  correlated result polls then produced repeat passes at 31.995 and 30.817 FPS
  with identical combat chains and 31.220/32.087 ms best paint-gap p50/p95. The
  isolated non-FIRE baseline passes at 30.879 FPS. The complete warmed resident
  suite and T7.1–T7.3 visible evaluators pass.
- P12.0 completion (2026-07-17): final isolated production-default runs passed
  at 32.064 FPS for ordinary movement and 31.999 FPS for FIRE every eight tics,
  both with 300/300 unique frames, zero stalls, and their exact expected chains.
  The complete T5.1–T7.3 regression passes after reconciling the T6.1 audit with
  the separate canonical-ledger package and the T6.4 live oracle with the
  already-selected 64-tic production checkpoint cadence. The pulled-forward
  enabling gate is complete; P8 resumes. Ten-frame presentation latency and
  plane-span/cold-tail headroom remain non-blocking follow-up optimizations.
- P12.0 combat correction and measurement reconciliation (2026-07-17): the
  earlier completion evidence is superseded for combat because it depended on
  the projectile-owner collision defect. After owner-safe projectiles, catalog
  caching, packed-delta tracing, coordinate hoisting, retained scratch arrays,
  and renderer texture specialization, the first valid post-JIT-quiescence
  300-frame FIRE-every-eight route produced 300 unique frames and the exact
  expected chain at 20.786 FPS. Its paint-gap p50/p95 was 31.724/93.828 ms.
  Warm averages were 23.417 ms render (18.268 kernel, 10.408 portal walk),
  10.085 ms durable apply, 5.812 ms prepare, 3.664 ms codec, and 2.815 ms
  commit; retained projectile work was only 0.440 ms. Therefore projectile
  tuning is no longer the gate. P12.0 is reopened until corrected combat again
  passes 30 unique FPS at p50 and p95.
- JIT measurement rule (2026-07-17): never retain a warm-path benchmark taken
  while Oracle's `MZ00`/`MMON_SLAVE` JavaVM JIT worker is consuming foreground
  CPU after `loadjava`. Wait for the worker to quiesce, confirm the hot methods
  are `USER_JAVA_METHODS.IS_COMPILED='YES'`, and record container CPU alongside
  the sample. Post-load transition measurements belong only in cold/JIT-tail
  evidence. Synchronous `DBMS_JAVA` compilation is required after loading the
  renderer and its dependent worker classes; it is a no-op only when every
  non-`<clinit>` production method is already compiled.
- Two-stage retained-render overlap (active, 2026-07-17): the serial critical
  path cannot meet 33.3 ms reliably because rendering and durable relational
  apply are summed. Add one bounded resident render Scheduler session and a
  compact, versioned render-delta envelope. The simulation worker sends the
  pending camera/HUD, dirty actor, sector-light, and dynamic-world changes to
  that session, which stages the exact response while relational delta apply,
  state/hash work, and commit preparation proceed concurrently. The renderer
  must retain a pending frontier and expose explicit ACCEPT/DISCARD; it may not
  advance accepted arrays until the authoritative command transaction commits.
  Tables remain the durable authority, SQL simulation and SQL rendering remain
  independently executable differential oracles, and the public API remains
  generated AutoREST `SUBMIT_STEP`/`POLL_FRAME` with exact request correlation.
- Two-stage acceptance gates: keep the render envelope within the bounded RAW
  transport or fail closed; fence every request by session, lineage,
  generation, command sequence, and expected tic; make duplicate delivery
  idempotent; discard staged renderer state on simulation rollback; recover
  either worker from tables/checkpoint with an identical state/frame SHA chain;
  survive renderer death after stage and simulation death before/after commit;
  pass 300-frame SQL/retained parity plus the complete T5--T7 suite; then pass
  two quiescent corrected-combat runs at >=30 unique displayed FPS with
  <=33.3 ms p50/p95 paint gaps. Report input-to-correlated-frame latency
  separately. Do not call uncommitted or eventually consistent output playable.
- Two-stage overlap result (2026-07-17): the default-off implementation passes
  packed/direct frame parity, staged/final BLOB identity, explicit accept,
  post-render precommit discard, SQL-frontier rollback, generation fencing,
  and restart recovery. It is rejected as a performance selection on Oracle
  Free's two CPUs: the same 330-tic route measured 75.855/140.160 ms caller
  p50/p95 with two workers versus 66.476/112.506 ms with one. Concurrent render
  inflated other database work and added a second commit/rendezvous. Preserve
  the implementation and gates default-off as evidence; do not enable or retry
  it without a materially cheaper rendezvous or more CPU headroom.
- Retained passive-world result (2026-07-17): specials 1/12 now have a clean-room
  array-resident implementation that emits the existing DMWP/v1 delta and still
  persists it through the strict SQL applier. A focused fixture matches both
  the SQL-built 48-byte pack (three ordered sectors, three RNG draws) and the
  complete unified delta byte-for-byte. Rollback/restart and the final 330-tic
  owner/SQL parity gate pass. The quiescent same-revision route improved only
  modestly to 64.911/105.244 ms caller p50/p95 because an active mover forced
  the full-world branch on 280/300 measured tics (279 active). The exact
  remaining full-world slices are world-machine advance at 1.709/40.975 ms and
  geometry/switch packing at 13.830/15.127 ms; render is 19.278/21.658 ms and
  durable apply 5.371/8.737 ms. Next move active mover/switch state into the
  retained owner and emit only ordered dirty sector/line deltas. Keep the SQL
  world-machine path as the differential oracle and durable delta applier.
- Sparse retained-geometry result (2026-07-17): DMWG/v4 replaces the complete
  sector image with an ordered delta containing passive-light sectors, active
  mover sectors, and just-reached/reopened/blocked mover sectors; the complete
  MOBJ-Z image remains conservative for lift carry and blocking. Movement, LOS,
  monster chase, the unified owner, and the renderer stage the same fenced pack
  and retain exact discard snapshots. The use lifecycle, pre/post-commit
  rollback/restart, passive-world byte parity, 330-tic owner/SQL parity, and
  exact frame chain all pass. With every selected hot method native and the DB
  quiescent, caller latency improved from 64.911/105.244 to 60.932/96.945 ms
  p50/p95; geometry packing fell from 13.830/15.127 to 9.177/10.315 ms and
  world synchronization measured 0.214/0.378 ms. The remaining active-mover
  world-machine advance is 1.763/40.945 ms and is now the dominant p95 target.
  Move mover timers/heights/directions and switch timers into the retained owner,
  emit strict ordered SQL deltas, and keep the current SQL machine as the
  differential oracle and recovery authority.
- World-machine spatial reuse result (2026-07-17): the SQL mover oracle was
  repeatedly invoking `DOOM_BSP_LOCATE` for every player/MOBJ during door
  occupancy, lift blocking, and lift carry despite already having the exact
  post-movement player sector and durable MOBJ sector IDs. Reusing those
  frontiers, with a locate fallback only for intentionally null-sector
  projectiles, preserves the complete lifecycle, rollback/restart suite,
  330-tic owner/SQL parity, and exact frame chain. World-machine advance fell
  from 1.763/40.945 to 1.878/3.623 ms p50/p95; the same quiescent database route
  improved caller p95 from 96.945 to 91.526 ms. This removes the active-mover
  tail and defers a larger retained-mover protocol unless a future route makes
  it dominant again. It does not solve corrected combat: the current public
  FIRE route has no active world machine and measured 19.59 FPS, with retained
  render kernel 15.341/31.089 ms and delta apply 8.551/24.808 ms. Optimize those
  two independent slices next; do not attribute the public gate to movers.
- Direct retained-world DML result (2026-07-17): DTIC world operations are
  fenced mutations of existing IDs, so a `FORALL MERGE ... USING dual` paid
  unnecessary match/row-source work. Separate direct bulk UPDATE and DELETE
  statements retain exact ordered row-count/race checks, weak-reference
  detachment, transient projectile reuse, and rollback. The projectile lifecycle
  and full worker rollback/restart gates pass. On the corrected 300-frame
  FIRE-every-eight public route, world-DML p95 fell from 10.608 to 5.210 ms,
  total apply p95 fell from 24.808 to 14.420 ms, and displayed throughput rose
  from the same-day 19.59 sample to 25.19 FPS with 300/300 unique frames and the
  identical frame-chain SHA. The route still fails on 63.564 ms paint-gap p95;
  its worker averages 41.364 ms between completions, with mean render 19.344 ms
  and mean durable apply 9.159 ms. A depth-2/one-poller transport A/B regressed
  to 15.35 FPS by starving correlated retrieval; retain two pollers and do not
  retry that shape. Continue with retained render-walk and delta-decode/DML CPU,
  not buffering claims—the producer itself remains below 30 FPS.
- Corrected-combat 30 FPS selection (2026-07-17): production wall ownership is
  disjoint across all 1,321 stored cardinality samples, so the non-diagnostic
  renderer no longer clears/checks a 64,000-byte ownership plane or increments
  a static counter per wall pixel; diagnostic mode still asserts the invariant.
  Full synchronous compilation now covers every non-`<clinit>` method in the
  renderer and retained simulation graph, eliminating the minute-long MZ00
  contention previously triggered by newly claimed worker sessions. Async
  worker heartbeat/commit-metric DML is sampled every 32 tics, while the
  authoritative tic commit is pinned to `COMMIT WRITE IMMEDIATE WAIT`.
  Finally, DMF3 replaces the redundant inner JSON/base64 frame with a compact
  gzip binary envelope; generated AutoREST still transports the response BLOB,
  legacy JSON frames remain decodable, and the frame/state SHA contract is
  unchanged. Typical response size fell from about 44 KB to 25.75 KB. Two
  quiescent corrected FIRE-every-eight runs produced 300/300 unique frames and
  the identical chain `89e25e27276963b1602523a08beee647aad84c11911eef9c20317f066fce6121`
  at 31.951/30.807 displayed FPS, with paint-gap p50 31.213/31.222 ms and p95
  32.136/32.278 ms. Producer throughput independently measured 31.55/30.40 FPS.
  Retained-render parity, codec v2/v3 compatibility, projectile lifecycle, and
  rollback/restart/generation fencing pass. Complete the full T5--T7 regression
  before closing P12.0, then resume the preserved P8 route.
- Corrected-combat regression checkpoint (2026-07-17): T5.1, T5.2, T5.3, and
  T6.1--T7.3 pass unchanged against the deployed revision. T5.2 retained its
  reviewed `df931aead5a878018c9ad36cff0b73ed56545b290dcff9f59001fbec9a3f11f4`
  frame hash and all 1,856,885 declared assertions. The T6.2 public route now
  records the corrected combat cadence (the pre-fix checkpoints had stale
  health/kill counts); two consecutive 163-command runs matched exactly.
  T5.4 source, mutation, and all nine reviewed PNG/golden checks pass. Its live
  SQL presentation pass reached normal game, pause, menu, and automap without
  an assertion failure, but was stopped after 73 minutes when its repeated
  full-frame oracle renders starved concurrent `NEW_GAME` requests on the
  two-core primary stack. Never rerun T5.4 live beside an interactive session:
  use a clean isolated database or a declared idle maintenance window. This is
  test isolation, not a production-renderer performance regression; the
  selected retained path remains qualified at 30.807--31.951 displayed FPS.
- Actor snapshot bulk-collection rejection (2026-07-16): replacing the ordered
  record assignment loop with `BULK COLLECT` passed T7.2 and the exact
  163-command route, but measured 1,168.745 ms over the route versus the prior
  1,157.735 ms. Oracle charged essentially the same row materialization to the
  cursor. The experiment was reverted; do not retry it without reducing the
  relational/visibility work or snapshot width itself.
- New ray, screen-axis, clip, span, and cache-key relations use an explicit
  resolution profile.  `CANONICAL_320X200` remains the only selected profile and
  keeps all reviewed hashes.  A future 640x400 profile is a required design
  target, not part of the current golden set: it has four times the pixels and
  must be addable without redesigning resolution-independent visibility or
  geometry.  No claim of 30 FPS at 640x400 follows from meeting it at 320x200.
- Exact dependency caches may accelerate unchanged/revisited states, but cache
  keys must cover every render dependency and cache-miss moving frames remain
  the playability authority. Only after renderer work approaches the budget may
  ORDS pool settings or compression-level tuning be treated as finishing work.
  The exact Java frame hash/RLE/JSON/GZIP/BLOB codec is part of the <=20 ms
  renderer gate because the measured SQL codec cannot remain in production.
  Database In-Memory,
  MLE, UTL_TCP, alternate HTTP surfaces, approximation, reduced resolution, and
  client prediction/rendering remain rejected.
- Every candidate must retain the exact reviewed T5 frame hashes and pass the
  complete T5-T7 correctness and mutation gates. Record rejected attempts and
  raw timings. Select an optimization only after repeat measurements show a
  material local improvement without cursor-shape regression.
- Accept: representative local render and STEP timings are recorded, exact
  renderer/state hashes and payload schema remain unchanged, all T5-T7 gates
  pass, and P8 resumes against the selected faster revision. This is an enabling
  gate, not final T12 acceptance; T12.1/T12.2 still require the fixed 300-frame
  replay and independent local/cloud evidence after P11.

### P12.M - Mocha Doom inside Oracle JVM

This migration is the active implementation path. Preserve the paused SQL-route
working tree as diagnostic evidence, but do not spend additional effort extending
the clean-room engine unless it is needed to validate the new public contract.

#### T12.M1 Pinned source, license, and reproducible OJVM build

- Pin `AXDOOMER/mochadoom` at
  `c0af1322ee5fd168b5cf8aaaf504cab2d1aabe93` as an explicit third-party source
  dependency. Do not track generated classes, JARs, credentials, WAD files, or
  local Oracle artifacts.
- Preserve upstream GPLv3 and per-file notices. Add a machine-readable license
  ledger and document that the project adapter and combined engine distribution
  are GPLv3-compatible while Oracle Database is a separately licensed runtime.
- Compile all sources with the pinned Oracle toolchain using `javac --release
  8`, the bytecode floor supported by Autonomous OJVM; package a deterministic
  JAR; load it with client-side `loadjava -resolve`; fail on any invalid Java
  object or resolver error. Java 11 remains valid for historical local probes,
  but is not the production cloud artifact contract.
- Spike evidence (2026-07-18): all 442 upstream Java sources compiled unchanged
  into 820 classes and a 1.2 MB JAR. A disposable OJVM schema resolved all 820
  classes with zero errors and a SQL call returned
  `ok|headless=true|fineSine=10240|fineTangent=8192`. Reproduce this from checked-
  in scripts before closing the task.
- Accept: a clean build verifies the pinned commit and source hash, resolves the
  complete class graph in a disposable schema, runs the headless call probe, and
  removes the schema without leaving credentials or generated files.

#### T12.M2 Bounded headless engine adapter and IWAD source

- Add a GPLv3 OJVM adapter that owns no JFrame, Canvas, desktop event listener,
  audio device, network socket, filesystem configuration, wall-clock loop,
  background renderer pool, or `System.exit` path.
- Refactor startup just enough to inject command variables, configuration,
  ticker, sound sink, presentation sink, and WAD loader. Prefer upstream-facing
  patches that keep engine logic unchanged over a forked second implementation.
- Store the pinned Freedoom IWAD bytes in an Oracle SecureFile BLOB or a correctly
  named Java resource. Verify its SHA before constructing the engine and provide
  seekable/read-only lump access without writing a host temporary file.
- Export catch-all entry points for bounded `probe`, `initialize`, `new_game`,
  `step`, `frame`, `save`, `load`, `reconstruct`, and `dispose` operations.
- Implementation checkpoint (2026-07-18): the pinned 442-source engine plus
  GPLv3 adapter compiles to 822 classes; the schema reports 852 valid Java
  classes including 30 preserved legacy helpers. A 28,795,076-byte
  database-resident Freedoom IWAD is verified as
  `7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d`.
  Narrow patch overlays remove the desktop loop/window, inject the seekable
  IWAD, ignore absent host configuration, avoid privileged logging setup, and
  block external configuration/translucency-map file I/O. E1M1 now initializes
  wholly inside a 4 GB Oracle container and produces a deterministic 320x200
  indexed framebuffer. The selected tic-zero SHA is
  `a1c9b0378eed9e82425cae593b82dfa44715627d8aa635562b450e4c1af3d3b5`.
  A bounded no-input tic advances to tic 1, the caller-owned BLOB handoff writes
  all 64,000 bytes in 1.431 ms, and caller-selected new-game plus deterministic
  disposal entry points pass. Interpreted cold initialization was 15.75-18.40 s;
  after selected native renderer compilation it is 6.21 s and remains
  startup-only. All 18 upstream `System.exit` sites are mechanically replaced
  with catchable fenced errors and deployment fails if a new exit remains.
  Native vanilla save/load is implemented as a bounded diagnostic but rejected
  for production: a 61,498-byte checkpoint reload changed the immediate frame
  and the next 20-command branch. Exact reconstruction now uses the durable
  packed `ticcmd_t` ledger. A fresh-engine replay of 70 forward/FIRE-every-8
  commands reproduced tic 70, level time 70, RNG index 82, player pose, command
  SHA `afb9740b82590f9678ababc1376ba6fd1d388130f39a1e060b9127b5d3235140`,
  and frame SHA
  `1404cf810faeb1a237a86966b4b3d67cb7f9f42d6a2be91cf1207facccdca509`
  exactly. Persisted replay integration and a complete state token remain open;
  T12.M2 is not yet complete.
- Accept: E1M1 initializes inside OJVM without GUI/audio/filesystem access; one
  deterministic no-input tic returns a complete 320x200 indexed framebuffer and
  state token; every entry point converts all failures into a fenced error.

#### T12.M3 Deterministic command, frame, audio, and persistence bridge

- Map the current ordered AutoREST tic command fields to Mocha Doom `ticcmd_t`
  without response-dependent input synthesis or browser gameplay logic.
- Convert the selected indexed framebuffer, palette, HUD/weapon/menu/automap/
  intermission state, and authored sound events into the existing compact public
  response envelope. Version the envelope when semantics differ; retain legacy
  decoding during migration.
- Persist accepted command batches, correlated result metadata, frame/state
  hashes, save material, and periodic reconstruction checkpoints in Oracle before
  signaling completion. Record the pinned engine and IWAD revisions in every
  lineage root.
- Reconstruction decision (2026-07-18): do not select `VanillaDSG` as the
  authoritative checkpoint. It is a deliberately lossy vanilla compatibility
  format and failed both immediate-frame and continued-branch parity. Rebuild
  from the SHA-locked ordered command ledger instead. The compiled engine makes
  replay bounded; record clean-deploy reconstruction time separately from the
  17.28 s interpreted adapter-reload diagnostic, which is not valid performance
  evidence because loading the adapter invalidated renderer native methods.
- Command-bridge checkpoint (2026-07-18): the retained adapter now maps the
  existing normalized AutoREST axes/buttons to vanilla walk/run magnitudes,
  the first-five-tic slow-turn ramp, fire/use, and zero-based weapon bits. Each
  combined step/render/BLOB call returns the exact executed eight-byte
  `ticcmd_t`. `DOOM_MOCHA_COMMAND` is an append-only, generation-fenced schema
  ledger for those bytes plus command/frame hashes. `GAME_ENGINE` now defaults
  to `MOCHA` after cutover gates passed. The byte-level database gate passes seven control
  cases. A clean 30-warmup/300-sample forward/FIRE-every-8 combined-path rerun
  produced 300 unique frames at 1.704/3.191/6.025 ms p50/p95/p99 and 22.047 ms
  max. The first durable
  bridge gate committed turn-bearing command `3228fec000000017`, disposed the
  retained JVM, reconstructed solely from the lineage-aware Oracle ledger, and
  reproduced frame SHA
  `c426186759cd917ce9465ea0ad93bbb180b0b5f498e3a4804e3bbe048709c7d8`.
  This exposed upstream `ticcmd_t.unpack` sign-extension of the low short byte;
  the replay adapter now decodes network-order shorts explicitly unsigned.
  A subsequent 300-sample path added both ledger inserts, frontier update, and
  per-tic `COMMIT WRITE IMMEDIATE WAIT`: 6.124/20.889/39.378 ms p50/p95/p99,
  42.324 ms max. It then replayed all 330 committed commands to final frame SHA
  `e8d24e1073c833486dd738b6c18c4e4cc29a277536c8f050c48c654b18d710ec`.
  The durable p95 leaves 12.444 ms for response codec, AQ/ORDS, wire, decode,
  and paint; those stages remain before selection.
  The existing gzip/DMF3 public envelope is now integrated and independently
  decompressed/field-checked in Oracle. Its component path is 4.900/12.797 ms
  p50/p95. With encoding, both ledgers, frontier update, and synchronous commit
  together, 300 samples measured 8.290/19.560/38.798 ms p50/p95/p99 and 69.414
  ms max; the final payload was 10,480 bytes and the 330-command replay still
  matched. The selected p95 leaves 13.773 ms for AQ/ORDS, wire, decode, and
  paint. AQ integration is now the next implementation slice.
- Scheduler/AQ/AutoREST checkpoint (2026-07-18): the unchanged public command
  envelope now selects Mocha only when `GAME_ENGINE=MOCHA`. Synchronous STEP,
  byte-identical duplicate replay, async SUBMIT_STEP/POLL_FRAME, and a four-
  command pipelined burst pass with exact durable frontiers/results. A real
  localhost 300-frame HTTP/browser-decode/palette/presentation run with movement
  and FIRE-every-8 rejected depth-2/buffer-2 at 27.933 FPS, then passed the
  existing depth-4/buffer-10 shape at 32.029 displayed FPS, 300 unique frames,
  zero stalls, 31.215/32.058 ms p50/p95 paint gaps, and 32.795 ms max. The frame
  chain SHA is
  `a1888c88d8fa779b9b90e8e650a8a5324f3085c21fe4b44f8e810b26b84be900`.
  This closes the first local Mocha 30 FPS gate. The harness restores the
  engine selector it observed and removes its session; subsequent native-code,
  recovery/concurrency/audio/gameplay/presentation gates passed and `/play/`
  now selects Mocha for new sessions.
  An independent rerun reproduced the exact frame-chain SHA at 32.038 FPS with
  300 unique frames, zero stalls, 31.219/31.976 ms p50/p95 paint gaps, and
  32.777 ms max. The two-fresh-run deterministic AutoREST chain gate is green.
  Concurrent isolation is green: two games owned distinct Scheduler/OJVM
  sessions, matched under identical commands, then diverged under opposite
  turns with 62 correctly partitioned exact rows. A forced stop at tic 50
  exposed stale `READY=1` trust in async status; status now also proves the
  Scheduler job is running. The repaired public request advanced generation
  382→383, reconstructed from Oracle, and matched an uninterrupted twin at tic
  51 with 102 commands. Concurrent, stale-generation, forced-restart, and
  no-lost-command gates are closed.
  Persistence integration is now green. `NEW_GAME` publishes an exact retained
  tic-zero payload; `SAVE_GAME` records an immutable lineage pointer; `LOAD_GAME`
  forks the exact command/audio/frame prefix while preserving the global public
  command sequence. A save-at-24/diverge-to-34/load/continue-at-sequence-35 gate
  reproduced the saved payload and replayed all 25 branch frames exactly.
  Replay uses an immutable tic-zero row plus a lineage/tic index into the
  already-durable worker-result BLOB, avoiding a second per-tic SecureFile copy.
  Original-lineage 0..12 replay, completed-cursor idempotency, and loaded-lineage
  0..25 replay pass. The normalized `TIC_COMMANDS` insert now binds the actual
  Mocha lineage instead of its migration sentinel.
- Recovery-hardening checkpoint (2026-07-18): API exception entries capture the
  original SQL code/message before rollback or nested cleanup, eliminating the
  `ORA-21002` cleared-error failure. Loaded lineages now chain predecessor state
  by lineage-local tic while preserving the monotonic global command sequence;
  save-at-24, abandon-through-34, load, and command 35 pass exact replay. A
  forced stop with a still-fresh heartbeat is repaired from `POLL_FRAME` only
  after the correlated request ages one second: the exceptional path verifies
  Scheduler liveness, reconstructs, and idempotently migrates the stored command
  bytes to the next generation. The final rerun advanced 529→530 and passed 102
  commands with identical tic-
  51 frames. Admission also force-stops/reclaims only worker jobs whose owner
  session is provably gone. Admission and Scheduler startup now derive map/engine
  identity from the immutable session lineage, closing the cross-session global-
  selector race. Core gates preserve the caller's engine selector and explicitly
  require a PASS marker; `/play/` remains on `MOCHA` after tests.
- Accept: duplicate batches are byte-identical and apply once; two fresh runs of
  a fixed 300-tic trace have identical state/frame chains; save/load and restart
  reconstruction reproduce the uninterrupted chain across the seam.

#### T12.M4 Resident worker and generated AutoREST cutover

- Reuse the existing Scheduler/AQ worker, exclusive generation lease, durable
  request/response queues, and generated AutoREST procedures. Keep the Mocha
  engine heap only in the worker session; never assume ORDS connection affinity.
- Support dynamic independent game sessions. No command route, player outcome,
  or preselected playthrough may be hardcoded. Enforce bounded active-engine
  memory with deterministic eviction/reconstruction under Oracle Free's 2 GB
  database memory limit.
- Add a default-off engine selector until new-game, step, save/load, restart,
  timeout, duplicate, stale-generation, and concurrent-session gates pass.
- Integration checkpoint (2026-07-18): new-game, save/load, exact replay,
  duplicate, concurrent-session, authored-audio, gameplay-defect, initial-frame,
  forced-restart, pause, automap, menu, and native-code gates pass. Two fresh
  deterministic 300-frame runs exceeded 30 displayed FPS, so the selector is
  now `MOCHA` for new `/play/` sessions. Full public workflow parity remains in
  T12.M5 rather than blocking the playable cutover.
- Browser lifecycle checkpoint (2026-07-18): `/play/` now fetches the
  database-owned Freedoom `TITLEPIC` and palette through generated AutoREST,
  renders the real 320x200 indexed title, then follows title → main menu → New
  Game → skill selection before allocating a session with the selected skill.
  The canvas takes focus on click; macOS Chrome additionally requests fullscreen
  Keyboard Lock so its double-Control Dictation shortcut cannot escape the
  game. Both Ctrl keys and F fire, including cancelled held-key repeats. Hidden
  tabs pause, but a visible window can no longer freeze because browser focus
  was initially elsewhere.
- Authentic-menu checkpoint (2026-07-18): the pinned-IWAD loader imports the
  16 Freedoom/Mocha main-menu, skill, and skull-cursor lumps into Oracle as
  SHA-checked `mocha_ui_patch` BLOB assets. Generated `GET_ASSET` AutoREST
  allowlists those names. The thin client decodes Doom column/post patches with
  transparency and signed offsets, then composites the main and skill menus at
  Mocha Doom's original 320x200 coordinates with the alternating skull cursor.
  The HTML menu is now invisible accessibility/click geometry only; it supplies
  no visible approximation.
- Accept: the unmodified static client can start and freely play a new game only
  through generated AutoREST endpoints; killing and restarting the worker loses
  no accepted command and never returns another session's frame.
- Worker-admission hardening (2026-07-19): a live outage traced "shooting and
  new games stopped working" to Oracle's Scheduler job coordinator silently
  losing asynchronous `RUN_JOB` dispatches after host virtual-clock stalls
  (`Time stalled`/`backward drift` in the alert log); `CLAIM` then burned its
  whole 120 s window on a worker process that never started and public
  `NEW_GAME` returned ORA-20702. Delayed duplicate dispatches also raced
  `run_slot`, and the loser's unfenced cleanup clobbered the winner's control
  row (the observed `worker ready fence`/`worker state-map fence` fatals).
  `run_slot` now exits quietly on a stale start or when superseded, and both
  its stop and failure cleanups are generation-fenced to the claim they own;
  `claim` re-dispatches `RUN_JOB` every three seconds while the slot has no
  running Scheduler job and rebuilds a released claim; `start_worker` reclaims
  dead claims (target set, never ready, no running job, heartbeat older than
  60 s) so a poisoned slot cannot block the pool until session expiry. The
  operational remediation for a wedged coordinator is bouncing
  `job_queue_processes` (now pinned to 8 in local initdb for slave headroom);
  a full instance restart alone did not clear it. Three direct-bridge gates
  (durable-bridge, durable-audio-ledger, presentation-controls) now pin
  `GAME_ENGINE='SQL'` and restore it, because under the post-cutover `MOCHA`
  default their `NEW_GAME` claims a real worker whose control row collides
  with the manual slot-3 harness on the unique target-session constraint.
- Bounded eviction (2026-07-19): when every slot hosts a ready worker,
  `start_worker` now asks the least-recently-active ready worker (oldest
  committed request, then slot order) to stop and waits up to ten seconds for
  a slot instead of refusing the new player outright. Durable state makes the
  evicted session a later reconstruct, never a loss; this closes the
  refresh-a-few-tabs pool-exhaustion outage under the deliberate 600-second
  idle retention and satisfies the T12.M4 bounded-memory eviction requirement.
  A live five-session probe over public AutoREST confirmed the fifth `NEW_GAME`
  evicts and succeeds in about 13 s while all four slots were ready.
- macOS Ctrl-fire (2026-07-19): both Control keys are bound to fire on every
  platform again. Because a windowed browser cannot suppress macOS's rapid
  double-Control Dictation prompt, canvas clicks remain exclusively windowed
  mouse capture and a separate top-right button is the only fullscreen entry.
  That explicit opt-in enables Keyboard Lock (locking both Control keys and the
  gameplay set) so Ctrl-fire never raises the Dictation prompt; leaving
  fullscreen unlocks and returns to windowed capture. The control has no ticcmd
  mapping and cannot collide with fire, menu, Escape, or Pointer Lock.
- Collision-free key map (2026-07-19): Escape had three simultaneous meanings
  (database menu, pointer-lock release, fullscreen exit). Escape is now
  reserved for the browser — one press releases the captured mouse and exits
  fullscreen when active — while the Doom menu moved to Tab, the automap to M, and audio
  toggle to V. Escape stays a bound no-op control so the reviewed T10.2
  keyboard contract (every bound key emits a command) is unchanged, and the
  pre-game skill menu keeps Escape as back.
- New-game latency (2026-07-19): the entire FREEDOOM-title stall after skill
  confirmation is `NEW_GAME`; the browser pipeline paints within ~200 ms of
  its payload. Cold Mocha engine construction in a fresh worker session
  measures ~10–20 s (one-time per JVM: class loading plus giant interpreted
  static initializers; repeat `InitNew` is ~1 s, the IWAD BLOB read is
  ~0.5 s, and targeted `DBMS_JAVA` compilation of loader classes did not
  move it — one monolithic class also stalls the accelerator and must be
  skipped). Selected mitigations: the skill menu speculatively allocates the
  highlighted default-skill game the moment NEW GAME is chosen (a different
  confirmed skill falls back to a fresh allocation; title/main-menu lurkers
  allocate nothing), and the startup status line ticks elapsed seconds so the
  wait is visibly alive. An 8-second menu dwell cut confirm-to-first-paint
  from ~13 s to ~5 s. The identified structural fix is a pre-warmed standby
  worker that constructs the engine before it is claimed and only runs
  `InitNew` at claim time; it requires its own fencing/differential gates and
  remains open follow-up work.
- Pre-warmed standby worker selection (2026-07-19): `doom_worker_control` now
  carries a `standby` flag; a target-less Scheduler worker arms by running
  the adapter's `initialize` only (construct, medium `InitNew`, first
  display), then waits — heartbeating, honoring `stop_requested`, and
  expiring on the idle timeout with a fenced flag clear so a simultaneous
  claim keeps its warm engine. Claims prefer a standby slot (skipping the
  redundant `RUN_JOB`), fall back cold if the standby job died, and each
  successful claim best-effort arms at most one replacement standby on a free
  slot other than the gates' slot-3 harness. Exactness was the hard
  requirement: the first arming shape (full `new_game`) produced a third
  `InitNew`/display whose leftover melt-wipe and border-redraw presentation
  state diverged early frames from the canonical cold chain (caught as an
  alternating save/load state SHA); adapter-side buffer surgery was rejected
  because it would also change same-JVM reconstruct semantics that existing
  gates baseline. Initialize-only arming makes the claimed sequence
  identical to a cold claim by construction: a two-fresh-session 24-tic
  differential is byte-identical in every frame/state/payload SHA, repeated
  pre-token-v2 save/load runs reproduced the historical `c60c0fc9…` state SHA,
  while the inventory-complete token selected below now produces `2d91b991…`;
  the `standby-worker-gate` (now part of the 11-gate core suite) measures cold
  ~17 s versus standby-claimed ~1.4 s with the exact canonical tic-zero
  frame. Browser measurements show 0.4–3.4 s confirm-to-first-paint when a
  standby is available; a fully occupied pool falls back to eviction plus
  cold construction. One same-JVM caveat is recorded: engine-class statics
  survive `dispose`, so second constructions inside one session are not
  byte-exact with first constructions — production never does this, and the
  differential therefore compares fresh sessions.

#### T12.M5 Gameplay and performance selection

- Re-run the T8.3 defects against Mocha Doom: continuous monster visibility,
  weapon animation, bounded keyboard-to-correlated-frame latency, and complete
  health-damage causality. Replace obsolete SQL goldens only with reviewed Mocha
  fixtures; do not weaken public behavior checks.
- Benchmark single-threaded rendering first. Treat desktop parallel renderers as
  rejected unless an isolated OJVM experiment proves they improve throughput on
  Oracle Free's two CPUs without starving ORDS or the worker.
- First interpreted warm-path evidence (2026-07-18): eight moving tics and one
  firing tic measured 136-193 ms inside the Java entry point (about 5-7 FPS),
  while the 64 KB BLOB copy is only 1.431 ms. This is a correctness milestone,
  not a performance selection. Detailed stable no-input samples isolate the
  ticker at 4.4-6.9 ms, `Display()` at about 193 ms, and framebuffer hashing at
  1.4-1.7 ms; early cold samples reached 302 ms render and one 37 ms ticker.
  Rendering is the current blocker. Verify native compilation of the actual
  hot Mocha renderer methods, and then measure a stationary 300-tic route before
  considering parallel rendering or transport work.
- Native renderer checkpoint (2026-07-18): synchronous compilation of 18
  serial-renderer classes changed stable `Display()` from about 193 ms to
  2.8-4.9 ms while preserving every observed frame SHA. Stable no-input ticker
  time is 2.7-6.5 ms, framebuffer status/hash is 1.2-1.6 ms, and complete
  internal step time is 7.0-11.1 ms after the first call (roughly 90-143 engine
  steps/s). Cold initialization fell to 6.21 s. This restores 30 FPS component
  budget feasibility but is not an end-to-end claim; make the compilation gate
  reproducible, then run moving/combat percentiles through AQ/commit/ORDS and
  the browser.
- Moving/combat native checkpoint (2026-07-18): the first 300-sample
  forward-moving, FIRE-every-8 route exposed route-only partially compiled
  draw records/functions, action dispatch, and map traversal; it measured
  22.584/49.013 ms p50/p95 with 299 unique frames. Extending the synchronous
  gate to 44 evidence-selected classes produced the same 299 unique frames at
  1.323/3.927/8.236 ms total p50/p95/p99 and 14.239 ms maximum. Ticker p95 is
  2.080 ms and renderer p95 is 1.876 ms. This leaves 29.406 ms of the 33.3 ms
  display budget for durable persistence, AQ, ORDS, wire, decode, and paint.
  The engine component is decisively feasible; next integrate it without
  weakening the end-to-end or determinism gates.
- Run two clean 300-frame moving/combat routes with unique-frame verification,
  producer completion rate, paint-gap p50/p95/max, and input-to-frame latency.
  Repeat at 640x400 as a scaling report after 320x200 selection; 640x400 need not
  meet the initial 30 FPS gate.
- Post-persistence trace (2026-07-18): a 300-sample database-only retained-worker
  run under current host contention measured ticker/render at 4.038/4.319 ms p95
  but codec/BLOB stages at 33.893/11.383 ms p95 and worker completion at 104.058
  ms p95. The corresponding HTTP run was red, so the earlier 32.029/32.038 FPS
  results are historical feasibility evidence, not current selection evidence.
  A `Deflater.BEST_SPEED` experiment worsened codec p95 to 108.651 ms and was
  reverted. Continue isolation at the gzip/LOB boundary; do not retune engine
  simulation or duplicate frame BLOBs while ticker/render remain below 8 ms.
  Raw binary DMF3 then removed gzip without changing the indexed frame or hash
  semantics; the client detects raw DMF3 first and retains gzip decoding for the
  SQL engine and existing ledgers. The next 300-sample database run measured
  12.806/23.837 ms worker p50/p95, 1.956 ms ticker p95, 0.960 ms render p95,
  0.820 ms codec p95, and 1.454 ms BLOB p95. The first raw-wire AutoREST run
  delivered 300 unique frames at 26.902 FPS but had 57 stalls and 126.689 ms
  fetch p95, so transport remains open. Raising fetch depth to four was rejected
  under contention at 8.927 FPS. Stateless bytewise PackBits shrank one frame to
  29,030 bytes but cost 176.067 ms codec p95 in OJVM and was reverted.
  A bulk-array PackBits rewrite reduced codec p95 to 32.987 ms but still pushed
  worker p95 to 46.296 ms, so raw DMF3 remains selected. ORDS standalone now
  uses its documented Jetty XML extension point and Jetty 12 `GzipHandler` for
  `application/json` responses at least 1 KiB. A representative new-game
  response fell from 123,611 bytes of JSON to 7,443 wire bytes with DMF3 still
  raw inside AutoREST base64. This preserves the Oracle DB + ORDS + static-site
  architecture and moves compression off the database worker.
  Two fresh depth-4/fetch-2/buffer-4/lookahead-4 runs then passed at 31.516 and
  31.787 displayed FPS with 300 unique frames, exact frame-chain SHA
  `a1888c88d8fa779b9b90e8e650a8a5324f3085c21fe4b44f8e810b26b84be900`,
  31.204/32.097 and 31.255/32.104 ms paint-gap p50/p95, and 155.1/187.1 and
  155.3/158.9 ms input-to-frame p50/p95. These close the local post-persistence
  30 FPS requalification. Remaining selection work is public-client workflow
  and cutover evidence, not producer throughput.
- AutoREST async-submit tail closure (2026-07-18): ASH proved the longest
  missing time was outside the instrumented Mocha stages. Generated AutoREST
  procedure discovery through `USER_PROCEDURES`/`USER_ARGUMENTS` caused cursor
  pin/load-lock bursts when the pool grew mid-route, so ORDS now starts and
  remains at exactly six physical connections for the selected four-submit,
  two-poll shape. More importantly, async `SUBMIT_STEP` had still entered the
  synchronous worker routine and executed an empty response-AQ dequeue averaging
  about 16 ms per command. The new `doom_worker_api.submit_async` persists the
  identical correlated request but skips response dequeue/result retrieval.
  Two consecutive warm 300-frame moving/FIRE-every-8 continuations passed at
  30.751 and 32.050 displayed FPS with 300 unique frames, paint-gap p95
  32.080/32.052 ms, and input-to-frame p95 231.770/157.187 ms. The second run
  had zero stalls and a 33.022 ms maximum. The full 47-class native audit passed
  with no missing compiled methods. Cold post-redefinition tails remain startup
  evidence and do not replace the required warm-play measurements.
- Accept: 320x200 produces at least 30 unique displayed FPS with paint-gap p50
  and p95 no greater than 33.3 ms, deterministic replay/recovery remains green,
  and a human can freely complete the required E1M1 workflow through `/play/`.
- Tic-zero presentation correction (2026-07-19): Mocha's canonical initial
  payload intentionally contains vanilla Doom's GRNROCK border with an
  unrendered black view because `Display()` does not draw the player view at
  gametic zero. Keep that payload and its state/frame hashes unchanged, but do
  not paint it in the thin client; retain TITLEPIC until the first correlated
  post-tic frame. The live browser gate fingerprints the canvas at the initial
  payload boundary and requires tic zero to remain unpainted.
- Presentation follow-up: define and populate the DMF3/DMF4 `complete` byte or
  remove it from the protocol; require one canonical framebuffer orientation
  for `frame_sha` instead of accepting either row-major or transport-major
  bytes; and reconcile the binary `dead` mode with `PresentationState` so death
  presentation cannot be silently discarded.
- Presentation follow-up resolution (2026-07-19): the Mocha adapter now
  populates DMF3 byte 9 from `gamestate` (1 once vanilla `G_DoCompleted` leaves
  `GS_LEVEL`, 0 during play), matching the SQL retained producer that already
  carried `liveComplete`; the tic-zero payload and every recorded mid-level
  chain are byte-identical because the byte was previously always 0. The client
  codec now enforces one canonical `frame_sha` orientation per producer format
  instead of accepting either: raw DMF3/DMF4 (only the Mocha adapter emits it)
  must hash the row-major framebuffer, while every gzip-wrapped envelope
  (legacy JSON v1/v2 and the SQL retained worker's gzip DMF3) must hash the
  column-major transport bytes, so a transposed frame can no longer validate.
  `PresentationState` accepts `DEAD`, and `Frame` exposes `complete`. The
  codec fixture asserts both the canonical acceptances and the cross-orientation
  rejection.
- Core requalification (2026-07-19): the post-presentation eleven-gate suite
  passes control-codec, initial-frame, replay, save/load, durable bridge/audio,
  forced reconstruction, concurrent isolation, gameplay-defect, presentation-
  control, and standby-worker checks. The state identity is the domain-separated
  rolling transition token over the predecessor identity, exact packed ticcmd,
  framebuffer identity, and deterministic engine material; the authoritative
  ordered ticcmd ledger is the complete reconstruction source. This supersedes
  T12.M2's earlier "state token open" checkpoint without selecting the rejected
  lossy native save codec.

### P8 - Full E1M1 and presentation workflows

#### T8.1 Full completion replay

- Route: Sol high.
- Author a deterministic command script that starts a normal game, collects needed
  resources/key, fights representative monsters, operates required door/lift
  specials, finds a secret, reaches the exit, and enters intermission.
- User reviews the route and milestone screenshots before approval.
- Accept: state and frame hashes at every milestone, final completion flags,
  kills/items/secrets, and replay repeatability match approved goldens.
- Route checkpoint (2026-07-17): the isolated route lab now commits slot 99 at
  tic 3,543 with state SHA
  `8c25c91be470e6b0f9808e229b3e2db4dac6722a9b0fda04ae7295eec1bc996a`.
  The player is alive at `(-95.98417569201497, 2000)`, angle 180, with 53 HP,
  33 kills, 30 items, one secret, the blue key, the plasma rifle, 240 cells,
  and 14 shells. The accepted sequence builds from the prior tic-3,158 health
  recovery, takes the nearby sector-87 plasma rifle and sector-74 stimpack, and
  returns to the blue-door approach. Two clean rebuilds from slot 96 reproduced
  the exact pose and SHA.
- Exit checkpoint (2026-07-17): `route-exit-completion.sql` drives only public
  tic commands from slot 99, clears the blue-door and exit encounters, activates
  linedef 407's real `USE|ONCE|EXIT` switch, and ends alive at tic 4,118 with
  49 HP, 42 kills, 34 items, one secret, and 143 cells. Two clean replays matched
  exact state SHA
  `ac5d82cba9ab641192e91e02dc6856dd9210dc57b4b7fad156bab0b40373b7e6`.
  The route exposed and now guards a combat correctness defect: player hitscan,
  projectile, and splash blockers consulted static sector heights while monster
  LOS consulted live `sector_state`, so an opened door could pass monster fire
  but reject player fire. Both paths now use the same session-bound live door
  geometry. The exit-causing command now transitions from `COMPLETED/GAME` to
  `DONE/INTERMISSION` before canonical capture; death takes precedence on a
  simultaneous terminal tic, and later commands freeze gameplay. The remaining
  terminal presentation contains all 64,000 database-authored palette bytes:
  frame SHA
  `32028078e1db3695ff9b8809641d3dea3a1c458caa25973c4f5a88489ce8e851`
  and indexed PNG SHA
  `b5a37ae70425b5f536936439ae999ec059fb0a9d6fcd3cc8913beade12e99581`.
  The remaining T8.1 slice replaces the accepted checkpoint-chain prefix with
  one uninterrupted public-command replay and freezes its intermediate frames.
- Mocha no-cheat completion checkpoint (2026-07-19): an uninterrupted skill-1
  public route now reaches E1M1 intermission at tic 762 without any cheat field,
  direct state injection, or non-AutoREST game mutation. Its first 289 commands
  are the pinned Cactaceae Freedoom 0.13 complevel-3 demo; a legal movement/use
  suffix compensates for Mocha's movement-compatibility drift. The exit required
  an explicit USE release/press because vanilla Doom consumes USE on its rising
  edge. Two clean executions reproduced terminal state SHA
  `268b9e62567b8f1d8591d61d63bf9f2d8aa84986fdb14374900be8d8043515a5`
  and frame SHA
  `7ad3d6e57913d2f2cca837b54a37d74bceeb5b56a52885735b2c5e8718b3f2fe`.
  This closes the basic uninterrupted/no-cheat completion proof, but it does not
  weaken the frozen T8.1 evaluator: its normal-skill-3 resource, representative-
  combat, keyed-door, lift, secret, milestone, replay, and visual-review matrix
  remains open. Replaying the same route at skill 3 ended in GAME at tic 762,
  so that broader acceptance still needs its own authored route.
- Skill-3 route-authoring diagnostic checkpoint (2026-07-20): the retained
  engine status now exposes a bounded, distance-ordered `nearby` field for at
  most 24 pickups, shootable actors/barrels, and missiles within 1,024 map
  units. It is read-only, excluded from canonical state material and public
  payloads, and has a defensive 8,192-thinker traversal ceiling. This isolated
  the route's false 32-unit portal at linedef 550 (a 160-unit floor jump), the
  immediate shotgunner/projectile lanes at tic 4,092, and the actual shotgun
  drop. A save/load authoring branch now owns the shotgun at tic 4,397 with
  18 HP and state SHA
  `1d4814cea4bba63af4dea15fc94c302df3a5aa423d4dadee64d51f3140bcd09f`.
  The 173 normalized public commands from the tic-4,224 slot-93 checkpoint to
  that pickup remain in Oracle's durable request ledger; exporting and replaying
  them after a later save/load sequence gap reproduced both that exact state SHA
  and frame SHA
  `79ecae9d8a485f0ca90a515113157102c07bf279fe7b295924eb2815001332ee`.
  That branch is navigation evidence only: it used public save/load while being
  authored and does not replace the required fresh uninterrupted AutoREST
  replay or any T8.1 acceptance gate.
- Long-route replay and engine-hardening checkpoint (2026-07-19): the lineage
  exporter now follows each frame-ledger request back to its original worker
  command and emits large routes as aligned base64, so a complete 6,336-command
  save/load branch replayed through public AutoREST with exact terminal state
  SHA `68de10756199650d18572616912d96e918a5d5eec3506822d5c8a485a138d5c6`
  and frame SHA
  `0cc39549ed4989ae93af34113b62a179426b8e8267a2bd1d20ed593b888e16ad`.
  A fresh clean replay then reached a safe tic-7,953 checkpoint with state SHA
  `9c621f1dd7521bcba28e390a8c271db23c113c02fc663ceb31003722fdde6e78`.
  The next combat branch deterministically fenced its worker after tic 8,006:
  `AbstractDoomAudio.AdjustSoundParams` indexed `finesine` with upper unsigned
  angle bits. Overlay `0007-audio-fine-angle-mask.patch` constrains the lookup
  to `FINEMASK`; after deployment and reconstruction, the exact failing branch
  advanced through tic 8,048 in GAME mode with state SHA
  `508f2d9af8393f9b983b05278f6e952c321f44b88a56e529508b418be726eabd`
  and frame SHA
  `ce31d6dd25fb2d8df0f02029db40b7132dfb1a385a89eb6d312ca2108f52c01a`.
  These are route-authoring and crash-recovery evidence only; the required
  uninterrupted normal-skill-3 completion, milestones, and replay remain open.
- Skill-3 lift checkpoint (2026-07-20): the no-cheat authoring lineage now
  extends the verified 6,336-command prefix to tic 9,223 and preserves all
  9,223 public commands in
  `artifacts/t8.1-live/mocha-skill3-lift-prefix-9223.json`. The added branch
  survives the lower-area combat route, collects another health bonus, calls
  linedef 594's tagged down-wait-up platform from the pit, enters it while
  lowered, rides sector 98 back up, and exits alive into sector 150. Slot 94
  pins the resulting 5-HP pose at approximately `(77,329)` with state SHA
  `0e5bdddcdc0a42047a984f0cb458e75f2546ce3f8d957650dd10bde716ca22f8`
  and frame SHA
  `8ee1dc8772e6ee45a01381d2e18d39f2ef0b3bed2266719f8494ac08851b2823`.
  The exported route is structurally cheat-free and its first 6,336 commands
  are byte-for-byte equal to the independently replayed prefix. This remains
  authoring evidence until the complete route reaches intermission and the
  entire 9,223-plus command stream passes a fresh uninterrupted replay.
- Skill-3 hitscan checkpoint (2026-07-20): the authoring lineage now extends
  that prefix to 9,696 cheat-free public commands in
  `artifacts/t8.1-live/mocha-skill3-sergeant-prefix-9696.json`. The added
  branch returns from the sector-98 lift, kills the portal-320 sergeant from
  repeatable pillar cover, and remains alive at 5 HP with state SHA
  `2d394e4049d608bc2e1402e31709472b048bb338280e656075bdefe687c282d7`
  and frame SHA
  `4efb6b134ab28bd5d2e6f0c2fbb46f5cea0ce9edc70ced9dd2ad0b0d5c523ec2`.
  Slot 92 preserves the exact pose. A fresh slot-93 reconstruction and public
  replay reproduced both hashes. The next lift approach exposed a separate
  fixed-tic upper shotgunner lane; failed standing-wait, movement-dodge, and
  below-floor return-fire variants are rejected because the hitscan cannot be
  dodged and the lift wall consumes upward auto-aim. Resource acquisition or
  pre-alert timing must make that crossing survivable before it joins the
  candidate route.
- Skill-3 resource checkpoint (2026-07-20): the wall-bounded resource detour
  from the sergeant checkpoint is now solved and independently replayed. The
  183-command suffix first clears linedef 619's south endpoint, then collects
  the health bonus at `(576,-352)` and all three armor bonuses along
  `y=-800`. It ends alive at tic 9,879 with 6 HP, 3 armor, state SHA
  `2b944b64ff8070979410a7f6c3f874306d89a31432d10e80051f45416e9ef8a6`,
  and frame SHA
  `eff53d27ba0a6a3bc01723bdb8b8d92d2392e703447dfe3f243204b28ad5fb61`.
  Slot 91 and
  `artifacts/t8.1-live/mocha-skill3-resource-prefix-9879.json` preserve the
  exact result; a fresh slot-92 reconstruction reproduced both hashes, and
  the full 9,879-command export retains byte-identical 9,696-command ancestry.
  The remaining immediate gate is proving that this added health/armor
  survives the fixed upper-shotgunner attack while sector 103 lowers.
- Skill-3 completion checkpoint (2026-07-20): the full database-ledger command
  stream now reaches authentic E1M1 intermission at tic 13,272 through only
  generated AutoREST `NEW_GAME`/`STEP` commands and an empty cheat field. The
  route survives the upper lift, acquires the blue key and shotgun, opens the
  final thin manual door with a single centered use edge, defeats the last
  exit-room shotgunner, and activates linedef 407 through vanilla's use ray.
  It ends alive with 9 HP, 17/29 kills, 19/49 items, 1/4 secrets, and terminal
  state/frame SHAs
  `2dee7fcc7d54586bd91714341186299ac19c5c70cd9c1b53f55dbf4ae9172369` /
  `7ad3d6e57913d2f2cca837b54a37d74bceeb5b56a52885735b2c5e8718b3f2fe`.
  The authoring lineage contains one canonical frame-ledger row for every tic
  1..13,272 and exports to 1,152 normalized command runs. A brand-new skill-3
  session replayed that exact stream to the same intermission identity with
  13,272/13,272 exact state, frame, and response hashes and zero mismatches.
  The normalized accepted script, machine-readable lineage comparison, and
  reviewed terminal frame are frozen under `artifacts/t8.1-live/` as
  `mocha-e1m1-skill3-route.json`, `mocha-skill3-repeatability.json`, and
  `mocha-skill3-intermission.png`. This closes T8.1 without promoting any
  save/load authoring branch as acceptance evidence.

#### T8.2 Menu, pause, automap, cheats, save/load workflows

- Route: Terra high.
- Drive every in-session feature only through the public STEP input contract;
  restart uses the existing public NEW_GAME endpoint and a fresh session, as the
  live Mocha client does.
- Accept: Playwright plus direct API scenarios cover new game/skill, pause freeze,
  menu navigation, automap modes, each required cheat, save/load, rewind, replay,
  death/restart, and intermission.
- Mocha direct-workflow checkpoint (2026-07-19): the existing public `cheat`
  field now admits exactly `GOD`, `ALL`, `NOCLIP`, and `FULLMAP` for Mocha
  sessions. The opcode occupies reviewed high bits of Doom's existing
  `ticcmd_t.consistancy` word, so the append-only eight-byte command ledger,
  save/load branches, and killed-worker reconstruction replay each toggle at
  its exact tic without a second control channel. The transition token now
  covers scalar armor plus weapon ownership, ammo, keys, powers, and cheat
  flags; normal frame identities remain unchanged. The eleven-gate core suite
  passes with seven cheat transitions and exact reconstruction, and a real
  42-request generated-AutoREST workflow passes pause, automap/full-map,
  GOD/ALL/NOCLIP, save/load branch equality, replay, and invalid-command
  atomicity over raw DMF3. The Mocha Playwright replacement is now green on
  desktop and mobile: it drives raw-DMF3 pause, menu, automap/full-map,
  GOD/ALL/NOCLIP, save/load, and byte-identical branch replay through the real
  generated AutoREST procedures. The focused live-client contract also proves
  that the dedicated button is the only fullscreen entry, Tab is the Doom menu
  command, and Escape exits browser capture/fullscreen without becoming a game
  menu command.
- Signed-input/intermission checkpoint (2026-07-19): public command envelope v2
  admits exact signed Doom axis bytes (`-127..127`) for Mocha sessions while v1
  remains frozen at normalized `-1/0/+1`; keyboard acceleration and every
  durable eight-byte ticcmd/reconstruction contract are unchanged. The client
  now preserves pointer-lock mouse deltas instead of reducing them to a sign.
  A pinned Freedoom 0.13 E1M1 demo supplies the authentic first 250 commands;
  because Mocha's movement compatibility diverges from that complevel-3 demo,
  a measured NOCLIP-assisted suffix closes only the T8.2 presentation fixture,
  not T8.1's no-cheat acceptance. Three pinned Chromium workflows now drive the
  public AutoREST API on desktop, mobile, and through 343 commands to a complete
  intermission frame. The terminal tic is 343, state SHA is
  `0438e180f3e9a0b644004563223c20f67aaaeddd9a6d41b3dd08070088408921`,
  and frame SHA is
  `7ad3d6e57913d2f2cca837b54a37d74bceeb5b56a52885735b2c5e8718b3f2fe`.
  A second no-cheat, skill-5 demo route reaches the exact DEAD frame at tic 188
  (state SHA `27563d3aa36e1ef8c1ff230573569a853b732b38d47951f06be93348078a0962`,
  frame SHA `2982e30c9fc6d2d0f2c36cd3ec05d9a1bb86765cbc0d0451e9bb87ab1a1bb31c`).
  Its pinned Chromium workflow paints death, starts a new same-skill AutoREST
  session, and proves a distinct token with byte-identical canonical spawn.
  T8.2 is complete; T8.1 retains the distinct uninterrupted no-cheat full-E1M1
  route.

#### T8.3 Live-client playtest defect closure

- Treat the 2026-07-16 `/play/` reports as release blockers and reproduce each
  against the real static client plus generated AutoREST endpoints before making
  a fix:
  1. record a moving/combat trace that demonstrates monsters blinking in and out;
  2. record FIRE press/release tics and returned weapon-frame pixels to demonstrate
     the missing gun animation;
  3. measure key event to submitted ticcmd, correlated frame, decode, and paint to
     attribute the delayed movement response;
  4. start from a stationary fresh game and correlate every health decrement with
     ordered damage/projectile/monster events and line-of-sight state.
- Resolve causes in the dynamic renderer, retained simulation, or thin-client
  scheduler as the evidence requires. Do not hide actors, synthesize weapon frames,
  predict movement, or suppress legitimate damage in the browser.
- Add deterministic regressions for continuous monster visibility across valid
  state transitions, database-authored weapon fire/lower/raise frames, bounded
  input-to-corresponding-frame latency, and zero unexplained health changes. A
  health loss is valid only when the same correlated tic carries a replayable
  damage cause.
- Reproduce a transient worker/ORDS interruption while a play tab is open. Keep
  async requests retrying across the bounded interruption and expose an
  unmistakable keyboard/click restart path if the retry budget is exhausted;
  never leave a failed pipeline looking like dead keyboard controls.
- Keep the reviewed live scheduler at depth 2 with at most one queued successor;
  reject configurations where corrected combat throughput makes fresh keyboard
  state wait behind a four-command prefill backlog.
- Accept: a fresh 300-frame keyboard moving/combat soak through `/play/` has no
  actor disappearance outside death/occlusion, shows every fired weapon's authored
  animation, reports key-to-paint p50/p95 and maximum without a ten-frame startup
  backlog, and reconciles the complete health delta/event ledger. Playwright,
  direct API parity, restart/fencing, and the sustained 30 FPS gate remain green.

### P9 - MODEL fire

#### T9.1 Ordered MODEL implementation

- Route: Sol high.
- Generate 150 frames at 160x96 with one documented MODEL-based SQL operation,
  explicit `RULES SEQUENTIAL ORDER` and dimension ORDER BY. Noise is deterministic
  and independently authored. Store compressed frame runs, not redundant JSON.
- Run small/full feasibility and memory probes before committing the full insert.
- Accept: cell/range invariants, independent TS cellular reference, exact frame
  hashes, mutation checks, and a human-reviewed animation pass. Full-size failure
  blocks; do not reduce frames or dimensions.
- Completed 2026-07-19: two independent full-size production executions each
  stored 604,369 canonical RLE rows and reproduced all 150 frame hashes plus
  animation SHA `b1eac353252af51494cfe4ca77a80ac2bad502761bbaf79dd382f1146cb7e4ba`.
  The database-derived APNG and five exact review frames passed visual review.

### P10 - AutoREST integration and thin client

#### T10.1 Production package and least exposure

- Route: Terra high.
- Implement Section 5.4 package, grants, object enablement, rollback/error mapping,
  gzip payload, asset allowlist, and health view.
- Accept: metadata lists exactly DOOM_API and PUBLIC_HEALTH; base tables are not
  reachable; all endpoint contract, malformed input, concurrency, payload hash,
  and cursor-reuse tests pass.

#### T10.2 Client

- Route: Terra high.
- Build a full-viewport 320x200 canvas experience with keyboard controls, audio,
  minimal icon controls for touch/mobile, and no marketing/landing page. Serve the
  game immediately. Client modules are limited to API, input, codec, palette,
  canvas, audio, and presentation state.
- Accept: TypeScript/lint, static forbidden-import scan, independent decoder, exact
  canvas hashes, responsive screenshots, no overlap, no failed requests/errors,
  and complete keyboard/touch workflows.

#### T10.3 Local end-to-end gate

- Route: Terra medium.
- Fresh-bootstrap the complete local stack and execute all visible SQL, API,
  simulation, mutation, and Playwright tests from the evaluator container.
- Accept: capability matrix core rows all green; production artifact/schema audit
  clean; repeated run has identical correctness hashes.

### P11 - Required S3 + Autonomous Database deployment (final execution gate)

P11 runs only after P13 and the post-multiplayer T12.1/T12.2 re-verification.
It deploys and verifies the finished architecture; it is not an intermediate
dependency for multiplayer implementation or local performance work.

**Execution readiness checkpoint (2026-07-21).** `verify.sh phase P11` is the
single fail-closed entry point. The source audits, 48 isolated evaluator
mutations, deterministic upload/database/teardown dry-runs, and secret audit
pass. The local seed collector was exercised against Oracle and now emits all
24 populated domains (29,596 rows); its JSON syntax and canonical sprite/audio
asset sources were corrected after the former query failed locally. The cloud
completion ledger is reproducibly expanded from the accepted no-cheat
13,272-tic route and pins its terminal state/frame hashes. No live operation
has run because this shell lacks the Autonomous connection, wallet, managed
ORDS URL, target S3 bucket, and pinned SQLcl. Absence remains `NOT RUN`, never
`PASS`.

**OJVM deployment reconciliation (2026-07-21).** The earlier database deployer
installed Java call specifications without loading the selected Mocha class
graph or IWAD, and attempted runtime finalization before either existed. The
production gate now builds a deterministic 830-class Java 8 JAR (SHA-256
`a27903f2dcd81aecb0292f605453969ad3d4389382bebdb8386dff3cb13f23ab`),
preflights the target JDK, deploys pre-Java schema/seed sources, loads the JAR
with Oracle's supported client-side `loadjava`, loads and verifies the
28,795,076-byte IWAD, then installs post-Java runtime/REST sources and native-
compiles the selected hot classes. Local reconstruction of that exact sequence
passed all eleven Mocha core gates; two independent real-browser 300-frame
routes reproduced identical chains at 32.39 and 35.51 FPS. Autonomous requires
an administrator to enable `JAVAVM` and restart the database before this gate;
absence fails before production schema mutation.

#### T11.1 Cloud database deployment

- Route: Terra high.
- First run the unchanged P0 capability and transport probes against the target
  Autonomous Database. Any unsupported feature or transport mismatch blocks P11.
- Require an administrator-enabled and restarted Autonomous `JAVAVM` feature;
  preflight `DBMS_JAVA.GET_JDK_VERSION` before deploying production objects.
- Build and verify the pinned release-8 class graph locally, use client-side
  `loadjava` (server-side loadjava is unsupported on Autonomous), and load the
  SHA-verified IWAD before runtime call-spec finalization.
- Apply the same schema/seed/engine/rest scripts to the target database using a
  pinned deployment tool. Validate resource limits, grants, object exposure,
  package compilation, and transport contract.
- Accept: cloud seed counts/hashes equal local and all direct API tests pass.

#### T11.2 S3 deployment and browser gate

- Route: Terra high.
- Upload only allowlisted static production artifacts with deterministic metadata
  and cache policy. Configure the client with the managed ORDS base URL at build
  time, not a runtime proxy.
- Accept: Playwright from the actual S3 HTTPS index URL passes CORS/preflight,
  new-game, STEP, asset, canvas, audio, save/load, replay, and completion-smoke
  tests. No non-S3/non-Oracle runtime dependency appears in the network log.

### P12 - Post-multiplayer golden-preserving performance re-verification

Run P12 after P13 so the measured build includes the selected multiplayer
architecture and its single-player compatibility path. Complete the local
protocol first; retain the identical managed-ORDS protocol for the final P11
deployment gate.

#### T12.1 Baseline and cursor hygiene

**Approved selected-engine evidence reconciliation (2026-07-21).** T12.1 is
the single-player compatibility baseline for the selected retained Mocha/OJVM
production path; P13 retains its separate multiplayer routes, performance, and
soak evidence. The frozen statement-family labels map to real generated
AutoREST surfaces: `step` is `DOOM_API.SUBMIT_STEP`, `frame` is
`DOOM_API.POLL_FRAME`, and `asset` is `DOOM_API.GET_ASSET`. Their required
90-call `ALLSTATS LAST`/cursor-hygiene matrix is a separate attribution pass,
not a claim that asset reads occur per gameplay frame. The primary two-run
300-frame browser gate keeps intrusive diagnostics off and requires identical
state/frame/payload chains; an identical third replay collects private worker
stages and must reproduce that chain. Legacy evidence keys `r1Ms` and `r2Ms`
remain only as documented aliases for authoritative ticker/command application
and presentation+DMF codec+BLOB write respectively. The report must also carry
the canonical prepare, ticker, render, codec, BLOB, finalize, commit, ORDS,
transfer, decode, palette, blit, and input-to-correlated-paint stages. The SQL
renderer remains an independently executable differential oracle, not the
measured production renderer. Cloud samples remain final-P11 work.

The old `c393f8f…` replay identity is orphaned: no corresponding replay bytes
exist in the worktree or reachable history, and the old validator trusted the
declared identity instead of hashing the file. Never relabel new bytes with
that digest. Supersede it with a content-addressed 300-frame fixture derived
from the accepted canonical route, update its review manifest explicitly, and
make the validator hash the actual bytes before any live T12.1 collection.
The selected-engine candidate is now materialized at
`artifacts/performance/t12.1/mocha-replay-300.json`: 300 ordered frames derived
from the tracked skill-3 route, all five command classes/four observation phases,
SHA-256 `1ad47bc8…327fe3`. Its source/expansion/content-address gate, explicitly
superseded evaluator manifest, async DMF3/4 live driver, credential-private
collector, and local production/evaluator evidence validation now pass. The
isolated matrix records exactly 90 generated AutoREST invocations per family
and real internal `ALLSTATS LAST` anchor plans without mislabeling anonymous
PL/SQL blocks as row-source plans.

**Local T12.1 checkpoint (2026-07-21).** The first selected-engine 300-frame
attribution run measured 37.81/56.09 ms p50/p95 serial correlated latency and
25.54 effective serial FPS after reducing `POLL_FRAME`'s readiness quantum from
50 ms to 5 ms (before: 78.64/82.06 ms and 15.27 FPS). The retained worker is
not the limiter: database 7.14/11.87 ms, ticker 0.30/1.68 ms, render 1.02/1.95
ms, codec 0.06/0.16 ms, and BLOB 0.24/0.47 ms before commit. Commit is sampled
every 32nd tic (9/270 measured samples, 1.18–2.41 ms) so profiling does not add
a second hot-path update; unsampled commits remain in the external remainder.
The depth-2 browser pipeline plus bounded backlog catch-up passes the live
interaction gate at 31.36 FPS with 32.1/33.1 ms p50/p95 paint gaps and 126.1 ms
input-to-correlated-paint. The exact fixed fixture then passed two independent
browser runs at 31.70 and 31.56 FPS; their state, frame, and payload chain
digests match each other and the private attribution replay exactly. The
fail-closed `verify.sh task T12.1` gate validates the complete local envelope.
T12.1 is locally complete. T12.2's local profile/stop-rule ledger remains next;
stable-host tails and managed ORDS remain final P11.

- Route: Terra medium.
- Collect the Section 6.6 replay, execution plans with runtime statistics, V$SQL
  parse/execution data, stage timers excluded from payloads, and payload sizes.
- Record separate out-of-band timers for prepare, ticker/command application,
  render, DMF codec, SecureFile BLOB write, finalize, commit, ORDS, transfer,
  browser decode, palette expansion, canvas blit, and input-to-correlated-paint.
  Keep `r1Ms`/`r2Ms` only as the documented compatibility aliases above. Run
  the primary 300-frame browser capture without route diagnostics, then replay
  identical bytes in the private attribution pass. Package the identical probe
  for managed ORDS, but execute that cloud half only inside final P11.
- Accept locally: bound statement shapes remain stable across poses/commands and
  the complete local raw/report artifact exists. P11 appends the managed-ORDS
  samples before final project acceptance.
- Reuse T12.0 artifacts only as ancestry and local diagnostic evidence. Capture
  the complete 300-frame local and cloud baseline here; the pulled-forward gate
  does not satisfy or shorten this acceptance contract.

#### T12.2 Profile-guided optimization loop

**Local completion (2026-07-21).** The fail-closed local ledger selected the
2 ms correlated readiness quantum: versus the immediate 5 ms baseline it
improved serial p50 from 41.827 to 30.060 ms (28.13%) and reached 31.248
effective serial FPS with zero clock-anomaly samples. The exact selected browser
runs passed at 31.814/31.591 FPS with unchanged state/frame/payload chains. A
1 ms transport attempt regressed to 36.464/72.954 ms p50/p95 and captured one
backward-clock sample, so it was rolled back. A technically distinct redundant
`(request_id,request_status)` index did not change the poll plan and regressed
p50 by 3.92%; it was dropped. Attempts 2 and 3 are the first consecutive,
distinct sub-5% pair, satisfying the stop rule. `verify.sh task T12.2` validates
the retained attempt evidence, rollback state, selected source, exact chains,
and browser FPS. Local T12.2 is complete; only final-P11 cloud publication is
withheld.

- Route: Sol high for SQL changes, Terra for transport/client changes.
- Optimize the measured bottleneck using indexes, join/order changes, precomputed
  static relations, partitioning, aggregation shape, or codec changes that retain
  the public decompressed schema and all goldens.
- Evaluate the already measured shared-portal/single-derivation SQL shape before
  any codec experiment if T12.0 did not already select it. Treat the selected
  T12.0 revision as the initial candidate state, not as proof of final local or
  cloud performance. MLE and UTL_TCP remain out of scope under Section 1.8.
- Stop only under Section 6.6. Record every attempt, including regressions.
- Collect local attempts and the selected local replay now, but do not publish
  final T12.2 evidence until P11 appends the identical managed-ORDS/S3 sample.
  Primary FPS runs keep route diagnostics/statistics overhead disabled; use a
  separate exact-chain attribution replay because current diagnostics add DML
  and a second commit per tic and would otherwise measure the profiler.
- Accept locally: all correctness and mutation tests remain green and the report
  states the highest verified local FPS without a marketing estimate. The same
  report receives its verified cloud FPS during final P11; no cloud work runs
  ahead of that gate.

### P13 - Database-authoritative multiplayer

P13 is the next planned workstream after the P8-P10 single-player/local
correctness gates are green and before P12 performance re-verification. It
reuses Oracle DB + generated ORDS AutoREST +
the static browser. It may not add peer-to-peer traffic, WebSockets, an ORDS
game loop, or an external relay/game server. Mocha Doom already contains
vanilla four-player state (`MAXPLAYERS=4`, per-player `netcmds`, co-op and
deathmatch spawning, frags, respawn, and per-player display state); adapt those
primitives to database-supplied command vectors instead of its socket layer.

One retained OJVM worker owns one match and one authoritative engine. Never run
one independent engine per player. Each accepted tic contains an ordered
four-slot command vector and membership bitmap. The engine advances once, then
renders immutable POV responses for active players without advancing again.
Match, membership, commands, results, events, frame identities, checkpoints,
and generations remain authoritative and restartable in Oracle. Every mutation
is fenced by match, slot, membership epoch, worker generation, tic, and sequence.

#### T13.0 Feasibility, contracts, and schema

- Route: Codex high for OJVM/SQL; Terra high for client/AutoREST security.
- First build a disposable two-player adapter probe. Explicitly set `netgame`,
  `playeringame`, and slots; feed two distinct `ticcmd_t` values into one tic;
  prove one world advance, mutual sprites, damage/death, and two stable POV hashes.
- Benchmark one world tick plus one, two, and four POV renders on pinned two-CPU
  Oracle Free. Report simulation, each render, codec/BLOB, persistence, ORDS,
  decode, and paint. Two-player work proceeds only with credible dual-30-FPS
  evidence; four players remain evidence-gated, never a projected claim.
- Add normalized `doom_match`, `doom_match_member`, `doom_match_command`,
  `doom_match_tic`, `doom_match_frame`, and `doom_match_checkpoint` contracts.
  Store only salted hashes of unguessable host/join/player capabilities. Tokens,
  display names, and client metadata never enter state/frame hashes or replay RNG.
- Freeze v1 membership: two slots assigned only in `LOBBY`, all READY before
  start, no mid-match join, reconnect to the same slot, and deterministic leave/
  timeout. Spectators, host transfer, public matchmaking, and bots are deferred.
- Accept: bootstrap/drop, constraints/cascades, fence mutations, exact adapter
  hashes, recorded 1/2/4-POV timings, and unchanged single-player hashes.
- Adapter feasibility checkpoint (2026-07-20): the internal-only OJVM probe now
  initializes two active co-op slots in one engine, consumes two distinct
  ordered ticcmds in exactly one world/level tic, renders two deterministic
  distinct POVs without changing the fenced state fingerprint, and proves
  shared damage, player-0 frag attribution, death, and player-1 reborn. Two
  clean initializations returned byte-identical evidence; POV hashes are
  `44c4422bda405eb4cdff0c2f4d84d913e2801dd0b53b8cc30ebc8b8bad686651`
  and
  `9f55a44b95a35841a1d1e8e341a2c49de8f165ababaa563a99cb7e607eb94ae2`.
  The pinned 300-sample benchmark measured total p50/p95/max of
  2.515/3.396/8.257 ms for one POV, 3.228/5.670/41.936 ms for two,
  3.699/4.919/6.565 ms for three, and 5.575/7.933/35.886 ms for four.
  Four-POV render p95 was at most 1.249 ms per POV, codec p95 at most 0.728 ms,
  and BLOB p95 at most 0.036 ms. This clears the engine-level dual-30-FPS
  feasibility gate with margin and permits the normalized schema/lifecycle
  slice; it does not claim end-to-end multiplayer FPS before persistence,
  AutoREST, browser decode/paint, replay, and recovery are measured.
- Schema checkpoint (2026-07-20): `doom_match`, `doom_match_member`,
  `doom_match_command`, `doom_match_tic`, `doom_match_frame`, and
  `doom_match_checkpoint` are installed through the normal bootstrap order.
  Their validated constraints cover lifecycle states, salted capability hashes,
  membership/generation/slot/sequence fences, bounded command vectors, immutable
  per-player frames, checkpoints, and cascading cleanup. Both the deterministic
  source gate and a live Oracle fixture/cascade gate pass; the tables remain
  private and contain no fixture rows. The lifecycle API is the active slice.

#### T13.1 Lobby, capabilities, and AutoREST lifecycle

- Extend only allowlisted `DOOM_API` with generated AutoREST procedures:
  `CREATE_MATCH`, `JOIN_MATCH`, `READY_MATCH`, `MATCH_STATUS`,
  `SUBMIT_MATCH_STEP`, `POLL_MATCH_FRAME`, and `LEAVE_MATCH`. Base tables and
  worker controls remain unreachable. Public discovery is deferred by default.
- Use a public match id plus separate host/player bearer capabilities. Compare
  only hashes in Oracle, rotate on explicit reconnect, use constant-shape errors
  for unknown/unauthorized matches, and redact capabilities everywhere.
- Bound names/metadata, match/member counts, body size, future-tic lead, retries,
  poll duration, idle lifetime, and create/join rates. Reject duplicate slots,
  old-token replay, cross-match polling, excessive gaps, and commands for another
  slot. Cleanup is generation-fenced with replay-safe retention.
- Host mode/skill/map and start/cancel apply only in `LOBBY`. Start atomically
  freezes membership, creates the worker generation, and returns tic-zero POVs.
- Accept: two browser contexts create/join/ready/start entirely through AutoREST;
  authorization, enumeration, race, retry, expiry, reconnect, leave, rate-limit,
  and cleanup tests pass without secret-bearing output or table exposure.
- Implementation checkpoint (2026-07-20): all seven generated AutoREST
  procedures are implemented. Capabilities are independently salted and hashed,
  error shapes do not enumerate matches, and generation/membership bounds are
  enforced. Direct HTTP gates pass lifecycle, arbitrary command arrival,
  per-player polling, retry, and authorization with bearer material redacted.
  Expiry, reconnect, and cleanup are live-tested. The serialized global create
  admission boundary is exercised at exactly 16 creations/minute and the next
  call returns the public retryable capacity code; join admission is exercised
  through the frozen two-slot/full-lobby boundary.

#### T13.2 Deterministic lockstep and retained match worker

**Approved paced-input amendment (2026-07-20).** The user's standing approval
authorizes a feature-flagged `PACED_INPUT` retained-worker mode as the next
bounded performance architecture. In that mode the browser still uses only
generated AutoREST: authenticated input transitions append to Oracle, while the
match's Scheduler session independently samples the latest durable transition
at an absolute 35 Hz boundary and materializes a private, generation-fenced
ordered command vector. That prepare transaction is the input linearization
point and releases the match-row lock before OJVM/render work; the worker then
advances the one authoritative engine and atomically commits hashes, events,
POV frames, checkpoints, and the public replay frontier. A prepared vector has
no public frame/result visibility and is resumed exactly after recovery. The committed
`doom_match_tic.command_vector` remains the replay truth; there is no browser
prediction or client-side world simulation. Worker mode is frozen when a match
starts, active lineages are never converted, and `LOCKSTEP` remains executable
as the differential oracle until paced mode passes input linearization,
idempotency, ledger identity, 300-tic replay/parity, recovery seams,
disconnect/leave, co-op/deathmatch, two consecutive two-browser performance
runs, and soak. Wall-clock cadence is presentation policy and never enters the
deterministic state/hash chain. This amendment replaces delayed future-command
reservation only for matches explicitly created in `PACED_INPUT` mode; all
other P13 authority, durability, security, and AutoREST rails remain unchanged.

- Use server-authoritative delayed lockstep, initially two tics. Clients submit
  keyboard-state commands for bounded future tics without deriving them from
  frames. At each deadline the worker orders by slot and durably records a
  neutral command for a missing connected player. Late commands are reported
  idempotently and never cause rollback or client-side prediction.
- Arrival order never determines world order. Advance only after the complete
  next command vector/deadline decision is durable; publish player frames only
  after command vector, state/hash, events, frames, and commit succeed.
- Add catch-all adapter entry points for multiplayer new-game, vector-step,
  per-player render, checkpoint, reconstruction, and disposal. POV rendering
  must restore selectors on failure and must not mutate RNG, thinkers, audio, or
  world state. Author spatial audio separately for each listener slot.
- A disconnected slot receives neutral commands for a bounded grace period,
  then becomes `LEFT` at a recorded tic. Co-op v1 makes it inactive until match
  end. Reconnect before expiry resumes only at a future command boundary.
- Accept: randomized arrival order, duplicate/out-of-order HTTP, missing input,
  reconnect/leave, simultaneous use/fire, and contention reproduce a direct
  ordered command/state/event/frame chain with no cross-match visibility.
- Implementation checkpoint (2026-07-20): one private Scheduler session owns a
  two-player engine, accepts a complete ordered four-slot vector, advances one
  world tic, writes two immutable POV payloads directly into persistent BLOB
  locators, and atomically commits its command/state/frame frontier. Live gates
  pass arbitrary arrival, one-tic advancement, POV separation, idempotency,
  root determinism, fencing, and match isolation. A 75 ms deadline now records
  a neutral command/bitmap for a missing peer, same-capability reconnect restores
  a disconnected slot, and tic 32 writes a verified native Mocha checkpoint in
  the frontier transaction. A fresh OJVM session also replayed all 32 ordered
  vectors with the original per-tic POV cadence and reproduced the exact final
  state SHA and both frame hashes. Public polling now detects a failed/stale
  owner, launches a replacement generation, preserves an accepted partial
  next-tic command, republishes identical selected POVs, and advances normally
  after the seam. Active guest leave is now fixed to an exact future tic: the
  durable vector records `NEUTRAL_LEFT`, membership changes from `03` to `01`,
  the retired POV is no longer rendered, and reconstruction reproduces the
  one-POV frontier. Idle members transition ACTIVE → DISCONNECTED after three
  seconds and to the same terminal LEFT boundary after a three-minute transport
  grace (long enough for a measured generated-ORDS restart); the host can
  explicitly finish the match idempotently. Tic 1 alone uses a 500 ms cold
  generated-procedure allowance, while every warm missing-peer deadline remains
  75 ms. Sound origins are captured once per shared tic and re-evaluated through
  vanilla attenuation/panning for each active listener before immutable POV
  encoding; a clean-run fixture proves distinct player audio without changing
  the canonical co-op frame hashes. Bounded final leave semantics are closed.

#### T13.3 Co-op client, replay, and recovery

- Select two-player co-op first. Verify starts, mutual visibility, shared world
  machines, monster targeting, friendly-fire policy, vanilla netgame pickups,
  keys, death/reborn, exit, intermission, player colors/HUD, and listener audio.
- Add a compact lobby/join/reconnect flow to the static client. It samples local
  input, submits future ticcmds, and decodes only its database-authored POV/audio.
  It does not simulate, interpolate world state, or expose another capability.
- Record membership epochs and four-slot vectors in the lineage. Checkpoints
  include every player and multiplayer flag. Reconstruction replays slot order
  and reproduces all player state, RNG, events, and POV hashes. Save/load is
  host-only and match-wide; personal rollback/divergent saves do not exist.
- Accept: two browsers complete a representative E1M1 co-op route. Fixtures
  cover damage, death/respawn, pickup contention, door/lift/use, reconnect, and
  exit. Kill the worker mid-fight and ORDS mid-poll; fenced reconstruction must
  resume both clients with the same final chains as an uninterrupted twin.
- Browser checkpoint (2026-07-20): `/play/multiplayer` creates a private match,
  carries the join capability only in the URL fragment, removes it after join,
  keeps each player capability in session storage, captures dynamic input, and
  displays only that player's Oracle frame. A real two-context Playwright gate
  reached synchronized tic 24 and proved distinct POVs without bearer output.
  The client now treats bounded network/ORDS failures as retryable, refreshes
  authoritative fences, and never predicts. A live two-context gate restarted
  the complete ORDS container mid-poll; both slots survived the measured
  two-minute generated-API startup, resumed in lockstep, reloaded the guest,
  and reached synchronized tic 114 with distinct POVs. The disconnected-to-LEFT
  grace is three minutes so this measured transport recovery is possible;
  explicit leave and match expiry remain immediate. At this checkpoint the
  300-frame FPS gate and full-route two-browser replay were still open; both
  are closed by the later checkpoints below.
- Co-op route checkpoint (2026-07-20): the retained adapter now mirrors Doom's
  exact internal consistency word after each world tick, including the reborn
  case where `DoReborn` replaces the player mobj before vanilla records the
  ring. The formerly failing neutral-peer skill-3 prefix passes through tic
  4,200. Paired traces then found two independent harness defects: keyboard
  turn acceleration was packed incorrectly, and upstream `ticcmd_t.unpack()`
  sign-extended the low byte of 16-bit fields. One shared exact decoder now
  serves live and reconstruction paths. The remaining real divergence begins
  when the solo demo receives damage knockback at tic 75 but co-op player 0
  does not; a frozen 18-byte correction specification adjusts side movement on
  tics 78--90 and forward movement on tics 78--82. The accepted two-slot route
  keeps membership `03`, applies eight real player-1 strafe commands on tics
  700--707, and reaches intermission at tic 762. A fresh Oracle session replayed
  the complete ledger and reproduced state SHA
  `dd7c3f04e66ffdee72f303a442a95d354603aaa4638ac63d9d2956971f1b59b7`
  plus POV hashes `80a7b9a9…e2f24` and `57844ee6…8c376`. Player 1 moved more
  than 63 map units, so the contribution is applied world state rather than a
  nonzero-byte fiction. The canonical specification is
  `artifacts/p13.3-coop-e1m1-route.json`. Private traces remain opt-in and add no
  normal-path DML. A separate live gate forcibly stops and drops the owning
  Scheduler job at tic 400, invokes fenced reconstruction in a replacement
  session, completes the route at tic 762, and reproduces the same state and
  both POV hashes. The public two-browser gate presents all 762 ordered frames,
  applies the player-1 contribution to world state, reaches authentic
  intermission, and reproduces the canonical terminal state hash. The
  deterministic OJVM fixture already locks mutual visibility, one shared world
  tic, simultaneous fire/use, one-winner ammo contention, per-player netgame
  keys, damage/death, frag attribution, and co-op reborn with identical results
  across two clean initializations.

#### T13.4 Deathmatch and player-count expansion

- Enable deathmatch only after co-op passes. Use authored deathmatch starts,
  vanilla spawn RNG, damage, armor/ammo/pickups, frags, suicide attribution,
  death/reborn, scoreboard/intermission, and frozen frag/time limits.
- Prove two-player correctness first, then remeasure three/four players. If POV
  rendering or four frame streams exceed the two-CPU/ORDS budget, retain the
  verified lower cap; never reduce resolution, duplicate simulation, skip unique
  frames, or infer per-client FPS from aggregate throughput.
- Accept: deterministic spawn/frag/respawn, simultaneous-kill/tie, scoreboard,
  isolation, replay, and restart fixtures. A selected player count requires every
  browser to show 300 unique frames at >=30 FPS with paint-gap p50/p95 <=33.3 ms
  and input-to-own-frame p95 <=250 ms while single-player remains green.
- Two-player checkpoint (2026-07-20): `CREATE_MATCH` now accepts the frozen
  `DEATHMATCH` mode through the same salted capabilities, ready boundary,
  retained worker, and generated AutoREST surface as co-op. A production live
  gate advances two distinct POVs, kills the worker, and reconstructs the exact
  tic/state/POV frontier in generation 2. A deterministic engine fixture runs
  twice with identical output and proves distinct authored starts, frag credit,
  vanilla deathmatch respawn, reciprocal-kill tie accounting, and suicide
  attribution. Two real browser contexts select deathmatch, submit dynamic
  input, reload/reconnect, retain distinct POVs, and reach synchronized tic 18.
  Production now freezes the first-score-at-10-frags or 10-minute/21,000-tic
  terminal rules in the retained engine. A low-limit live fixture proves the
  winner enters Doom's authentic scoreboard/intermission, alongside all combat
  assertions above. The full 21,000-tic boundary also runs twice without an
  early exit and enters the authentic intermission exactly after the limit.
  Two consecutive enforced deathmatch browser runs reached 35.36/34.96 and
  35.34/34.98 FPS, 32.0--32.5 ms paint p95, and 149.2--176.3 ms input p95.
  Each canvas now reuses one browser-owned RGBA surface instead of allocating
  ~256 KiB per presented frame. The refreshed engine-only 300-sample benchmark
  remains credible through four POVs (7.13 ms total p95), but four interactive
  players require four held polls plus four simultaneous input writers. The
  required eight-session ORDS pool already regressed the selected two-player
  gate, while six sessions cannot guarantee those eight hot lanes. Per the
  frozen evidence-gated rule, v1 therefore selects the fully verified
  two-player cap without reducing resolution, skipping frames, or projecting
  unmeasured four-client performance; three/four-player transport is deferred.

#### T13.5 Operations and local multiplayer gate

- Report bounded lobby/active/finished counts, worker occupancy, command lead/
  misses/late rejects, per-player submit/poll latency, match tick rate, per-POV
  render/codec, recovery count, and ORDS pool waits. Use pseudonyms only.
- Admission control uses measured worker, Java/shared-pool, SecureFile/redo,
  ORDS, and bandwidth budgets. Full capacity returns a retryable error and never
  evicts a match. Purge uses an explicit replay-safe retention policy.
- Package the same security, correctness, recovery, and selected-player
  performance protocol for later execution through P11 managed ORDS/Autonomous
  Database and the real S3 client. Cloud capacity may reduce admitted matches/
  player count but never deterministic semantics.
- Accept locally: two consecutive matches at the selected modes/cap pass exact
  replay/recovery and per-client performance; a 30-minute soak has bounded
  storage/memory, no worker/session leak, unexplained neutral command, capability
  exposure, or cross-match data. P11 repeats this packaged protocol in cloud;
  only then may final project acceptance be marked complete.
- Retention checkpoint (2026-07-20): the local stress history reached Oracle
  Free's 12 GB hard cap and proved that single-player-only cleanup was
  insufficient. The off-request Scheduler purge now runs every minute in
  bounded batches for both expired game sessions and expired matches, stopping
  and dropping retained match jobs before cascading their LOB-backed history.
  Static and live expired-match gates pass. Active matches now retain tic zero
  plus a 128-tic two-POV response-BLOB ring and the latest two native
  checkpoints, while preserving the complete compact command/state vector
  ledger required for exact replay. A live 160-tic gate held exactly 258 frame
  BLOBs, two checkpoints, 161 state rows, and 320 ordered commands. The
  30-minute resource/session soak remains open.
- Fresh-stack checkpoint (2026-07-20): the empty-config ORDS path now copies
  Jetty configuration into its writable volume, replaces the bundled repository,
  and republishes the allowlisted AutoREST schema/package/view after installation.
  The persisted SPFILE target is rebuilt with balanced 256/256/256 MiB
  shared/Java/buffer floors; this corrects the measured 128 MiB Java-pool
  exhaustion during concurrent retained-match initialization. Static ownership,
  lifecycle HTTP, full retained-worker, neutral deadline, checkpoint, exact
  replay, and public generation-recovery gates pass on the recreated stack.
- Performance checkpoint (2026-07-20): the selected candidate retains ordered
  four-command reservations, two correlated poll lanes per player, and the
  fixed six-session ORDS pool. DMF5 encodes three temporal XOR/PackBits deltas
  behind each four-tic keyframe; reconnect batches prepend the required base.
  Dynamic input is no longer trapped behind the immutable reservation horizon:
  an append-only transition ledger is inserted atomically with the command
  batch at `current_tic+1`, and that same AutoREST response returns a
  self-contained frame chain through the effective tic. Reconnect reads the
  durable input sequence frontier, preserving strict idempotency. The browser
  keeps every authoritative frame and caps reservation lead at six tics.
  A 300-frame diagnostic with 27 observable transitions per player passed at
  40.54/40.53 FPS, 23.7/33.1 and 23.8/33.0 ms paint-gap p50/p95, and input
  p50/p95/max of 198.5/245.9/247.6 and 155.5/229.0/246.2 ms. The first enforced
  repeat narrowly missed (33.6 ms paint p95; 265.9 ms input max), so selection
  still requires two consecutive green 300-frame runs. Rejected evidence now
  includes pool sizes seven/eight, per-transition standalone requests,
  presentation acknowledgements, one-poll input mode, and presentation-relative
  lead five or lower; each lost throughput or amplified tails.
  Codec A/B evidence also rejects raw DMF3 keyframes (25--26 FPS, 113--128 ms
  paint p95) and a byte-identical preallocated PackBits output buffer (two warm
  runs at only 27--31 FPS with 73--110 ms paint p95). The original
  `ByteArrayOutputStream` DMF4 keyframe implementation remains selected. A
  retained diagnostic localized normal slow commits mainly to tics congruent
  to one modulo four; a separate 2.03-second terminal gap was positively
  attributed to the expected post-browser `NEUTRAL_DEADLINE`, not the codec.
  A wider 32-tic keyframe interval with ordered client-side delta-chain decode
  is also rejected: tested variants ranged from 18--49 FPS but repeatedly
  produced 61--113+ ms paint tails and 263--395+ ms input tails. Reusing the
  previous-frame buffer removed a 128 KB allocation per tic without improving
  the result (26.5 FPS, paint p95 above 113 ms). Keep each response independently
  decodable on the selected four-tic cadence; do not reintroduce cross-response
  decode state or defer the early input frame behind a long delta chain.
  Further bounded trials close the remaining obvious transport/codec branches.
  Two correlated `EXCHANGE_MATCH_BATCH` lanes averaged 38.6 FPS but missed at
  39--40 ms paint p95, 269--300 ms input p95, and 273--296 ms exchange TTFB.
  Native DMF6/zlib keyframes were catastrophic both with per-frame compressor
  allocation (3.4 FPS, ~1.2 s paint p95) and retained/reset compressors
  (13.8 FPS, 180--221 ms paint p95). An independently implemented array-only
  DMF7/LZ4 block improved that result but remained rejected at 17--18 FPS and
  108--140 ms paint p95. Fixed/buffer-aware 24--30 ms presentation and 4--12 ms
  input catch-up variants moved latency between paint and input without passing
  both gates. Adaptive poll admission also failed repeat selection: its first
  clean diagnostic reached 39.4/39.5 FPS, but a fully quiesced repeat fell to
  32.4 FPS with 71--75 ms paint p95 and 310--329 ms input p95. Do not retry
  native compression, custom keyframe scans, correlated exchange lanes, client
  jitter pacing, or adaptive poll throttling. The pushed four-tic DMF4/DMF5
  candidate remains selected while a new architecture is evaluated.
  A Sol xhigh architecture review selected a feature-flagged, absolute-clock
  35 Hz retained worker as that next bounded experiment. It removes the cyclic
  browser-reservation/peer/worker/poll dependency by separating the durable
  input-transition ledger from authoritative frame production. Selection is
  not claimed: first prove server cadence p95 at or below 28.57 ms and two
  poll-only clients at or above 30 displayed FPS, then complete the amendment's
  exactness, recovery, gameplay, repeat-performance, and soak gates.
  Implementation checkpoint (2026-07-20): `PACED_INPUT` is now frozen per new
  match behind `MATCH_WORKER_MODE`; existing `LOCKSTEP` lineages remain valid.
  The worker samples the append-only authenticated input ledger on an absolute
  35 Hz schedule, writes the exact applied command rows, and publishes only
  committed database POVs. A generation-fenced prepare/render split reduced
  input endpoint p95 to 27--36 ms by removing the match-row lock convoy.
  Two-frame self-contained poll batches reduced ordinary poll-ready p95 to
  63--145 ms, and incremental two-row frame retirement replaced 32-tic LOB
  delete bursts. Tic 32 remains the mandatory native checkpoint; steady
  checkpoints are every 1,024 tics because current recovery replays the compact
  exact ledger. The best clean 150-frame run reached 36.03/34.99 FPS,
  33.5/32.6 ms paint p95, and 249.3/195.0 ms input p95. The first enforced
  300-frame run missed one player at 34.5 ms paint and 316 ms input p95, so at
  this checkpoint selection and the required two consecutive passes were still
  open; the later superseding selection closes them. A true
  SecureFile locator-reuse ring is rejected: its second wrap stalled around
  tics 257--258 and regressed both clients to ~32 FPS with 42--54 ms paint p95.
  Focused paced gates now pass exact input retry/mismatch handling, sampled
  command-vector identity, forced Scheduler generation recovery, and the
  128-tic frame/1,024-tic checkpoint retention contract. A 400-tic isolated
  worker trace measured PRE_JAVA 1.18 ms, Java 20.35 ms, POST_JAVA 2.03 ms,
  and total precommit 22.30 ms p95, proving the retained worker can sustain
  35 Hz without browser load. Under concurrent polling, precommit p95 rises to
  ~60 ms. Live ASH and segment statistics identify cached SecureFile pressure
  (`write complete waits`, 2,569 LOB buffer-busy waits, and a 32.25 MiB segment
  for ~7.9 MiB retained payload) as the leading cause; OJVM GC remains the
  secondary hypothesis. A four-frame poll burst and a cross-response delta
  spike were rejected because they worsened input/presentation behavior. Next:
  attribute slow tics with stage/wait/GC telemetry, then run the bounded
  preallocation x deferred-retirement factorial before changing storage shape.
  Superseding selection (2026-07-21): per-stage tracing proved every tic over
  28.57 ms was an OJVM GC tic; no-GC Java p95 was 10.74 ms and persistent BLOB
  writes were ~1.04 ms p95. The old codec allocated at least ~424 KiB per
  two-player tic. Fused transpose/XOR plus fixed session-private raw, packed,
  and double-buffered transport workspaces reduced isolated Java p95 to
  10.01 ms, codec p95 to 1.67 ms, GC pause p95/max to 1/2 ms, and total p95 to
  13.92 ms. A sequential `DMB3` stream carries the exact delta base across
  two-frame responses, eliminating duplicated keyframe-block copies while
  preserving every canonical frame payload and SHA. An intermediate 300-frame
  browser run reached 34.90/34.52 FPS with 32.5/32.3 ms paint p95 and
  203.1/192.9 ms input p95. Six warm
  ORDS sessions remain selected (eight regressed CPU contention). A missing
  Scheduler job behind a stale `STARTING` claim is now reclaimed after its
  one-second creation fence. After a long ORDS restart ages an in-flight batch
  out of the 128-tic ring, the client re-fences through `MATCH_STATUS`, resets
  at the latest keyframe, and resumes its delta chain; the live restart/reload
  gate passes. Performance is selected; soak remains open.
  Final tail hardening (2026-07-21): paced streams now keyframe every 32 tics
  while lockstep retains its self-contained four-tic contract. This cut the
  retained response average to 3.2--4.0 KiB/POV. Oracle call-heap counters then
  confirmed movement/presentation GC (30 collections reclaiming 60.5 MiB in a
  sampled session). The serial patch-column path no longer creates a capturing
  lambda and one `Horizontal` per column, the closed menu no longer allocates a
  message buffer, and the E1M1-reached weapon/monster/RNG/audio plus HUD/video
  classes are synchronously native-compiled. Two exact recovery repeats, forced
  ORDS restart/re-fencing, bounded retention, co-op, and deathmatch browser
  gates pass. The consecutive enforced 300-frame results are 35.18/34.80 and
  35.18/34.85 FPS, 32.2--32.7 ms paint p95, and 145.3--181.9 ms input p95.
  Multiplayer presentation and soak checkpoint (2026-07-21): one retained
  engine now retargets the existing status-bar and heads-up widgets for each
  POV without recreating them; deterministic probes prove player color
  translations `0/1` and distinct HUD-region hashes. The public two-browser
  canonical co-op route presented every tic 1--762 without a skip and matched
  terminal state SHA `dd7c3f04e66ffdee72f303a442a95d354603aaa4638ac63d9d2956971f1b59b7`.
  A 120-second production-paced soak advanced both clients from tic 104 to
  4,187, retained 258 frame rows/two checkpoints, held Java session heap flat
  at 3,409,920 bytes, and recovered one authoritative resync per client. Four
  disconnect-neutral tics were correctly bounded to that recovery; deadline
  and leave substitution remained zero. The soak gate now requires a final
  consecutive post-resync run and correlates any disconnect-neutral interval
  with a recorded recovery of at most 30 seconds. The full 30-minute run is
  still required. The first long run exposed an exact 20-minute lifecycle
  cutoff: `expires_at` was an absolute creation deadline even while both
  clients remained active. It is now a sparse authenticated idle lease—status,
  input, or polling extends it from ten minutes remaining back to twenty,
  while worker tic advancement alone never renews an abandoned match. The
  compare-and-update avoids hot match-row DML/lock convoy. A post-fix 30-second
  two-browser smoke passed 1,038 measured tics, then the full 1,800-second gate
  advanced both clients from tic 136 to 59,904 with zero measured resyncs or
  disconnect/deadline/leave neutral substitutions, 258 retained frames, two
  checkpoints, bounded memory, and Java session heap 3,328,000 → 3,395,584
  bytes. Paint p99.9/max was 195.6/1,517.3 and 200.4/1,556.2 ms; those extreme
  tails are provisional on this known clock-stalling host and must be repeated
  on stable-clock native Linux/OCI.
  Local-host timing finding (2026-07-21): failed repeats were traced outside
  the renderer. Colima 0.10.1/Lima 2.1.1 steps the guest clock backward about
  every ten seconds on this host; 98.7% of 865 Oracle VKTM `Time stalled`
  alerts aligned within 1.5 seconds. Restarting VZ and testing a separate
  native-x86 QEMU profile (generic TSC, host CPU, and HPET trials) did not stop
  the corrections. FPS tail evidence from an affected interval is therefore
  provisional even though browser timers truthfully show the degraded user
  experience and deterministic hashes remain valid. Match pacing now derives
  from monotonic `DBMS_UTILITY.GET_TIME`; Oracle Free uses a two-vCPU cpuset
  instead of CFS quota, and the database container has only `SYS_NICE`, which
  removes the VKTM/LGWR priority startup error. A live single-player rerun
  passed at 36.7 ms input-to-submit and 207.9 ms input-to-correlated-paint.
  Final P13 performance/soak acceptance must be repeated on stable-clock native
  Linux or OCI and report p99.9/max gaps in addition to the existing p50/p95.

## 8. Final acceptance matrix

`verify.sh final` prints and enforces these rows:

| Capability | Required proof |
|---|---|
| Fresh local bootstrap | clean volume + second-run idempotence |
| WAD/seed | hashes, exact counts, closure, constraints |
| Geometry/BSP | hand cases, spawn 140, all THINGS, hidden transforms |
| R2 renderer | 64,000 pixels, independent spots, approved hashes |
| Complete presentation | sprites, weapon, HUD, menu, automap, intermission |
| World simulation | movement plus every present line/sector special |
| Gameplay | every present monster, weapon, item, combat behavior |
| Persistence | save/load, rewind, recording, replay hash continuity |
| Fire | full MODEL dimensions, reference hashes, visual check |
| AutoREST | only approved objects, exact BLOB/error/CORS contract |
| Client | raw canvas equality and responsive Playwright workflows |
| Full E1M1 | approved completion replay and milestone hashes |
| Mutation suite | every required mutation detected |
| Production audit | no evaluator/reference/test shortcuts |
| Cloud | actual S3 + Autonomous Database browser run |
| Performance | external samples, optimization history, final p50/p95/FPS |
| Multiplayer | co-op lockstep/reconnect/recovery and per-POV hashes/FPS; deathmatch/player cap if selected |

No partial capability matrix may be described as project completion.

## Appendix A - Camera rays

Angle `a` is radians, counter-clockwise, with 0 along +x.

```
dir   = (cos(a), sin(a))
plane = (-sin(a), cos(a)) * tan(FOV/2)
camx  = 2 * (column + 0.5) / width - 1
ray   = dir + plane * camx
```

The ray is intentionally unnormalized. `ray dot dir = 1`, so intersection `t`
is perpendicular camera distance and no additional fisheye correction is used.

## Appendix B - Ray/segment intersection

For player `p`, segment start `v1`, segment vector `e=v2-v1`, and ray `r`:

```
D = r.x*e.y - r.y*e.x
t = ((v1.x-p.x)*e.y - (v1.y-p.y)*e.x) / D
u = ((v1.x-p.x)*r.y - (v1.y-p.y)*r.x) / D
```

Reject when `ABS(D) < 1e-12`. Accept when `t > 1e-9` and `0 <= u <= 1`.
Stable hit order is `(t, linedef_id, seg_id, facing_side)`.

Oracle NUMBER vs TypeScript double tolerance for diagnostic math is
`ABS(delta_t) <= 1e-6` and `ABS(delta_u) <= 1e-9`. Final palette pixels and
state hashes are exact project-owned outputs.

## Appendix C - Projection and textures

```
k     = (width/2) / tan(FOV/2)
y_top = height/2 - (ceil_z-eye_z)*k/t
y_bot = height/2 - (floor_z-eye_z)*k/t
```

Screen rows grow downward. Pixel centers are `(row+0.5)`. Clamp spans to
`0..height-1`. Facing sidedef determines sector and textures. Horizontal wall
coordinate is segment distance at `u` plus sidedef x offset and seg offset.
Vertical origin follows upper/lower/middle texture role, sidedef y offset, and
the upper/lower unpegged flags. Floor/ceiling reverse projection uses the active
sector interval for that pixel, not merely the nearest wall sector.

`floor_mod(a,n) = a - n*FLOOR(a/n)` for negative coordinates; do not use Oracle
MOD or JavaScript `%` directly.

## Appendix D - Collision and openings

Candidate lines come from BLOCKMAP and/or SDO_FILTER, then exact swept-circle
tests. A line blocks when it is one-sided, has the blocking flag, or its current
portal opening cannot admit the player's radius/height/step. Determine the
earliest contact by `(fraction, linedef_id)`. Project remaining displacement onto
the blocking tangent and repeat for a fixed maximum of two contacts. If still
blocked, retain the last valid point. Hidden cases verify that candidate filters
cannot change the exact result.

## Appendix E - Canonical RLE

For each column ordered by row, a run continues while palette index is equal.
Emit `[y0,length,cidx]`. Runs must be adjacent, positive length, cover exactly
rows 0 through 199, and never merge across columns. Expanding all runs must equal
the canonical 64,000-row frame in both SQL MINUS directions and in the independent
client decoder.

## Appendix F - Tic ordering

Each logical tic performs this order in one transaction:

1. Lock session and validate consecutive command sequence.
2. Apply pause/menu/automap/cheat control state.
3. If gameplay is not paused: apply player intent and weapon intent.
4. Advance sector movers, switches, lights, and damage-sector cadence.
5. Resolve player movement, use/cross triggers, pickups, and exit/secret events.
6. Advance weapon states and resolve player attacks/projectiles.
7. Compute sound reachability and monster perception from the post-player state.
8. Advance monster/object states in stable mobj id order as set-based relations.
9. Resolve object movement, attacks, projectiles, damage, deaths, and drops in
   `(event_class, source_id, target_id, event_ordinal)` order.
10. Consume project RNG values in the engine-definition-declared event order.
11. Append commands/events/audio, increment tic, and persist history/snapshot.
12. Render from the post-tic logical state and build the response payload; commit
    only after payload construction succeeds.

Damage and simultaneous-event tie rules live in independently authored engine
definitions and are included in the state hash. Changing ordering is a contract
change requiring new evaluator approval.

## Appendix G - Research anchors

- Oracle MODEL ordered and iterative rules:
  https://docs.oracle.com/en/database/oracle/oracle-database/23/dwhsg/sql-modeling-data-warehouses.html
- Oracle Spatial query model and SDO_FILTER:
  https://docs.oracle.com/en/database/oracle/oracle-database/23/spatl/querying-spatial-data.html
- Oracle JSON_ARRAYAGG ordering and RETURNING:
  https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/JSON_ARRAYAGG.html
- ORDS 26.2 AutoREST and LOB behavior:
  https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.2/orddg/oracle-rest-data-services-developers-guide.pdf
- ORDS standalone document root:
  https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.2/ordig/deploying-and-monitoring-oracle-rest-data-services.html
- Oracle SQL property graphs and GRAPH_TABLE:
  https://docs.oracle.com/en/database/oracle/property-graph/23.1/spgdg/sql-property-graphs.html
  https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/graph_table-operator.html
- Oracle Database Free limits:
  https://docs.oracle.com/en/database/oracle/oracle-database/26/xeinl/licensing-restrictions.html
- Freedoom releases:
  https://github.com/freedoom/freedoom/releases
- Oracle Free container documentation:
  https://github.com/gvenzl/oci-oracle-free
- id Doom source and exact R_PointOnSide source, used for behavioral audit only:
  https://github.com/id-Software/DOOM
  https://raw.githubusercontent.com/id-Software/DOOM/master/linuxdoom-1.10/r_main.c
- Playwright Docker and visual comparisons:
  https://playwright.dev/docs/docker
  https://playwright.dev/docs/test-snapshots
- METR reward-hacking findings and hardened-evaluation motivation:
  https://metr.org/blog/2025-06-05-recent-reward-hacking/
  https://metr.org/blog/2026-05-19-frontier-risk-report/
- S3 static hosting constraints:
  https://docs.aws.amazon.com/AmazonS3/latest/userguide/HostingWebsiteOnS3Setup.html
- S3 CORS behavior:
  https://docs.aws.amazon.com/AmazonS3/latest/userguide/cors.html
- Autonomous Database managed ORDS tools/endpoints:
  https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/connect-database-actions.html
