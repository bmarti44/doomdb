# T12.0 OJVM production-shaped kernel spike

Date: 2026-07-15

The reproducible disposable probe is
`artifacts/performance/t12.0/ojvm-kernel-handoff.sql`. It creates no persistent
production object and verifies zero probe/invalid objects after cleanup.

The probe deliberately exercised the brute analytic architecture before a full
renderer was written: 320 columns by 2,057 segment determinant/intersection
tests, 64,000 indexed samples, sparse presentation writes, SHA-256, column RLE,
canonical-shaped JSON, GZIP, and mutation of a PL/SQL-created BLOB locator. Its
compressed payload was 244,435 bytes, larger than the current exact 92,658-byte
response and therefore a conservative codec/handoff workload.

After 10 warmups, 30 unique seeds measured:

| Metric | Result |
| --- | ---: |
| p50 | 1,133.882 ms |
| p95 | 1,461.524 ms |
| p99/max | 3,223.690 ms |
| compressed payload | 244,435 bytes |

An explicit `DBMS_JAVA.COMPILE_CLASS` attempt on the monolithic probe did not
finish after several minutes. The database alert log reported the JIT process
requesting a full stop. The server session was killed, all disposable objects
were dropped, and the database returned to zero invalid objects. This is a
failed JIT/code-shape gate, not a 30 FPS result.

The brute analytic route is rejected. The next kernel must split hot methods so
they can be compiled and must reduce work before sampling: front-to-back BSP
traversal, bounding-box rejection, solid screen-column coverage, wall columns,
plane spans, and primitive masked fragments. Its generated corpus must match the
real run-count and compressed-size distribution. It must pass <=20 ms p95 before
production integration.
