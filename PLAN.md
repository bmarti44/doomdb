# DoomDB v2 - Doom rendered and simulated by Oracle Database

Execution plan for Codex CLI. The orchestrator is Sol at medium effort. It routes
bounded tasks to Luna, Terra, or Sol using Section 3, but it may not alter the
charter, acceptance matrix, evaluator, or approved goldens.

This document is the implementation contract. A task is not complete because a
demo looks plausible or because a subset passes. It is complete only when its
listed acceptance command succeeds without weakening an existing check.

## 0. Charter

### 0.1 Mission

Build a complete, playable Freedoom Phase 1 E1M1 experience in which Oracle
Database owns the game:

- WAD geometry, render assets, engine definitions, live objects, player state,
  sector machines, saves, replays, and audio events are relational data.
- SQL performs collision, triggers, weapons, projectiles, damage, pickups,
  monster state advancement, perception, and AI decisions. Under the approved
  P12.0 amendment, a project-owned Java 11 stored procedure inside Oracle JVM
  may perform the production visibility, projection, texture/sprite sampling,
  lighting, composition, frame hashing, RLE, JSON, and GZIP hot path.
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

Multiplayer presence and deathmatch are optional only after all core rows above
are green.

### 0.3 Non-goals

- No byte-for-byte vanilla framebuffer, state, savegame, or .lmp compatibility.
- No claim that the project reproduces vanilla bugs or integer overflow.
- No MLE JavaScript, WebAssembly, native extproc, or embedded Doom engine in the
  simulation or render path. The sole Java exception is the narrow, clean-room
  Oracle JVM render/codec procedure approved for P12.0; simulation remains SQL.
- No custom ORDS modules, templates, or handlers.
- No client-side prediction, interpolation, gameplay, collision, ray casting,
  sprite sorting, or reference implementation.
- No maps beyond E1M1 in core scope.
- No pre-authorized lower resolution, flat-color mode, removed effects, or
  smaller game as a substitute for a failed requirement.
- No vendored, translated, mechanically generated, or copied implementation or
  engine-definition tables from GPL Doom engine source.

The id and Chocolate Doom sources may be cited as behavioral research. Do not
copy code, data arrays, state tables, or translated control flow from them.
Engine definitions must be independently authored from public file-format and
behavior specifications and documented in this repository.

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

Execution order is P0-P7, the local T12.0 acceleration gate, P8-P11, then the
full local-and-cloud T12.1/T12.2 protocol. T12.0 may improve implementation
speed but may not relax or replace the final 300-frame local/cloud evidence.

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
- OJVM data architecture: load the selected deterministic revision-keyed
  relational BLOB packs into exact-width primitive session arrays through
  internal JDBC; do not
  fetch 3,040,239 `AT` rows per pooled session and do not embed a WAD. Cap and
  prewarm the real ORDS pool because OJVM static caches are database-session
  private. Retained immutable cache is capped at 12 MiB per pooled session and a
  warm dynamic snapshot at 5 ms p95. Reuse one profile-sized indexed framebuffer,
  column clip/interval arrays, plane bounds, masked primitive indexes, and codec
  buffers with no full GC in the 300-frame corpus.
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

### P8 - Full E1M1 and presentation workflows

#### T8.1 Full completion replay

- Route: Sol high.
- Author a deterministic command script that starts a normal game, collects needed
  resources/key, fights representative monsters, operates required door/lift
  specials, finds a secret, reaches the exit, and enters intermission.
- User reviews the route and milestone screenshots before approval.
- Accept: state and frame hashes at every milestone, final completion flags,
  kills/items/secrets, and replay repeatability match approved goldens.

#### T8.2 Menu, pause, automap, cheats, save/load workflows

- Route: Terra high.
- Drive each feature only through the public STEP input contract.
- Accept: Playwright plus direct API scenarios cover new game/skill, pause freeze,
  menu navigation, automap modes, each required cheat, save/load, rewind, replay,
  death/restart, and intermission.

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

### P11 - Required S3 + Autonomous Database deployment

#### T11.1 Cloud database deployment

- Route: Terra high.
- First run the unchanged P0 capability and transport probes against the target
  Autonomous Database. Any unsupported feature or transport mismatch blocks P11.
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

### P12 - Final golden-preserving local and cloud performance work

#### T12.1 Baseline and cursor hygiene

- Route: Terra medium.
- Collect the Section 6.6 replay, execution plans with runtime statistics, V$SQL
  parse/execution data, stage timers excluded from payloads, and payload sizes.
- Record separate out-of-band timers for renderer materialization, RLE,
  canonical JSON aggregation, frame hashing, UTF-8 conversion, gzip, response
  copy/ORDS marshaling, browser decode, and canvas blit. Measure one-command and
  four-command STEP latency locally and on managed ORDS.
- Accept: bound statement shapes remain stable across poses/commands and the
  complete raw/report artifact exists.
- Reuse T12.0 artifacts only as ancestry and local diagnostic evidence. Capture
  the complete 300-frame local and cloud baseline here; the pulled-forward gate
  does not satisfy or shorten this acceptance contract.

#### T12.2 Profile-guided optimization loop

- Route: Sol high for SQL changes, Terra for transport/client changes.
- Optimize the measured bottleneck using indexes, join/order changes, precomputed
  static relations, partitioning, aggregation shape, or codec changes that retain
  the public decompressed schema and all goldens.
- Evaluate the already measured shared-portal/single-derivation SQL shape before
  any codec experiment if T12.0 did not already select it. Treat the selected
  T12.0 revision as the initial candidate state, not as proof of final local or
  cloud performance. MLE and UTL_TCP remain out of scope under Section 1.8.
- Stop only under Section 6.6. Record every attempt, including regressions.
- Accept: all correctness and mutation tests remain green and the final report
  states the highest verified local and cloud FPS without a marketing estimate.

### P13 - Optional multiplayer

Only after P0-P12 are complete:

- Add multiple player rows, player damage/death/respawn, database-authoritative
  command ordering, other-player sprites, and deathmatch starts.
- Verify two and four concurrent clients with deterministic server ordering,
  independent frames, no state leakage, and replayable match history.

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
