# T8.1 `NEW_GAME` render profiling

Date: 2026-07-15

Environment: isolated `doomdb-t81-live` stack on port 25481.

## Blocker isolation

- A production `doom_api.new_game(3)` call with four pre-existing game
  sessions exceeded 299.92 seconds before returning or committing.
- A staged tic-0 render showed `doom_history.save_game` completing in less
  than 0.01 seconds and `frame_column` setup in 0.01 seconds.
- The `frame_pixel` insert from `doom_api_presentation_rows` exceeded 200
  seconds. RLE, JSON, frame hashing, and compression had not started.
- Direct `doom_r2_pixel_rows` evaluation exceeded 70 seconds. The presentation
  explain plan contained roughly 1,380 operations and repeatedly expanded the
  R1 hit, R2 portal-hit, and sector-interval relations before the outer session
  predicate.

## Non-shipping optimization probe

A relational-equivalence probe derived wall hits and sector intervals from one
local portal-hit CTE. Direct world rendering improved to 53,760 rows in 35.39
seconds (from greater than 70 seconds), and the plan shrank to 286 operations.
The analogous masked probe returned 10,789 rows in 40.67 seconds (from greater
than 50 seconds).

These renderer edits were reverted. T5.2 freezes the exact SHA-256 identity of
`sql/render/r2/020_pixels.sql`, so changing that reviewed source would violate
the golden contract even if the rows were identical. No evaluator, golden, or
locked-manifest files were changed.

## Clean baseline

All obsolete evaluator sessions were deleted and committed. With
`GAME_SESSIONS=0` and no active DOOM database sessions, the original committed
renderer completed a single public `doom_api.new_game(3)` in 121.79 seconds,
within the 180-second bound:

- session: `f5c560edf961fb6373e0c0cf47814af3`
- tic: `0`
- compressed payload: `92,658` bytes
- state SHA-256: `3e05a3305cd738a2115b2a233fedad173a6a81f664621d81d0363c46482ab640`
- frame SHA-256: `1e9b6e40177c1234a87159cdc69cac93e968c7da4f1f54389a8426286f12d90f`

Slot 96 was saved in 0.15 seconds with the same state SHA-256. This isolates
the observed production timeout to multi-session renderer fanout rather than
tic-0 initialization, history, RLE/JSON aggregation, hashing, or compression.
Multi-session scaling belongs in the later performance phase; the frozen
renderer remains unchanged for the current evaluator handoff.
