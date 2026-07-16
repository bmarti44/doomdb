# P12.0 performance handoff — reaching 30 FPS end-to-end (2026-07-16)

Audience: implementation agent (Codex). Goal: the complete per-frame path —
SQL simulation tic + render + codec + BLOB + AutoREST + browser decode — at
**≤33.3 ms p50 and p95** over ≥270 unique moving frames after warmup
(PLAN.md rule 12, P12.0 gate). Everything below keeps the project goal intact:
as much as possible runs inside Oracle Database.

## 1. Ground truth (do not re-measure from scratch; these are current)

| Stage | Measured p50 / p95 | Source |
| --- | --- | --- |
| OJVM compiled renderer (world+masked+presentation) | 6.379 / 7.313 ms | reports/performance-T12.0-ojvm-renderer-2026-07-15.md |
| Packed-v2 codec (GZIP level 1) | 2.755 / 3.081 ms | same |
| BLOB handoff (two bounded locator writes) | 0.033 / 0.061 ms | same |
| **OJVM renderer + codec + BLOB total** | **9.188 / 10.517 ms** | same |
| Render-free SQL simulation `DOOM_TIC_TX.APPLY_BATCH` | **21.260 / 30.856 ms** best clean; **24.162 / 36.939 ms** conservative repeat | reports/performance-T12.0-simulation-state-los-2026-07-16.md (was 36.842 / 49.503 before f00803c) |
| Production SQL render path (moving frame, warm) | ~7,840 ms | PLAN.md P12.0 ledger |

Update 2026-07-16 (commit f00803c): the state/history/LOS slice landed —
direct AL32UTF8 BLOB JSON, persistent `tic_commands.state_blob` locator (the
CLOB→BLOB copy is gone), interval history wrapping the state BLOB without
CLOB round-trips, stationary-tic scan skips, single bounded combat ray per
hitscan, and set-based REJECT + BLOCKMAP-bounded LOS. Remaining profiled
simulation slices on the 163-tic route: actor snapshot ~7.1 ms/tic and
canonical state JSON ~5.6–7.1 ms/tic. Conservative sim p95 (36.939) +
renderer p95 (10.517) = 47.456 ms before ORDS/browser — still over budget.

Two consequences drive all the work below:

1. **The production API still renders through the relational SQL path**
   (`doom_api.render_payload`, sql/rest/010_doom_api.sql:135-374), which is
   ~7.8 s per moving frame. The 10.5 ms OJVM renderer exists only as a
   benchmark class and renders a hard-coded tic-zero scene. Integrating it is
   the single largest win (~3 orders of magnitude) and is already
   charter-approved.
2. **The simulation tic alone exceeds the whole frame budget.** Even with a
   0 ms renderer, 49.5 ms p95 of simulation fails the gate. Target ≤10 ms p95
   (reports/performance-T12.0-simulation.md), leaving ~10.5 ms renderer +
   ~10 ms ORDS/wire/decode headroom.

Budget allocation to work toward: simulation ≤10 ms, renderer+codec+BLOB
≤10.5 ms (already passing), ORDS + base64 + client decode + blit ≤12 ms.

## 2. Constraints Codex must not violate (charter, PLAN.md)

- **Simulation stays SQL / set-based DML** (rule 3). The approved OJVM
  amendment (PLAN.md "Approved P12.0 OJVM amendment — 2026-07-15") covers
  *render and codec work only*: visibility, projection, palette sampling,
  masked composition, presentation, frame hashing, RLE/packed encoding, JSON
  generation, GZIP. State JSON generation and hashing are codec work and are
  explicitly in scope for Java; simulation *decisions* are not.
- Transport is AutoREST via `ORDS.ENABLE_OBJECT` only. No
  `ORDS.DEFINE_MODULE`, no custom handlers, no UTL_TCP, no websockets
  (rules 1–2; reports/performance-mle-utl-tcp-evaluation.md). The base64 JSON
  wrapping of the BLOB OUT parameter is a fixed cost — plan around it.
- The canonical SQL renderer and `MATCH_RECOGNIZE` RLE stay byte-locked as
  independent parity oracles. Never edit them for speed; selection of any
  fast path requires exact byte/hash/RLE/schema parity plus the full T5–T7
  suite (amendment text; rule 11).
- No GPL material: JavaBox, Mocha Doom (`c0af1322`), id Doom, and any other
  engine source are architecture evidence only. No copied or translated code,
  tables, constants, or control flow (Section 1.6; P12.0 ledger).
- 320×200, full effects, exact hashes; resolution/capability reduction is
  forbidden (rule 13). No client-side rendering, prediction, interpolation,
  or delta frames that break the cold unique-moving-frame acceptance
  (reports/performance-sol-max-codec-research-2026-07-15.md).
- Restart safety: no correctness dependence on session state that cannot be
  rebuilt after instance restart. Numeric determinism rules (PLAN.md 1.3)
  apply to every new SQL entry point.
- Oracle Free limits: 2 cores, 2 GiB. Do not reach for parallel query/DOP or
  OJVM threading; both were evaluated and rejected
  (reports/performance-sol-max-render-bottleneck-research-2026-07-15.md).

## 3. Do-not-retry list (measured dead ends)

Documented failures — do not propose these again:

- Native PL/SQL compilation of hot sim bodies: 1.8 ms gain, below threshold
  (performance-T12.0-simulation.md).
- Correlated zero-motion SQL-macro fast path: reproducible `ORA-07445`
  (same report).
- CTE materialization hints, GTT clip-window staging, indexed row-range
  generation, KEEP(DENSE_RANK) presentation, ray materialization — all
  regressed end-to-end (performance-T12.0.md, performance-T12.0-stage-profile.md).
- MLE JavaScript anywhere on the hot path; UTL_TCP transport
  (performance-mle-utl-tcp-evaluation.md).
- v1 RLE codec variants (level 6/level 1/Huffman-only): all ≥8.9 ms codec-only
  vs the 5 ms gate; preset-dictionary and multi-member GZIP are
  decoder-incompatible (performance-sol-max-codec-research-2026-07-15.md).
- Monolithic "brute analytic" OJVM renderer: 1,461 ms p95 and an
  uncompilable method (performance-sol-max-render-bottleneck-research-2026-07-15.md).
- **Multi-query OJVM state serialization** (the former B1 route 1): byte-exact
  but 69.286 / 106.270 ms p50/p95 — internal-JDBC row walking dominates; the
  server-side driver pays full SQL execute cost per statement and per-row
  accessor overhead. Rejected 2026-07-16; the SQL-native direct-BLOB
  `json_object` shape won instead (commit f00803c,
  performance-T12.0-simulation-state-los-2026-07-16.md). Lesson for all
  future OJVM work: Java wins on compute over arrays already in memory, not
  on relational reads — keep row-walking in SQL, cross the boundary with
  packed buffers.
- SecureFile LOB deduplication: <1 ms p95 gain, reverted (same report).
- Unordered LOS existence check: failed the T7.2 source contract (same report).

## 4. Workstream A — productionize the OJVM renderer (biggest win)

Current state: `DoomBspKernelBench.renderTicZero(Blob)`
(scripts/performance/DoomBspKernelBench.java:1565-1588) renders a fixed camera
at spawn (-416, 256, angle 0) with monster positions loaded once from
`doom_map_thing` (lines 466-481). PL/SQL wrapper:
sql/accel/020_ojvm_renderer_calls.sql. It is not called from
`doom_api.step()`.

### A1. Parameterize the renderer with live state

- Add an entry point taking `(session_token, tic, payload BLOB)` — or better,
  explicit scalar binds for camera plus a compact state snapshot (see A2) —
  replacing every hard-coded tic-zero input:
  - Camera: live `players.x/y/z/angle/view_height` for
    `game_sessions.current_player_id`.
  - Mobjs: live `mobjs` rows (position, angle, state_id, sprite/rotation
    inputs) instead of the `doom_map_thing` spawn snapshot.
  - Sector heights/light: live `sector_state` (movers change floor/ceiling
    heights and light every tic — planes and clips depend on them).
  - Presentation state: mode (GAME/MENU/AUTOMAP/INTERMISSION/DEAD/paused),
    weapon, ammo/health/armor digits, keys — whatever
    `doom_api_presentation_rows` currently derives.
- Keep the static caches exactly as they are (BSP arrays, four asset packs
  from `doom_renderer_asset_pack`): loaded once per session, revision-keyed.

### A2. Make the per-tic dynamic snapshot cheap

The renderer must read live state without re-running five separate JDBC
queries per frame if that measures poorly. Options in preference order:

1. Single internal-JDBC bulk read per frame of only render-relevant columns
   (mobjs + sector deltas + player + presentation scalars). E1M1 has a few
   dozen live actors and 182 sectors; this is a small read. Measure first —
   it may already fit the ≤17 ms "warm dynamic snapshot + full render" gate
   (performance-sol-max-render-bottleneck-research-2026-07-15.md).
2. If query overhead dominates, have `APPLY_BATCH` maintain a packed binary
   snapshot (RAW/BLOB, fixed layout, written with one set-based statement per
   tic) that the renderer decodes into primitive arrays. Charter-safe:
   simulation still makes all decisions in SQL; the pack is a derived,
   revision-keyed relational artifact like the asset packs.
3. Only changed-row reads keyed by `sector_state.updated_tic`-style columns —
   add such columns only if 1 and 2 measure above budget.

### A3. Wire into `doom_api.step()`

- Replace the `render_payload()` call at sql/rest/010_doom_api.sql:507 with
  the OJVM call producing the identical envelope (same JSON schema, packed-v2
  `frame_b64` plus metadata/audio rows, same GZIP framing) into the same
  `step_responses` BLOB.
- The envelope must remain byte-compatible with the client decoder
  (client/src/codec.ts already handles v2).
- Keep `render_payload()` intact and callable as the parity oracle. Gate the
  cutover behind config (`doom_config` flag) so verification can run both.
- Move the class out of `scripts/performance/` into a production location
  (e.g. `sql/accel/` deployment via the existing
  deploy-t12.0-ojvm-renderer.sh pattern, wired into bootstrap order.txt) and
  rename it — it is no longer a bench. Deployment must: `loadjava`,
  `DBMS_JAVA.COMPILE_CLASS` every hot method, verify
  `user_java_methods.is_compiled='YES'`, and run the bounded warmup
  (scripts/performance/ojvm-renderer-warmup.sql) — all restart-safe and
  idempotent from a fresh volume (rule 15).

### A4. OJVM runtime hardening (correctness of the warm path)

Facts from OJVM research (2026-07-16), each with a concrete action:

- **Statics persist per session; an uncaught Java exception, `System.exit`,
  or Java OOM silently kills the session JVM and cold-starts statics on the
  next call while the DB session survives.** Wrap every OJVM entry point in
  a catch-all that reports and returns an error payload; treat an unexpected
  cold-start (caches empty when they shouldn't be) as a logged event, not a
  silent multi-second reload inside a frame.
- **JIT compiled code is instance-wide but does not survive restart** (it
  lives in `/dev/shm/JOXSHM_EXT_*`; deleted on shutdown). The bounded warmup
  plus `DBMS_JAVA.COMPILE_CLASS` must run as a restart-safe startup step, not
  only at deploy time. Check `COMPILE_CLASS`'s return count — 0 means it
  declined. `/dev/shm` must stay `rw,exec` (compose already provides 256 MiB
  executable; interpreted fallback is 50–170× slower and silent).
- **NCOMP no longer exists** (removed in favor of the JIT since 11.1) — any
  plan language about static native compilation should say JIT.
- **PL/SQL→Java boundary costs ~20–25 µs per call.** One renderer call and
  one codec call per frame is negligible; never cross the boundary
  per-entity or per-column.
- **Passing state: 32,767-byte ceiling on PL/SQL RAW/VARCHAR2 binds; above
  that use a BLOB locator (passed lazily, no copy at call time).** Reuse one
  long-lived cache-enabled LOB per session rather than creating temp LOBs
  per frame — JDBC silently switches to create+copy+free temp-BLOB binding
  at ≥32,767 bytes, and unfreed temp LOBs accumulate in temp tablespace.
  The current two bounded locator writes (0.061 ms p95) already follow this;
  keep the pattern for the state snapshot path too.
- **Dedicated server processes only.** Shared-server mode migrates the
  entire reachable Java object graph to SGA session space at the end of
  every call — fatal for multi-MB texel caches. Verify the local and cloud
  configs use dedicated servers.
- Memory ceiling: Oracle Free's 2 GiB covers SGA + PGA + Java session space
  + JIT shm together. Size the static caches with that ledger in mind
  (`JAVA_MAX_SESSIONSPACE_SIZE` kills the session if exceeded).

### A5. Parity gates for A1–A4 (mandatory before selection)

- 300-frame corpus: exact framebuffer, frame_sha, state_sha, decompressed
  payload equality against the SQL oracle, across moving frames with doors,
  lifts, monsters awake, projectiles, pickups, and every presentation mode —
  not just tic zero.
- Composite gates from the research reports: no-JDBC render kernel ≤12 ms
  p95; warm dynamic snapshot + full render ≤17 ms p95; renderer + codec +
  BLOB ≤20 ms p95; every hot method natively compiled.

## 5. Workstream B — simulation tic: 36.9 ms → ≤10 ms p95, SQL-side

Hot path call order: sql/sim/tic/010_tic_transaction.sql (`APPLY_BATCH`).
Status after commit f00803c: 21.260 / 30.856 ms best clean, 24.162 / 36.939 ms
conservative (performance-T12.0-simulation-state-los-2026-07-16.md). The
CLOB→BLOB copy, per-pellet renderer expansion, repeated LOS BFS, and
stationary-tic scans are already fixed. The two remaining profiled slices on
the moving/firing route are the **actor snapshot (~7.1 ms/tic)** and the
**canonical state JSON (~5.6–7.1 ms/tic)**.

Ordered by expected gain:

### B1. Take full-state JSON serialization off the per-tic path (~5–7 ms/tic)

The OJVM serializer route was tried and rejected (69/106 ms — see Section 3);
the state document is now a direct-BLOB `json_object` written through the
persistent locator. The remaining lever is **cadence**: modern lineages
already checkpoint every 4 tics (010_tic_transaction.sql). If the full state
document is only *needed* at checkpoints and save/load/rewind boundaries
(verify against 040_history_replay.sql `reconstruct()` and the retry
contract on `step_responses`), skip `state_document()` on non-checkpoint
tics and persist only the state SHA chain. This changes the
`tic_commands.state_blob` contract — confirm nothing reads per-tic blobs for
non-checkpoint tics before doing it (t8.1 artifacts and history gates do
read history; run the full P6 suite). The response envelope must keep
returning a per-tic `state_sha`; if the SHA is currently derived from the
serialized document, define the canonical bytes for non-checkpoint tics
(e.g., serialize-then-discard is not a win — the hash input needs a cheaper
canonical form, or the SHA chain semantics must be amended with evaluator
approval).

### B2. Convert row-by-row DML loops to set-based/bulk (~3–6 ms/tic)

Charter rule 3 *prefers* this ("SQL and set-based DML own simulation
decisions"), so it is alignment, not just optimization:

- `doom_world_machines.advance_movers`
  (sql/sim/030_world_machines.sql:192-291): per-mover UPDATE of
  `active_movers`, `sector_state`, `players.z`, `mobjs.z`, plus per-mover
  DELETE. Rewrite as one snapshot SELECT + single set-based UPDATE/MERGE per
  table + one DELETE ... WHERE mover finished. Movers are few, but each row
  currently costs 4–6 statements.
- `doom_monsters.advance` (sql/sim/060_monsters.sql): after f00803c the
  **actor snapshot query is the single largest route slice (~7.1 ms/tic)**.
  Attack it first: profile which joined derivations dominate (visibility
  determinants, REJECT/BLOCKMAP joins, geometry), and gate expensive columns
  on need — dormant/asleep actors don't require visibility or LOS columns at
  all (prior art: look-checks run at ~11 Hz, not every tic; Section 8.3).
  Split the snapshot into a cheap all-actors pass plus an expensive pass over
  only awake-and-near actors. The mutation side still issues per-actor
  UPDATEs (state transitions, damage, wake, movement); accumulate decisions
  into collections and flush with FORALL per column-group, or fold into a
  single MERGE where logic permits.
- `doom_combat.apply_pickups` (sql/sim/050_combat_inventory.sql:189-290):
  per-item SELECT + up to 8 conditional UPDATEs + 3 DELETEs via
  `remove_mobj`. Compute all pickup effects in one set-based pass (join
  player × touched items), apply player mutations with one UPDATE, remove
  consumed items with one DELETE.

### B3. Kill redundant reads inside the tic (~1–2 ms/tic)

- `doom_combat.choose_weapon` / `fire_weapon`
  (050_combat_inventory.sql:292-323, 420-459) re-SELECT the `tic_commands`
  row inserted moments earlier in `APPLY_BATCH` (010_tic_transaction.sql:445-456).
  Pass the parsed command record down as a parameter instead.
- `doom_world_machines.config_number` (030_world_machines.sql:46-51) hits
  `doom_config` 5–10× per tic for constants (door/lift/blaze speeds, waits).
  Cache in package-level state, invalidated by a config revision counter —
  restart-safe because it repopulates on first call.
- `doom_monsters.advance` (060_monsters.sql:329-344) re-derives player id/max
  mobj id and repairs null `sector_id` every tic. Cache the player identity
  per session in package state; make the sector-id repair conditional on a
  flag set only when something can invalidate it.
- `reject_pair`/`sound_reach` single-row lookups per monster per tic
  (060_monsters.sql:60-69, 143-153): join these tables into the bulk monster
  snapshot query instead of calling scalar functions in the loop.

### B4. Re-profile, then stop or escalate

After B1–B3, rerun the profiler harness from
performance-T12.0-simulation.md. Conservative estimate: 49.5 ms p95 →
~20–30 ms if B1 lands as OJVM codec plus bulk DML. Prior art (Section 8.2)
independently indicates the remaining cost — swept-contact collision plus
per-statement overhead of the bounded statement list — is a structural floor
of set-based execution, so expect a plateau above the ≤10 ms target. Prepare
the escalation evidence *in parallel with* B1–B3, not after: file the
charter-versus-hardware feasibility conflict per the P12.0 instructions with
the measured plateau, and draft the one escalation with precedent — a *new,
narrow charter amendment* (human approval required, like the renderer
amendment) moving the per-tic inner loop (collision sweep + monster
decisions) into clean-room OJVM with SQL remaining the system of record for
all state, synced by delta writes of dirtied rows after each tic, verified
bit-for-bit against the PL/SQL tic as differential oracle (the same
oracle-and-parity pattern the renderer used). Calibration for the amendment
case: a compiled Doom tic is ~5–50 µs in prior art (Section 8.1), so an
OJVM tic in the low single-digit milliseconds is a conservative expectation.
Do not implement this without the amendment; prepare the evidence for the
decision instead.

## 6. Workstream C — request path and client (keep, verify, polish)

- The client already couples input + frame in one AutoREST POST with a 10 ms
  debounce and sequential chaining (client/src/main.ts:78-99,
  client/src/api.ts:52-58). Keep this; do not split input and frame into two
  round trips.
- Fixed wire costs to budget, not fight: base64-in-JSON of the ~42–44 KB GZIP
  payload (~56 KB on the wire) is required by AutoREST BLOB semantics
  (reports/transport-contract.md). Client decode already measures ~1.8 ms.
- After A3 lands, measure the full local loop (curl + browser harness,
  scripts/verify-local-e2e.sh) and produce the stage split: ORDS dispatch,
  DB call, wire, decode, blit. Only optimize here if the measured ORDS+wire
  share exceeds ~12 ms locally.
- **ORDS affinity was measured and does not retain OJVM heap state**
  (2026-07-16 local ORDS 26.2 probe):
  - The smallest viable fixed local pool is `InitialLimit=MinLimit=MaxLimit=2`.
    A `1/1/1` pool returned HTTP 500 during AutoREST discovery. Reuse is set
    to 100,000,000, inactivity to 86,400 seconds, and cleanup remains
    `RECYCLE`.
  - The first 300 one-second probe requests all used SID/AUDSID
    `176/1840351`, while both a Java static and PL/SQL package global returned
    `1` on every request. ORDS request cleanup reinitializes both states even
    with perfect database-session affinity.
  - The probe result is documented, unconditional ORDS behavior with no
    supported off switch: "ORDS always performs:
    dbms_session.modify_package_state(dbms_session.reinitialize) at the end
    of each request" (ORDS Developer's Guide), and Oracle documents that
    OJVM application data "can[not] be shared in any way with other
    sessions." Full research, citations, and decision table:
    **reports/performance-P12.0-ords-ojvm-state-research-2026-07-16.md**.
  - **Do NOT settle on per-request rebuild** — the measured 481 ms cold path
    (167 ms pack decode + 268 ms fresh-session snapshot + render) sits atop
    an unavoidable fresh-JVM floor and cannot plausibly reach 33.3 ms even
    fully optimized. The selected architecture from the research is a
    **database-resident DBMS_SCHEDULER render worker**: one long-lived
    session holds the warm renderer (statics, PreparedStatements,
    framebuffers survive for the session's life; JIT code is already
    instance-shared), singleton-guarded by an exclusive DBMS_LOCK 'UL'
    lock, `restartable`/`restart_on_recovery` supervised. The AutoREST
    procedure rendezvouses via DBMS_PIPE: packed dynamic snapshot in (the
    A2 pack, a few KB — pass it through the pipe so the worker never needs
    cross-session read consistency or table reads), ~42 KB frame back as
    chunked ≤4 KB RAW messages (pipe `maxpipesize` defaults to 65,536 in
    23ai and auto-grows), in-session SQL-render fallback on timeout. Pipe
    waiters wake on message arrival; the integer-second timeout bounds only
    the dead-worker path. This is Oracle's own documented DBMS_PIPE daemon
    pattern (and RMAN's production pipe mode), keeps AutoREST as the sole
    browser transport, everything inside Oracle, SQL authoritative for
    simulation. Run the report's three bounded experiments first (pipe
    ping-pong ≤2 ms p95; worker skeleton with request-path overhead minus
    APPLY_BATCH ≤14 ms p95; fresh-session floor attribution to close the
    per-request line with a recorded number), and record the one-paragraph
    charter clarification for hosting the approved OJVM render/codec path
    in a resident session.
  - ORDS 26.2 package subprogram paths are case-sensitive in this pinned image:
    uppercase catalog names work (`DOOM_API/NEW_GAME`), while lowercase names
    return 404. The client performs one casing fallback during startup and
    then reuses the selected route without a second request per frame.
  - Authentication placement matters: DB-credential Basic auth has measured
    60–160 ms per request — an order of magnitude over the whole frame
    budget. Keep the demo path on the current session-token scheme (no
    per-request DB auth); never add ORDS `preHook` (extra DB round trip per
    request) to the hot path.
  - Document the final pool settings in the acceptance evidence; p95 must
    not be sampling cold sessions.

## 7. Measurement and acceptance protocol (unchanged, enforce it)

- Warmup: 30-frame cursor/buffer warmup plus bounded JIT warmup; only warmed
  steady-state counts (P12.0; renderer report).
- Corpus: ≥270 unique moving frames, caches cold for uniqueness; cached
  spawn/menu/pause/retry/replay responses reported separately and cannot
  satisfy the gate.
- Both p50 and p95 ≤33.3 ms, measured end-to-end at the external
  AutoREST/browser boundary, evidence in reports/ following the
  performance-T12.0-* format.
- Every optimization is select-only-if: exact parity (frame bytes, state
  bytes, both SHAs, envelope schema) + full adjacent gate suite (T5–T7 for
  render, P6/P7 for sim) + measured improvement above noise. Anything else
  is reverted — the repo's own history (Section 3) shows most "obvious" SQL
  tweaks regressed.

## 8. Prior-art guidance (architecture only; observe licensing)

Web research digest, 2026-07-16. All Doom-logic ports are GPL-family:
architecture evidence only, no copied/translated code, tables, constants, or
control flow. Documentation sources (doomwiki.org, Game Engine Black Book
prose, the "doom_tour" bookdown) are the safe clean-room inputs.

### 8.1 Calibration: a full Doom tic is sub-millisecond in compiled code

- Vanilla Doom `-nodraw -timedemo` on 1993 486-class hardware: ~1.1 ms/tic
  for the full playsim (Game Engine Black Book DOOM,
  fabiensanglard.net/gebbdoom; its flame graph shows gameplay "barely
  visible" next to rendering).
- HeadlessDoom (original C source, 56,111-frame demo, Core i3-8350):
  ~78 µs/frame *including* the 320×200 software render
  (github.com/jwhitham/HeadlessDoom).
- ViZDoom: ~7,000 single-threaded steps/s including low-res render
  (github.com/Farama-Foundation/ViZDoom, arXiv:1605.02097).

Best estimate for a normal map in JIT-compiled code: ~5–50 µs/tic. Even with
a 100× OJVM/JDBC-boundary penalty, a primitive-array Java tic lands in the
low single-digit milliseconds. The ≤10 ms simulation target has orders of
magnitude of headroom *if* the tic runs as one compiled invocation.

### 8.2 Confirmation that the SQL plateau is structural

CedarDB's DOOMQL/DoomBench (MIT, cedardb.com/blog/doombench) runs a far
simpler Doom-like raycaster fully in SQL: ~33 ms/frame at 128×64 on the
fastest tested engine, ~10 ticks/s on Postgres. That an engine built for
this workload lands at the same ~33 ms as DoomDB's 36.8 ms PL/SQL tic is
independent evidence that per-statement/set-based execution overhead — not
missing indexes or DML shape — is the floor. No prior project runs real
WAD-based Doom logic set-based in SQL; the industry pattern for
simulation-in-database is compiled code in-process (pg_doom: C thread inside
the Postgres backend; SpacetimeDB: WASM "reducers" as stored procedures).
DoomDB's OJVM renderer is already this pattern.

Implication for Workstream B: B1–B3 are worth doing (they are real,
measured per-tic costs), but expect a plateau in the ~15–30 ms range, not
≤10 ms. Prepare the B4 amendment evidence in parallel rather than after.

### 8.3 Architecture that makes a tic cheap (documented, clean-room-safe)

From doomwiki.org (Tic, Thinker, Blockmap, Reject, Monster behavior, PRNG,
Demo, Fixed point), GEBB prose, and bookdown.org/robertness/doom_tour:

1. **Active-thinker iteration, never world scans.** One list of *active*
   objects, each with a state/action id; doors and lifts are on the list
   only while moving; a dormant monster costs one counter decrement per
   tic. Cost is O(active objects), independent of map size. (DoomDB's SQL
   sim partially has this via `active_movers`; the monster pass does not.)
2. **Blockmap-bounded collision with a visit stamp.** Movement tests only
   the blockmap cells overlapping the mover's bounding box, with a
   `validcount`-style int stamp so no line/thing is tested twice per query.
3. **Throttled expensive AI checks.** Look-for-player runs at ~11 Hz, not
   35 Hz; REJECT bitmap consulted before any line-of-sight geometry;
   reaction-time delays; sound wake-up via sector flood fill (DoomDB already
   has the closure table). Slaughter-map evidence (nuts.wad) shows
   sight/sound checks are what blows up first at scale.
4. **Primitive-int 16.16 fixed point, zero allocation on the hot path.**
   Mocha Doom's documented lesson (mochadoom.sourceforge.net/tech.html):
   fixed-point values are raw `int`s (long-widened multiply), never objects.
   Prefer switch-on-int state dispatch over per-object lambdas for
   JIT friendliness.
5. **Host-driven tic inversion.** One external call = one fixed-timestep
   tic (doom-sokol's documented restructuring of doomgeneric); maps exactly
   onto one OJVM call per tic/batch from the session.
6. **Integer determinism.** Single-index 256-entry random table split into
   sim vs presentation streams; input-stream tics give exact replay — this
   matches DoomDB's existing hash/replay contracts and enables bit-for-bit
   SQL-vs-Java differential verification during any migration.

### 8.4 Source ledger (licensing)

| Source | License | Use |
| --- | --- | --- |
| id-Software/DOOM (linuxdoom) | GPL | architecture only |
| Mocha Doom (canonical: github.com/AXDOOMER/mochadoom) | GPLv3 | architecture only |
| Managed Doom (github.com/sinshu/managed-doom) | GPLv2+ (not permissive) | architecture only; best name-level map of p_*.c into OO subsystems |
| doomgeneric / doom-sokol | GPLv2 | architecture only (tic-inversion idea) |
| room4doom (Rust) | MIT file but self-described transliteration of GPL code | treat as GPL-equivalent; do not rely on its MIT claim |
| DOOMQL / duckdb-doom / doomql / DoomHouse | MIT | usable, but raycaster demos, not Doom logic |
| pg_doom | unstated, embeds GPL Doom | reference only |
| doomwiki.org, GEBB prose, doom_tour | documentation | safe clean-room inputs |

**JavaBox identification:** "JavaBox" is the project owner's own repository
(github.com/bmarti44/javabox): OpenJDK 21 compiled to WebAssembly via
Emscripten, running Mocha Doom in the browser at ~30 FPS on an
interpreter-only JVM (no JIT). Two consequences: (a) the Doom engine inside
it *is* Mocha Doom (GPLv3), so every "JavaBox-informed" architecture note in
README.md/PLAN.md carries Mocha Doom's licensing posture — architecture
evidence only, no copied code; record this identification in the provenance
ledger (PLAN.md rule 16). (b) It is a strong calibration point: a complete
Doom tic + software render sustains 30 FPS even on an *interpreted* JVM, so
a natively compiled OJVM tic has enormous headroom (consistent with
Section 8.1).

## 9. Suggested execution order for Codex

0. ~~ORDS session-affinity probe~~ DONE 2026-07-16: affinity does not
   preserve state (Section 6). New step 0: the **DBMS_PIPE ping-pong
   benchmark** (experiment 1 of
   reports/performance-P12.0-ords-ojvm-state-research-2026-07-16.md,
   ≤2 ms p95 round trip), plus the `DBA_SERVICES.RESET_STATE` one-query
   diagnostic and the fresh-session floor attribution (experiment 3) to
   close the per-request-rebuild line with recorded numbers.
1. A1–A2: live-state renderer entry point + packed snapshot (the snapshot
   now doubles as the pipe payload); parity on moving frames (doors moving,
   monsters awake), composite ≤17 ms gate. Apply the A4 hardening items
   (catch-all entry points, restart-safe warmup) as part of this slice, not
   later. Then the resident-worker skeleton (experiment 2: request-path
   overhead minus APPLY_BATCH ≤14 ms p95) and the charter clarification
   note.
2. B2 actor-snapshot reduction (largest remaining sim slice, ~7.1 ms/tic) +
   B1 checkpoint-cadence state serialization (~5–7 ms/tic); rerun sim
   profile after each.
3. Remaining B2–B3: bulk DML + redundant-read elimination; rerun sim
   profile. Start assembling B4 amendment/feasibility evidence from these
   profiles.
4. A3, A5: production cutover of `step()` to the OJVM renderer behind a
   config flag; 300-frame parity corpus; full T5–T7.
5. C: end-to-end local measurement, stage split, documented pool settings.
6. B4: stop, or file the feasibility conflict + draft amendment if the sim
   plateau is above budget (Section 8.2 predicts it will be).
