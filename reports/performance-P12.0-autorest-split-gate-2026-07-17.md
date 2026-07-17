# P12.0 split AutoREST 30 FPS gate — 2026-07-17

## Result

The dynamic browser architecture passes the 300-frame local throughput gate.
Oracle remains authoritative for commands, simulation state, hashes, history,
rendering, compression, and response storage. The browser uses only generated
AutoREST procedures and displays decoded indexed frames.

Selected protocol:

- `SUBMIT_STEP`: idempotently records one live tic command in the durable worker
  ledger and returns its deterministic request identifier.
- `POLL_FRAME`: returns the immutable committed response for a command sequence.
- Depth-four command submission, exactly one result waiter, ordered decode, an
  absolute 32 ms command deadline, a 31.8 ms presentation clock, and a ten-frame
  startup buffer.
- Idle Scheduler workers back off from 5 ms polling and release their slot after
  60 seconds.

## Passing evidence

| Run | Frames | Unique | Display FPS | Paint gap p50/p95 | Notes |
| --- | ---: | ---: | ---: | ---: | --- |
| Fresh A | 300 | 300 | 31.064 | 32.154/33.040 ms | zero stalls |
| Fresh B | 300 | 300 | 30.924 | 32.274/33.110 ms | fresh worker repeat |
| Abandoned-worker load | 300 | 300 | 30.333 | 32.220/33.262 ms | second idle worker present |
| Instrumented exact run | 300 | 300 | 30.352 | 32.223/32.981 ms | retry-safe cold frontier |
| Selected post-index run | 300 | 300 | 31.083 | 31.214/32.357 ms | exact frontier uniqueness enabled |

The final 330-frame chain (30 warm frames plus 300 moving frames) is
`4d9a7a22dd8c3d02c37d40523e6f5d9fcec18665a374eccd7a9b63427d49b6fd`.
The client-side ordered hash and the independently aggregated Oracle result-row
hash are identical.

The live Chromium smoke test reached `30 FPS database pipeline active`, accepted
movement, advanced the player from the E1M1 spawn, and produced no application,
HTTP, or JavaScript errors.

## Rejected alternatives and defects fixed

- The first harness accumulated its 0–4 ms timer lateness into every subsequent
  command deadline, imposing an artificial ~29 FPS ceiling. Deadlines now
  advance from the prior absolute target.
- Three concurrent table waiters contended with the renderer on Oracle Free's
  two CPUs. Exactly one waiter is selected.
- Correlated response AQ regressed the full workload to 23.775 FPS even though
  its isolated ping-pong latency was good. Do not retry it without new evidence.
- Tightening the result-table poll from 50 to 30 ms regressed to 27.838 FPS.
  The additional queries cost more than the reduced wake quantization.
- Abandoned workers previously queried every 5 ms forever. Adaptive idle
  backoff plus the 60-second lease preserves multi-session throughput.
- Concurrent first-frame prefill raced worker ownership and caused a transient
  ORDS error. The browser now completes request 1/worker warmup before sending
  the remaining prefill commands.
- The command and display clocks are separate. Commands retain their 32 ms
  deterministic cadence; the 31.8 ms display clock consumes ready buffered
  frames with scheduling margin and does not alter simulation timing or hashes.

## Remaining P12.0 work

The ten-frame buffer adds roughly 320 ms of presentation latency and is a
throughput solution, not the final responsiveness target. Further renderer and
submit-tail reduction should shrink it. A rare cold maximum hitch also remains
visible even though p50/p95 and sustained FPS pass. Retained `use`, barrel
recursion, player projectiles, and the complete T5–T7 rerun remain before P12.0
is complete.
