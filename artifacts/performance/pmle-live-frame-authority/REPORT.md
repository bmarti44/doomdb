# Production live-frame integration evidence

Classification: `IN_PROGRESS_NOT_RELEASE_EVIDENCE`

The disposable OCI v84 cell proved that one retained MLE context can advance
the authority, rasterize and compose a 64,000-byte indexed frame, and update a
persistent BLOB locator at 32.025 ms p95 over 300 frames. It did not prove the
production worker, ORDS, or browser path.

## Authority mismatch found by the production gate

The first local worker attempt failed closed:

```text
ORA-04161: TypeError:
engine.presentationWorldGeometryDeltaSnapshotLength is not a function
```

The pinned production authority `5ec18cbe...` predates the presentation
snapshot exports used by v84. The diagnostic had used a newer authority
artifact. Therefore the initial production-integration claim was false.

The corrected headless authority candidate is:

```text
source bytes:              1,181,281
source SHA-256:            c613bb5106d6572d1023ae6caf9045f52d493005bc1be001326acd3826d8eae1
input bytecode SHA-256:    b80f697e8a49775c4b98db6b5ce47df46aee99398b22227a8408585c103ceaa4
Mocha bytecode SHA-256:    42b25147133bb5c84c3b19c1511583bbd36219fb2a68996244106f40078f943e
```

The exact three files are preserved in this directory. `versions.lock` records
them as an unpromoted live-frame authority candidate. The live-frame loader
now recomputes the authority BLOB length and SHA inside Oracle before it may
create the importing MLE environment.

The preserved candidate Mocha JAR does not carry the production authority's
`0006-teavm-authority-no-blocking-wait.patch`: bytecode inspection shows the
original 21-byte `WaitVBL(int)` sleep body. TeaVM eliminated that unreachable
method from the emitted candidate: the exact `WaitVBL` and `Thread.sleep`
symbols are absent from `c613...`. Generic TeaVM `suspendCallback` and
`.suspend(...)` runtime/call-site code is still present, however, so symbol
inspection does **not** prove that the entire artifact is de-CPS. The narrower
finding is only that the blocking `WaitVBL` path is unreachable in these
emitted bytes. Promotion still requires a post-ledger rebuild with the pinned
patch explicitly applied. If that build does not reproduce the exact
`c613...` bytes, it is a new candidate and must not inherit this ledger's
verdict.
`probes/mle/teavm-engine/run-live-frame-authority-reproducibility.sh` is the
fail-closed promotion rebuild: it binds the preserved candidate and input
hashes, applies the production patch, refuses concurrent evidence work, and
requires the generated module to compare byte-for-byte with `c613...`.

That gate has now run and correctly failed closed. The production-patched
build used the exact `b80f...` input JAR but changed the Mocha JAR from
`42b251...` to `c6d266...`; it emitted 1,090,709 bytes with SHA-256
`6d9fcada...`, not `c613...`. It therefore cannot inherit the c613 ledger.
The complete run is preserved in
`rebuild-c613-with-production-patch.log`.

Two additional exact-lineage diagnostics rebuilt with the original
`b80f...`/`42b251...` pair and no extra patch. They emitted:

```text
1,181,281 bytes  a3d0f89c1021a6b962abd977101deea16dd8549f423bb092023fa5e22a0e9693
1,181,282 bytes  49dda197cc4e5055a0c40876978a2cac6ab4f4232f7a70798c28b7dab04abbe2
```

Those runs prove that the current TeaVM emission is not byte-reproducible
even with identical declared bytecode inputs. The matching first-run byte
count is not identity evidence. The preserved c613 bytes remain the only
artifact covered by the terminal ledger, and **no artifact is promoted**.
The next promotion candidate must either make emission reproducible and pass
the full artifact-specific battery, or be admitted under a separately
authorized exact-SHA-selection policy; this report does neither.

Disabling TeaVM minification did not remove the nondeterminism. Two further
same-input diagnostics both emitted 4,097,704 bytes, but with different
SHA-256 values (`43a1d10f...` and `2bf5cfd4...`). A deterministic external
minifier alone therefore cannot solve the problem; the unstable ordering is
already present in TeaVM's readable JavaScript output.

## Manual local integration observation

During interactive development with `c613...` installed in a retained local
26ai Free session, the console reported:

```text
tic 0 bytes: 64,000
tic 0 SHA-256: 0903f63ceabbc4cf8d6c2c655e6f99dc16ea9a6451f5a7271b55c2aa86eb409c
input: forward command accepted for effective tic 2
tic 1 bytes: 64,000
tic 1 SHA-256: b3888de862d337a6071d532d3009f297258387ed57ac9fc3f49f6952deb43dfa
tic 0 != tic 1: PASS
```

No no-overwrite raw log containing those hashes was retained, so this block is
not accepted evidence and must be reproduced by the E2E harness after
promotion. The browser was then changed to select the database framebuffer
path. A headless local browser was observed presenting 18 consecutive
database-frame events (tics 12 through 29), with a nonblank canvas, zero
JavaScript errors,
and a rate of roughly 2 FPS. No no-overwrite raw log was retained for that
observation, so it is classified as an unproven manual observation rather than
evidence or an acceptance result. The repeatable E2E harness below must produce
the retained local verdict after promotion. OCI remains unmeasured for this
production shape.

`tests/verify-mle-live-frame-e2e.mjs` makes the authenticated tic-zero,
movement, 64,000-byte, capability-rejection, and DPB2 batch checks repeatable.

## Candidate determinism gate

The exhaustive every-tic run is:

```text
artifacts/performance/pmle-ledger-every-tic/
  run-live-frame-c613-2026-07-28.log
```

It compares all 13,272 accepted E1M1 tics against the preserved OJVM oracle.
The run reached exactly one terminal marker at tic 13,272 with cumulative
SHA-256
`089ba1518faf0e62be1c59d09e576c00e75c1845c00c3d45e497f7e3b7048584`.
All 133 cumulative markers mechanically match the accepted `5ec...` and
`2848...` runs. The terminal comparator reports
`classification=TERMINAL`, `baselines=2`, and the same terminal SHA.
This proves determinism of the preserved c613 bytes on the accepted route;
it does not override the failed reproducibility gate above.
The fail-closed comparison is implemented by
`probes/mle/teavm-engine/compare-ledger-progress.mjs`; its built-in mutation
self-test rejects malformed, duplicated, gapped, divergent, and mismatched
terminal evidence.

The ledger wrapper printed an alert-window PASS when it terminated, but its
alert state and terminal alert marker were not preserved in a repository
sidecar. Therefore alert-window/postflight closure is not claimed from this
run and remains a separate promotion prerequisite.

## Transport correction staged after the local proof

Latest-only polling cannot guarantee 30 unique FPS when RTT approaches one
frame period. The staged `DPB2` contract returns up to eight consecutive
complete frames from the bounded 64-frame ring. The client buffers and
presents those already-confirmed frames at 35 Hz. Pixel-poll lease writes are
throttled to once per second instead of committing on every HTTP request.
Each DPB2 entry also carries the database-selected PLAYPAL index alongside
the 64,000 indexed pixels. The database endpoint verifies and returns the full
14-palette PLAYPAL lump; the client then only expands the database-authored
index/palette pair into canvas RGBA. Damage and bonus flashes are derived from
authoritative snapshot counters. Berserk fade and radiation-suit palettes
remain explicitly unimplemented because those two power counters are not
present in the current `c613...` presentation snapshot.

An independent xhigh audit found that the first draft counted and fetched in
separate Oracle statements, accepted ring gaps, did not reset on a generation
advance, and had stale compiled clients. The corrected source now:

- assembles and counts each DPB2 envelope from one cursor snapshot;
- returns only a consecutive frame run;
- explicitly resets a self-contained confirmed-frame stream after a ring gap
  or authority-generation advance;
- gives the pixel endpoint ownership of the same busy-lease and
  SID+serial-fenced worker recovery trigger as the retired transition path,
  so a database-frame client cannot poll an empty dead authority forever;
- rejects nonconsecutive entries in the browser decoder;
- makes compiled staging/release-client parity a source-verifier fence; and
- captures the authenticated E2E verdict in a no-overwrite raw evidence log.

These corrections remain source-only until the candidate ledger terminates.
They still require compilation, local behavioral execution, temporary-LOB
observation, OCI deployment, and browser-observed unique-moving-frame
evidence. The hosted browser gate now also requires presentation-interval
p99 at or below two native tic periods and no individual pause above 100 ms;
the 30-FPS p95/mean cannot conceal periodic checkpoint or scheduler freezes.
The local runtime battery now includes an adversarial pixel-only recovery
cell: it kills the retained authority session, drains any already-published
old-generation frames, and requires pixel polling itself to return a DPB2
frame from exactly generation + 1. The caught-up recovery path authenticates
the player capability before inspecting or mutating worker liveness. Its E2E
cell also submits an invalid capability with an artificially advanced
frontier and requires the generation, worker status, and `PIXEL_POLL`
liveness-probe count to remain unchanged.
The coordinator source is intentionally ahead of its `versions.lock` pin
while this source batch is open, so the live-frame loader currently fails
closed. It must be rebuilt, hashed, and repinned once—after the source batch
stabilizes and before any database deployment.

The checkpoint tail is a specifically open production risk rather than a
hypothetical one. The latest preserved high-awake serializer diagnostic
measured 673.142 ms for a checkpoint save, while the worker still performs
bounded-cadence checkpoint serialization synchronously in its retained
authority session. That measurement predates the final OCI live-frame
artifact and therefore does not predict its exact cloud cost, but a production
browser run must either measure the operation below the 100 ms pause gate or
move checkpoint creation off the live frame path. The disposable v84 rank did
not execute production checkpoint cadence.

The hosted gate now closes two earlier evidence gaps directly. Its retained
client allowlist is the 17-object database-pixel build and requires zero
browser TeaVM module loads. After the 300-frame browser sample, an Oracle
postflight locates the released match by its retained SHA-256 identity,
requires at least two durable checkpoints inside the exact scored tic range,
and fails if a checkpoint step or save crossed 100 ms. The same postflight
binds the installed authority, renderer, and coordinator SHAs to
`versions.lock`; smooth client buffering cannot hide a slow checkpoint or a
stale database artifact.

Checkpoint timing in that postflight is explicitly classified as
`EXACT_STAGE_PLUS_SPARSE_GT_100MS_TOTAL`. Every durable checkpoint row records
its save and publication durations; the existing sparse slow-call table
remains the total-step backstop. The retained evidence therefore reports
actual checkpoint-stage maxima while preserving the 100 ms end-to-end tail
gate.

Multiplayer throughput is a separate required cell, not inferred from the
one-POV result. `tests/run-oci-live-frame-two-pov.sh` opens two independent
browser contexts against the hosted ORDS multiplayer page, requires both
300-frame streams to carry `database-framebuffer` provenance, requires
distinct POV canvases, 300 unique framebuffer hashes, and consecutive tics,
and applies the 30-FPS/p95 gate independently to each player. It also carries
the same p99-at-two-tics and 100 ms maximum-pause bounds as the solo hosted
gate, so alternating or checkpoint-stalled viewpoints cannot pass on average.
The raw 600-frame sample envelope is written with no-overwrite semantics
before the verdict assertions and is then re-evaluated by a ten-mutation
self-tested evaluator. At least 250 same-tic samples must overlap and every
overlap must have distinct player-view hashes; the retained PASS marker binds
the envelope SHA-256. Its terminal record also reports each client's buffer
occupancy and DPB2 request count/TTFB/download p95, separating generation or
delivery starvation from canvas playout behavior without retaining URLs,
match identifiers, or capabilities. The envelope and terminal marker bind the
authority, renderer, and coordinator SHA-256 values selected by
`versions.lock`; immediately before and after the browser window, the runner
independently reads the same three values from the Oracle-resident
`DOOM_MLE_LIVE_FRAME_SOURCE` singleton and refuses the PASS marker unless both
deployed tuples match exactly. Those SQLcl markers are parsed through the
shared wrap-normalizing database-output helper and a four-mutation self-test,
so a mid-run deployment change, line folding, duplicates, added fields, or a
digest mismatch cannot silently attest the deployment.

The existing one-POV v84 stage record also makes the two-POV cell a real
capacity risk rather than a formality. Its measured mean was 3.691 ms for the
single authoritative step and about 23.1 ms for one snapshot/raster/compositor/
locator-publication path. A straight sequential extrapolation is therefore
roughly 50.1 ms per two-view tic, or about 20 FPS. This extrapolation is
`DIAGNOSTIC_NOT_GATE`—shared caches and the production transaction can move
the result—but no 30 FPS multiplayer claim may use the one-POV number.

If the measured two-POV cell confirms that limit, the next engineering branch
is not reduced fidelity, alternating viewpoints, or merely moving the same
work into more sessions. The accepted ADB venue is provisioned at one ECPU
(`CPU_COUNT=2` is catalog metadata, not two provisioned ECPUs), so concurrent
renderer sessions cannot manufacture CPU throughput. With a measured
3.691 ms shared authority mean, two POVs must each fit approximately
`(28.571 - 3.691) / 2 = 12.440 ms` to sustain the native 35 Hz production
rate. The current 23.213 ms mean per POV therefore requires about a 1.87x
per-view reduction.

The viable escalation is a measured renderer batch: remove or amortize the
4.053 ms persistent-LOB publication cost across both frames; eliminate
duplicated snapshot/compositor work where the two views share authoritative
state; and specialize the remaining wall/sprite loops against real two-POV
cardinality. Retained snapshot-fed renderer sessions remain useful only if a
stage decomposition identifies wait/serialization overlap rather than CPU
work. Any such branch must preserve generation fencing, bounded backlog, full
64,000-byte POVs, and the independent 30 FPS canvas gates.

Checkpoint-bank selection is also source-hardened for promotion: the
live-frame staging row records the authority bytes and SHA actually installed,
and both warm-origin paths select the bank using that deployed provenance.
The retiring `5ec...` SHA is no longer embedded in worker/runtime source.
These changes remain source-only pending compilation and database execution.

## Claims not established

- The ordinary generated-authority target is currently an empty file. The
  preserved 1,181,281-byte `c613...` evidence copy remains intact, but
  promotion must restore that exact byte sequence under the pin/rebuild gates;
  no loader may consume the empty target.
- The public OCI application still uses the confirmed-state browser renderer.
- The integrated database-frame application has not passed 30 FPS.
- Two-POV multiplayer performance has not been measured.
- Full visual fidelity remains incomplete. Although the generic development
  source contains a 160-column partial-wall-depth implementation, the pinned
  `9cee...` unified renderer selected by the production loader was specialized
  to 106 logical columns and 56 sampled world rows expanded into the 320x168
  viewport. Its fast world core leaves partial-wall depth invariant, so
  two-sided upper/lower wall bands do not yet clip sprites correctly. Native
  world sampling, masked midtextures, sky rendering, complete Doom lighting
  and sprite effects, berserk/radiation palette effects, audio events, and streamed
  title/menu/automap/intermission/finale states remain outstanding.
- No candidate promotion, release commit, or cloud deployment has occurred.

The future T11.1 direct-API contract is now 20 cases: it includes the legacy
single-frame poll, DPB2 poll, base PLAYPAL, and full 10,752-byte PLAYPAL set.
This corrects a source-only 19-observation-versus-17-fixture mismatch found by
the independent audit. The T11.1 evaluator self-check and all 26 mutation
canaries pass; no live T11.1 rerun is claimed.

The generated-world build transform now has a source-only partial-wall-depth
candidate: it resets the retained depth plane once per frame and bulk-fills
each visible wall band with its projected distance. Its Node gate requires a
real accepted-route partial band rather than source presence alone. It is not
part of `9cee...`; after the authority ledger, it must pass exact mutation/
restore tests and a direct OCI A/B before its artifact can replace the pinned
renderer.

The production worker now renders the actual authoritative member-slot cursor
rather than assuming occupied POVs are dense in `0..count-1`. The database
pixel client also retains zero-copy views into each DPB2 response and schedules
empty polls against the next 35 Hz slot. Its first source draft presented an
atomic batch immediately and therefore let confirmed occupancy fall to zero
before the next WAN response. The corrected client treats batch cardinality as
the normal sawtooth width separately from an adaptive jitter reserve, waits for
reserve plus one recent-p90 batch before starting, and uses a batch-aware
confirmed-only controller whose free-running band spans that complete
sawtooth. Only positive late-delivery deficit grows the reserve; early
backlog-drain responses do not. Generation, ring-gap and hidden-tab boundaries
reset the estimator and advance a pixel-poll epoch so an in-flight pre-reset
response cannot mutate the new stream. Ordinary presentation never predicts,
reorders, or skips; an explicit generation, ring-overrun, or visibility resync
may intentionally jump past frames no longer retained by the bounded ring.
Cloud evidence now records reserve, batch, occupancy and controller-mode
distributions, requires the startup invariant and positive scored occupancy,
and rejects scored starvation or pixel resynchronization as well as capping
pixel polls per scored frame.
An independent xhigh source audit reproduced the original atomic-batch drain
and visibility-race defects, then re-audited the corrected controller, timed
jitter cell, epoch fence, and cloud assertions with no remaining source-level
blocker. That is review evidence only: TypeScript compilation and runtime
behavior remain deliberately unclaimed until the active authority ledger
releases the environment.
The hosted-static source batch no longer copies the browser TeaVM authority,
presentation engine, canonical table pack, or full IWAD; it also removes the
four diagnostic-only authority modules from the publish inventory. The
Freedoom license remains hosted because the database-generated pixels still
derive from those assets.
