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

## Co-op route evidence

Active guest leave is now fixed to an exact future tic and reconstructs the
one-player frontier exactly. Long-route testing also found and fixed the
vanilla consistency-ring edge at rebirth: the adapter now copies Doom's actual
post-`DoReborn` ring word, and the formerly failing skill-3 prefix advances
through tic 4,200.

The solo route initially diverged because the harness packed held turns too
quickly and multiplayer used upstream's lossy short decoder. After both fixes,
poses match through tic 75. The remaining authentic difference is solo-only
damage knockback. A bounded movement correction plus eight late player-1 strafe
tics now reaches intermission at tic 762 with membership `03`; fresh replay
reproduces state SHA `dd7c3f04…1b59b7` and both terminal POV hashes. Private
trace tables perform no inserts when their diagnostic flag is off.

The canonical live gate also stops and drops the match's Scheduler worker at
tic 400. Fenced reconstruction resumes at exactly that frontier and the
replacement session completes tic 762 with the same state SHA and both POV
hashes as the uninterrupted accepted run. This closes the retained-worker-loss
route seam without weakening the dynamic two-player command path.

The browser transport seam is also live. Both independent contexts were active
when the ORDS container restarted and republished the generated API. The client
kept the database frontier authoritative, retried transport failures, refreshed
generation fences, and resumed both POVs; the guest then reloaded and both
clients reached synchronized tic 114. The measured local restart can exceed two
minutes, so automatic LEFT now follows a three-minute disconnected grace.
Explicit leave and match expiry are unchanged.

The deterministic engine fixture now additionally proves one-winner ordinary
ammo contention, retained netgame keys acquired by both players, and concurrent
fire/use bits in one ordered shared-world tic. These run beside mutual sprite
visibility, damage/death, frag attribution, and co-op reborn, and reproduce the
same canonical POV hashes in two clean initializations.

## Remaining P13 gates

The full two-browser route, remaining authored co-op interaction fixtures,
deathmatch selection,
capacity telemetry, the 300-frame two-browser run, and the 30-minute soak remain
open. T12 performance follows P13; P11 cloud deployment remains the final
milestone.

## Storage incident and retention response

Accumulated development lineages autoextended the local PDB beyond Oracle
Free's 12 GB limit. The cap is enforced when the PDB opens, so the disposable
local volume had to be rebuilt from source. That clean bootstrap exposed the
deployment-order defects listed above. Cleanup now runs every minute in bounded
batches and covers expired multiplayer matches as well as single-player
sessions, stopping their Scheduler owners before cascade deletion. This prevents
abandoned matches from being retained indefinitely; active-history bounding is
still required for the soak gate.
