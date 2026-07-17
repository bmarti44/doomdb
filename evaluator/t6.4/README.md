# T6.4 history, save/load, rewind, and replay evaluator

This frozen evaluator is independent of production implementation. It imports
no production SQL, snapshot serializer, state hasher, replay package, or engine
code. The visible fixture uses a deliberately small noncommutative state machine
whose state and frame hashes are fixed in `expectations.json`.

## Frozen production boundary

Production provides one definer-rights, noneditionable package with unique,
non-overloaded public names:

```sql
DOOM_HISTORY.CAPTURE_TIC(p_session, p_state_sha, p_frame_sha)
DOOM_HISTORY.SAVE_GAME(p_session, p_slot, p_state_sha OUT)
DOOM_HISTORY.LOAD_GAME(p_session, p_slot, p_payload OUT BLOB)
DOOM_HISTORY.REWIND_TO_TIC(p_session, p_tic, p_payload OUT BLOB)
DOOM_HISTORY.START_REPLAY(p_session, p_from_tic, p_to_tic, p_replay_id OUT VARCHAR2)
DOOM_HISTORY.STEP_REPLAY(p_replay_id, p_payload OUT BLOB)
```

`DOOM_TIC_TX` invokes `CAPTURE_TIC` after authoritative state/events are complete
and before response construction. Neither package commits, rolls back, opens an
autonomous transaction, or uses dynamic SQL. The later public `DOOM_API` delegates
its fixed save/load/replay procedures to this boundary; rewind remains an internal
review/debug action until a public contract is separately approved.

Snapshots are schema-versioned canonical UTF-8 JSON BLOBs. They close over every
authoritative session, player, mobj, sector, line, mover, and switch field, plus
lineage and the global sequence/command/event chain frontiers. A blob hash protects
the complete envelope. Canonical logical-state and palette-frame hashes exclude
persistence metadata such as lineage and global command sequence, so identical
continuations after save/load or rewind can and must match uninterrupted play.

History is lineage qualified. `TIC_COMMANDS`, `GAME_EVENTS`, and `AUDIO_EVENTS`
are insert-only; restoration never updates or deletes them. Load and rewind restore
state into a deterministic new lineage while global command sequence continues
monotonically. The original lineage remains replayable. Periodic snapshots occur
at logical tics divisible by four in the compact model and differential fixture;
production uses the selected relational configuration
`HISTORY_SNAPSHOT_INTERVAL=64`, which the live oracle checks before temporarily
shortening its fixture and rolling that test-only change back.
Every save creates or reuses a complete checkpoint at its exact tic, including
non-periodic tics. Replacing a slot changes only the slot pointer.

Reconstruction chooses the greatest verified snapshot tic not exceeding the
target, then applies the exact ordered command range. Every predecessor command
hash, event hash, recomputed state hash, and recomputed frame hash is checked at
each step. Corruption, omission, duplicate event ordinal, reorder, incomplete
range, invalid slot/range, or unknown replay id fails before trusted frontier or
live state changes. `STEP_REPLAY` advances exactly one logical tic from cursor-
owned reconstructed state and never reads mutable live gameplay state.

Run the complete production-visible gate with:

```text
bash evaluator/t6.4/run-visible.sh
```

The source-policy audit can be reviewed before implementation with
`node evaluator/t6.4/source-audit.mjs`; `run-visible.sh` requires production.
