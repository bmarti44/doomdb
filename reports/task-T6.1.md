# T6.1 deterministic tic transaction report

Status: **PASS**.

## Delivered

- `sql/sim/tic/010_tic_transaction.sql` defines the internal, definer-rights
  `DOOM_TIC_TX.APPLY_BATCH` interface frozen by the approved evaluator.
- The session row is locked before request expansion. Exact JSON shape, command
  domains, one-to-four size, UTF-8 byte limit, and consecutive sequence ranges
  are validated before any append-only row changes.
- Canonical envelope, per-command, logical-state, and response documents use
  deterministic key and collection order with SHA-256 hashes. State identity
  excludes transport token, timestamps, and append-only cache/history rows.
- One command advances one logical tic at 35 Hz without consuming RNG. Control
  events use dense per-tic ordinals in Appendix F order: pause, menu, automap,
  then cheat.
- Exact current-range retries return cached BLOB bytes after taking the same
  session lock. Conflicts, old ranges, gaps, malformed documents, and unknown
  sessions propagate fixed application errors without transaction control in
  the package.
- Payload construction completes before response-cache persistence. The caller
  remains the sole owner of the transaction boundary.
- Bootstrap, teardown, root task routing, and the dynamic command schema include
  T6.1. `TIC_COMMANDS.CHEAT_CODE` is nullable because Oracle maps reviewed JSON
  `""` to SQL NULL; canonical JSON preserves the empty string through a raw JSON
  fragment rather than changing its command hash.

## Canonical evidence

The implementation was compiled against the pinned Oracle 23.26 database. The
frozen live evaluator then ran both identical and conflicting two-session races.

```text
PASS T6.1-EVAL-SELF-CHECK (70/70 fixture-contract assertions)
PASS T6.1-EVAL-MUTATION-SELF-CHECK (18/18 isolated mutations killed)
PASS T6.1-SOURCE-AUDIT (1 SQL files; locked set-based deterministic transaction)
PASS T6.1-ORACLE-PRODUCTION (19 live checks)
PASS T6.1-CONCURRENCY-DB (4 live checks)
PASS T6.1-CONCURRENCY-DB (4 live checks)
PASS T6.1-CONCURRENCY (4/4 identical and conflicting callers serialized exactly once)
PASS T6.1-VISIBLE (20/20 test ids, 430/430 declared assertions)
```

The canonical root route produced the same result:

```text
./verify.sh task T6.1
PASS T6.1-VISIBLE (20/20 test ids, 430/430 declared assertions)
```

## Integrity and regressions

```text
PASS T6.1-INTEGRITY (18/18 paths)
PASS T0.4 (8/8 assertions)
PASS T3.1-static (24/24 assertions)
PASS T1.2-static (10/10 assertions)
PASS T1.3 (12/12 assertions)
PASS secret ignore audit (8 ignored paths, 3 visible templates, no tracked secret-like paths)
```

The approved evaluator and its `integrity.pending-T6.1.json` manifest were not
edited. No credential value was written to source or verification output.
