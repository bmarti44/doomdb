# P13 retained multiplayer checkpoint — 2026-07-20

## Result

The first end-to-end two-player slice works locally. Two independent browser
contexts create, join, ready, submit dynamic input, and poll distinct player
views through generated ORDS AutoREST. Oracle owns one retained Mocha Doom world
and advances it once for each complete ordered command vector. This is a
correctness checkpoint, not final multiplayer acceptance or a 30 FPS claim.

## Verified layers

- The OJVM adapter initializes one two-player netgame, consumes a 32-byte
  four-slot vector, advances one world/level tic, and renders immutable POVs.
- Private normalized tables enforce membership, generation, slot, sequence,
  command, frame, and checkpoint fences.
- One private Scheduler session owns each active match; public sessions can use
  only the seven allowlisted `DOOM_API` procedures.
- Java writes persistent response BLOB locators directly, committed with the
  command, state identity, frame identities, and frontier.
- HTTP gates prove arbitrary player arrival, idempotent retry, authorization,
  tic-zero polling, one-tic advancement, and distinct POVs.
- The browser gate proves private-fragment joining, bearer removal from the URL,
  two active contexts, live keyboard input, synchronized tic 11, and distinct
  canvases. Output and cleanup paths redact capabilities.

## Measurements

The pinned 300-sample adapter probe measured two POVs at 3.228 ms p50 and
5.670 ms p95 for the complete world-tic plus both renders/codecs. End-to-end
persistence, AutoREST, decode, and paint have not yet been measured over the
required 300 unique moving frames, so no multiplayer display-FPS is claimed.

## Integration defect fixed

Single-player `NEW_GAME` was synchronously purging expired sessions. A long
13,272-tic lineage made the request block because its frame-ledger result
foreign key lacked an index and LOB removal ran on the request path. Request
purging is removed, both cascade foreign-key paths are indexed, and bounded
cleanup runs in a separate Scheduler job.

## Remaining P13 gates

Deadline-neutral commands, disconnect grace/reconnect, multiplayer checkpoints,
exact worker reconstruction, fault injection, representative E1M1 co-op
mechanics, deathmatch selection, capacity/retention telemetry, the 300-frame
two-browser run, and the 30-minute soak remain open. T12 performance follows
P13; P11 cloud deployment remains the final milestone.
