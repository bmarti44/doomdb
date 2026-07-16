# T12.0 packed-v2 caller-owned BLOB handoff

Date: 2026-07-15

The disposable gate in
`artifacts/performance/t12.0/ojvm-packed-blob-handoff.sql` writes the measured
42,140-byte packed-v2 GZIP payload size into one PL/SQL-created temporary BLOB.
The Java stored procedure owns no locator lifecycle and creates no temporary
LOB. Three OJVM Java 11 locator interfaces were measured after 200 warmups over
1,500 samples each.

| Handoff | p50 | p95 | p99 |
| --- | ---: | ---: | ---: |
| One `Blob.setBytes` call | 0.085 ms | 0.252 ms | 0.505 ms |
| Two bounded `Blob.setBytes` calls | 0.093 ms | 0.232 ms | 0.383 ms |
| One `Blob.setBinaryStream` write | 0.159 ms | 0.434 ms | 2.276 ms |

Every path produced exactly 42,140 bytes with SHA-256
`b0645abb2d73cb5ad8f2b891a430a375abe0b1158aee7d517120e98051ebecf0`.
Cleanup left zero probe objects and zero invalid database objects.

The selected path is two locator writes: 32,767 bytes followed by the
remainder. It has the best measured p95 and keeps each call inside the
documented internal-driver data-interface bound. The measured packed codec
p95 is 1.800499 ms, so the conservative component sum is 2.032499 ms for
codec+BLOB, comfortably inside the 5 ms gate. Renderer+codec p95 is 6.811515
ms; adding the selected handoff component yields 7.043515 ms. This sum is not a
substitute for the required compiled OJVM combined measurement.

The next gate loads the real renderer/codec class into OJVM, requires every hot
method to report native compilation, and measures the combined render,
packed-v2 codec, and selected caller-owned BLOB write in one database call.
