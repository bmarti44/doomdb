# P12.0 AutoREST-only 30 FPS design review

Date: 2026-07-16
Question: given a 20.323/25.109 ms database worker, a 19.521/25.316 ms scalar
AutoREST floor, a 23.109/39.131 ms committed 45 KB-frame replay, and a
47.919/52.925 ms active AutoREST step (all p50/p95), what is the narrowest
AutoREST-only design that reaches 30 displayed FPS? Constraints honored: ORDS
AutoREST only, no custom handlers, state/rendering stay in Oracle.

Status labels: MEASURED (Codex's numbers), ARITHMETIC (derived from them),
HYPOTHESIS (must be benchmarked).

> Codex reconciliation: the scalar numbers were already measured with a
> persistent Node `fetch` connection, not per-request `curl`. Pool 4 later
> settled at 12.912/18.462 ms. Measured depth two and three reached only 22.666
> and 28.099 FPS; depth four plus a six-frame presentation buffer produced the
> first cadence-only pass. Fresh runs still lack 270 unique frames. A local
> active-frame extraction also found naive XOR deltas larger than independent
> compressed frames, so that codec is rejected unless a different transform is
> proposed and measured. These results supersede the hypotheses below without
> changing the report's latency-versus-throughput distinction.

---

## 1. The decisive arithmetic

The four measurements are mutually consistent and tell one story:

- Active step 47.9/52.9 ≈ scalar floor 19.5/25.3 + worker 20.3/25.1 + a few ms
  of AQ/payload marginal cost. The path is a SERIAL chain:
  HTTP → enqueue → worker tic → dequeue → HTTP response. ARITHMETIC.
- A serial chain can never reach 33.3 ms while its two big stages sum to ~40 ms
  at p50. Even a perfectly tuned floor (~5 ms) leaves serial p95 at
  ~25.1 + ~10 ≈ 35 ms — still over. ARITHMETIC.
- Therefore the answer is not more tuning of the serial path. **30 displayed FPS
  is a throughput property; 33.3 ms round-trip is a latency property. The gate
  (rule 12: 30 unique moving frames/s at p50 and p95 over ≥270 frames) is a
  throughput gate.** Pipelining decouples them: with one request in flight while
  the previous frame is decoded/displayed, steady-state inter-frame time =
  max(stage times), not sum. ARITHMETIC.

Pipelined steady state with TODAY'S untuned numbers:

| Stage | p50 | p95 |
|---|---:|---:|
| Worker tic (request-through-commit) | 20.323 | 25.109 |
| Transport (floor + 45 KB payload marginal) | ~23.1 | ~39.1 |
| **Serial (today)** | **47.9** | **52.9** |
| **Pipelined = max(stages)** | **~23.1** | **~39.1** |

Pipelining alone almost makes it; the transport stage's p95 (39.1) is the only
number over 33.3, and ~25 ms of it is the untuned scalar floor. Fix the floor
and the bottleneck becomes the worker at 25.109 ms p95 → **39.8 FPS p95
ceiling**, with ~8 ms of jitter headroom against the 33.3 ms bar. ARITHMETIC.

So the narrowest design is: **(1) attack the scalar floor, (2) depth-2 client
pipelining on the existing correlated step API, (3) delta codec only as
reinforcement.** No new server architecture, no charter change.

---

## 2. The scalar floor is the anomaly — attack it first

19.521/25.316 ms for an AutoREST call that does no work is 3–10× out of line;
localhost ORDS AutoREST round trips are typically low single-digit ms. Before
any config change, rule out a measurement artifact:

- If the floor was measured by spawning `curl` per request, process startup +
  TLS/TCP + no keep-alive is ~10–20 ms of pure artifact. Re-measure with a
  persistent HTTP client (Node/Java loop or browser `fetch` over a kept-alive
  connection, 300+ sequential calls, report p50/p95). HYPOTHESIS — likeliest
  single explanation.
- Attribute what remains by subtraction: ORDS standalone access log `%D`
  (request duration) vs DB-side time for the wrapper call (v$sql elapsed for the
  AutoREST anonymous block). Floor = client→ORDS + pool checkout +
  ORDS↔DB round trips (incl. the unconditional
  `dbms_session.modify_package_state(reinitialize)`) + response write.

ORDS/pool tuning candidates, in expected-impact order (all HYPOTHESIS until
measured, all standard `ords config set`):
1. Pool warm + sized: `jdbc.InitialLimit` = `jdbc.MinLimit` ≥ 4 (two in-flight
   steps hold two connections in dequeue-wait; keep spares),
   `jdbc.MaxLimit` ~8–10. A cold/undersized pool serializes requests behind
   connection creation — exactly a ~20 ms symptom.
2. `jdbc.MaxConnectionReuseCount` / `jdbc.MaxConnectionReuseTime` raised so
   connections are not being recycled mid-benchmark (each recycle = fresh
   session + OJVM/package warmup on next use).
3. HTTP: confirm keep-alive is on (default), consider
   `standalone.http.port` plain HTTP for the local demo (no TLS handshakes),
   and gzip: base64 JSON compresses ~25–30%; only matters at 45 KB payloads,
   irrelevant after the delta codec.
4. Confirm ORDS container CPU allocation does not overlap the DB's 2-core cap
   (compose currently caps only the DB service; contention shows up as floor
   jitter, not p50).

Target after this step: scalar floor ≤6 ms p50 / ≤10 ms p95. If a correctly
measured floor will not go below ~15 ms, report that number back — it changes
§4's conclusion arithmetic and makes the delta codec mandatory rather than
reinforcing.

---

## 3. Design A (selected): depth-2 pipelining on the existing correlated step

No server change. The browser keeps exactly one extra step in flight:

- t=0: send step(tic N+1) carrying current input state; immediately begin
  decoding/blitting the already-received frame N.
- Response N+1 arrives while the user watches frame N; send step(N+2) on
  arrival (or on a 30 Hz pacing timer, whichever is later).

Doom's input model makes this safe: a ticcmd is keyboard/mouse STATE, not a
request/response dependency — the client never needs frame N to compose the
command for tic N+1 (vanilla Doom does exactly this; absent new input the last
ticcmd repeats). Commands remain per-tic, correlated, durably recorded in
tic_commands — determinism/replay parity is untouched, so **no amendment is
needed**. The worker consumes the AQ queue sequentially exactly as today; two
in-flight requests just means the queue is never empty.

Client mechanics: two parallel fetches over HTTP/1.1 keep-alive (or one HTTP/2
connection); a pacing timer clamps sends to one per 33.3 ms so the pipeline
depth stays at 2 and latency does not grow unboundedly; a sequence counter
drops/reorders any out-of-order completion (shouldn't happen — AQ is FIFO per
worker — but cheap insurance).

Reported metrics (keep them separate, as asked):
- **Steady display throughput**: distribution of inter-frame display gaps over
  ≥270 moving frames. Gate: p50 AND p95 ≤ 33.3 ms. Expected after §2:
  bottleneck = worker 25.1 ms p95 → ~39.8 FPS ceiling, gate green with ~8 ms
  margin. ARITHMETIC.
- **Input-to-corresponding-frame latency**: keydown timestamp → paint of the
  frame whose tic consumed that ticcmd. With depth 2 this is up to one
  in-flight tic + own tic + transport ≈ p50 ~45 ms, p95 ~60–65 ms (~1.5–2 tics)
  with today's worker; ~40–55 ms after floor tuning. This is normal for 35 Hz
  Doom-family engines (vanilla runs 1–2 tics of input buffering) and should be
  reported as a number, not hidden inside the FPS claim. ARITHMETIC.

## 3b. Design B (fallback only): free-running worker + input register + frame poll

Recorded for completeness: worker self-paces at 35 Hz consuming a
last-writer-wins input register; client POSTs input changes and GETs the latest
committed frame on its own cadence. Decouples everything, but it changes the
command model (input register vs per-request correlated command), touches the
amendment's "enqueue command, wait for correlated committed response" wording,
and adds an idle-burn question (worker ticking with no players). Only escalate
here if Design A's measured inter-frame p95 misses after §2 — do not pay the
charter cost speculatively.

---

## 4. Delta response codec — reinforcement, not the load-bearing fix

Marginal payload cost today is only ~3.6 ms p50 (replay 23.1 − floor 19.5), so
the codec cannot rescue the serial path — but in the pipelined design it hardens
the transport stage and cuts browser decode:

- Doom frames are temporally coherent; XOR-vs-previous + the existing RLE/gzip
  packing typically collapses 45 KB to a few KB in corridors, ~10–15 KB in
  heavy motion. HYPOTHESIS — measure on the 270-frame moving route, report the
  payload-size distribution not just the mean.
- Keyframes: full frame every 32 tics, aligned with the checkpoint cadence so
  recovery/replay boundaries coincide; client requests a keyframe on any gap
  (sequence skip, decode error). The response header (already versioned) gains
  frame_type=key|delta + base_tic.
- Parity discipline unchanged: the delta stream must reconstruct byte-identical
  framebuffers vs the SQL renderer oracle at every tic (same SHA chain), so the
  codec is a pure transport encoding, not a rendering change.

Order it AFTER §2 and §3: if floor tuning lands, the codec converts "green with
8 ms margin" into "green with ~15 ms margin" and roughly halves client decode
time; if floor tuning stalls at ~15 ms, it becomes mandatory to pull transport
p95 under 33.3.

---

## 5. Bounded experiments (≤3, in order)

1. **Floor attribution (half a day).** Re-measure the scalar floor with a
   persistent keep-alive client; attribute via ORDS access-log `%D` vs DB-side
   elapsed; apply §2 pool settings; re-measure. Pass: ≤6/≤10 ms p50/p95, or a
   documented irreducible floor number.
2. **Pipelined client prototype (one day).** Depth-2 pipeline in the existing
   TS client against the current correlated step API, 300-frame moving route.
   Measure inter-frame display gap p50/p95 and input-to-frame latency
   separately. Pass: gaps ≤33.3 ms p50 AND p95. This is the gate experiment —
   it can pass even before experiment 1 lands if transport p95 happens to sit
   under 33.3 on the day.
3. **Delta codec (one–two days).** XOR+pack delta with 32-tic keyframes, parity
   SHA chain vs oracle, payload-size distribution + new transport p95. Pass:
   byte parity at every tic and transport p95 comfortably under the worker's
   p95 (i.e., worker remains the sole bottleneck).

Sequencing note: experiments 1 and 2 are independent and can run in parallel;
3 depends on neither but is only worth building once 2's harness exists to
measure it.

---

## 6. Honest-reporting requirements for the eventual claim

- The 30 FPS claim must cite the inter-frame gap distribution (p50/p95, ≥270
  unique moving frames, per rule 12), with input-to-frame latency reported
  alongside it as a separate number — never conflated.
- The pipeline depth (2) and pacing policy must be stated in the claim, since
  they are part of the displayed-throughput definition.
- Benchmark validity: the projectile-lifecycle leak makes long runs
  non-stationary; use matched-length runs until removal lifecycle lands, and
  state the retained-object count at start/end of any run used for a claim.
