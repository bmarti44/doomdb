# De-CPS authority rank and reproducible successor — 2026-07-24/25

## Current status — 2026-07-25

The reproducible `5ec18cbe…` successor is now promoted and deployed. Its
13,272-tic every-tic ledger, canonical, 762-tic co-op, membership recovery,
four-cell asynchronous-admission race battery, and five-cell warm-slot
lifecycle battery pass. The final artifact-specific recovery battery and
30-minute soak remain cutover gates.

The fresh exact-stream Node CPU profile is terminal and SHA-validated:
`node-decps-peak-5ec18cbe4cff-v3.log` and
`node-decps-peak-5ec18cbe4cff-v3.cpuprofile`. The 5,250-tic run sampled
542.891 ms. The inspector `post` control path accounts for 80.743 ms outside
the ticker loop; excluding it leaves 462.148 ms of sampled ticker work.

| Ranked work | Ticker-work share | Perfect-removal ceiling |
|:--|--:|--:|
| Sight/BSP | 23.558% | 1.308x |
| Mobj long/flag handling | 14.042% | 1.163x |
| Active-state action dispatch | 9.299% | 1.103x |
| Movement/AI | 8.368% | 1.091x |
| Garbage collection | 1.129% | 1.011x |

Sight/BSP is below the predeclared 25% threshold, so staged patch `0007` is
not selected. The narrow long/flag candidate passed its property test and
every-tic Node parity, but the direct exact-stream MLE A/B produced only
1.035% p50, 4.122% p95, 2.707% throughput, and 1.401% median improvement in
matched high-awake windows. It is rejected under the standing 5% rule; see
`mobj-low-word-decision-2026-07-25.md`. Perfectly eliminating all four named
categories would remove 55.266% of sampled ticker work, a 2.235x Amdahl
ceiling. This is trajectory evidence, not yet the Free capacity-clause
terminal: the residual `other` work still needs classification and the
hidden-JIT final-artifact closeout is the next measured branch.

That closeout has now produced a localized `LANDING_SIGNAL`: in two
consecutive default-configuration 5,250-tic passes, matched window 701–800
improved 25.501% by corrected wall median and 41.079% by 100-tic monotonic
throughput. Four/10,500 clock suspects were symmetrically excluded under the
0.5% cap. No unsupported parameter was set. This reopens a focused
fresh-session reproduction/persistence experiment; it is not yet production
qualification or a 35 Hz claim. See `async-jit-decision-2026-07-25.md`.

Two earlier profile build attempts are retained as `VOIDED` harness evidence.
The first caught a numeric field sent through a SHA-only extractor; the second
caught textual-row SHA versus canonical binary-expanded stream SHA. Both
failed before CPU profiling. Their corrected parsers now have adversarial
offline self-tests.

Verdict: **the source-level de-CPS change is accepted for full promotion
gating, but no artifact is promoted yet.** Removing the authority build's reachable
`Thread.sleep`/`WaitVBL` path changes no canonical state and improves the full
preserved deathmatch route from 6.002 to 19.788 tics/second. Quiet windows now
clear 35 Hz; peak-combat windows do not. The measured `2848ef7a…` artifact is
historical because its exact timestamp-bearing input JAR was not retained.
Final promotion targets the byte-reproducible `5ec18cbe…` successor and
requires fresh final-artifact evidence.

## Candidate and correctness

- candidate JavaScript: 1,081,331 bytes, SHA-256
  `2848ef7a8dc4799de7faa46bcf304f4ac3d351da97be94b144a53f3300607f29`;
- reproducible successor JavaScript: 1,081,335 bytes, SHA-256
  `5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3`;
- reproducible successor input JAR SHA-256:
  `2ca1278998385efb83aba0358119f70f2e135b569b446f6b43f6afddf51ca914`;
- TeaVM adapter input JAR SHA-256 (unchanged from pinned `e485…`):
  `631f3d7657b3b9521ed800d1b4ec518d4b6f102e5bf2a9f3e7caf1cb45624ecd`;
- patched Mocha bytecode dependency SHA-256:
  `c6d26633316b7a6251e79b9013bfb16ca877e2d93642ebbaba17bfc66c8861a4`;
- source patch SHA-256:
  `6092f86c9c70a20be9a011db34e1dd75669e7f2f0b0f3da76d702f57c5866e29`;
- TeaVM 0.15.0, JavaScript backend, `ADVANCED`, minification enabled;
- pinned oracle: `e485b9418e5845b78e9e1593918d8bbb6f3c441c41a43cb8f3faf046e595148b`;
- exact stream SHA-256:
  `fa7637570c30d3a33cbf8456e98268890e9f5bd82f5ba39fd7f69b139ddc4085`.

The Node differential compared the complete canonical byte stream at tic zero
and after every one of 5,250 live deathmatch tics. All 5,251 comparisons pass;
the terminal 75,818-byte canonical state has SHA-256
`b3f667c9395455fd42e31586dd79006fc9c091132cb09c8b1f4627a7d93a9907`.
This proves the pacing call was outside authoritative semantics on the accepted
stream. It does not replace the canonical, co-op, membership, ledger, recovery,
and lifecycle batteries required before promotion.

The generated module is 90,565 bytes smaller than pinned `e485…`. The
authoritative native-thread runner disappears and generated suspension call
sites fall from three to two. The two retained runtime sites implement TeaVM
sleep and XMLHttpRequest support; no generated native-thread runner reaches
the authoritative exports.

## Direct Oracle MLE result

Both the historical ADVANCED baseline and this candidate replay the exact same
5,250-tic stream with the retained pool parked and no active match, under the
edition-enforced Oracle Free envelope (`CPU_COUNT=2`, PDB utilization limit
50, running-session limit 2).

| Metric | ADVANCED baseline | de-CPS candidate | Effect |
| --- | ---: | ---: | ---: |
| Whole-route throughput | 6.002 tics/s | 19.788 tics/s | 3.297x |
| Whole-route p50 | 148.208 ms | 36.640 ms | 4.045x |
| Whole-route p95 | 296.126 ms | 142.665 ms | 2.076x |
| Whole-route p99 | 391.336 ms | 196.411 ms | 1.993x |
| Maximum | 591.380 ms | 376.974 ms | 1.569x |
| Cold initialization | 43,800.991 ms | 40,568.874 ms | 1.080x |
| Restored 500-tic prefix p50 | 264.913 ms | 109.791 ms | 2.413x |

The 100-tic window speedup is density-shaped. Tics 1–700 improve 2.35–3.04x.
The late quiet plateau at tics 4,400–5,250 improves 10.64–12.06x: its
candidate windows take approximately 10.0–11.3 ms/tic and therefore clear the
35 Hz slot. Peak windows still take approximately 106–141 ms/tic, so the
candidate does not satisfy the live contract under combat density. No 30 FPS
claim is made.

The clean full-stream log has SHA-256
`61efa443e39dbfc4c9fd5f7a7d78f75d683f49e5aeecc2a9589ca6afb9cc819c`.
The shorter 500-tic preview independently measured 8.703 tics/s and
109.225/213.580 ms p50/p95.

## Hidden compilation

The hidden controls remain diagnostic-only and disabled in production. Two
candidate cells were attempted:

1. immediate + synchronous + fatal compilation;
2. synchronous + fatal compilation with immediate compilation disabled.

Each remained in `MLE park` for more than five minutes without reaching
initialization or a replay terminal marker. Each tagged session was killed by
full SID/serial, the pinned `e485…` database module was restored through its
SHA fence, both warm slots returned to `READY`, and the later full interpreter
cell's alert window contained no new Oracle error. The kill records report
`Result = ORA-00000`, Oracle's success code; the alert scanner now excludes
that code while continuing to fail on every nonzero `ORA-nnnnn`.

These two cells are void diagnostics, not performance evidence. De-CPS solved
the interpreter's ticker wrapper cost but did not make Oracle's undocumented
whole-module compilation path operational.

The post-promotion JIT closeout is deliberately narrower. First, run two
consecutive exact 5,250-tic passes in one retained session under untouched
default asynchronous settings. The comparator uses matched 100-tic medians:
at least 20 percent improvement in any matched window is a landing signal;
less than 10 percent in every window classifies async JIT as inert; the
10–20-percent middle is explicitly inconclusive. The cell is time-boxed at 60
minutes and records an Oracle process/compiler-thread census as secondary
evidence. It changes no unsupported parameter.

Only after the fresh de-CPS Node CPU profile exists, the second cell builds
TeaVM `SIMPLE` as an explicitly unpromotable JIT-digestibility diagnostic. If
that smaller generated shape reaches a terminal ticker marker instead of
parking, a debug-build function-size census may rank targeted
`org.teavm.interop.NoInline` annotations; without that signal no `NoInline`
source patch is permitted. The third cell runs one session-scoped
`_mle_max_heap_size=1500` diagnostic on the exact authority. All cells retain
full SID/serial cleanup and the production leak guard. An inert async pair
plus SIMPLE and heap parks closes hidden JIT on this Free venue.
Every rank cell restores the pinned production module and validates its Oracle
alert window before restarting the warm pool; failed session cleanup, module
restoration, or alert validation holds capacity closed.

## Maximum-density acceptance and Free envelope

The claim gate remains 35 authoritative tics/second at the maximum measured
combat density on every venue. A quiet-window pass is not a full-engine pass,
and a Free-edition density envelope is not a substitute for that claim.

The density envelope may be published only after an Amdahl escalation record
fires. That record requires all of the following evidence from the exact
5,250-tic stream:

1. a fresh de-CPS Node CPU profile assigns the peak window to named
   categories and directly ranks sight/BSP, movement/AI, and long/flag work;
2. every category at or above five percent is either measured by a direct MLE
   A/B or explicitly rejected with a property/correctness reason;
3. the de-CPS specialization batches, wasm2js generated-shape branch, and
   three-cell hidden-JIT closeout have terminal verdicts; and
4. the measured irreducible fraction `u` and current peak throughput `T`
   imply an infinite-acceleration ceiling `T/u < 35`.

Until that marker exists, per-awake-window measurements are diagnostic
performance evidence only. After it exists, Free may expose a table of
sustained tics/second by awake-monster bucket while retaining the explicit
maximum-density 35 Hz failure. Brian Martin remains the acceptance authority
for invoking the capacity clause.

`0007-teavm-authority-sight-pooling.patch` is source-staged only and is
classified `UNRANKED_NOT_AUTHORIZED`. It cannot enter a build, A/B, or
promotion set unless the fresh profile assigns sight/BSP at least 25 percent
of peak tic time. Movement/AI flattening and mobj-flag work likewise remain
unselected until that same profile ranks them.

## Exact-frame database egress rank

The presentation rank keeps the 64,000-byte frame inside the retained MLE
session. Its primary transport passes the frame `Uint8Array` as an IN BLOB
bind on an `INSERT` executed through the built-in MLE SQL driver. Where the
26ai surface exposes a `DB_TYPE_BLOB` constant the probe supplies it;
otherwise the target BLOB column drives the documented
`Uint8Array`-to-BLOB conversion. `ORACLE_BLOB` is reserved for the documented
wrapper/locator path rather than being mislabeled as a node-oracledb BLOB
constant. If the real 64 KB direct insert fails, the in-harness fallback
inserts one persistent `empty_blob()` row and reuses that database LOB.
This boundary follows Oracle's 26ai type-conversion and LOB APIs:
[`Uint8Array` and `OracleBlob` both map to BLOB](https://docs.oracle.com/en/database/oracle/oracle-database/26/mlejs/mle-type-conversions.html),
while [`OracleBlob` is globally exposed and provides synchronous
`open`/`write`/`close`](https://docs.oracle.com/en/database/oracle/oracle-database/26/mlejs/large-objects-lob-mle.html).
The documented MLE driver exposes `ORACLE_BLOB`; it explicitly does not expose
the node-oracledb `BLOB` streaming constant. Therefore `DB_TYPE_BLOB` is
treated only as an optional runtime capability and never as a required API.
Oracle forbids
a selected persistent locator from spanning transactions, so each frame
reacquires the row's locator through `UPDATE ... RETURNING`, explicitly opens
it, performs `OracleBlob.write(1, frame)`, and closes it before the caller can
commit. This creates no per-frame temporary LOB. The 300-frame record
captures this session's cache, nocache, and abstract counts from
`V$TEMPORARY_LOBS` before and after the run. Neither arm returns the payload
through a call specification. The acceptance comparator requires zero net
temporary-LOB growth across the 300 scored frames. The capability probe uses
the full 64 KB frame so a RAW-sized
false pass is impossible. A failed probe records both
`direct_supported=NO` and `direct_mode=UNSUPPORTED`, allowing the strict
extractor to select the locator arm without accepting a contradictory
capability record. The selected arm must then pass a separate
300-unique-frame, end-to-end 33.333 ms p95 gate before it can support the live
exact-rendering claim. Every scored frame is committed inside the timed
pipeline, which both measures durability and proves the locator path across
real transaction boundaries; committed diagnostic rows are then removed and
the persistent sink is reset deterministically.
Both SQL harnesses pin SQL*Plus `LINESIZE 32767`, so the complete timing,
corpus, transport, and chain record remains one extractor-validated line.
After any rank outcome, the runner restores the pinned production module and
validates the Oracle alert window before restarting the warm pool. Failure of
either proof leaves gameplay capacity held closed.

The transaction boundary is pinned to Oracle's 26ai LOB rules:
[explicitly opened LOBs must close before commit](https://docs.oracle.com/en/database/oracle/oracle-database/26/adlob/programmatic-environments-that-support-LOBs.html)
and an
[ORA-22990 locator must be reselected in the new transaction](https://docs.oracle.com/en/error-help/db/ora-22990/).

## Decision

The candidate has crossed the structural-promotion threshold: exact accepted
stream, 3.297x full-route throughput, and more than 10x improvement in quiet
windows. Its Oracle promotion battery now passes:

- four-player 330-tic canonical differential;
- two-player 762-tic co-op differential with deep equality every tic;
- leave/neutral/checkpoint/rejoin membership recovery through tic 100, bound
  to candidate `2848…` and OJVM oracle `2a102…`.

The exhaustive 13,272-tic every-tic ledger, recovery/lifecycle gates, and final
soak still remain before any pin or production deployment changes. The next
performance work must target peak monster AI/movement/sight cost; hidden JIT is
not a usable fallback on this artifact, and the rejected Binaryen 131 wasm2js
output remains closed until its `long` high-word corruption is fixed.

The running ledger's SQL evidence file intentionally contains only the
determinism transaction. Its wrapper restores the retiring production module,
restarts the retained pool, and closes the Oracle alert window after the SQL
terminal, so those operations cannot be inferred from the ledger PASS itself.
The live run's outer alert origin is preserved separately at byte offset
742386 (`2026-07-24T22:50:22Z`). After the wrapper exits,
`attest-decps-ledger-postflight.sh` must independently reproduce the retiring
module/table tuple, observe both unbound slots READY, and rescan that complete
alert window. Promotion readiness requires the resulting ordered postflight
PASS. This prevents a deterministic ledger from qualifying promotion if its
environment restoration or incident scan failed afterward.

Promotion is deliberately a two-phase, fail-closed operation. After the
ledger PASS, `run-decps-reproducibility.sh` first rebuilds the exact candidate
bytes. `promote-decps-authority.mjs` then defaults to a read-only plan, requires
the complete readiness record, and only writes when invoked with both
`--apply` and `PMLE_DECPS_PROMOTION=YES`. It updates the runtime SHA, byte
count, Mocha bytecode digest, content-addressed browser artifact, and patch-set
provenance as one source transaction. Forward and rollback file replacement
use exclusive temporary creation plus atomic rename; the browser artifact must
not pre-exist, and rollback attempts every original even if one restoration
fails. The apply transaction runs the PMLE, cloud-manifest, dashboard, and
production Java-removal source verifiers before it may succeed; verifier
failure restores the original files. Historical evidence
references are intentionally never rewritten, and
the content-addressed retiring JavaScript artifact is retained as the Node
differential and database-deployment rollback oracle.
The source transaction also owns
`promotion-5ec18cbe-2026-07-25.log`: it writes the unique BEGIN and complete
readiness record before building the dashboard, and appends verifier and
terminal PASS markers only after every source verifier succeeds. A failed
transaction removes that evidence together with its other forward writes.
During that bounded transaction the dashboard builder accepts the explicit
`PMLE_DECPS_SOURCE_PROMOTION_IN_PROGRESS=YES` state; every later source-pinned
dashboard build requires the terminal promotion PASS. Dashboard evidence links
always resolve to an existing repository file—pre-promotion truth falls back
to this report, while promoted truth binds the promotion log—so the source
phase cannot publish links to database-deployment evidence that does not yet
exist.

The measured `2848ef7a…` authority predated the database-frame egress adapter
work and its exact input JAR was not retained. Investigation after its ledger
PASS showed that TeaVM treats every `@JSExport` in the input JAR as a root:
presentation-only Java exports therefore reshape the authority too. The final
design keeps both reachability adapters byte-identical to the source used for
the measured authority and implements database-frame transport around the
existing `Uint8Array` result in JavaScript.

The build now pins Maven `project.build.outputTimestamp`, making the input JAR
digest reproducible instead of encoding wall-clock build time. Two consecutive
builds from that exact input produced the same 1,081,335-byte
`5ec18cbe…` successor. It matched `2848ef7a…` over 5,250 tics and 5,251 full
canonical-state comparisons. A fresh 13,272-tic every-tic Oracle differential
is required on those final reproducible bytes; evidence inheritance from the
unreproducible module is explicitly rejected.

The predecessor/successor structural diff is classified in
`identity-break-classification-2026-07-25.md`. A fixed-input timestamp A/B
proves that archive metadata changes TeaVM output identity, and a debug-named
build maps the first large changed minified class (`BdB`) to TeaVM classlib's
`UTF16Decoder`, not Doom simulation code. Clean/incremental build shape is
still treated as an identity input. This classification explains the generated
diff but grants no semantic inheritance: the reproducible successor must pass
the full promotion battery on its own bytes.

The primary direct-MLE rank was rerun under dual-clock instrumentation. Every
tic records both `SYSTIMESTAMP` and `DBMS_UTILITY.GET_TIME`; disagreements over
30 ms are symmetric suspects, the predeclared cap is 26 of 5,250 (0.5%), and
the 100-tic GET_TIME windows are authoritative for throughput. The final
matched pair had two suspects in each cell. Against `2848ef7a…`, `5ec18cbe…`
improved p50 by 1.241%, improved p95 by 0.819%, and improved monotonic
throughput from 19.587 to 19.828 tics/s. It therefore passes the unchanged 5%
promotion rule.

Two predecessor attempts and one otherwise-passing mixed-host pair remain
preserved as void evidence. The cause was not the engine: Lima guestagent
stepped Colima's clock roughly 125 ms every ten seconds while the separately
enabled `systemd-timesyncd` was already slewing at its 500 ppm limit.
Disabling the redundant timesyncd owner while retaining Lima's host
synchronization reduced suspects from 27 to two. No clock threshold or
exclusion cap changed. `compare-decps-dual-clock-rank.mjs` unfolds arbitrary
SQLcl line wrapping, validates all 5,250 paired samples and all 53 monotonic
windows, and promotion regenerates its terminal directly from the two raw
logs. The earlier SYSTIMESTAMP-only comparison is corroboration, not primary
evidence.

Before `versions.lock` may move from the retiring input digest, the promotion
transaction verifies the complete POM and both adapter source SHAs. Its
promotion plan then records a
`PMLE_DECPS_INPUT_PROVENANCE_TRANSITION` marker and pins the new input-JAR
digest shared by the authority and subsequent presentation build. Any other
source change, source hash, output byte, or output SHA fails promotion.
The currently pinned `e55d…` presentation artifact retains its historical
nested input-JAR digest until a new presentation artifact clears its own rank
and promotion. Ordinary pinned presentation builds now verify that nested
input digest in addition to their Mocha and output SHAs; candidate builds
record the new shared authority input digest without prematurely rewriting the
deployed presentation pin.

Three post-ledger diagnostic rebuilds correctly failed closed while isolating
the cause. They are preserved as the
`rebuild-2848ef7a8dc4-failed-*.log` records; none is promotion evidence.

Source promotion does not silently mutate the running database.
`deploy-decps-authority.sh` is a second explicitly authorized transaction. It
requires a quiet host and zero active matches, parks the retained pool, loads
the promoted module through the database SHA fence, rebuilds the ten-entry
tic-zero checkpoint bank under the promoted authority SHA, installs the
matching worker contract, verifies the database-resident artifact, and only
then updates the dashboard's database-deployment qualification and restarts
prewarming. Source promotion alone is reported as
`SOURCE_PINNED_DATABASE_DEPLOYMENT_PENDING`; it cannot be mistaken for a
running-database promotion. Any failure restores all three coupled
surfaces—the retiring module, checkpoint bank, and worker package—and returns
the dashboard to database-pending truth before capacity is reopened. Rollback
is not considered successful until `artifact-metadata.sql` reproduces the
retiring module SHA and the installed worker body independently reproduces
the retiring contract SHA. If either check fails, capacity remains held
closed and the dashboard enters
`INTERVENTION_REQUIRED_CAPACITY_HELD_CLOSED`.
Every deployment failure re-runs the lifecycle-owned pool park and proves
zero live retained slots before touching the imported module. This is
unconditional: a failed `start_warm_pool` may have created only one worker
without updating the shell's bookkeeping, and a failure after a successful
restart may leave both workers live. If that re-park cannot be proven,
rollback is skipped and the dashboard enters
`INTERVENTION_REQUIRED_CAPACITY_UNPROVEN` with
`rollback_pool_park_failed`; it does not falsely claim that capacity is held.
Module replacement underneath a live MLE context is prohibited. A failed
post-rollback pool restart is likewise re-parked before
`INTERVENTION_REQUIRED_CAPACITY_HELD_CLOSED` may be emitted; if that second
park fails, the unproven state records `capacity_restart_repark_failed`.
Intervention state records bind the final capacity marker in the deployment
log—not merely any earlier marker—and persist its exact reason into
`mle-status.json`. Mixed rollback attempts therefore cannot let a stale
`HELD_CLOSED` line mask a later `UNPROVEN` result.
Both the ordinary intervention retry and the post-rollback restart-failure
path record an explicit dashboard/state PASS or FAIL. Neither may discard a
failed state write with `|| true`; capacity remains parked (or explicitly
unproven) even when publishing dashboard truth itself needs operator repair.
The rollback trap also closes and validates the Oracle alert window before
it may restart the pool. An unclassified alert-window failure or a failed
dashboard-state write uses the same intervention-required state with its
specific held-capacity reason; a verified module/worker rollback alone is
not permission to reopen capacity. The deployment window remains open through
the database-pending dashboard verification. If a later failure occurs after
that window has closed, rollback opens and validates a dedicated
`DECPS_DEPLOY_ROLLBACK` window; failure to open or validate that window is
itself an intervention-required capacity hold. A verified rollback whose warm
pool cannot restart also transitions to the intervention-required state with
`capacity_restart_failed`; ordinary source-pinned pending truth is reserved
for a rollback whose capacity was actually restored.

The successful deployment state is
`DATABASE_DEPLOYED_LIFECYCLE_RERUN_PENDING`. It clears only through
`set-decps-deployment-state.mjs` after a committed lifecycle manifest binds
the promoted authority to PASS evidence for recovery, admission, lifecycle,
and the final soak; every named marker and evidence file must exist in that
same commit. The resulting terminal state is
`DATABASE_DEPLOYED_LIFECYCLE_QUALIFIED`. These four states form the complete
normal/held dashboard deployment state machine. The fifth, exceptional
`INTERVENTION_REQUIRED_CAPACITY_UNPROVEN` state exists only when the lifecycle
mechanism cannot prove its own hold; neither a source edit nor an
uncommitted runtime result can skip a transition.

`build-decps-lifecycle-manifest.mjs` is the only supported manifest assembly
path. It requires the promoted source pin and the deployed-pending
predecessor, whose evidence must contain exactly one database-ready marker and
one terminal deployment PASS with no rollback failure or capacity hold. It
accepts exactly the four named gates and verifies that each
single-line marker contains a delimited `PASS` token and occurs exactly once
in its repository-relative evidence file. Every gate file must also contain
exactly one complete `PMLE_ARTIFACT` record for the promoted 1,081,335-byte
authority and canonical table pack; an old artifact's otherwise-valid PASS
cannot qualify the deployment. An embedded substring such as `BYPASS` is
rejected. The manifest and evidence are committed while the dashboard
still records the deployed-pending predecessor; that commit is then supplied
to `set-decps-deployment-state.mjs` for the final qualified transition.
The transition script independently rechecks the manifest schema, exact
four-gate key set, predecessor evidence, repository-relative paths, promoted
artifact tuple, and exactly-once committed markers; it does not trust the
builder's prior run.
