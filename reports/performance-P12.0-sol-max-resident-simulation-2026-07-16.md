# P12.0 Sol Max retained-simulation review — 2026-07-16

This read-only Sol Max review reconciles the selected AQ/Scheduler worker,
17.590 ms static-renderer worker p95, rejected 42.373 ms live-snapshot p95,
24.162/36.939 ms conservative SQL simulation, and the first retained turn
kernel. Its conclusion is that 30 FPS remains plausible only when simulation,
canonical state writing, rendering, and delta persistence share one retained
state and never rebuild it from relational rows per frame.

## Selected implementation order

1. Split immutable catalogs, double-buffered session state, worker transaction
   control, canonical writer, and sorted dirty-row writer into cohesive classes.
2. Use `prepare -> relational commit -> accept`; `discard` on any pre-commit
   failure, and kill/reload the worker if commit succeeds but `accept` fails.
3. Keep stable primitive structure-of-arrays state, fixed-capacity work queues,
   dirty bitsets/sorted dirty indexes, and preallocated event/audio buffers.
4. Preload Oracle-built 64-angle movement values. Use `oracle.sql.NUMBER` only
   at exact arithmetic boundaries and doubles for conservative broad phases and
   rendering. The local follow-up matched 1,152/1,152 movement NUMBER byte
  representations and one exact quadratic root; lookup+exact-add measured
  0.54–0.69 microseconds/op and quadratic entry 9.7–15.0 microseconds/op.
5. Rewrite canonical state directly from retained arrays, hash the same bytes,
   write the command-state BLOB once, and reuse it for checkpoint envelopes.
6. Persist only sorted dirty rows with standard JDBC batching on the worker's
   default connection; microbenchmark and reject it if dirty DML exceeds 4 ms
   p95. Large BLOBs retain bounded locator writes.
7. Use durable request rows and AQ `ON_COMMIT` for production. The dequeue,
   relational deltas, histories, response, request completion, and completion
   token must commit atomically. Persistent request/command keys provide logical
   exactly-once behavior; generation fencing prevents stale workers writing.
8. Advance actors in deterministic phases over prior-tic state: common counters
   and state transitions, bounded wake/LOS queues, then actions/chase/collision
   in stable MOBJ order to preserve RNG and event order.

The smallest useful next parity corpus is a complete quiet/turn tic including
all common timers/state transitions, failing closed on any unsupported action.
Movement/collision/WALK/USE follows, then pickups/weapons/projectiles, monsters,
movers/specials, and audio. A hybrid that row-walks unimplemented subsystems in
the hot path is not selectable.

## Platform findings and caveats

- Oracle runs Java threads in one database session on one operating-system
  thread, so JavaBox-style renderer thread pools add coordination without OJVM
  CPU parallelism. See [Oracle JVM threading](https://docs.oracle.com/en/database/oracle/oracle-database/21/jjdev/threading-in-database.html).
- Standard JDBC batching is the supported path; Oracle's old proprietary update
  batching is deprecated. See [OraclePreparedStatement](https://docs.oracle.com/en/database/oracle/oracle-database/26/jajdb/oracle/jdbc/OraclePreparedStatement.html).
- Production AQ must use `ON_COMMIT`, not the disposable latency probe's
  autonomous `IMMEDIATE` visibility. See [Oracle AQ operations](https://docs.oracle.com/en/database/oracle/oracle-database/26/adque/aq-operations-using-pl-sql.html).
- Oracle's JDBC `NUMBER` exposes exact internal bytes and arithmetic operations;
  every selected expression still requires byte/text parity against SQL. See
  [oracle.sql.NUMBER](https://docs.oracle.com/en/database/oracle/oracle-database/26/jajdb/oracle/sql/NUMBER.html).
- JavaBox demonstrates persistent-VM/direct-buffer architecture, not measured
  sustained 30 FPS p95. Its canvas producer suppresses frames until 33 ms has
  elapsed while the browser repeatedly presents the latest buffer. Its Mocha
  Doom code is GPL-family and remains architectural evidence only—no code,
  tables, constants, data, or control flow may enter this MIT repository.

Required gates remain per-tic SQL/Java row/event/hash parity, NUMBER tangency and
tie cases, full T5–T7 and 163-route parity, batch/retry/concurrency semantics,
crash injection at every transaction boundary, generation fencing, and 30 warm
+ 270 unique integrated frames at no more than 33.3 ms p50 and p95.
