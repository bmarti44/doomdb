# T0.3 AutoREST transport contract

Status: **PASS against pinned local ORDS 26.2.0** on 2026-07-14.

The disposable package and curl suite implement the exact contract to be tested:

- package-level `ORDS.ENABLE_OBJECT`, with POST and `application/json` only;
- NUMBER/CLOB inputs and VARCHAR2/CLOB/BLOB outputs;
- default AutoREST base64 representation of the BLOB;
- a gzip member whose decompressed bytes are canonical compact JSON;
- non-success status and rollback after a raised application error;
- public-origin CORS response;
- configurable frame-sized and asset-sized payload probes.

Observed contract results:

- NUMBER/CLOB echo plus VARCHAR2/CLOB/BLOB outputs: PASS.
- AutoREST BLOB base64 decode and gzip validation: PASS.
- Decompressed canonical JSON values: PASS.
- raised application error returned non-success and rolled back the inserted row: PASS.
- public-origin CORS header: PASS.
- 2,097,152-byte high-entropy JSON produced a 1,891,713-byte wire response in
  2 externally measured seconds.
- 8,388,608-byte high-entropy JSON produced a 7,567,401-byte wire response in
  9 externally measured seconds.
- ORDS remained running after both requests and used approximately 679 MiB at
  the post-test sample with `-Xmx768m`.

The live command ended with `PASS T0.3 (23/23 assertions)`. The contract does
not provide or permit a fallback transport.

Oracle documentation basis: ORDS 26.2 Developer's Guide sections 2.3.1.11 and
2.3.3. It specifies package-level exposure, POST with JSON, OUT-parameter JSON,
and default base64 encoding of AutoREST LOB values.
