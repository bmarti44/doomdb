# Voided de-CPS diagnostics

- `interpreter-2848ef7a8dc4-500-void.log` is the first harness invocation. The
  candidate was loaded in the DOOM schema, but the replay block was
  accidentally sent through a SYS connection and failed at PL/SQL compilation.
  It contains no timing marker. The runner was corrected to use `db_sql.sh`;
  both subsequent interpreter cells passed.
- `hidden-jit-2848ef7a8dc4-500.log` and
  `hidden-jit-hot-2848ef7a8dc4-500.log` contain no replay terminal marker.
  Both unsupported hidden-compilation cells parked for more than five minutes
  and were terminated by full session incarnation. They are operational
  failure observations only.

All three runs restored the pinned production module and retained warm pool.
The clean 5,250-tic interpreter run is the only permanent Oracle rank result in
this directory.
