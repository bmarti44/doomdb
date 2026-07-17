# P12.0 AutoREST worker integration — 2026-07-16

## Result

`DOOM_API.STEP` now selects the retained AQ/Scheduler worker for an eligible
single DMSC/v2 movement command. The selection is session- and command-driven;
it contains no fixed route. Unsupported batches and fire/use/weapon/UI actions
continue through the complete SQL path until their retained parity slice lands.

The first reused-connection 20-frame HTTP run measured 58.699/83.536 ms
p50/p95. Moving worker selection ahead of the legacy SQL canonicalization then
reduced the active path to **47.919/52.925 ms**. The matching database request
distribution is 20.323/25.109 ms, so the public 33.3 ms gate is still open.

## Correctness and failure isolation

- Deterministic request IDs return immutable committed responses after a lost
  response, including after the durable game frontier has advanced.
- A repeated ready-worker `CLAIM` leaked its `FOR UPDATE` row lock. The worker
  then waited 10--30 seconds on its own control row even though its stage sum
  was about 23 ms. The ready path now commits before returning.
- `AUTOREST_WORKER_STEP_OK` verifies two claims, one dynamic public package
  step, one committed worker request, matching tic/sequence, and a nonempty
  frame. The measured reconstructed-worker package call was 45.082 ms.
- The client no longer appends a trailing slash to case-sensitive package
  procedure paths; the pinned ORDS image returns 404 for that POST shape.

## Boundary attribution

- retained database request: 20.323/25.109 ms p50/p95
- active AutoREST request after early selection: 47.919/52.925 ms
- immutable full-frame AutoREST replay, 100 requests: 23.109/39.131 ms
- scalar AutoREST floor, 20 requests: 19.521/25.316 ms

The remaining public optimization must treat displayed-frame throughput and
corresponding-input latency separately. The bounded candidates are ORDS pool
configuration, a one-frame asynchronous pipeline, and a smaller retained
response/delta codec. Browser traffic remains AutoREST-only and SQL remains the
independent simulation/render oracle.

## Pipelined follow-up

Pool 4 settled the scalar floor at 12.912/18.462 ms p50/p95. Depth two and
three active pipelines reached only 22.666 and 28.099 completed FPS. The
selected feasibility shape is therefore a hard depth-four request window, a
32 ms deadline/catch-up dispatch clock, ordered decode, and a six-frame
presentation buffer.

The best 300-frame cadence-only run measured 30.350 displayed FPS with
32.135/33.083 ms paint-gap p50/p95. Input-to-decoded-response latency remained
70.417/169.555 ms and is reported separately. A fresh-session repeat reached
31.039 FPS and 32.197/33.103 ms gaps but only 112 unique frame hashes. A more
active fresh input pattern produced 113 unique hashes and missed cadence at
28.921 FPS. The final public gate therefore remains open until one run has at
least 270 unique moving frames and the selected paint cadence.

Longer execution also found an exact boundary at `x=-192`: double BSP lookup
returned sector 141 while Oracle NUMBER lookup returned 99. The transaction
rolled back. Final movement location now uses the exact SQL tie rule after
portal traversal; the failed command commits and `sim_movement_parity=270/270`.
