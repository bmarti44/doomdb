# T8.2 public workflow evaluator

This evaluator freezes the complete presentation workflow without implementing
or importing production game logic. It drives in-session controls only as
versioned commands submitted to the public `DOOM_API.STEP` contract; a restart
creates a fresh session through public `NEW_GAME`, matching the live client.
Direct HTTP and pinned-Chromium paths independently exercise the same operations.

## Frozen control vocabulary

Menu actions are exact uppercase values `NONE`, `OPEN`, `DOWN`, `UP`, `SELECT`,
`BACK`, and `RESTART`. Automap STEP toggles `OFF` and `NORMAL`; `FULLMAP` toggles
the full relational view while automap is active. The four required cheats are
exactly `GOD`, `ALL`, `NOCLIP`, and `FULLMAP`. Aliases, case changes, surrounding
whitespace, and unknown values fail before mutation.

Section 5.4 intentionally exposes no public rewind procedure, while T8.2 requires
an arbitrary-tic rewind workflow and requires every feature to enter through
STEP. This evaluator closes that seam without expanding the public package:
`cheat:"REWIND:<tic>"` is a reserved workflow command, where `<tic>` is canonical
unsigned decimal. It restores a verified snapshot/history prefix into a new
continuation lineage. Logical tic returns to the target, but the public command
sequence remains globally monotonic. The old lineage remains replayable. This
reserved encoding is not one of the four player cheats.

## Exact observations

Pause and menu commands advance logical command history, but freeze player,
actor, sector, mover, switch, weapon, RNG, pickup, damage, and audio effects.
The evaluator brackets authoritative rows and verifies exact allowed changes.
It expands every response to 64,000 palette bytes, checks its canonical frame
hash, maps bytes through the actual `PLAYPAL` asset, and hashes raw Chromium
`getImageData()` RGBA bytes. No screenshot is treated as a golden.

Save/load and rewind continuations are compared tic by tic with uninterrupted
play. Replay is walked independently after the live session diverges and must
match stored state/frame/audio while leaving live rows unchanged. Death and
intermission are reached through frozen, no-cheat and cheat-assisted signed-axis
routes respectively. Restart must create a new session equal to a fresh E1M1
spawn for the retained skill, not partially resurrect dead state.

All HTTP requests are same-origin `application/json` POSTs to the seven fixed
AutoREST procedures. Redirects, external origins, base-table paths, internal
history packages, evaluator paths, console errors, failed requests, skipped
tests, missing sessions, and missing machine results fail closed.

## Entry points

Evaluator-only checks, which do not inspect unfinished production:

```text
node evaluator/t8.2/self-check.mjs
node evaluator/t8.2/mutation-self-check.mjs
node evaluator/t8.2/source-audit.mjs
```

The complete live gate is `bash evaluator/t8.2/run-visible.sh`. It requires a
real `DOOM_T82_BASE_URL`. It never substitutes mocks, empty discovery,
screenshots, or implementation-authored expected files for the real public paths.
