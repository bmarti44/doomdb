# P12.M Mocha Doom inside Oracle JVM

Date: 2026-07-18

> Production cloud supersession (2026-07-21): this report preserves the
> historical Java 11 feasibility spike. The selected Autonomous artifact now
> targets Java 8 bytecode and contains 830 classes; see
> [the P11 OJVM readiness report](performance-P11-ojvm-cloud-readiness-2026-07-21.md).

## Result

The production migration is feasible. Pinned Mocha Doom now initializes E1M1,
accepts dynamic Doom tic commands, advances bounded game tics, renders 320x200
indexed frames, and writes them into caller-owned Oracle BLOBs inside OJVM.
This is an engine-component result, not yet an end-to-end AutoREST selection.

## Reproducible inputs

- Mocha Doom commit: `c0af1322ee5fd168b5cf8aaaf504cab2d1aabe93`
- License: GPL-3.0-or-later; upstream and per-file notices preserved
- Upstream Java sources: 442
- Mocha Doom and adapter classes: 822
- Total valid DOOM-schema Java classes including 30 legacy helpers: 852
- Freedoom IWAD bytes: 28,795,076
- Freedoom IWAD SHA-256:
  `7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d`
- Oracle container limit during the spike: 4 GiB

The build compiles with Oracle's embedded Java 11 compiler, applies tracked
headless/no-filesystem/logging patches to a disposable copy, mechanically
converts all 18 pinned `System.exit` sites into catchable OJVM errors, loads the
complete graph with `loadjava -resolve`, and rejects invalid Java objects.

## Correctness checkpoint

E1M1 initializes without a desktop window, audio device, external WAD file,
configuration file, network socket, or wall-clock loop. The first indexed frame
is 64,000 bytes and hashes to:

`a1c9b0378eed9e82425cae593b82dfa44715627d8aa635562b450e4c1af3d3b5`

A caller-owned temporary Oracle BLOB received all 64,000 bytes in 1.431 ms and
reported the same framebuffer SHA. Caller-selected new-game and deterministic
dispose entry points pass.

Mocha's 61,498-byte `VanillaDSG` save stream was tested and rejected for
authoritative recovery: the immediate post-load frame and the next 20-command
branch both diverged. Exact recovery now replays Oracle's ordered packed
`ticcmd_t` ledger from a fresh game. A 70-command forward/FIRE-every-8 seam
reproduced tic 70, level time 70, RNG index 82, player pose, and frame SHA
`1404cf810faeb1a237a86966b4b3d67cb7f9f42d6a2be91cf1207facccdca509`.
The 560-byte command stream SHA is
`afb9740b82590f9678ababc1376ba6fd1d388130f39a1e060b9127b5d3235140`.

The production bridge now records immutable lineage roots (skill, episode, map,
engine revision, and IWAD SHA) plus exact generation-fenced commands. Its first
turn-bearing transactional gate committed command `3228fec000000017`, disposed
the retained JVM, reconstructed solely from Oracle rows, and reproduced frame
SHA `c426186759cd917ce9465ea0ad93bbb180b0b5f498e3a4804e3bbe048709c7d8`.
That gate exposed an upstream network decoder bug: signed promotion changed the
low byte of `FEC0` to `FFC0`. The adapter now decodes both shorts with explicit
unsigned bytes; straight-only replay had not exercised this case.

## Performance progression

All samples below execute the game loop inside one retained OJVM session.

| Checkpoint | Ticker p95 | Renderer p95 | Total p50 | Total p95 | Result |
| --- | ---: | ---: | ---: | ---: | --- |
| Interpreted moving samples | not split | about 193 ms | 136 ms | 193 ms | rejected |
| Initial 18-class native stationary trace | 2.7-6.5 ms observed | 2.8-4.9 ms observed | 7.0 ms | 11.1 ms | component green |
| First 300 moving/FIRE-every-8 route | 16.136 ms | 36.356 ms | 22.584 ms | 49.013 ms | route-only compile gaps |
| Selected 44-class native route | 2.080 ms | 1.876 ms | 1.323 ms | 3.927 ms | engine green |
| Normalized controls + tic + render + 64 KB BLOB, clean rerun | included | included | 1.704 ms | 3.191 ms | worker core green |
| Above + exact ledgers/frontier + durable commit | included | included | 6.124 ms | 20.889 ms | durable core green |
| Above + gzip/DMF3 public payload | included | included | 8.290 ms | 19.560 ms | encoded durable core green |

The selected 300-sample route includes 30 warmups, forward movement, and FIRE
every eighth tic. It produced 299 unique frames and measured 8.236 ms p99 and
14.239 ms maximum. The p95 engine ceiling is about 255 tics/second, leaving
29.406 ms of the 33.3 ms display budget for durable persistence, AQ, ORDS,
wire transfer, decoding, and paint.

The production-shaped control-path row uses the public normalized control
fields, vanilla walk/run magnitudes and six-tic turn acceleration, a combined
ticker/render/BLOB call, 30 warmups, and 300 measured forward/FIRE-every-8 tics.
The clean post-fix/native-compile rerun produced 300 unique frame hashes; p99
was 6.025 ms and max was 22.047 ms.
The reproducible control-codec gate also byte-checks signed movement, the turn
ramp, and combined fire/use/weapon bits. This excludes ledger DML, durable
commit, AQ, ORDS, wire, decode, and paint.

The pre-codec durable row additionally inserts both normalized and exact commands,
advances the authoritative session frontier, and executes `COMMIT WRITE
IMMEDIATE WAIT` on every tic. Its p99 was 39.378 ms and max was 42.324 ms. After
the run, a fresh engine replayed all 330 committed commands to final frame SHA
`e8d24e1073c833486dd738b6c18c4e4cc29a277536c8f050c48c654b18d710ec`.
Its 20.889 ms p95 was the baseline used to admit the response-codec slice below.

The selected codec emits the existing client-compatible gzip/DMF3 binary
envelope, including a deterministic command/state chain token, frame SHA,
empty bounded audio array, and column-major indexed pixels. Oracle independently
decompressed the gate payload and verified its 64,142-byte DMF3 body, tic,
state SHA, and frame SHA. Codec-inclusive component timing was 4.900/12.797 ms
p50/p95 (35.914 ms p99, 85.546 ms max). With ledger/frontier DML and synchronous
commit included, the selected 300 samples measured 8.290/19.560/38.798 ms
p50/p95/p99 and 69.414 ms max. The final moving frame compressed to 10,480 bytes
and all 330 committed commands replayed to frame SHA
`e8d24e1073c833486dd738b6c18c4e4cc29a277536c8f050c48c654b18d710ec`.
The selected durable p95 leaves 13.773 ms for AQ/ORDS, wire, decode, and paint.

This gzip-in-OJVM codec was superseded after audio and persistence integration.
Under host contention its codec p95 reached 33.893 ms while ticker/render stayed
at 4.038/4.319 ms. Raw DMF3 reduced the database worker to 12.806/23.837 ms
p50/p95, with codec/BLOB p95 of 0.820/1.454 ms. ORDS Jetty HTTP compression then
reduced a representative outer JSON response from 123,611 to 7,443 wire bytes.
Two low-latency depth-4/fetch-2/buffer-4/lookahead-4 runs passed at 31.516 and
31.787 FPS with the exact frame chain and 155–187 ms input-to-frame latency.

## Scheduler/AQ and AutoREST checkpoint

The existing generated package contract is reused unchanged. A synchronous
`DOOM_API.STEP` gate claimed the retained Scheduler session, crossed AQ, wrote
the exact command and correlated result, returned a valid 27,796-byte gzip/DMF3
payload, and returned the byte-identical cached payload for a duplicate without
advancing tic/sequence. An asynchronous gate then submitted a four-command
burst without waiting and reached tic/sequence/exact-ledger/result count 5/5/5/5
through `SUBMIT_STEP` and `POLL_FRAME`.

The real localhost generated-AutoREST harness ran 300 moving, FIRE-every-8
frames through HTTP, browser payload decoding, palette application, and timed
presentation. A conservative depth-2/buffer-2 probe was rejected at 27.933 FPS
with 44 stalls and 62.497 ms p95 paint gaps. The existing depth-4/buffer-10
pipeline then passed at **32.029 displayed FPS**, 300 unique frames, zero stalls,
31.215/32.058 ms p50/p95 paint gaps, and 32.795 ms maximum. Submit p50/p95 was
16.270/34.949 ms and fetch p50/p95 was 62.936/73.962 ms; overlap and buffering
turn those latency distributions into stable throughput without synthesizing
input from prior responses. The frame-chain SHA was
`a1888c88d8fa779b9b90e8e650a8a5324f3085c21fe4b44f8e810b26b84be900`.

This is the first green local end-to-end Mocha 30 FPS gate. The selector stayed
guarded until the recovery, stale-generation, concurrent-session, audio, and
gameplay-defect gates passed; `GAME_ENGINE` now defaults to `MOCHA`, and every
test harness restores the selector it observed before removing its session.

An independent second 300-frame run reproduced the exact frame-chain SHA at
32.038 FPS, again with 300 unique frames and zero stalls. Its paint gaps were
31.219/31.976 ms p50/p95 and 32.777 ms max; submit p95 improved to 26.017 ms and
fetch p95 to 67.020 ms. This closes the two-fresh-run deterministic AutoREST
frame-chain gate without changing the selected configuration.

Two concurrent sessions then claimed two distinct Scheduler/OJVM workers. They
produced the same frame after 30 identical commands and different frames after
opposite turn commands, with 62 exact commands partitioned by lineage. A forced
Scheduler stop at tic 50 exposed a stale-owner defect: async `worker_status`
trusted `READY=1` without proving the job lived. It now verifies
`USER_SCHEDULER_RUNNING_JOBS`, causing submit to invoke the existing stale-
generation claim/restart path. The repaired gate advanced generation 382→383,
reconstructed from the committed ledger, and matched an uninterrupted twin at
tic 51 with 102 exact commands. Concurrent isolation, stale generation, forced
restart reconstruction, and no-lost-command seams are green.

A later clean regression found two recovery gaps hidden by the original gate.
First, a freshly stopped job could retain a recent heartbeat long enough for one
command to be durably queued to the dead generation. An aged `POLL_FRAME` now
performs the Scheduler lookup only on that exceptional tail, reconstructs the
worker, and migrates the exact stored command under a deterministic request id.
The final rerun advanced generation 529→530 and matched both tic-51 frames across
102 commands. Second, a failed `NEW_GAME` could leave an idle Scheduler job whose
owner session had already been deleted. Admission now force-stops and reclaims
only that provable orphan; active sessions are excluded. The same pass fixed
save/load predecessor chaining to use lineage-local tic 24 rather than abandoned
global sequence 34, preserved API error codes across cleanup, updated the durable
codec gate to raw DMF3, and made every gate restore its incoming engine selector.
Admission and Scheduler startup also derive map/engine identity from the immutable
lineage, eliminating a global-selector race; the next clean tic-zero gate passed
in 13.4 seconds and left `GAME_ENGINE=MOCHA` with zero orphan owners/jobs.

Cold initialization improved from 15.75-18.40 seconds interpreted to 5.29-6.21
seconds after native compilation. It is startup-only and belongs in the retained
Scheduler worker, never in an ORDS request session.

## Current gate status

### Async submit and fixed-pool requalification

ASH isolated the remaining long tail outside the measured Mocha stages. ORDS
was repeatedly describing generated AutoREST procedure signatures through
`USER_PROCEDURES`/`USER_ARGUMENTS`, and asynchronous `SUBMIT_STEP` still entered
the synchronous worker routine, including an empty response-AQ dequeue that
averaged about 16 ms and could never return an async response. The selected
fixes pin `jdbc.InitialLimit=jdbc.MinLimit=jdbc.MaxLimit=6`, retain warm workers
for 600 idle seconds, use a stale-heartbeat fallback for the expensive
Scheduler liveness query, and route async requests through `submit_async`.

Two consecutive warm 300-frame moving/FIRE-every-8 continuations passed at
30.751 and 32.050 displayed FPS with 300 unique frames each. Paint-gap p50/p95
was 31.185/32.080 and 31.206/32.052 ms. The second run had zero stalls and a
33.022 ms maximum; submit p50/p95 was 13.222/24.989 ms and input-to-frame
p50/p95 was 155.101/157.187 ms. The 47-class native audit passed with zero
classes requiring recompilation. Fresh post-redefinition runs retain cold
AutoREST/OJVM tails and are reported separately from steady play.

Authored audio, the four reported gameplay defects, selector cutover, save/load,
replay, concurrent isolation, and forced recovery are now green locally. The
remaining production evidence is the complete public E1M1 workflow and an
independent managed-ORDS/cloud run; neither is inferred from localhost results.

## Reproduction

```sh
bash scripts/mochadoom/deploy-ojvm-spike.sh
```

Then, in one connected DOOM session:

```sql
select doom_mocha_initialize from dual;
select doom_mocha_benchmark(300,30,25,0,0,8) from dual;
select doom_mocha_dispose from dual;
```

Then run `scripts/mochadoom/control-codec-gate.sql` and
`scripts/mochadoom/control-path-benchmark.sql` in that same connected schema.
The encoded component gate is `scripts/mochadoom/payload-path-benchmark.sql`.
The lineage/commit seams are
`scripts/mochadoom/durable-bridge-gate.sql` and
`scripts/mochadoom/durable-path-benchmark.sql`; both create and remove their
own isolated game session and refuse to borrow an occupied worker slot.
The real HTTP gate is `bash scripts/mochadoom/http-pipeline-gate.sh`.
