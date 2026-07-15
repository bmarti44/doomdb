# T7.3 audio events and browser assets

Status: **COMPLETE — PASS 684/684**

Route: `T7.3-IMPL | Terra | high | source-first plus ordered integration`.
The refreshed approved evaluator manifest is
`6267d2dcce1bf52136309c7bda6641325ac69ce1e95b506bf4b3812bd89e9da6`.
Production did not modify the frozen evaluator.

## Production implementation

`sql/sim/070_audio.sql` installs the unique definer-rights
`DOOM_AUDIO.EMIT(session,tic)` transaction participant. The ordered bootstrap
creates the constrained `DOOM_AUDIO_EVENT_DEF` relation, installs nine reviewed
sound/music mappings backed by `DOOM_ASSET`, and delegates once after all
authoritative gameplay transitions and before state/history capture.

The emitter is session- and lineage-scoped, ignores unmapped transitions, and
orders mapped events by `(tic,event_class,actor,target,source ordinal)` before
assigning dense zero-based per-tic audio ordinals. `AUDIO_EVENTS` now carries
only the relational `(asset_kind,asset_name)` provenance identity; the legacy
sound-only column and foreign key were removed.

T6.4 history was migrated with the schema: its insert trigger, canonical audio
hash function and replay verifier all hash and validate asset kind/name. This
keeps music and sound in one append-only predecessor chain without a parallel
or compatibility identity.

`client/src/audio.mjs` exports the frozen `createAudioPresenter({endpoint})`
boundary. It validates complete five-field tuple batches before cache access,
advances a strictly increasing logical cursor, shares one GET_ASSET/decode
promise per asset, queues before consent, and drains exactly once after an
AudioContext resume. A serialized drain preserves database order even when
network/decode promises finish out of order. Gain and pan are the only client
conversions.

Bootstrap, teardown and `verify task T7.3` routing now own all task files. The
existing TypeScript renderer bootstrap and review dashboard assets were left
intact.

## Verification

Two complete 537-seed / 32-entry bootstraps succeeded on a fresh isolated
Oracle 23ai stack. The second exercised package/table teardown and idempotent
reconstruction. The default database and dashboard containers were untouched.

```text
PASS T7.3-EVAL-SELF-CHECK (48/48 fixture-contract assertions)
PASS T7.3-EVAL-MUTATION-SELF-CHECK (24/24 isolated mutations killed)
PASS T7.3-SOURCE-AUDIT
PASS T7.3-ORACLE-PRODUCTION
PASS Chromium (2/2 strict browser cases, 2.2 seconds)
PASS T7.3-VISIBLE (20/20 test ids, 684/684 declared assertions)
PASS T7.3-HISTORY-CLOSURE
PASS T7.3-AUDIO-UNIT (including concurrent decode-order witness)
PASS T7.2-VISIBLE (25/25 test ids, 2565/2565 declared assertions)
PASS T7.1-VISIBLE (23/23 test ids, 1582/1582 declared assertions)
PASS T6.4-VISIBLE (28/28 test ids, 848/848 declared assertions)
PASS production object audit (0 invalid objects)
PASS git diff --check
```

The evaluator's Oracle and browser portions completed in seconds; no numeric
performance threshold was required. The isolated stack was removed with its
volumes after final verification.
