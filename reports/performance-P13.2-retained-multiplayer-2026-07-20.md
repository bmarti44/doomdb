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
- A missing command is durably synthesized as neutral after 75 ms, an idle slot
  transitions to `DISCONNECTED`, and the same capability resumes that slot.
  The browser gate reloads one active player and reconverges at tic 23.
- Tic 32 writes a native Mocha save directly into the durable checkpoint BLOB.
  Its byte count, SHA-256, and state identity are verified in the same frontier
  transaction.
- Native save/load was explicitly rejected for recovery because it restored the
  world but not the exact POV hashes. A fresh OJVM session instead replayed all
  32 durable ordered vectors with the production render cadence and reproduced
  the exact final state SHA and both player frame hashes.
- A clean-volume bootstrap exposed and fixed missing Mocha teardown tables,
  stale finalizer object names, and a missing OJVM renderer-call deployment
  step. The corrected finalizer reports zero invalid runtime objects.
- Recovery is wired into the public poll path. A forced Scheduler loss after
  tic 33 was detected from its stale heartbeat; a replacement generation
  replayed the ledger, migrated the accepted partial tic-34 command, published
  the same selected POVs, recorded the missing peer as neutral, and returned
  the tic-34 frame through `DOOM_API`.

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

Bounded final-leave semantics, broader fault injection, representative E1M1 co-op
mechanics, deathmatch selection, capacity/retention telemetry, the 300-frame
two-browser run, and the 30-minute soak remain open. T12 performance follows
P13; P11 cloud deployment remains the final milestone.
