# T7.3 audio events and browser assets evaluator

This evaluator freezes a database-authored audio boundary. Production provides
one non-overloaded `DOOM_AUDIO.EMIT(session,tic)` invoked once at Appendix F step
11. It joins authoritative `GAME_EVENTS` to relational
`DOOM_AUDIO_EVENT_DEF`, resolves seeded `DOOM_ASSET` sound/music identities and
inserts session/lineage-scoped `AUDIO_EVENTS`. Ordering is logical
`(tic,event_class,source_id,target_id,source_event_ordinal)` and audio ordinals
are dense from zero per tic. The payload shape remains exactly
`[tic,ordinal,asset,volume,separation]`.

The reviewed scenario matrix covers E1M1 music, player weapon/pain, pickups,
doors, monster wake/pain/death and barrel explosions. Unmapped transitions are
silent. `AUDIO_EVENTS` uses `(asset_kind,asset_name)` so the same stream can
referentially contain both `sound` and `music`; production must migrate the old
sound-only column/trigger without weakening asset provenance.

The client exports `createAudioPresenter({endpoint})`. It validates a strictly
increasing tuple cursor, rejects duplicates/reordering/malformed tuples, caches
one in-flight or decoded buffer promise per asset name, and obtains bytes only
by JSON POST to `DOOM_API.GET_ASSET`. It may fetch/decode before consent but
schedules nothing until a user gesture resumes `AudioContext`. Gain/pan are
presentation-only conversions of database volume/separation. It never examines
frames, state hashes, commands, gameplay tables, or local simulation state.

Candidate checks:

```sh
node evaluator/t7.3/self-check.mjs
node evaluator/t7.3/mutation-self-check.mjs
node evaluator/t7.3/source-audit.mjs
```

After T6.4, T7.1, and T7.2 production acceptance, run:

```sh
bash evaluator/t7.3/run-visible.sh
```

The live path runs Oracle session/rollback checks and pinned Chromium with strict
console/page/request guards. It fails closed while either production boundary is
absent. No mutable production source is pinned by this candidate.
