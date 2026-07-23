# PMLE Oracle 26ai MLE/PLSQL renderer feasibility

Date: 2026-07-22

## Superseding production-shaped result

The initial cached-column decision below has been superseded by the real draw
cardinality and end-to-end probes completed later the same day. It remains in
this report as the reproducible sequence of experiments, not as the selected
production architecture.

Disposable Mocha instrumentation measured a representative frame at 1,416
column calls, 667 span calls, and about 45,363 rasterized pixels. Nearly every
draw command was unique, invalidating the 320-column cache assumption. The
production-shaped experiments then measured:

```text
PMLE_TAPE|mle_production_cardinality_blob|bytes=33328|columns=1416|spans=667|p50_ms=30|p95_ms=70
PMLE_TAPE|mle_cached_blob_egress|bytes=33328|columns=1416|spans=667|p50_ms=10|p95_ms=20
PMLE_FFI_BATCH|draw_commands=2083|bytes=33328|p50_ms=10|p95_ms=20|p99_ms=40
PMLE_FFI_RASTER|draw_commands=2083|target_pixels=45363|frame_bytes=64000|p50_ms=110|p95_ms=190
PMLE_BIND|non_pure_session_execute_blob|bytes=64000|batch=20|samples=30|p50_ms=3.794|p95_ms=4.561|p99_ms=5.680
PMLE_TEAVM_ENGINE|simulation=-72999817|warm_avg_ms=69.242
PMLE_TEAVM_ENGINE|render=-503651723|one_warm_invocation_ms=393.901
PMLE_TEAVM_SIMULATION_LOAD|bytes=1129556|table_pack_bytes=114732
PMLE_TEAVM_TICKER_INIT|iwad_bytes=28795076|wall_ms=109744.410
PMLE_TEAVM_TICKER|warmup=30|samples=300|p50_ms=10.014|p95_ms=18.342|p99_ms=32.909|max_ms=37.077
PMLE_TEAVM_TICKER_BARE|warmup=30|samples=300|p50_ms=7.699|p95_ms=14.926|p99_ms=26.367|max_ms=31.321
PMLE_TEAVM_DIFFERENTIAL|PASS|tics=330|fields=14
PMLE_TEAVM_DIFFERENTIAL|PASS|tics=330|fields=14|canonical=native-sha256-save-world-plus-references
PMLE_TEAVM_TICKER_BARE|warmup=30|samples=3000|p50_ms=8.213|p95_ms=13.810|p99_ms=17.381|max_ms=29.308|throughput_tps=114.314|over_slot=3|backlog_p99_ms=0|backlog_max_ms=0.737|backlog_end_ms=0
PMLE_TEAVM_SIMULATION_LOAD|bytes=1158461|table_pack_bytes=180272
PMLE_TEAVM_TICKER_INIT|iwad_bytes=28795076|wall_ms=76124.354
PMLE_TEAVM_TICKER_BARE|warmup=30|samples=3000|p50_ms=8.231|p95_ms=13.999|p99_ms=18.254|max_ms=39.806|throughput_tps=111.997|over_slot=6|backlog_p99_ms=0|backlog_max_ms=11.235|backlog_end_ms=0
PMLE_CANONICAL_STAGE|stage=mle-material|warm_ms=256.833-290.288|bytes=72418
PMLE_CANONICAL_STAGE|stage=mle-export|warm_ms=22.708-25.895
PMLE_CANONICAL_STAGE|stage=native-hash|warm_ms=0.189-0.235
PMLE_CANONICAL_STAGE|stage=ojvm-material|warm_ms=1.080-1.328
PMLE_TEAVM_LEDGER_DIFFERENTIAL|PASS|tics=10|deep_every=1|route_runs=1152|vector_runs=4
PMLE_TEAVM_LEDGER_DIFFERENTIAL|PASS|tics=13272|deep_every=100|route_runs=1152|vector_runs=1246|wall=5:40.29
PMLE_TEAVM_LEDGER_DIFFERENTIAL|PASS|tics=13272|deep_every=1|route_runs=1152|vector_runs=1246
PMLE_TEAVM_RECOVERY|PASS|checkpoint_tic=40|checkpoint_bytes=79350|checkpoint_sha256=fb6affd31bf9612e148f55376ccb803459e6184bf20eb84725bf29255892038b|restore_ms=7884.132|continued_tics=330|final_tic=370
PMLE_TEAVM_MULTIPLAYER|PASS|players=4|tics=330|deep_every=50
PMLE_TEAVM_MULTI_RECOVERY|PASS|players=4|fresh_context=1|checkpoint_tic=100|checkpoint_bytes=89042|restore_ms=1818.683|continued_tics=330|final_tic=430
PMLE_WORKER_CUTOVER|PASS|tics=33|checkpoint_tic=32|recovery_generation=2|dmd1=33|legacy_frames=0|engine=MLE|cold_start_ms=97937.651|cold_recovery_ms=104104.709
PMLE_WARM_RESTORE_CANDIDATE|PASS|init_ms=98301.253|warm_restore_ms=2711.117|config_fence=PASS|checkpoint_bytes=88378
PMLE_WORKER_CUTOVER|PASS|tics=33|checkpoint_tic=32|recovery_generation=2|dmd1=33|legacy_frames=0|engine=MLE|cold_start_ms=99284.397|standby_wait_ms=81961.327|warm_recovery_ms=3067.692
PMLE_WORKER_CUTOVER|PASS|tics=33|checkpoint_tic=32|recovery_generation=2|dmd1=33|legacy_frames=0|engine=MLE|public_admission=STANDBY_READY|pre_admission_command=REJECTED|cold_start_ms=197681.124|standby_wait_ms=.633|warm_recovery_ms=3794.754
PMLE_TEAVM_MULTI_INIT|players=4|iwad_bytes=28795076|wall_ms=76489.680
PMLE_TEAVM_MULTI_TICKER|players=4|warmup=30|samples=3000|p50_ms=8.026|p95_ms=14.165|p99_ms=20.876|max_ms=36.729|throughput_tps=115.030|over_slot=7|backlog_p99_ms=0|backlog_max_ms=8.158|backlog_end_ms=0
```

The TeaVM engine slice is real pinned Mocha bytecode: 185 reachable classes,
1,263 methods, actor/state metadata, deterministic RNG and ticcmd code, fixed
and BSP math, plus `R_DrawColumnBoomOpt` and `R_DrawSpan`. Its Node and Oracle
MLE checksums match exactly. This proves Java-bytecode-to-MLE deployment, while
the measured renderer time rejects executing the pixel functions in MLE. A
subsequent full-ticker TeaVM profile compiled 1,277 classes and 8,467 methods
with zero reachability errors. Its 1,129,556-byte ES module loaded successfully
as a stored module in the same local 26ai database. It preserves the complete
game-action switch, demo paths, and level/intermission/finale/demo tickers;
only presentation-only desktop operations are stubbed. Real IWAD bootstrap and
ledger differential execution remain required before simulation parity is
proved. The module then booted the real 28,795,076-byte IWAD inside MLE and ran
330 changing E1M1 tics. The 300 measured calls include construction and
marshalling of the full diagnostic snapshot; their 18.342 ms p95 misses the
provisional 15 ms simulation-plus-delta budget. The shared-core `stepBare`
export isolates simulation from that diagnostic serialization and measured
7.699/14.926/26.367 ms p50/p95/p99. After replacing the live `FixedMul` long
intermediate with a property-proved 32-bit limb implementation, a sustained
3,000-tic run measured 8.213/13.810/17.381 ms p50/p95/p99 and 114.314 tics/s.
Only three calls exceeded a 35 Hz slot; modeled backlog was 0 ms at p99, 0.737
ms maximum, and 0 ms at completion. Compact persistence output and worker soak
still require end-to-end proof.

The canonical runtime pack was then extended with the exact 65,536-byte
Freedoom TRANMAP. A direct property test matched the unmodified JVM renderer's
synthesis byte-for-byte. Loading it with the trig tables reduced MLE cold
initialization from 108.7--110.1 seconds to 76.124 seconds. The repeated
3,000-tic gate remained healthy at 111.997 tics/s with zero ending backlog, and
the 330-tic deep OJVM/MLE differential remained exact.

The comparator now exports one versioned canonical material stream and hashes
the resulting BLOB with Oracle's native SHA-256. Native hashing costs only
about 0.2 ms warm, but interpreted MLE save/world serialization remains
257--290 ms and bounded RAW export 23--26 ms. Exhaustive per-tic ledger
evidence is therefore a long-running test, not a live-path operation; it does
not affect the measured 8--14 ms authoritative ticker. The accepted-route
harness passed its first ten commands with deep equality on every tic and also
supports periodic checkpoints for the complete route. The full accepted route
then passed all 13,272 commands with deep comparison every 100 tics and at the
terminal state in 5:40.29 wall time. The unattended exhaustive run subsequently
passed the same 13,272 commands with canonical comparison after every tic. Its
sidecar confirms exactly one execution and terminal marker; the SQL*Plus log
wrapped the marker across two physical lines and truthfully records that the
pre-directive run shared the host with concurrent builds.

The first checkpoint recovery attempt correctly failed because the vanilla
save omitted the RNG cursor; the next exposed its mobj/special thinker
reordering. DMC1/v4 adds those missing authoritative fields, spatial/list
topology, multiplayer mode, both consistency rings, weapon-psprite states, and
mobj floor/ceiling bounds. Its v3 predecessor restored the resulting
79,350-byte checkpoint in 7,884.132 ms in Oracle,
matched the OJVM canonical state at tic 40, and remained exact for 330 more
tics. This establishes rehydration into a pre-initialized MLE context, not yet
the complete standby-worker lifecycle or cold-start SLA.

DMC1/v4 then passed the stronger lifecycle gate with four players: the test
checkpointed at tic 100, released all MLE engine/IWAD/table state, rebuilt a
fresh context from Oracle-resident artifacts, restored 89,042 bytes in
1,818.683 ms, matched OJVM immediately, and remained exact for 330 more tics.
The 1,818.683 ms interval begins only after asset transfer and full engine
initialization. The scheduled production-worker gate later measured the complete
request-to-ready boundary at 104,104.709 ms (cold start 97,937.651 ms) under
the enforced 50% Free PDB cap. It passed DMD1/DMC1 continuity and produced zero
legacy frame rows, so functional Java removal is proven; recovery performance
is not. A prewarmed retained-context promotion gate is now required.
That gate now passes. An independently initialized, exact-config retained MLE
session promoted from standby to generation 2 and completed recovery in
3,067.692 ms, then committed tic 33 on the existing DMD1 chain. Standby job
names include their base generation, so the promoted G1 owner can arm a G2
replacement without targeting its own Scheduler job. Cold fallback remains
available when no ready standby or tic-32-or-later DMC1 checkpoint exists.

The first standby result also exposed an admission-semantics hole: the database
row and API became `ACTIVE` after the primary's approximately 99-second cold
start while its approximately 82-second recovery context was still warming.
The production worker now keeps its control row `STARTING`, does not enter the
paced/lockstep authority loop, rejects both scalar and batched commands, and
maps the public status to `STARTING` until the generation-matched standby is
`READY`. The strengthened live gate observed the durable tic-zero/STARTING
window, verified the public state, and proved a tic-1 command was rejected.
Only then did it admit the match. Total first admission was 197,681.124 ms on
the enforced 50% PDB baseline; once admitted, standby readiness was already
present (0.633 ms lookup) and forced generation-2 recovery took 3,794.754 ms.
Thus the warm-recovery SLA now applies to the entire publicly playable
interval, while the approximately 198-second first-admission cost is explicit
rather than hidden.

Four-player cooperative simulation then matched OJVM for 330 tics with deep
checks every 50. Its 3,000-tic run sustained 115.03 tics/s at 8.026/14.165/
20.876 ms p50/p95/p99. Backlog remained zero at p99 and completion, proving
that multiplayer command application does not threaten the 35 Hz simulation
tier on this target.

The 30-minute retained-session gate then ran four players for 1,800.007 seconds
and 230,671 tics at 128.15 tics/s. First-five-minute p99 was 15.7 ms and
last-five-minute p99 improved to 11.3 ms. Although 217 calls exceeded a single
28.57 ms slot and one outlier reached 1,005.772 ms, modeled backlog recovered
from its 977.201 ms maximum to zero. Session PGA stayed at 15,907,136 bytes,
with an 18,135,360-byte high-water mark. The evidence therefore passes the
accepted throughput/backlog and late-tail contract. It does not prove total
memory stability: a controlled retained 64 MiB allocation subsequently left
PGA near 16--17 MiB while the owning process reported roughly 284 MiB RSS and
156 MiB PSS. The eventual final presentation artifact must repeat the soak
with calibrated OS-process RSS/PSS/private-memory accounting.
That calibration is now executable and fail-closed. A fresh retained session
touched a 67,108,864-byte MLE allocation; owning-process PSS rose by 51,314,688
bytes and private memory by 50,880,512 bytes, clearing the 48 MiB visibility
floor even though session PGA fell by 458,752 bytes. Process memory remained
reserved after the live reference was released. The final soak therefore gates
bounded/no-growth RSS, PSS, and private memory rather than immediate release to
the operating system.

A profiler-only non-minified TeaVM build then replayed all 13,272 accepted
commands in a 726.353 ms measured Node ticker window. Grouped CPU self samples
put action/collision paths at 21.3%, TeaVM `Long_*` helpers at 18.3%, and
ActiveStates method-reference paths at 13.1%; thinker ticker, P_MobjThinker,
and DoomMain ticker were the largest individual engine frames at 10.9%, 10.4%,
and 5.0%. Three measured-window scavenges totaled 14.32 ms and GC represented
2.0% of CPU samples. This profile selects investigation candidates only; MLE
server-wall measurements retain final authority.

The first same-session OJVM/MLE correctness run matched 14 authoritative state
fields at initialization and after every tic through tic 86. At tic 87,
`playerY` was `26469452` in MLE and `26469453` in OJVM. The one-unit fixed-point
drift blocks parity and is not rounded away. Mocha's `Tables.InitTables()`
procedurally generates trigonometric LUTs with host `Math.sin`, `Math.tan`, and
`Math.atan`; a versioned JVM-generated canonical table pack is therefore being
added before rerunning the differential. The first trig-only pack was 114,732 bytes with
SHA-256 `cd10fc773c356ff17c005b12ef89b0a20d0375e94398e8d84ed1debc52955cfe`.
It is generated from a separate base 830-class JAR by the pinned Oracle 26ai
container JVM. The MLE module has no reachable `Math.sin`, `Math.tan`, or
`Math.atan` fallback, validates the pack header, and loads it before derived
engine initialization. The rerun matched all 14 fields after every tic through
330. A shared canonical digest then matched 61,342 save-semantic bytes plus
stable references for 219 thinkers after every ticker-only transition through
tic 330. The former OJVM `Ticker()+Display()` comparison differs at tic 1
because `Display()` mutates save-serialized presentation state; it is not a
ticker transition mismatch. The final reachable `Math.sqrt` was subsequently
replaced with a host-independent implementation that matched 1,000,196
pinned-JVM boundary/random cases bit-for-bit. The emitted artifact now contains
zero `Math.sin`, `tan`, `atan`, or `sqrt`, and its post-change four-player
330-tic canonical differential passes.

The original live database-rendering contract is infeasible on the pinned local
target. The user-approved 2026-07-22 role-swap amendment now selects retained
MLE-authoritative simulation with non-authoritative browser rendering from
database deltas and asynchronous exact database audit/DVR rendering.
The 640-byte command gate printed by `verify.sh phase PMLE` proves only the
stored-MLE/native mechanics and remains a lower-bound regression check; it must
not be reported as a complete renderer pass. The production-shaped compositor
result (110/190 ms p50/p95) supersedes that synthetic pass and rejects it for
the live local renderer.

## Decision

Continue the selected Java-removal implementation through these remaining gates:

1. The accepted 762-tic co-op every-tic differential and the membership
   leave/neutral/checkpoint/rejoin differential are complete on the final
   paired-input authoritative artifact.
2. Retained MLE authority, DMC1 checkpoints, DMD1 transitions, DMB1 polling,
   standby-gated admission, and the confirmed-only browser mirror are wired.
   Complete the final presentation-capable process-memory soak, WAN matrix, and
   Java-removal acceptance audit before declaring production cutover.
3. Run the prepared arithmetic probe on an actual Autonomous 26ai service. A
   result at or below 15 ns/iteration reopens exact live MLE rendering; a result
   at or above 100 ns/iteration closes it; the middle range requires the full
   production renderer probe.
4. Render live 320x200 frames in the browser from ordered authoritative deltas,
   with no client prediction or simulation, and retain exact MLE rendering as
   the asynchronous audit/DVR tier. Measure the existing unique-moving-frame
   30 FPS gate at the client.

The pinned paired build uses adapter JAR `d80a591d…` and patched Mocha JAR
`6a611ad8…`. Its authoritative output is 1,162,821 bytes, SHA-256 `4cc6da90…`;
the presentation output is 1,224,315 bytes, SHA-256 `61e483d9…`. The final
authoritative A/B measured 7.005/12.662/19.034 ms p50/p95/p99 and 128.842
tics/s under the enforced 50% PDB cap. A real Chromium run SHA-verified both
modules, the table pack, and the IWAD; initialized two independent contexts in
2,156.1 ms; advanced both to tic 1; and rendered a nonblank 64,000-byte frame.
The presentation gate produced 94 unique frames per POV across 96 tics. Its
only serialized render residue was the expected `ML_MAPPED` automap discovery
bit, isolated from the ticker-only verifier context.

The complete two-browser integration now passes at 35.042/35.034 FPS with
38/35 ms p99 presentation gaps and a two-tic confirmed playout buffer. The hot
worker uses DMS2 replay identity because isolated measurement proved a 6.156 ms
authority step followed by a 583.137 ms full canonical rebuild; the latter was
the measured cause of the rejected 1.3 FPS runs. Exact canonical comparison
remains in the completed ledger/co-op/membership differentials and audit tier,
not the live transaction. Free also selects zero-hold DMB1 with
`long_poll_enabled=0`: unconditional DBMS_ALERT signaling caused measured UL
contention, while the separately enabled long-poll contract remains available
for a capacity-qualified deployment. Post-change cutover recovery passes at
3,353.507 ms with checkpoint tic 32, generation 2, 33 DMD1 rows, and no legacy
frames.

This is not yet a production cutover pass. Local 26ai Free has no
measured exact-rendering path with enough headroom: real command cardinality
invalidates column caching, interpreted MLE pixels fail, and the
production-shaped MLE/native compositor fails. Autonomous MLE performance is a
standing renderer-reopen probe, not a blocker for the selected role swap.

## Environment and method

- Branch: `feature/mle-javascript-doom-26ai`
- Image: repository-pinned `gvenzl/oracle-free:23.26.2-full`
- Banner: `Oracle AI Database 26ai Free Release 23.26.2.0.0`
- MLE: stored ES modules and call specifications with retained session state
- Pure-JS output: two `RAW(32000)` values mapped from `Uint8Array`
- Selected output: one 640-byte MLE command RAW, followed by native PL/SQL
  composition directly into two `RAW(32000)` values
- Timing: `DBMS_UTILITY.GET_CPU_TIME`, batched to reduce the timer's 10 ms
  quantization; JavaScript clocks are not acceptance evidence
- Samples: 30 per pure-MLE matrix point and 100 per native/boundary point

Oracle documents stored MLE modules, retained per-context module state, RAW to
`Uint8Array` mappings, and the 26ai PL/SQL FFI. TeaVM documents an ES2015
JavaScript-module target, but also warns that large existing Java applications
usually require manual adaptation. Those mechanisms inform the port; measured
database behavior selects the boundary.

## Results

```text
PMLE_CAPABILITY|{"navigator":"object","navigatorUserAgent":"OracleMLE","webAssembly":"undefined","arrayBuffer":"function","uint8Array":"function","sharedArrayBuffer":"function","atomics":"object","bigInt":"function","performanceNow":"function"}
PMLE_STATE|counter=1,2
PMLE_ARITHMETIC|iterations=1000000|ns_per_iteration=450.000|checksum=-251430693
PMLE_RENDER_PREFLIGHT|samples=30|p50_ms=65.000|p95_ms=70.000|p99_ms=70.000|max_ms=70.000
PMLE_COLUMN_MATRIX|dynamic_columns=0|samples=30|p50_ms=15.000|p95_ms=20.000|p99_ms=20.000|max_ms=20.000
PMLE_COLUMN_MATRIX|dynamic_columns=80|samples=30|p50_ms=20.000|p95_ms=25.000|p99_ms=30.000|max_ms=30.000
PMLE_COLUMN_MATRIX|dynamic_columns=320|samples=30|p50_ms=40.000|p95_ms=45.000|p99_ms=50.000|max_ms=50.000
PMLE_GATE|FAIL_FAST|reason=optimized_dynamic_columns_over_budget|baseline_p50_ms=65.000|column_p95_ms=45.000|column_p99_ms=50.000

PMLE_NATIVE|translated_columns|samples=100|p50_ms=4.000|p95_ms=4.000|p99_ms=4.000|max_ms=4.000
PMLE_NATIVE|gathered_columns|samples=100|p50_ms=34.000|p95_ms=42.000|p99_ms=50.000|max_ms=54.000
PMLE_HYBRID|ffi_translated_columns|samples=100|p50_ms=36.000|p95_ms=46.000|p99_ms=48.000|max_ms=50.000
PMLE_COMMAND|mle_commands_plus_native_compositor|samples=100|p50_ms=4.000|p95_ms=4.000|p99_ms=6.000|max_ms=6.000
PMLE_COMMAND_GATE|PASS|p95_limit_ms=20|p99_limit_ms=33.3
```

The tests identify three bad boundaries and one viable boundary:

- A fully dynamic interpreted-MLE pixel loop is too slow.
- Native PL/SQL that gathers and serializes every pixel is also too slow.
- Calling the native compositor from MLE through FFI and copying the complete
  frame back through MLE is too slow, despite the compositor itself being fast.
- Returning 640 bytes of commands from MLE and composing the frame afterward
  in native PL/SQL is 4/4/6 ms p50/p95/p99 in the lower-bound prototype.

`UTL_RAW.TRANSLATE` is the important native primitive: it applies a 256-byte
colormap to a complete source column in database C code. The real compositor
must preserve that bulk shape. A design that falls back to per-pixel PL/SQL or
MLE work has already been rejected by measurement.

## Engine-port implications

The frozen DMB1 transport now batches up to 64 consecutive independently
chained DMD1 records behind a 32-byte frontier header. It enforces one
outstanding poll per player, a 500 ms hold maximum, and a global maximum of four
held polls in the six-session local ORDS pool, preserving two sessions for
input and recovery/control. Its live database test returned two records,
produced a valid empty timeout, rejected a duplicate held poll, and measured
2.857 ms from the post-commit visibility marker to batch return. Immediate
zero-hold batching is retained as the fallback.

The final soak has also been strengthened: five minutes of warmup are excluded
from all timing and memory statistics. The first scored OS-process sample is
the recorded baseline; RSS, PSS, and private memory must each remain below that
baseline plus 67,108,864 bytes for the entire 30-minute scored run. Ending
values and PSS plateau steps of at least 8 MiB are reported explicitly.

- WebAssembly is absent in this runtime, so Java-to-WASM and C-to-WASM cannot
  be the deployed artifact.
- TeaVM's ES2015 JavaScript target remains a candidate for bringing across the
  bounded Mocha simulation/BSP code, but desktop, reflection, JDBC, threading,
  resource-loading, and framebuffer code need explicit MLE adapters.
- Binaryen `wasm2js` or a hand-bounded Doom C port is a fallback source route,
  not an acceleration mechanism; emitted scalar JavaScript runs in the same
  measured MLE tier.
- The renderer port must emit exact wall-column, visplane/span, masked-column,
  patch/HUD, palette, and fuzz commands. The native package owns only bulk
  sampling/translation/composition, not world or visibility decisions.
- Exact SQL/frozen frames and current OJVM output remain parity oracles during
  migration. OJVM is removed only after the replacement passes deterministic
  recovery, multiplayer, moving-frame, 30 FPS, and soak gates.

## Reproduction and cleanup

Run:

```sh
./verify.sh phase PMLE
```

The suite requires the pure-MLE rejection and the command-boundary pass, then
prints:

```text
PMLE_GATE|PASS|scope=mechanics_only|architecture=mle_command_stream_plus_native_plsql_compositor
```

Its trap drops every disposable call specification, MLE module/environment,
and native package on success, failure, or interruption.

## Sources

- [Oracle 26ai: using JavaScript modules in MLE](https://docs.oracle.com/en/database/oracle/oracle-database/26/mlejs/using-javascript-modules-mle.html)
- [Oracle 26ai: runtime isolation and retained context](https://docs.oracle.com/en/database/oracle/oracle-database/26/mlejs/runtime-isolation-mle-call-specification.html)
- [Oracle 26ai: PL/SQL Foreign Function Interface](https://docs.oracle.com/en/database/oracle/oracle-database/26/mlejs/introduction-pl-sql-foreign-function-interface.html)
- [Oracle 26ai: MLE type conversions](https://docs.oracle.com/en/database/oracle/oracle-database/26/mlejs/mle-type-conversions.html)
- [TeaVM JavaScript/Maven targets](https://www.teavm.org/docs/tooling/maven.html)
- [TeaVM scope and porting limitations](https://teavm.org/docs/intro/overview.html)
