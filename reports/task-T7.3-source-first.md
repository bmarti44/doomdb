# T7.3 source-first implementation handoff

Status: **PARKED FOR ORDERED INTEGRATION**

The frozen T7.3 evaluator and manifest were not modified. This implementation
is intentionally absent from shared bootstrap, drop, verification, routing and
tic-transaction files while T7.1 and T7.2 production acceptance is pending.

## Delivered

- `sql/sim/070_audio.sql`: definer-rights `DOOM_AUDIO` package with the unique
  `EMIT(session,tic)` transaction-participant procedure.
- `sql/sim/staged/t7.3_schema.sql`: constrained relational audio definitions
  and `(asset_kind,asset_name)` provenance on `AUDIO_EVENTS`.
- `sql/sim/staged/t7.3_defs.sql`: the nine reviewed music/sound mappings with
  stable event classes and database-authored volume/separation.
- `sql/sim/staged/t7.3_tic_hook.sql`: the single owning-transaction delegation,
  parked separately to avoid editing the shared T6 transaction.
- `client/src/audio.mjs`: strict tuple cursor, one shared in-flight/decoded
  promise per asset, GET_ASSET-only transport, media decoding, consent queue and
  one-time ordered Web Audio scheduling.
- `tests/verify-t7.3-audio.mjs`: deterministic client unit checks including
  decode-completion reordering resistance.

The emitter filters by current session lineage, joins `GAME_EVENTS` through
`DOOM_AUDIO_EVENT_DEF` and `DOOM_ASSET`, sorts by logical event keys, and assigns
dense zero-based ordinals per tic. It contains no transaction boundary,
dynamic SQL, host randomness or wall-time behavior. Unmapped transitions are
silent.

The browser validates an entire response before starting any cache access,
rejects malformed, duplicate and reordered tuples, and advances only the
presentation cursor. Decoding can complete in any order without changing
logical scheduling order. The only conversions are database volume to gain and
database separation to stereo pan.

## Source-first evidence

```text
PASS T7.3-EVAL-SELF-CHECK (48/48 fixture-contract assertions)
PASS T7.3-EVAL-MUTATION-SELF-CHECK (24/24 isolated mutations killed)
PASS T7.3-SOURCE-AUDIT (database-authored tuples; GET_ASSET cache; presentation-only client)
PASS T7.3-AUDIO-UNIT (strict cursor, cache, decode, gesture, one-time scheduling)
PASS git diff --check
```

The source audit was applied to the real production boundaries with the staged
tic hook composed in memory. The shared tic source remains untouched as
required. Frozen evaluator manifest remains
`86211a491b3821ed4f3b3f463c222fb0827b9a6a9a7b615a72c86d194fa366ea`.

## Ordered integration

After T7.1 and T7.2 are accepted:

1. Apply `t7.3_schema.sql` after T6.4 history and apply `t7.3_defs.sql` after
   the seeded asset catalog.
2. Install `070_audio.sql`, then insert the staged hook exactly once after
   authoritative gameplay transitions and before state/history hashing.
3. Update the T6.4 audio trigger, audio-event hash function and replay union to
   hash `(asset_kind,asset_name)`; remove the now-nullable legacy `sound_id`
   compatibility column once those references are migrated.
4. Add the files to ordered bootstrap/drop/routing in the owning integration
   turn and expose only `DOOM_API.GET_ASSET` to the browser.
5. Run `bash evaluator/t7.3/run-visible.sh` in a fresh isolated Oracle/browser
   stack and require all 20 IDs / 684 assertions plus all 24 mutation witnesses.

No Oracle or Playwright service was started and no live acceptance is claimed
in this source-first turn.
