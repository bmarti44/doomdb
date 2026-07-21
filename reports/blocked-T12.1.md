# T12.1 selected-engine evidence status

Status: **LOCAL COMPLETE; MANAGED CLOUD EXECUTION DEFERRED TO FINAL P11**.

The original source-first evidence driver targeted the retired production
shape: synchronous SQL-renderer `STEP`, gzip canonical JSON, and SQL R1/R2
stages. The selected runtime is now a retained Mocha Doom engine inside OJVM,
with generated AutoREST submission/polling and DMF3/4/5 frames. Filling the old
fields with zeroes or profiling the SQL oracle as production would be invalid.

The reconciled contract keeps the frozen statement-family names while mapping
them to real production surfaces:

- `step`: `DOOM_API.SUBMIT_STEP`;
- `frame`: `DOOM_API.POLL_FRAME`;
- `asset`: `DOOM_API.GET_ASSET`.

The required 90-call cursor/`ALLSTATS LAST` matrix is a separate attribution
pass. Primary FPS evidence comes from two identical 300-frame browser replays
with diagnostics off. A third exact-chain replay collects prepare, ticker,
render, codec, BLOB, finalize, commit, ORDS, transfer, decode, palette, blit,
and correlated-input stages. Legacy `r1Ms`/`r2Ms` remain documented aliases,
not fabricated SQL-renderer timings.

The prior replay identity `c393f8f…` had no corresponding bytes anywhere in
the worktree or reachable history. It must never be accepted on a caller's
declaration alone. The real selected-engine fixture is now tracked at
`artifacts/performance/t12.1/mocha-replay-300.json`, derived from the accepted
skill-3 route and content-addressed as
`1ad47bc8e2a5b7518d68b937a333492d66d7d539f827980086d4b4fdad327fe3`.
Its source, expansion, command/phase coverage, and bytes pass an independent
gate.

The reviewed manifest now pins the actual fixture bytes. The async production
driver independently decodes and hashes DMF3/4, and the credential-private
collector passed a real 300-frame run plus exactly 90 submit, poll, and asset
AutoREST invocations with internal `ALLSTATS LAST` anchors. Production and
independent evidence validators pass. That run measured 25.54 serial FPS after
the poll-wait fix; the live depth-2 browser path measured 30.91 displayed FPS
with 33.0 ms paint-gap p95.

The exact fixture subsequently completed two independent browser runs at 31.70
and 31.56 FPS. Both browser runs and the private stage-attribution run have
identical 300-state (`a4af25da…e4b3c`), frame (`e14a8f7e…1d19a`), and payload
(`b91ce8c7…a0f2`) chain digests. `verify.sh task T12.1` fails closed on any
missing artifact, sub-30-FPS browser run, chain drift, missing commit samples,
clock anomaly, or artifact-integrity failure.

No T12.1 local work remains. Managed ORDS/S3 repetition stays deferred to final
P11; T12.2 owns the next local optimization/stop-rule ledger.
