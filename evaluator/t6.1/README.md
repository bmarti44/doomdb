# T6.1 deterministic tic transaction evaluator candidate

This is evaluator-only work pending explicit user approval. It adds no production
SQL, does not edit any earlier evaluator or the root verifier, and freezes no
visual golden. The route is Sol high because Appendix F ordering, transaction
serialization, and deterministic hashing are simulation-oracle work.

## Reviewed production interface

The internal package `DOOM_TIC_TX` exposes exactly one public procedure:

```sql
DOOM_TIC_TX.APPLY_BATCH(
  p_session  IN  VARCHAR2,
  p_commands IN  CLOB,
  p_response OUT BLOB)
```

It is not AutoREST-enabled. T10's `DOOM_API.STEP` will be a transport wrapper.
The package locks the `GAME_SESSIONS` row before expanding or validating input,
does not commit or roll back, and propagates every error so its caller controls
the transaction boundary. Application errors are fixed as malformed `-20861`,
conflicting accepted range `-20862`, uncached old range `-20863`, gap `-20864`,
and unknown/expired session `-20865`.

The successful response is UTF-8 canonical JSON stored in a BLOB, with exact key
order:

```json
{"v":1,"tic":101,"logical_hz":35,"first_seq":1,"last_seq":1,
 "command_sha":"<64 lowercase hex>","state_sha":"<64 lowercase hex>",
 "event_count":0}
```

Canonical command JSON has envelope order `v,commands`; every command has order
`seq,turn,forward,strafe,run,fire,use,weapon,pause,automap,menu,cheat`.
Insignificant input whitespace and member order do not change `command_sha`.
SHA-256 is over those UTF-8 canonical bytes. Each individual `TIC_COMMANDS`
hash covers the canonical command object alone.

The state document is the exact object emitted by `stateDocument` in
`reference.mjs`: schema/version; logical session fields (excluding random token,
timestamps, expiry, and cached/append-only transport history); every player
field; and every logical MOBJ, sector, line, mover, and switch field. Collections
are sorted by their declared deterministic keys. Decimal numbers use Oracle
locale-independent shortest plain decimal notation, negative zero normalizes to
zero, strings use JSON escaping, and null is JSON null. The final fixed member
is `"ordering_version":"APPENDIX-F-1"`. This version marker makes an ordering
change an explicit hash-contract change.

For T6.1's control-only scope, one command advances exactly one logical tic and
consumes no RNG. Control events use dense ordinals in this order: pause, menu,
automap, cheat. Their types are `CONTROL_PAUSE`, `CONTROL_MENU`,
`CONTROL_AUTOMAP`, and `CONTROL_CHEAT`. Later tasks insert their stage-specific
events after the Appendix F ordering rules; they may extend state and event
fixtures only through a newly reviewed dependent evaluator.

## Independent oracle and live coverage

The JavaScript oracle imports no production SQL, package, parser, or renderer.
It validates exact JSON before applying anything, models ordered control tics,
serializes complete logical fixture state, and owns checked-in state, command,
event, and payload expectations. Visible tests cover single, two-command, and
maximum four-command batches; split-versus-batched equivalence; token-independent
reproducibility; exact retry; conflict, old, gap, and malformed rollback; stable
event ordinals; and 35-Hz logical time.

The concurrency harness opens two real SQL*Plus sessions against one seeded
session. Identical workers must both commit and print the same response SHA while
the database contains one command and one response row. Conflicting workers must
yield exactly one success and one `-20862`, with one committed command and no
mixed control state. A worker crash, timeout, missing marker, incidental Oracle
error, or duplicate application fails rather than counting as serialization.

The manifest declares 20 stable IDs and 430 assertions. Eighteen isolated
semantic mutations cover the session row lock, sequence validation, retry cache,
canonical hashes, wall-clock contamination, 35 Hz, RNG consumption, simultaneous
event order, atomic rollback, token/ROWID coupling, payload-before-commit,
procedural shadow simulation, and evaluator coupling. `source-audit.mjs` is
intentionally red until the implementation exists.
