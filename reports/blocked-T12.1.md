# T12.1 selected-engine evidence status

Status: **LOCAL IMPLEMENTATION ACTIVE; CLOUD EXECUTION DEFERRED TO FINAL P11**.

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

Local work remaining: update the reviewed manifest, require hashing those
actual replay bytes, add independent DMF decoding and the credential-private
local collector, then execute the three-pass protocol. Only managed-ORDS/S3
execution is blocked on final P11 credentials; local collection is not.
