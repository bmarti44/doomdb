# T12.0 state, history, and gameplay-route optimization

Date: 2026-07-16

This checkpoint keeps simulation and authoritative state in Oracle SQL/PLSQL.
It does not claim that the public STEP path or dynamic renderer has passed the
30 FPS gate.

## Selected changes

- Canonical SQL/JSON now returns AL32UTF8 BLOB directly, with bounded inner
  `VARCHAR2(4000)` row objects.  A real modern state remained byte-for-byte
  identical at 211,307 bytes and SHA-256
  `f60aad...938c`.
- `TIC_COMMANDS.STATE_BLOB` is written through the persistent SecureFile
  locator returned by the command insert.  This avoids a second full-row BLOB
  assignment.
- Interval history wraps the already-canonical state BLOB directly in a BLOB
  JSON envelope.  It no longer converts state BLOB to CLOB and back on every
  fourth tic.
- Stationary tics skip impossible WALK-trigger and swept-movement scans.
- Hitscan combat uses one exact bounded collision ray.  The previous code
  expanded the complete 320-column renderer for every pellet.
- Monster perception joins the immutable REJECT relation once, computes exact
  visibility in the actor snapshot, and bounds LOS candidates through the WAD
  BLOCKMAP before retaining the reviewed determinant/intercept ordering oracle.
- The 163-command opening route has an opt-in DBMS_PROFILER mode via
  `DOOMDB_PROFILE_ROUTE=1`.

## Measurements

The same clean-restart, 30-warmup, 270-committed-turn driver previously measured
36.842 / 49.503 ms p50/p95.  After the selected state/history changes, the best
clean run measured 21.260 / 30.856 ms.  A later conservative restart repeat
under Oracle background activity measured 24.162 / 36.939 ms with one 139.086
ms outlier.  Both are recorded; the lower observation is not used as proof of
the final p95 gate.

The exact moving/firing 163-command route changed more dramatically:

| Revision | Wall time | Approx. simulation throughput |
| --- | ---: | ---: |
| Full renderer invoked for each hitscan pellet | >9 minutes | <0.3 tic/s |
| Single bounded combat ray | 9.5 s | 17.2 tic/s |
| Set-based REJECT + BLOCKMAP-bounded LOS | 5.5 s | 29.6 tic/s |

The route figures include SQL connection, fixture construction, checks, and
cleanup, so they are not a frame-time distribution.  They are useful evidence
that real moving/firing work—not only stationary turning—improved while every
route checkpoint remained exact.

DBMS_PROFILER first attributed 3,380.641 ms over 1,902 LOS calls on the route.
After batching and BLOCKMAP candidate reduction, the actor snapshot is the
largest route unit at about 1,157.735 ms over 163 tics.  Canonical state JSON is
about 0.91-1.16 seconds over the route.  These two structural slices remain the
main simulation targets.

The compiled OJVM renderer/packed-v2/BLOB kernel remains 10.517 ms p95, but it
is currently a complete tic-zero parity kernel, not a dynamic production STEP
renderer.  Adding the conservative latest simulation p95 gives 47.456 ms before
ORDS/browser work.  Therefore the game is not yet a verified 30 FPS public
experience.

## Rejected experiments

- Six-query OJVM state serialization was exact but measured 69.286 / 106.270
  ms p50/p95; JDBC row walking dominated and the spike is not integrated.
- SecureFile LOB deduplication improved p95 by less than 1 ms and was reverted.
- Removing ordered LOS selection failed the T7.2 source contract; the unordered
  existence experiment was immediately reverted.

## Correctness

The selected revision passes T6.1-T6.4 and T7.1-T7.3 adjacent evaluator,
mutation, history, replay, concurrency, lifecycle, integrity, branch-isolation,
audio, and exact route gates.  The final full-suite rerun is required again at
the commit boundary.
