# TeaVM resident-simulation and engine-slice result — 2026-07-22

## Resident authoritative simulation

The full pinned Mocha Doom simulation now runs as resident TeaVM-generated
JavaScript. It initializes the real vendored Freedoom 0.13.0 IWAD at exact
`sk_medium` E1M1, retains the engine graph in MLE module scope, accepts a
caller-owned `ticcmd_t`, executes the real `DoomMain.Ticker`, and returns a
deterministic renderer-independent state snapshot.

The first Oracle AI Database 26ai load/runtime gate used this artifact:

- module size: 1,126,681 bytes;
- SHA-256: `e4a8c59c449e676c1868a0f3f09ce7ec0979dad9ebb01a650f7e29f9e7a52eef`;
- TeaVM reachability: 1,277 classes and 8,458 methods;
- real-IWAD initialization: 109,744.410 ms;
- 30 warm-up plus 300 changing-input tics with full snapshots: 10.014 ms p50,
  18.342 ms p95, 32.909 ms p99, and 37.077 ms maximum;
- initial MLE state matched the Node reference exactly.

The full-snapshot p95 is above the 15 ms authoritative-ticker gate, but that
number combines simulation, snapshot construction, number/string conversion,
and call-spec return marshalling. A subsequent build adds `stepBare`, which
uses the same private command/ticker core as `step` and returns only the new
gametic. The current build was then deployed and passed the isolated Oracle
gate:

- module: `target/javascript/doom-mle-simulation-engine-headless.js`;
- size: 1,127,499 bytes;
- SHA-256: `7dfb079649f9810000bcc21e0227fcb3c068f0070e52d916386aa31dcea05f44`;
- TeaVM reachability: 1,277 classes and 8,461 methods.
- real-IWAD initialization: 108,509.049 ms;
- 30 warm-up plus 300 changing-input bare tics: 7.699 ms p50, 14.926 ms
  p95, 26.367 ms p99, and 31.321 ms maximum.

Differential OJVM/MLE replay of that build matched 14 fields through tic 86,
then found a one-fixed-unit `playerY` drift at tic 87. The source was the
host-dependent `Math.tan`, `Math.sin`, and `Math.atan` calls in procedural
`Tables.InitTables()`.

The current build removes that nondeterminism with a canonical-table pack and
passed the differential Oracle gate:

- module size: 1,158,461 bytes;
- module SHA-256:
  `c47eeeed2a0e87e69dba42985c05c7a5b1f694dd12f7f85c6f2485b4f0e4e15d`;
- TeaVM reachability: 1,279 classes and 8,530 methods;
- canonical runtime pack: 180,272 bytes, SHA-256
  `058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44`.
- same-session ticker-only OJVM/MLE differential: 14 fields plus a canonical
  save/world/reference stream and stable topology for 219 thinkers matched
  after every tic from initialization through tic 330. The tic-zero stream is
  72,418 bytes; the accepted route's first ten commands also pass deep native
  SHA-256 equality on every tic. The complete 13,272-command accepted E1M1
  route passes with deep equality every 100 tics and at the terminal state in
  5:40.29 wall time.

The build-time generator runs on the Oracle JVM inside the pinned 26ai
database container against a separate, unpatched 830-class base JAR, invokes
the pinned procedural Mocha `Tables.InitTables()`, and
writes every `finetangent`, `finesine`, `finecosine`, and `tantoangle` integer
in an explicit big-endian/versioned format. The runtime adapter accepts bounded
sequential chunks, requires the full pack before `initialize`, and installs it
before `Engine.createHeadless`. `Tables.InitTables()` decodes the canonical
data at entry so no constructor-time renderer or visibility data can observe
JavaScript-generated transcendentals. Runtime checks reject wrong magic,
version, endian marker, pack/header length, or array cardinality; the build
also locks the complete pack SHA.

The runtime pack also carries the exact 65,536-byte Freedoom translucency map.
A build-time property test boots the unmodified JVM renderer, lets its original
float/`Math.sqrt` algorithm synthesize TRANMAP, and proves byte equality (SHA-256
`0b572f2a38b231196b8c15552e21aa04c3f9a7a9ebc545b1bead53dbb44d3c3a`).
MLE installs those bytes directly. Cold initialization fell from
108.7--110.1 seconds to 76.124 seconds, while the 330-tic canonical differential
still passes. The module also shrank because TeaVM pruned the synthesis path.

The latest module adds bounded canonical RAW export and an exact durable-command
entry point for the generated 13,272-tic ledger differential. Stage timing
attributes 257--290 ms to interpreted MLE material serialization, 23--26 ms to
export, about 0.2 ms to Oracle-native SHA-256, and 1.1--1.3 ms to the warm OJVM
oracle. This is evidence-path cost; the authoritative ticker remains at the
separately measured 8--14 ms.

### Exact checkpoint recovery

Mocha's vanilla save format omits the deterministic RNG cursor and does not
preserve spatial linked-list topology or the interleaving of mobjs and special
thinkers. The first recovery attempts exposed both gaps. DMC1/v4 now wraps the
vanilla bytes with RNG state, original thinker ordering, mobj links and targets,
sector/block roots, player references, full-width mobj fields, multiplayer mode,
both consistency rings, weapon-psprite states, and mobj floor/ceiling bounds.
Its DMC1/v3 predecessor restored a 79,350-byte tic-40 checkpoint in 7,884.132 ms
in Oracle and matched the OJVM
canonical state immediately, and stayed exact for 330 continued tics through
tic 370. This proves fast rehydration into an already initialized context;
cold context startup and standby orchestration remain separate gates. The
stronger v4 Oracle gate destroys the four-player MLE context at tic 100,
rebuilds it from database-resident artifacts, restores an 89,042-byte checkpoint
in 1,818.683 ms, matches OJVM immediately, and remains exact through tic 430.
That `restore_ms` field times only `doom_teavm_sim_restore` after asset transfer
and `Engine.createHeadless`/`InitNew`; it is not end-to-end recovery latency.
The production worker gate subsequently measured the honest boundary:
97,937.651 ms cold start and 104,104.709 ms from recovery request to a ready
fresh-generation worker under the enforced 50% Free PDB cap. DMC1 correctness
passes, but the recovery SLA now explicitly requires a prewarmed retained
context; the earlier 1.8-second result must not be cited as cold recovery.
The exact-config warm primitive then restored the identical state in 2,711.117
ms. The full Scheduler lifecycle gate passed after generation-scoping standby
job names: primary cold start 99,284.397 ms, standby readiness 81,961.327 ms
after tic 32, forced generation-2 promotion/recovery 3,067.692 ms, and exact
DMD1 continuation at tic 33 with zero legacy frame rows. A replacement G2
standby was armed without colliding with the promoted G1 owner.

### Four-player simulation

The MLE adapter initializes two-to-four-player cooperative netgames, consumes
one packed command vector per tic, and maintains the same per-player consistency
ring as OJVM. Four-player OJVM/MLE state matches for 330 tics with deep checks
every 50. A 30-warmup/3,000-tic Oracle run measures 8.026/14.165/20.876 ms
p50/p95/p99, 36.729 ms maximum, and 115.03 tics/s. Seven tics exceed one slot,
but modeled backlog is 0 ms at p99 and completion, with 8.158 ms maximum.
Fresh-context DMC1/v4 recovery also passes with all four players and 330 exact
post-restore tics.

The accepted skill-1 co-op route passes the stronger two-player gate: all 762
tics match the OJVM canonical state after every transition. Its 188 vector runs
come from fixture SHA-256
`12ceaf3e7a419ab92be370c44c2c049c1d93455cbb72934502af41e355765e61`;
the exhaustive Oracle run completed in 439.88 seconds.

### Retained-session soak

The four-player retained context ran continuously for 1,800.007 seconds and
completed 230,671 tics at 128.15 tics/s. Early and late five-minute p99 were
15.7 and 11.3 ms respectively, so the tail did not degrade over time. Of all
calls, 217 exceeded one 28.57 ms slot; the maximum was 1,005.772 ms and modeled
backlog peaked at 977.201 ms, then returned to exactly zero. Session PGA stayed
at 15,907,136 bytes throughout the ticker phase with an 18,135,360-byte
high-water mark. A later controlled 64 MiB retained allocation proved those PGA
counters do not include the full MLE heap, so this run passes throughput,
backlog recovery, and late-tail stability but does not yet prove total-memory
stability. The final presentation-capable artifact must repeat it with
calibrated process RSS/PSS/private-memory sampling before production cutover.
The repeatable calibration now passes: touching a retained 67,108,864-byte MLE
buffer increased process PSS by 51,314,688 bytes and private memory by
50,880,512 bytes, above the 48 MiB visibility floor, while session PGA fell by
458,752 bytes. Release removed the reference but the Oracle process retained
the heap pages, so the final criterion is bounded/no-growth process memory over
the soak rather than immediate OS-page reclamation.

The MLE-specific `Tables.InitTables()` has no procedural fallback: it requires
the installed pack, decodes it, and returns. The former renderer
`colorDistance` path is pruned with TRANMAP synthesis. The remaining
level-geometry square roots use deterministic binary32 and scaled-integer
implementations. An emitted-artifact gate now proves zero `Math.sin`,
`Math.tan`, `Math.atan`, and `Math.sqrt` tokens. The production build enforces
the stronger category fence: every emitted `Math.*` member must be one of
`imul`, `floor`, `ceil`, `round`, `fround`, `abs`, `min`, `max`, `trunc`, or
`sign`, and computed `Math[...]` access is forbidden. The current artifact
uses only `abs`, `ceil`, `floor`, `imul`, `max`, `min`, and `sign`.

### Node candidate profile

The accepted 13,272-command ledger has a profiler-only, non-minified TeaVM
build derived from the same input JAR. Its measured ticker window completed in
726.353 ms under Node. Self-sample grouping identifies three candidates above
the five-percent review line: action/collision code at 21.3%, TeaVM `Long_*`
helpers at 18.3%, and ActiveStates method-reference paths at 13.1%. The top
single engine frames are thinker ticker (10.9%), the P_MobjThinker method
reference (10.4%), and DoomMain ticker (5.0%). Three measured-window scavenges
cost 14.32 ms; GC was 2.0% of CPU samples. These are candidate rankings only:
the MLE wall-clock harness decides whether any source or build change survives.

The emitted production artifact now has no host math call. The deterministic
binary32/scaled square-root replacement matched the pinned JVM formulas for
1,000,196 boundary and pseudorandom input pairs, and the post-change
four-player 330-tic canonical differential passes.

### Interpreter-weighted dispatch and flag audit

A direct Oracle MLE microbenchmark now measures the exact `ActiveStates`
dispatch shape rather than inferring its cost from V8. Across twenty samples
of 1,000,000 calls, the current enum `isParamType` plus generic method-reference
lookup measured 1,805.823/1,957.885 ms p50/p95. A typed table created once at
initialization measured 309.298/348.466 ms. Inspection of the emitted module
confirms that the method references themselves are initialized once; the
candidate removes repeated type testing and generic lookup, not a nonexistent
per-call closure allocation. At roughly 250 thinker calls per tic, the measured
difference predicts about 0.37 ms per tic. The measured dispatch candidate
implemented the typed tables and worker-facing generalized multiplayer
initializer as a 1,161,004-byte intermediate artifact, SHA-256
`92a3b0ca005094ba4439b0b5c4393bbd52a4306b60c827c735ad286106d2e9b7`.
It passed the uncontended A/B and canonical/762 gates. The subsequent DMC1 v5
membership-recovery correction produced the final pinned artifact identified
below; that final byte sequence repeated the canonical and 762-tic batch.
The same candidate also exposes a fixed 32-byte authoritative step that applies
the durable membership bitmap before each ticker call and rejects nonzero
commands for inactive slots; the Node smoke covers deathmatch initialization,
one-player-left membership, and invalid-mode/inactive-command rejection.
`stepMultiplayerBare`, the method used by the performance A/B and existing
differentials, retains its original compact-vector implementation without a
wrapper allocation; therefore its sole hot-path delta is typed ActiveStates
dispatch. Any differential failure is bisected against that dispatch patch
first.

The uncontended deployed A/B measured a larger 1.103 ms p50 reduction:
7.758 to 6.655 ms, with p95 improving from 13.802 to 12.401 ms and throughput
from 116.230 to 132.902 tics/s. The 0.37 ms estimate modeled one typed dispatch
shape per thinker. The real loop performs the generic `isParamType` decision at
both relevant dispatch sites for non-mobj thinkers and also pays surrounding
generic dispatch-site work that the isolated single-shape microbenchmark did
not include. The discrepancy is recorded as a limitation of the prediction,
not attributed to an unmeasured secondary code change; `stepMultiplayerBare`
remained allocation-free and otherwise unchanged.

The membership contract has a dedicated ticker-only OJVM oracle entry point
in the pinned 830-class Java 8 artifact (temporary oracle build SHA-256
`2a102cb47626108d37127358ca18a34925709914606e8d89d04be22d0d72da74`).
The executed differential runs two players with a mid-game leave, twenty exact
neutral tics, an MLE DMC1 context rebuild at tic 60, and rejoin at tic 61,
comparing full canonical SHA-256 after every tic through 100. Its final result
is recorded in the membership-recovery section below.

The `Long_*` concentration cannot safely be removed by narrowing `mobj_t.flags`
to one Java `int`: the declared flag domain reaches bit 38. The only active
reference found to a high flag is inside an explicitly unused, commented-out
thinker-classification implementation, while the pinned vanilla data remains
32-bit, but that observation is not a sufficient semantic contract for a
production narrowing. The formerly proposed low/high field split is withdrawn:
it touches the object definition, metadata, save codec, and a broad set of flag
operations. If post-dispatch MLE evidence still attributes at least five
percent to `Long_*`, the only permitted next probe is a direct MLE microbench of
TeaVM's `(int)(long)` cast shape before considering low/high-word flag-test
helpers that leave fields and codecs unchanged.

The psprite path has the same enum `isParamType(PlayerSpriteConsumer.class)`
plus generic `fun` lookup in `player_t`, but it executes only on weapon-state
transitions rather than once per thinker. It is not expanded into a separate
optimization: its scale is roughly two orders below the thinker loop and does
not justify another hot-code delta.

### Fail-closed Oracle artifact staging

Every base64/SQL*Plus MLE loader now uses a 2,000-character, four-byte-aligned
fold and a read loop that processes a final unterminated piece. Before any
`CREATE MLE MODULE`, Oracle compares both `DBMS_LOB.GETLENGTH` and an in-database
`DBMS_CRYPTO` SHA-256 against the build-side byte count and digest. The full
simulation loader independently fences the JavaScript module and canonical
table pack; the slice and dispatch loaders use the same rule. Live post-change
gates passed for the 10,485-byte TeaVM slice and 32,183-byte dispatch module.
The JDBC IWAD loader applies the same in-database length/SHA requirement to the
complete IWAD and every streamed sound/menu asset before commit. Verifier greps
make the fold, final-line loop, and SHA comparisons mandatory.

Protocol naming is deliberately split and exact: `DMD1` is one independently
chained authoritative transition envelope; `DMB1` is the capacity-controlled
batch/long-poll container for consecutive DMD1 records.

### Resource-manager evidence discipline

The live 26ai Free environment reports `CPU_COUNT=2`, active resource plan
`DEFAULT_PLAN` with CPU management enabled, and PDB plan `DEFAULT_CDB_PLAN`
with a two-CPU/two-running-session cap and `CPU_UTILIZATION_LIMIT=50`.
`resmgr:*` waits are now classified separately in slow-call ASH evidence.
Dispatch A/B and final soak runners fail before measurement when host-side
Docker builds, Java/TeaVM compiles, or end-to-end verifiers are active, and
emit an explicit host-quiescence marker. The exhaustive every-tic ledger began
before this directive and experienced concurrent build work; it is retained
as correctness-only evidence with a truthful sidecar rather than relabeled as
uncontended performance evidence.

The fresh-install runtime grants now include `DBMS_CRYPTO` and access to
`V_$RSRCPDBMETRIC`. The JDBC IWAD and derived-asset integrity code passed live
for the complete 28,795,076-byte IWAD, 69 sound assets, and 16 menu patches.
Final membership evidence records both the MLE output SHA and temporary OJVM
oracle JAR SHA; deathmatch membership recovery is explicitly a post-cutover
extension, not a new cutover gate.

### Free resource-cap decision and capacity bound

An isolated scratch container built from the exact pinned 23.26.2 image—not
the evidence database—reported `V$OPTION.Database resource manager=FALSE`.
Creating a custom CDB plan with FREEPDB1 at 100%, and separately updating the
default PDB directive, both failed with `ORA-00439: feature not enabled:
Database resource manager`. The local 50% utilization and two-running-session
cap is Free-edition enforced and cannot be promoted to 100%. The recommendation
is to freeze `DEFAULT_CDB_PLAN` as the sole local acceptance baseline; all
prior timings are 50%-cap results, while Autonomous remains separately probed.
The complete disposable-container transcript, pinned image digest, observed
PDB metric, and evidence-container non-mutation marker are retained in
`artifacts/performance/pmle-resource-cap/scratch-2026-07-23.log`.

For DMB1, the ORDS lease bound remains four held polls from pool size six with
two connections reserved. The independent runnable bound is one poll-return
path after reserving one of the PDB's two runnable slots for the retained
worker and input/control path. Held `DBMS_ALERT` waits do not imply four
simultaneous 5 ms returns. WAN tests must confirm the post-commit p95 under this
bound; zero-hold immediate batching is the required fallback beyond it. Final
soak attribution explicitly confirms or refutes `resmgr:*` throttling as a
cause of over-slot tails.

### Membership recovery correction

The first leave/rejoin differential matched through the inactive checkpoint
at tic 60 and then failed at tic 61: MLE canonical material was 79,354 bytes
versus OJVM's 78,938. The gate exposed that vanilla savegames omit the
280-byte `player_t` record for a player outside `playeringame`; DMC1 had kept
thinker references but not that hidden player record. DMC1 v5 now stores every
initialized player record independently of current membership and restores it
before topology rewiring. A Node uninterrupted-vs-recovered rejoin regression
passes byte-for-byte. The final paired-input authoritative module is 1,162,821
bytes with SHA-256
`4cc6da908df03fbd7217aa0005c167dcf78451d14803ffa627b0360ae69c7094`.
That artifact passes the 3,000-sample four-player A/B (7.005/12.662/19.034 ms
p50/p95/p99, 128.842 tics/s, zero ending backlog), the 330-tic canonical gate,
the accepted 762-tic co-op route with deep comparison every tic, and
leave/20-neutral/recover/rejoin through tic 100 with deep comparison every tic.
The final membership marker binds OJVM oracle JAR
`2a102cb47626108d37127358ca18a34925709914606e8d89d04be22d0d72da74`.
The membership gate's stale hardcoded MLE digest first failed with `ORA-20796`;
the successful rerun binds the exact digest above, proving the runtime artifact
fence rather than merely inspecting its source.

### Paired browser presentation artifact

One adapter JAR (`d80a591d68d475d54b66ae1dc3ed14aca3cae40b4218d7306268ec2d3735573`)
and one patched Mocha JAR
(`6a611ad85d09eb0fa16996cefc891e9e7dd0c7f827eaa7e93f01ccff1726bd97`)
produce two pinned ES modules. The authoritative output is the digest above.
The presentation profile produces a 1,224,315-byte module with SHA-256
`61e483d95fd980bc6ccebd1fac47be0a5ea7a96744e8d0a89ddd96ec4d57a3ff`.
Both profiles pass the emitted `Math.*` allowlist.

The presentation Node gate advanced 96 two-player tics and produced 94 unique
moving frames for each POV. Render-owned canonical mutations occurred on 18
tics; every persistent byte was exclusively the high-byte `ML_MAPPED` bit in
line flags, with zero next-tic world residue. The client therefore instantiates
two independent modules: the ticker-only copy validates the database canonical
SHA, while the presentation copy applies the same confirmed DMD1 transition
and renders. A single shared instance is rejected by the client mirror.

The real local Chromium gate SHA-verified the two modules, canonical table pack,
and 28,795,076-byte IWAD, initialized both contexts in 2,156.1 ms, advanced
both to tic 1, produced a 78,730-byte verifier canonical state, and rendered a
nonblank 64,000-byte frame. The production multiplayer entry point now consumes
one-outstanding-poll DMB1 batches and no longer invokes the legacy frame-poll
path. HUD, automap, intermission, and finale completion remain open, so this is
not yet an audit/DVR completion claim.

The first complete two-client integration runs exposed three independent
contract/performance defects and rejected each intermediate design. The client
initially hashed full canonical bytes while DMD1 carried SHA-256 of the compact
canonical digest record; the two representations were corrected and regression
bound. The initial DMD1 predecessor was also corrected from zero to the
domain-separated `SHA256(DMD1_ROOT|match|membership_epoch)` used by Oracle.
A read-committed race that could return transition `N+1` under a header
advertising frontier `N` was closed by bounding both DMB1 record queries to the
sampled frontier.

Even after those correctness fixes, per-tic `canonicalState()` measured 583.137
ms versus 6.156 ms for the authoritative step and held complete play to roughly
1.3 FPS. Production now uses a SHA-256 DMS2 replay-state chain over the prior
state identity, membership byte, and exact 32-byte command vector. DMD1's
optional full-canonical marker is absent from the hot path; exact canonical
state remains load-bearing in the completed differentials and asynchronous
audit tier. Checkpoint bytes remain independently SHA-bound, and generation-2
recovery deterministically recomputes DMS2 from the durable ledger.

Finally, Free's two-runnable-session cap rejected two held long polls, and even
zero-hold requests collapsed throughput when unconditional `DBMS_ALERT.SIGNAL`
contended on UL locks. `long_poll_enabled` is therefore an explicit capacity
setting, default-off for Free. Zero-hold batching performs no DBMS_ALERT work;
the separately enabled long-poll contract still passes at 1.791 ms in its
single-game capacity fixture.

The final real two-browser run measured 35.042 and 35.034 displayed FPS, with
38.0/35.0 ms p99 presentation gaps, 110 confirmed transitions per client, and
a converged two-tic playout buffer. The exact worker then repeated checkpoint
tic 32 and generation-2 recovery in 3,353.507 ms with zero legacy frames.

### Superseded cutover artifact and acceptance packet

Checkpoint-output reuse and the additive worker/presentation exports produce
the final pinned pair from one input adapter JAR:

- authoritative module: 1,163,182 bytes, SHA-256
  `06ac33331d9a9158d63fba2da4688ad5d3ff30c316b4c20c09e38d77d3fdebf0`;
- presentation module: 1,224,686 bytes, SHA-256
  `bd35d27784db2332e1c06f08a7eeb8940b1a17a732bfb45de0b4b3b42d419b83`;
- input adapter JAR: SHA-256
  `8cae68323d62edfa56299569d15763e6dbd24974dc3a24f3ae64961071920d8b`;
- patched Mocha bytecode: SHA-256
  `6a611ad85d09eb0fa16996cefc891e9e7dd0c7f827eaa7e93f01ccff1726bd97`;
- OJVM differential oracle JAR: SHA-256
  `2a102cb47626108d37127358ca18a34925709914606e8d89d04be22d0d72da74`;
- canonical table pack: 180,272 bytes, SHA-256
  `058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44`.

`versions.lock` binds the profiles, TeaVM 0.15.0, ES2015 target, ADVANCED
optimization, minification, both outputs, both input bytecode digests, the
checkpoint format, and the differential oracle as one provenance set.

Every determinism PASS cited for cutover was rerun against that final
authoritative module, table pack, and OJVM oracle. The canonical 330-tic route,
762-tic co-op every-tic route, membership leave/neutral/checkpoint/rejoin
differential, and stale-SHA `ORA-20796` fence pass on the final bytes. The final
no-overwrite exhaustive ledger then passed all 13,272 commands with full
canonical comparison after every tic:

### Headless-authority init-diet promotion — 2026-07-23

The accepted Tier 2 batch retains the authority's texture/flat name
directories needed by switches and animations but skips patch-composite
assembly, sprite definitions, colormaps, tranmap, translations, drawing
functions, and screens; the authority also registers/parses the injected WAD
once instead of twice. The full browser presentation artifact retains renderer
initialization.

The promoted authority is 1,167,197 bytes, SHA-256
`a942cd2dcbdc8fa523a51af27aefc778ea9fbbebfe93f0a03fe4856c6df6c8e2`;
the paired presentation artifact is 1,232,713 bytes, SHA-256
`d45863e0c1be8fabdc63086fafc5d9d57193c4ed5758f259cd92af360426b39c`.
Both derive from input adapter JAR
`5194b73d7196804957221216052b552305632c943e8ea402327a220b326d0e06`
and patched Mocha bytecode
`42b25147133bb5c84c3b19c1511583bbd36219fb2a68996244106f40078f943e`.

Isolated MLE cold initialization measured 4,541.733 and 4,825.980 ms,
comfortably inside the 30-second gate and roughly 95% below the prior
100.314-second authority baseline. Canonical 330, accepted 762-tic co-op,
membership leave/neutral/checkpoint/rejoin, and the 13,272-command exhaustive
every-tic ledger all pass against the preserved OJVM oracle. Production load,
runtime SHA fence, and all ten E1M1 tic-zero checkpoint-bank entries passed
database-side length/SHA verification. Concurrent deploy prewarm reached two
READY slots in 34.669 seconds under Free's one-effective-CPU/two-session cap;
warm admission measured 4.341 seconds and the real `/play` path reached its
first confirmed frame 5.223 seconds after New Game confirmation.

The prior 30-minute production-shaped soak remains valid evidence for its
`06ac3333…` artifact and for the harness/platform baseline only. The final
promoted-artifact rerun below supersedes it for cutover evidence.
HUD/automap/intermission/finale and asynchronous audit/DVR completion remain
honestly open.

```text
PMLE_TEAVM_LEDGER_DIFFERENTIAL|PASS|tics=13272|deep_every=1|route_runs=1152|vector_runs=1246
PMLE_LEDGER_PROVENANCE|CONFIRMED|executions=1|terminal_markers=1
```

The allocation-free checkpoint serializer first matched its predecessor
byte-for-byte at tics 32, 1,024, and 2,048. That is smoke coverage, not the
equivalence gate. The named end-to-end gate is the final-artifact membership
differential: it exports the rewritten DMC1 v5 checkpoint, releases/rebuilds
the MLE context, restores, rejoins, and continues against OJVM after every tic.
The production-shaped soak independently exercises periodic checkpoint
publication and standby reconstruction for the full run.

The final process-memory soak used an isolated 128 MiB page-touched calibration.
PSS rose by 134,949,888 bytes and private memory by 134,344,704 bytes while
PGA stayed flat, proving `/proc/<spid>/smaps_rollup` sees the JS heap. After a
300-second excluded warmup, authority plus standby plus two real browser
clients ran for 1,800 scored seconds:

- authority PSS: 464,108,544 baseline; 518,277,120 maximum; 434,509,824 end;
- standby PSS: 442,265,600 baseline; 483,700,736 maximum; 413,642,752 end;
- both stable-SPID RSS/PSS/private gates remained below baseline + 67,108,864;
- zero browser reconnects and zero legacy Java frames; maximum confirmed
  presentation lag was 18 tics.

The attribution harness recorded 1,486 ASH samples covering calls above
100 ms and found zero `resmgr:cpu quantum` samples and zero commit-I/O
attribution. The specific resource-manager-tail hypothesis is therefore
refuted for this run: captured tails were primarily sampled `ON CPU`.
This does not project uncapped-tier performance; the Free-edition result is
reported under the enforced 50% PDB utilization and two-running-session cap.

### Promoted-artifact soak abort and lifecycle hardening — 2026-07-23

The first `a942cd2d…` final-soak attempt is **VOIDED**, not failed or passed.
After 300 excluded warmup seconds and 155 scored seconds, the authority process
was replaced. The legacy harness cleanup then stopped/dropped shared warm-pool
jobs before preserving its browser log, so that run could not prove its own
cause. A shorter pre-hardening diagnostic preserved the browser verdict
(5,397 player-0 frames in 300 seconds, below the gate) but is also VOIDED. Both
logs ship with terminal `VOIDED` markers and are excluded from acceptance.

The partial promoted-artifact memory window nevertheless records the init-diet
capacity improvement: authority/standby PSS occupied approximately 262–312 MiB
instead of the prior 462–518 MiB envelope. The full 30-minute run must still
prove that the observed roughly 50 MiB authority rise reaches a plateau inside
the fixed 64 MiB ceiling; this partial window cannot widen that margin.

Lifecycle hardening now routes every Scheduler stop through one durable intent
gateway. Warm slots bind incarnation token, SID, serial#, SPID, and job-run
token; `run_warm_slot` is the normal lifecycle writer, while a 30-second
janitor is the bounded stale-row exception. A live four-scenario gate passed:
incarnation mismatch rejected, cooperative stop honored, stale row reconciled,
and non-cooperative job force-stopped/reset after the five-second honor
deadline. The test also caught and fixed a missing `intent_id` predicate that
could have rewritten older terminal intent rows; all three terminal statuses
were rechecked after pool restart.

Deploy prewarm now retires both old incarnations, warms authority first, admits
when it is ready, and only then warms standby. Under the edition cap the live
measurement was 28 seconds to first-admittable and 55 seconds total. The
post-hardening causal soak then passed 180 scored seconds after the required
300-second excluded warmup: 6,286/6,287 unique client presentations (34.9
FPS), zero reconnects, stable SPIDs/incarnations, and zero process replacement.
Authority RSS/PSS/private ended below baseline; standby stayed within 9 MiB
RSS and 5 MiB PSS. Shared-dirty attribution was flat enough to produce zero
8-MiB plateau steps.

Two diagnostic failures leading to that pass remain in evidence. A 60-second
warmup put the RSS baseline before the Oracle `/SYSV` SGA working set was
touched; the resulting 124-MiB RSS rise decomposed to only 38 MiB PSS and
30 MiB private, with the excess confirmed in the shared SGA mapping. A later
five-minute run exposed Chromium background-tab timer throttling because the
two simulated user devices shared one headless browser process. A direct
5,000-tic Chromium profile measured only 0.04 ms verifier step, 0.04 ms
presenter step, and about 1.0 ms render per tic. The harness now disables
background/occluded renderer throttling so both pages model foreground clients;
no application gate or memory margin changed. The clean 30-minute
`a942cd2d…` soak below closes the acceptance gate.

### Final promoted-artifact soak — 2026-07-23

The lifecycle-hardened `a942cd2d…` authority passed the final production-shaped
soak under a quiet host and the recorded Free-edition envelope
(`DEFAULT_CDB_PLAN`, 50% PDB utilization on two CPUs, two running sessions).
The run excluded 300 warmup seconds, then scored 1,800 seconds with one
authority, one standby, and two real confirmed-only browser clients:

- both retained worker SPIDs and full incarnation tuples stayed stable and
  returned to `READY` after cleanup;
- the clients presented 58,875 and 58,858 confirmed updates, advanced 59,255
  and 59,256 tics, had zero reconnect time, and never exceeded 17 tics of
  confirmed-frontier lag;
- authority PSS was 326,010,880 baseline, 376,375,296 peak, and 300,486,656
  end; private memory was 237,096,960 baseline, 288,854,016 peak, and
  221,904,896 end;
- standby PSS was 231,512,064 baseline, 238,575,616 peak, and 238,160,896
  end; private memory was effectively flat at 172,462,080 baseline,
  172,544,000 peak, and 172,335,104 end;
- both roles passed the unchanged absolute `baseline + 67,108,864` byte
  RSS/PSS/private ceiling. The authority peak was transient and ended below
  baseline. Standby RSS growth decomposed into shared-dirty SGA pages while
  its calibrated heap-visible PSS/private counters stayed flat.

The slow-call attribution captured 1,457 ASH samples. It found zero
`resmgr:cpu quantum` and zero commit-I/O samples; captured outliers were
predominantly sampled `ON CPU`. The largest client paint p99.9 windows were
2,169.1 and 2,371.1 ms, but both confirmed replicas caught up without
reconnect, chain poison, process replacement, or ending backlog. These rare
Free-edition presentation tails are recorded, not projected onto an uncapped
tier.

The next qualified transport run uses long-polling enabled with its
cloud-shaped ORDS pool configuration recorded in evidence. It adds a
backgrounded-then-refocused client scenario. Product hidden-tab behavior is:
suspend presentation while hidden, batch catch-up on focus, checkpoint resync
past a bounded staleness threshold, and release poll lease/capacity after
prolonged hiding; a hidden client may never hold the guaranteed runnable
poll-return path. Before optimizing deploy admission, the measured 28-second
authority-first prewarm is decomposed into staging, engine initialization, and
checkpoint-bank construction. Building only the default solo/skill-3 entry
before admission remains optional and evidence-gated.

The build-review dashboard now consumes a generated, evidence-validated
`mle-status.json`, publishes the final pair and gate states, links to the MLE
single-player/multiplayer clients, and labels WAN, Java audit, presentation/DVR,
and ADB work honestly. A live Chromium gate passed against the local ORDS
document root with no console or page errors.

The Java-removal audit has a deliberately narrow scope: OJVM must be absent
from the production worker path, deployed production schema, and cloud
manifest. The OJVM oracle remains in repository and development tooling as the
permanent differential instrument; deleting it is prohibited and is not a
cutover task.

### MLE-only FixedMul closure

Every `fixed_t.FixedMul` overload now delegates to one allocation-free helper
which decomposes each signed operand into 16-bit high/low limbs. It reconstructs
the low 32 bits of the Java `long` product shifted by 16 using only wrapped
32-bit multiplies, additions, masks, and shifts. This change exists only in the
MLE headless patch; the base/OJVM source remains unchanged.

The Oracle-JVM build property test checks all six public/in-place overload paths
against the original signed and unsigned `long` expressions. It covers 23 × 23
boundary pairs plus 1,000,000 deterministic pseudorandom pairs: 1,000,529 total
with checksum `-448958198`. The generated TeaVM module independently computes
the same vector checksum under Node and matches exactly before the real-IWAD
smoke begins. Bytecode inspection of the shared helper contains `imul`/`iadd`
and integer shifts only—no `i2l`, `lmul`, or long shift helper.

`FixedDiv` remains the significant fixed-point long helper in the live hot
path: its exact branch still performs `i2l`, `lshl`, and `ldiv`. `FixedDiv2`
also retains the original long implementation in the source JAR but has no
call sites and is pruned from this TeaVM reachability graph. A double-numerator
rewrite was intentionally rejected: exact representation of the shifted
numerator does not prove that rounded floating division will always truncate
to the same integer as Java division.

The sustained server-side gate ran 3,000 changing tics after 30 warmups. It
measured 8.213/13.810/17.381 ms p50/p95/p99, 29.308 ms maximum, and 114.314
tics/second against Doom's required 35. Only three samples exceeded the 28.57
ms slot. A paced backlog model measured 0 ms at p99, 0.737 ms maximum, and 0 ms
at the end of the run. This establishes that the real authoritative ticker is
viable in the local interpreted MLE tier and catches up after isolated tails;
compact persistence output and the long worker soak remain open.

The stronger digest initially found a tic-1 mismatch when the existing OJVM
entry point performed `Ticker()` followed by `Display()` while MLE performed
only `Ticker()`. A ticker-only OJVM oracle then matched exactly. The mismatch is
therefore presentation state serialized by the vanilla save codec, not an
authoritative simulation transition. Renderer parity remains a separate gate.

The real-IWAD Node gate proves two independent full-snapshot runs are
identical, proves the full and bare exports produce exactly the same state for
the same commands, then advances 300 additional bare tics. At tic 302 the
deterministic state is player position `(-22424327, 8475639, 131072)`, angle
`1736441856`, RNG index 111, and leveltime 302. The inexpensive retained-state
inventory after the Oracle route reports a 28,795,076-byte IWAD, 64,000-byte
frame buffer, 218
thinkers, 1,196 vertices, 2,057 segs, 182 sectors, 682 subsectors, 681 nodes,
1,175 lines, and 1,829 sides.

Exports are `allocateIwad`, `loadIwadChunk`, `allocateTablePack`,
`loadTablePackChunk`, `initialize`, `step`, `stepBare`, `currentState`,
`canonicalState`, `memoryDiagnostic`, and `release`.
`0002-teavm-simulation-headless.patch`
keeps the complete game-action switch, demo command paths, intermission and
finale tickers, status-bar lifecycle, all 15 action-trait contexts, and the
real level/thinker/actor/collision/weapon/RNG implementations. Its replacements
are confined to unavailable desktop/presentation facilities such as AWT,
audio/MIDI, parallel renderers, HUD/automap drawing, screen blits, and art
loading. Under the user-approved 2026-07-22 role-swap amendment, this retained
module is the selected authoritative simulator. Live presentation will use a
render-only browser mirror driven by ordered database deltas; exact MLE
rendering remains the asynchronous audit/DVR tier.

## Earlier executable engine-slice result

The pinned Mocha Doom Java bytecode can be translated into an Oracle MLE-loadable
ES2015 module substantially beyond the original `Tables` proof. The green slice
contains 185 reachable classes and 1,263 methods and emits a 138,872-byte module:

- module: `target/javascript/doom-mle-engine-slice.js`
- SHA-256: `dadb62ba798ea40e2298e50db8ff7be93e4fc66d68da24dc8a9897d5699eb1ec`
- exports: `main`, `simulationChecksum`, `renderCommandChecksum`,
  `combinedChecksum`
- deterministic results: simulation `-72999817`, render commands `-503651723`,
  combined `1392844156`

`build.sh` rebuilt the patched engine from the pinned revision, compiled the
slice with TeaVM 0.15.0, and executed all three exported checksums twice under
Node. The same generated module was then loaded by the parent task into Oracle
AI Database 26ai MLE; all three MLE results matched Node exactly.

The slice is meaningful engine code, not a rewritten facsimile. It reaches:

- all vanilla `data.info.states` and `data.info.mobjinfo` records and their
  `ActiveStates` action identifiers;
- `DelegateRandom`, the exact eight-byte `ticcmd_t` packer, `Tables`, `BBox`,
  `fixed_t`, `divline_t`, and `MapUtils`;
- the upstream indexed `R_DrawColumnBoomOpt.Indexed` and `R_DrawSpan.Indexed`
  implementations over a 320x200 framebuffer;
- a synthetic workload sized from observed real frames: 1,416 column commands
  and 667 span commands.

## Required compatibility patch

TeaVM does not implement `java.util.logging.ConsoleHandler` or all of the
`Logger` configuration methods used by Mocha's static logging setup. The local
`0001-teavm-no-console-handler.patch` removes the console handler and makes the
logger factory use `Logger.getLogger` only. No game state, action metadata,
fixed-point code, input codec, or raster code is changed. Removing the handler
and its generated helper changes the probe JAR from 830 to 828 classes.

This patch closes the first exact simulation reachability blocker. The isolated
`actor-metadata` profile now compiles successfully: 153 classes and 926 methods.

## Full-engine boundary

`probe-full-engine.sh` forces reachability from patched
`Engine.createHeadless` through `InitNew`, `Ticker`, and `Display`. It still
fails deterministically with 152 TeaVM error lines, including 115 missing-class
diagnostics. The logging errors are gone. Remaining families are:

- AWT/image: `Canvas`, `Dialog`, `GraphicsEnvironment`, `Rectangle`, `Robot`,
  `BufferedImage`, `IndexColorModel`, and `ImageIO`;
- desktop audio/MIDI: `AudioSystem`, `SourceDataLine`, `Clip`, `MidiSystem`,
  `Sequencer`, and `Receiver`;
- concurrency: `Semaphore`, `CyclicBarrier`, `Executors`, and `ForkJoinPool`;
- file APIs: `FileInputStream.getChannel()`.

The next porting boundary is therefore an MLE-specific engine composition root,
not more TeaVM flags: instantiate the ticker/world graph without referencing
desktop video, desktop sound, parallel renderers, configuration files, or the
desktop `Engine` class. The existing database-injected IWAD stream and dummy
sound/video implementations provide most of the required seams.

## Earlier engine-slice MLE performance observation

The earlier 26ai MLE execution measured a warmed `simulationChecksum`
average of 69.242 ms and one `renderCommandChecksum` execution at 393.901 ms.
These methods are compatibility stress tests, not one real ticker: the former
rescans all actor/state metadata and reinitializes tables, while the latter
executes 2,083 Java raster commands in interpreted MLE. The render result is
evidence that naively transpiling thousands of individual pixel-loop commands
does not meet a 30 FPS target. It is slice-level evidence only: the resident
simulation result above supersedes it for ticker feasibility, while exact
in-database frame generation still requires its own measured implementation.

## Commands

```sh
./probes/mle/teavm-engine/build.sh
./probes/mle/teavm-engine/build-simulation.sh
./probes/mle/teavm-engine/probe-full-engine.sh  # expected nonzero; see target log
```

## Presentation HUD candidate — 2026-07-23

The pinned Oracle 26ai JDK build now renders the canonical 32-pixel Doom
status bar for both confirmed player POVs. TeaVM's headless desktop status
lifecycle left the `SB` buffer empty even though `STBAR` decoded correctly, so
the presentation-only adapter composes the immutable `STBAR` and `STFBn`
backgrounds directly into the indexed foreground and calls Mocha's own
retargeted widget renderer through an explicit abstract-status-bar bridge.

The 96-tic Node gate passed with 93 unique moving frames per POV. POV 0's HUD
contained 10,240 nonzero pixels across 45 palette indices with SHA-256
`3247c00d3ed00f57dd2cc6d14a2e314f5ae2a466e00c816ac721e765165d759a`;
POV 1 contained 10,240 across 43 indices with SHA-256
`b44d33e0e43969b2562d41a8e8d2396b28ca21dbe16b20724b26a34e7724426d`.
The next-tic authoritative residue remained zero.

This is an unpromoted candidate. Its Oracle-JDK presentation artifact is
1,228,582 bytes with SHA-256
`af6e526a5d4bfac15d2e926a604b7fd5afc386594e34dad01fb382229233f618`.
The shared compatibility bridge also changes the authority candidate to
SHA-256 `1e940a38c9d5131811bed81e886fdb153196e7af3298ff7471bb531629579d7e`.
`versions.lock`, browser assets, and production remain on the accepted
`06ac3333…`/`bd35d277…` pair until the canonical and 762-tic differential
batch passes for the changed authority artifact.

## Live match-admission contention correction — 2026-07-23

A real second single-player launch exposed a lifecycle/capacity mismatch that
the isolated soak did not cover. An abandoned match had reached terminal host
membership and its authority correctly failed with `ORA-20731`, but its
generation-matched standby remained `READY`. A subsequent match then ran its
authority and a second standby alongside that leaked context: three retained
MLE jobs competed under Free's two-running-session limit. The new solo
authority eventually sustained 35.88 tics/s, but cold admission appeared
frozen for minutes.

The source correction makes terminal host membership finish and immediately
expire the match while signaling its standby to stop. `MAX_ACTIVE_MATCHES=1`
now freezes the honest Free-edition game capacity in both creation and worker
admission; larger deployments must raise it only with separate capacity
evidence. The browser records its current solo capability and retires that
authority before starting another New Game. A migration fallback recognizes
older solo credentials without touching co-op hosts. Two live leaked terminal
matches were fenced by their exact error and cleaned up; both standbys reached
`STOPPED`. A subsequently created two-browser co-op match reached
authority/standby `READY` and tic 938. The new package bodies remain a source
candidate until that live match exits, because replacing a package used by a
retained session would invalidate the game being reviewed.

The same audit found that standby promotion was still triggered only by the
retired frame-poll API. The production DMD1 transition poll now fences the
worker heartbeat/status, initiates `recover_match`, and returns retryable
capacity while the exact frontier is promoted. Confirmed-only browser input
and transition loops preserve their queued input/frontier across
429/502/503/504 recovery responses and resume without prediction. This closes
the source-level production recovery trigger; forced live promotion remains a
required post-deployment gate.

## Authority-ready admission and initialization profile — 2026-07-23

The authority-ready contract is now deployed for every live mode, not only the
one-player wrapper. A fresh local Free solo gate reached `ACTIVE` in 100,314 ms
at generation 1/tic 18 while the new status output reported the recovery
context as `WARMING`. This proves admission waits for one cold authority rather
than serializing authority and standby initialization. Match status now exposes
`ABSENT`, `WARMING`, `READY`, `PROMOTING`, or `DEGRADED`; the browser shows that
state and uses bounded 500 ms, 1 s, 2 s, then 5 s lobby polling.

The exact deployed artifact's Node profile explains the remaining delay.
Against a roughly 1,135 ms Node initialization, `R_InitTextures` consumed
645 ms (57%), `InitSprites` 188 ms (17%), engine construction/class
initialization 185 ms (16%), and duplicate WAD-directory parsing roughly
110 ms (10%). The dominant functions were case-insensitive lump-name string
operations, typed-array/stream allocation, and garbage collection (16.6%).
The ratio-validated local MLE multiplier is approximately 83x, matching the
98–100 second live cold start.

An executable Node probe additionally proved that a retained E1M1 HMP co-op
context can restore byte-identical tic-zero DMC1 state for another skill and
for deathmatch on E1M1. A deliberately attempted E1M2 restore failed closed on
the current pre-`InitNew` sector-count fence, so the first deploy-time prewarm
pool is explicitly E1M1-scoped.

## Deploy-time E1M1 warm-pool admission — 2026-07-23

The production bootstrap now loads a database-SHA-verified bank of ten DMC1
tic-zero checkpoints (COOP/DEATHMATCH × skills 1–5) and starts two retained MLE
slots. A slot is admitted only after completing the pinned authority's cold
initialization. `CREATE_MATCH` never creates a third cold context: it either
claims a ready slot or returns a retryable starting/capacity state. Authority
readiness admits play while the second slot restores the same exact origin in
the background; `MATCH_STATUS` exposes that interval as `WARMING`, then
`READY`.

Ten consecutive live create/ready/status/leave cycles covered both modes and
all five skills. Admission measured 2,985–3,440 ms, with p50 3,100 ms and
observed p95/max 3,440 ms against the <=5,000 ms product gate. A separate
retained-match gate observed standby recovery transition `WARMING → READY`
after eight 500 ms polls. The original 100.314-second cold-authority result
remains the honest no-pool baseline; cold work has moved to deployment instead
of being hidden or removed.

The pool deliberately covers E1M1 only. Cross-map restoration remains fenced
until a map-specific bank or post-static-state engine image is accepted. The
next determinism-sensitive artifact batch is the headless-init diet; it is not
part of this lifecycle-only promotion.
