# TeaVM Mocha Doom MLE probes

## Resident authoritative simulation

`./build-simulation.sh` builds the MLE-specific headless profile, compiles it
with TeaVM, loads the real vendored Freedoom IWAD under Node, proves two
independent runs have identical snapshots, and advances a retained E1M1 engine
for 300 additional tics. The generated ES2015 module is
`target/javascript/doom-mle-simulation-engine-headless.js`.

Its Oracle MLE/JavaScript exports are:

- `allocateIwad(length)` and `loadIwadChunk(offset, Uint8Array)`;
- `allocateTablePack(length)` and `loadTablePackChunk(offset, Uint8Array)` for
  the canonical Oracle-JVM trigonometric tables;
- `initialize()` for exact `sk_medium`, episode 1, map 1 startup;
- `step(forwardMove, sideMove, angleTurn, buttons)`, returning the state after
  every caller-owned tic;
- `stepBare(forwardMove, sideMove, angleTurn, buttons)`, running the identical
  command/ticker core while returning only the new gametic for server-side
  ticker isolation;
- `stepCommandBare(forwardMove, sideMove, angleTurn, consistency, buttons)`,
  replaying exact durable ledger-command semantics;
- `canonicalStateLength()` and `canonicalStateChunk(offset, length)`, exporting
  complete canonical material for Oracle-native SHA-256;
- `checkpointLength()`/`checkpointChunk()` and
  `allocateCheckpoint()`/`loadCheckpointChunk()`/`restoreCheckpoint()`, which
  round-trip the DMC1/v4 recovery envelope;
- `initializeMultiplayer(activePlayers)` and
  `stepMultiplayerBare(activePlayers, commandVector)`, accepting one packed
  eight-byte command per player and maintaining the consistency ring;
- `initializeMultiplayerAtSkill(activePlayers, skill)` for provenance-locked
  multiplayer routes whose vanilla skill differs from the default skill 3;
- `fixedMulChecksum()`, a build/smoke-only cross-runtime parity checksum;
- `currentState()`, `memoryDiagnostic()`, and `release()`.

State snapshots include gametic, leveltime, random index, game state, episode,
map, player state/position/angle/health/view height/armor/weapon, and player and
world kill/item/secret counters. Module state is static and resident for the
MLE session. `memoryDiagnostic()` reports an inexpensive retained-state
inventory without depending on an unavailable JVM heap API.

`build-simulation.sh` first creates a separate 830-class base JAR without the
MLE headless patch, then runs `CanonicalTablePackGenerator` against it with the
Oracle JVM shipped in the pinned 26ai database container. The utility calls the
pinned procedural `Tables.InitTables()` and emits `target/canonical-runtime-v2.bin`: a
180,272-byte, versioned, big-endian runtime pack with locked SHA-256
`058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44`.
It contains the four trig tables and the exact 65,536-byte Freedoom TRANMAP.
`CanonicalTranmapPropertyTest` boots the unmodified JVM renderer and requires
its synthesized TRANMAP to match the packed bytes exactly.
The adapter requires the complete pack before initialization. The patched
`Tables.InitTables()` selects it at entry—before renderer visibility tables can
derive state—and validates magic, version, endian marker, total length, and all
four array counts. This removes JVM-versus-JavaScript transcendental rounding
from deterministic simulation. The MLE-specific `InitTables()` has no
procedural fallback, and the build rejects generated modules containing
`Math.sin`, `Math.tan`, or `Math.atan`.

`0002-teavm-simulation-headless.patch` is deliberately simulation-oriented. It
preserves the full `DoomMain.Ticker` game-action loop, demo command paths,
intermission/finale tickers, all 15 action-trait contexts, and the real level,
thinker, actor, collision, weapon, and RNG implementations. It replaces only
desktop/presentation dependencies: AWT rasters, audio/MIDI, parallel renderers,
HUD/automap drawing, back-screen blits, and intermission/finale art loading.
TeaVM cannot discover Mocha Doom's action contexts reflectively, so this profile
registers the same 15 `ContextKey` suppliers explicitly; no action is stubbed.

After building, `./load-mle-module.sh --no-build` stores the module as a BLOB
and creates call specifications in Oracle AI Database 26ai. The optional
`run-mle-simulation.sql` loads `freedoom1.wad` from
`doom_engine_artifact`, advances 3,000 genuine E1M1 tics using server-side
`SYSTIMESTAMP`, reports percentiles and sustained throughput, and models paced
backlog against Doom's 28.57 ms/35 Hz slot.

`step` and `stepBare` delegate to one private step core, so the diagnostic
export cannot drift from the state-returning production path. The Node smoke
test runs the same input sequence through both exports and requires their full
post-tic snapshots to match before timing 300 bare tics. It also proves that a
pack with corrupted magic is rejected.

`canonicalState` uses the same Mocha save serializer in OJVM and TeaVM with
host pointer placeholders canonicalized, then adds stable thinker, player, and
spatial-reference ordinals plus RNG and engine globals. The differential script
compares this complete save-semantic identity after every ticker transition.
`build-ledger-differential.mjs` expands the accepted 13,272-command E1M1 route
and can require native-SHA equality every tic or at a checkpoint interval.
`benchmark-canonical-state.sql` isolates material construction, RAW export,
native hashing, and OJVM-oracle costs. Renderer mutation is deliberately tested
separately from authoritative state.

The DMC1/v4 checkpoint wraps Mocha's vanilla payload with the RNG cursor,
original thinker order, mobj spatial/target topology, sector and blockmap roots,
player references, and full-width mobj values omitted or truncated by the
vanilla codec. Version 3 also carries netgame/deathmatch mode, console/display
players, the adapter and engine consistency rings, exact weapon-psprite states,
and mobj floor/ceiling bounds. `recovery-mle.sql` deliberately
advances away from a checkpoint,
restores it, compares the complete canonical state with OJVM, and continues both
engines together. Its DMC1/v3 predecessor restored 79,350 bytes in 7,884.132 ms
and remained exact for 330 continued single-player tics. The v4 Node gate also
destroys and recreates a four-player engine at tic 100 and remains exact through
tic 430. The equivalent Oracle gate restores its 89,042-byte checkpoint into a
fresh context in 1,818.683 ms, matches OJVM immediately, and remains exact for
all 330 continuation tics.

`multiplayer-mle.sql` compares a four-player retained MLE netgame with OJVM for
330 tics and deep-checks the complete state every 50. The companion benchmark
runs 3,000 four-player tics through the RAW call boundary and reports sustained
throughput and paced backlog. `recovery-multiplayer-mle.sql` proves fresh-context
DMC1/v4 recovery, while `run-multiplayer-soak.sh` samples session PGA during a
retained four-player soak. The 1,800.007-second evidence run completed 230,671
tics at 128.15 tics/s, with 15.7/11.3 ms early/late five-minute p99 and zero
ending backlog. Session PGA was flat at 15,907,136 bytes, but a controlled
allocation proved that metric omits MLE heap; the final memory gate uses
calibrated OS-process RSS/PSS/private-memory sampling.

`build-coop-differential.mjs` consumes the accepted 762-tic co-op artifact,
verifies its base-route SHA, applies its published player-0 transforms and
player-1 input runs, and emits a skill-1 MLE/OJVM canonical differential. Its
default is a full-state comparison after every tic.

The MLE-only patch also replaces every `fixed_t.FixedMul` overload with one
allocation-free 16-bit-limb helper. Its bytecode contains only integer masks,
shifts, multiplies, and adds; the regular pinned/OJVM build remains unchanged.
`FixedMulPropertyTest` compares all six overload paths with their original
`long` expressions for 529 boundary pairs and 1,000,000 deterministic random
pairs. The build passes its checksum into `fixedMulChecksum()` and requires the
TeaVM/Node result to match. `FixedDiv` deliberately retains Java `long`
shift/divide semantics: substituting floating-point division without a proof
over the full input domain could change truncation at integer boundaries.

## Executable engine slice

This spike moves beyond `../teavm`'s table-only proof. It transpiles and runs a
reachable slice of the pinned, patched Mocha Doom JAR containing:

- every vanilla actor/state record and action identifier;
- the engine's deterministic random path and exact eight-byte `ticcmd_t` codec;
- its fixed-point, BSP intercept, approximate-distance, and bounding-box math;
- the exact indexed `R_DrawColumnBoomOpt` and `R_DrawSpan` implementations;
- a production-cardinality synthetic tape (1,416 columns plus 667 spans) into a
  320x200 indexed framebuffer.

Run `./build.sh`. It builds the pinned source as an 828-class MLE JAR (the two
removed console-handler classes explain the difference from the 830-class OJVM
artifact), compiles the reachable slice to an ES2015 module with TeaVM 0.15.0,
and executes the module under Node
twice to verify deterministic output. The generated module is suitable for the
same Oracle MLE loader used by `../teavm` because it has no host imports.

The local `0001-teavm-no-console-handler.patch` is the first concrete porting
seam. The actor/state graph initializes Mocha's logging facade, but TeaVM 0.15.0
lacks `java.util.logging.ConsoleHandler`. The patch preserves logger levels and
removes only the console handler/stream-collector setup, allowing all vanilla
actor metadata to stay in the executable slice. The `actor-metadata` profile
can isolate this graph while changing the patch.

`./probe-full-engine.sh` is deliberately separate. It forces TeaVM reachability
from the patched `Engine.createHeadless` through `InitNew`, `Ticker`, and
`Display`. A nonzero result is a recorded compatibility boundary, not a failure
of the green engine-slice build; inspect `target/full-engine-build.log`. To
reproduce the smaller metadata boundary directly, run
`mvn -Pactor-metadata package` in the same Maven container used by `build.sh`.
