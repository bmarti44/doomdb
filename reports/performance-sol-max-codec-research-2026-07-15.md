# Sol/max codec bottleneck research

Date: 2026-07-15
Scope: exact 320x200 tic-zero framebuffer codec after the clean-room BSP renderer
reached 5.706218 ms p95 on Java 11 HotSpot.

This report changes no production code. Local probes were disposable and
allocation-flat. External technical claims use primary Oracle, JDK, zlib, RFC,
and repository sources. No JavaBox, Mocha Doom, id Doom, compressor, or other
third-party implementation was copied or translated.

## Executive decision

The current v1 column-RLE JSON contract is now the measured codec bottleneck,
not the framebuffer or SHA-256. It is the wrong representation for a textured
frame: tic zero has 45,317 runs for 64,000 pixels, an average of only 1.412
pixels per run. The RLE expands 64,000 indexed bytes to 481,989 bytes of JSON
before compression.

Three exact v1 compression choices were measured after a clean database
restart:

| Exact v1 codec | JSON bytes | GZIP bytes | Total p50 | Total p95 | <=5 ms? |
| --- | ---: | ---: | ---: | ---: | ---: |
| Level 6/default | 481,989 | 92,658 | not recaptured | 20.256889 ms | No |
| Level 1/default | 481,989 | 137,333 | 7.480495 ms | 10.465499 ms | No |
| Huffman-only | 481,989 | 192,338 | 7.562100 ms | 8.917733 ms | No |
| Level 0/stored | 481,989 | 482,047 | 2.903705 ms | 3.636932 ms | Yes, codec only |

Level 0 technically passes the isolated encoder gate, but it sends a 482 KB
inner BLOB that AutoREST then base64-encodes to roughly 643 KB, and the browser
must parse 45,317 nested run arrays. It is 10.9 times larger than the selected
packed candidate before outer base64 and has not passed BLOB, ORDS, browser, or
cloud p95. It is not the recommended production selection.

A narrow v2 candidate keeps the canonical 64,000 indexed bytes, dimensions,
mode, tic, state/frame SHA-256, audio, completion state, gzip BLOB, AutoREST
surface, and thin browser role, but replaces `cols` with allocation-free base64
of the column-major framebuffer. With Java's standard Base64 encoder and level-1
raw DEFLATE inside the same deterministic GZIP wrapper, 1,500 samples measured:

| Packed v2 stage | p95 |
| --- | ---: |
| `short` to bytes plus SHA-256 | 0.260647 ms |
| Canonical JSON plus framebuffer base64 | 0.111153 ms |
| Level-1 GZIP | 1.669251 ms |
| **Complete codec** | **1.993562 ms** |

Packed v2 is 85,578 bytes before gzip and 44,112 bytes after gzip. It is 3.11x
smaller than exact v1 level 1, 10.93x smaller than v1 level 0, and 2.10x smaller
than current v1 level 6. It passes the <=5 ms gate with about 3 ms headroom for
the BLOB locator operation.

**Recommendation: approve a narrow v2 transport amendment and select packed v2
subject to exact parity, BLOB, AutoREST, browser, and Autonomous gates below.**
Do not spend another renderer iteration optimizing v1 JSON. If the amendment is
denied, v1 level 0 is the only measured encoder under 5 ms, but it must pass the
complete external payload gate before selection and is expected to be a poor
cloud/640x400 choice.

## What the stage measurements say

For exact v1 level 1:

- framebuffer conversion plus SHA-256 p95: 0.305538 ms;
- RLE scan and canonical JSON p95: 3.383300 ms;
- GZIP p95: 6.599854 ms; and
- complete p95: 10.465499 ms.

This isolates two independent costs. Native zlib match search is the largest at
level 1, but even free compression would leave the 3.38 ms RLE/JSON build and a
481,989-byte BLOB. Lookup-table integer formatting may save part of the JSON
time; it cannot make level-1 v1 meet 5 ms, and it cannot repair payload size.

Level 0 proves the direct JSON builder is already reasonably efficient. The
remaining decision is therefore representation, not `StringBuilder` versus a
byte array, `GZIPOutputStream` versus a direct `Deflater`, or `short[]` versus
`byte[]`.

The packed result also bounds the value of further micro-optimization:
conversion, SHA, base64, JSON, and GZIP together are already below 2 ms p95.
Eliminating the `short`-to-`byte` conversion may recover at most part of the
0.26 ms combined conversion/hash stage. It is worthwhile in production only if
the renderer can safely make its completed canonical buffer a `byte[]`; it is
not a reason to keep v1.

## Compression-level and strategy decision

**Source-backed.** zlib defines level 1 as best speed, level 9 as best
compression, level 0 as stored/no compression, and the default as the current
level-6 compromise. It defines `FILTERED` as an intermediate that does less
string matching, `HUFFMAN_ONLY` as no string matching, and `RLE` as distance-one
matching. Strategy changes compression ratio, not decompressed correctness.
[zlib 1.3.1 manual](https://www.zlib.net/manual.html)

**Source-backed.** Java 11 `Deflater` exposes levels 0–9 plus default, but only
`DEFAULT_STRATEGY`, `FILTERED`, and `HUFFMAN_ONLY`; it does not expose zlib's
`Z_RLE` or `memLevel`. `reset()` reuses a compressor while retaining its level
and strategy. [Java 11 Deflater API](https://docs.oracle.com/en/java/javase/11/docs/api/java.base/java/util/zip/Deflater.html)

**Measured conclusion.** For v1, level 1 is too slow, Huffman-only is still too
slow and much larger, level 6 is far too slow, and level 0 trades the compressor
deadline for an unacceptably large external candidate. `FILTERED` is unlikely to
dominate both measured level 1 and Huffman-only, but one corpus run may be kept
as completeness evidence if v2 is rejected. Do not test levels 2–9 exhaustively:
none has a credible route to beat level 1's CPU while meeting the same schema.

For packed v2, select level 1/default. At 1.67 ms GZIP p95 and 44,112 bytes,
level 0 or Huffman-only cannot recover enough CPU to justify more BLOB/base64/
network bytes. Level 6 could be considered only if an external cloud trace
shows bandwidth dominating and still retains the <=5 ms codec p95; it is not
the starting choice.

## Why preset dictionaries, delta frames, and parallel gzip do not solve v1

### Preset dictionary

**Source-backed.** zlib requires compressor and decompressor to use exactly the
same preset dictionary. The zlib wrapper can signal a dictionary, but the GZIP
member format in RFC 1952 has no preset-dictionary identifier. Java's browser
`DecompressionStream('gzip')` contract supplies no dictionary argument.
[zlib dictionary contract](https://www.zlib.net/manual.html),
[RFC 1952 GZIP members](https://www.rfc-editor.org/rfc/rfc1952)

Therefore a dictionary is not transparent to the current client contract. A
custom raw-DEFLATE decoder and dictionary would be a broader, stateful client
codec for little benefit compared with measured packed v2.

### Cached or delta frames

Delta encoding requires a prior-frame identity, recovery/keyframes, ordering,
pool/session-independent history, replay/rewind invalidation, and a different
client schema. It cannot satisfy cold unique moving-frame acceptance. Exact
whole-response cache hits remain useful for unchanged states but must be
reported separately. Neither is a fix for the current codec.

### Parallel or multi-member GZIP

RFC 1952 permits concatenated members, but Oracle documents that Java threads
within one database session execute on one operating-system thread. Splitting
compression into Java threads cannot use the second core inside the OJVM call.
[Oracle JVM threading model](https://docs.oracle.com/en/database/oracle/oracle-database/21/jjdev/threading-in-database.html)

Multiple members also reset the DEFLATE history and add an 18-byte
header/trailer minimum per member. They add browser-compatibility and exactness
risk without a local CPU benefit. Reject this route.

## Exact v2 contract boundary

The smallest useful amendment is a versioned JSON envelope, not a custom binary
protocol. Preserve all current metadata and replace only the expanded `cols`
array with one exact field such as:

```text
"v":2,
"frame_encoding":"indexed-column-major-base64",
"frame":"<exactly 64,000 decoded bytes>"
```

The precise names/order must be frozen by the contract before implementation.
The browser must:

1. decode the existing outer AutoREST base64;
2. gunzip and parse the canonical JSON exactly as today;
3. base64-decode `frame` into exactly `w*h` bytes;
4. verify the existing frame SHA-256 against the contract's canonical ordering;
5. transpose only if the canvas buffer requires row-major order; and
6. apply PLAYPAL and blit, with no visibility, simulation, prediction, or
   interpolation.

SQL remains authoritative for state and assets. The byte-locked SQL renderer
and `MATCH_RECOGNIZE` RLE remain mandatory independent oracles. For every
reviewed frame, expand SQL RLE to the 64,000-byte canonical frame and require it
to equal the decoded v2 frame byte-for-byte. v2 removes only a redundant wire
expansion; it does not move a render decision to the browser.

JavaBox provides only high-level corroboration for publishing one existing
packed framebuffer rather than reconstructing it as object records. Its adapter
reads a `DataBufferInt` and publishes the packed buffer directly; its 33 ms
check is a limiter, not a codec benchmark.
[JavaBox Canvas adapter](https://github.com/bmarti44/javabox/blob/8241259df9d0a52b2a4e5a49b2133b90bc44e7bd/container/doom/adapter/CanvasRenderer.java)

No JavaBox or included GPL Mocha implementation is reusable. The v2 encoder
must remain independently authored from DoomDB's frame and payload contracts.

## OJVM, BLOB, ORDS, and Autonomous gates

### BLOB handoff

Packed v2 is 44,112 bytes, just over SQL RAW's 32,767-byte bound. Oracle warns
that the server-side internal driver's SQL-statement `setBytes` and
`setBinaryStream` BLOB interfaces are unsupported above 32,767 bytes.
[Oracle JDBC data-interface limits](https://docs.oracle.com/en/database/oracle/oracle-database/26/jjdbc/accessing-and-manipulating-Oracle-data.html),
[Oracle JDBC LOB guide](https://docs.oracle.com/en/database/oracle/oracle-database/26/jjdbc/LOBs-and-BFiles.html)

Run an isolated caller-owned locator matrix using the real 44,112-byte corpus:

1. one buffered `Blob.setBinaryStream` write;
2. two locator writes, each <=32,767 bytes; and
3. two RAW OUT chunks followed by bounded PL/SQL `DBMS_LOB.WRITEAPPEND`.

Use one Java call per frame, never one call per chunk. Require codec plus locator
mutation <=5 ms p95 over 1,500 warmed samples, zero per-frame allocation growth,
and exact self-gunzip. Kill any path that leaks temporary LOBs, relies on an
unsupported >32,767-byte bind, or adds more than 3 ms p95 to the measured codec.

### AutoREST and browser

**Source-backed.** AutoREST returns BLOB content as base64 text by default and
Oracle warns that base64 conversion of large LOBs can create memory pressure.
[ORDS 26.1 AutoREST BLOB behavior](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.1/orddg/developing-REST-applications.html)

The smaller v2 response reduces both this base64 work and browser input. It must
still pass a real endpoint trace with separate database-BLOB, ORDS base64,
response receive, outer base64 decode, gunzip, JSON parse, inner frame base64,
SHA, palette expansion, and canvas blit p50/p95. Test at least 270 unique moving
frames after warmup; do not substitute the 1,500 repeated-codec samples.

### Autonomous

Packed v2 uses only Java 11 standard `MessageDigest`, `Base64`, `CRC32`, and
`Deflater`, plus same-session BLOB access. Java's Base64 encoder supports writing
into a caller-provided destination array, avoiding a result allocation.
[Java Base64 Encoder API](https://docs.oracle.com/en/java/javase/11/docs/api/java.base/java/util/Base64.Encoder.html)

This requires no native library, filesystem, socket, `Unsafe`, Vector API,
extproc, MLE, or custom ORDS handler. Autonomous supports OJVM after enabling
`JAVAVM` and restarting, but the actual target must repeat class resolution,
JIT status, codec/BLOB, AutoREST, and browser measurements.
[Oracle Java on Autonomous](https://docs.oracle.com/en/cloud/paas/autonomous-database/serverless/adbsb/autonomous-oracle-java.html)

Third-party native compressors such as libdeflate, zstd, or LZ4 are rejected:
they are not the required gzip/client contract, are unavailable as Java 11
standard OJVM APIs, and would add native/extproc and Autonomous incompatibility.
A custom copied compressor is also outside the clean-room/license boundary.

## Ranked recommendation and falsifiable gates

| Rank | Action | Expected impact | Risk | Spike | Kill threshold |
| ---: | --- | --- | --- | --- | --- |
| 1 | Approve/select packed v2 level 1 | Measured 20.257 -> 1.994 ms p95; 92,658 -> 44,112 bytes vs current v1 | Medium: explicit schema/client amendment | Exact 300-frame corpus plus BLOB/ORDS/browser | Any frame/hash/metadata mismatch, codec+BLOB >5 ms p95, or external frame >33.3 ms p95 |
| 2 | Select fastest bounded BLOB handoff | Keeps packed codec headroom | Medium: internal-driver limits | Locator stream vs two <=32K writes vs RAW/PLSQL append | >3 ms added p95, temporary-LOB leak, unsupported bind, or invalid objects |
| 3 | Change final canonical buffer to `byte[]` if exact | Saves a fraction of 0.261 ms | Low | A/B conversion+hash across corpus | <0.1 ms p95 gain or sentinel/unsigned regression |
| 4 | Retain v1 level 0 only as amendment-denied fallback | Codec-only p95 3.637 ms | High external payload/browser cost | Full 482 KB BLOB through local and cloud AutoREST/browser | Codec+BLOB >5 ms, external >33.3 ms, memory pressure, or 640x400 infeasibility |
| 5 | Flat numeric lookup tables for v1 only | Could reduce 3.383 ms JSON stage | Low but strategically weak | Packed integer digits, no objects, exact bytes | <0.5 ms gain; never use to defer passing packed v2 |
| 6 | One FILTERED v1 completeness run | Uncertain; unlikely Pareto winner | Low | Exact corpus size/p95 | Not both <=5 ms and materially smaller than v1 level 0 |

## Dead ends

- v1 level 6/default, level 1/default, and Huffman-only: measured over 5 ms;
- exhaustive levels 2–9: no credible speed advantage over failed level 1;
- preset dictionary: not expressible to the current generic GZIP decoder;
- temporal delta or cached repeated frames: stateful contract and invalid for
  cold unique moving acceptance;
- parallel Java compression: OJVM session executes Java threads on one OS
  thread;
- concatenated per-column gzip members: resets compression history and adds
  overhead;
- `GZIPOutputStream`, `StringBuilder`, Jackson, or object run tuples: the direct
  reusable byte-array encoder is already the faster shape;
- SQL `MATCH_RECOGNIZE`, SQL JSON aggregation, `UTL_COMPRESS`, MLE, or UTL_TCP:
  reintroduces measured row/language/network boundaries;
- custom ORDS handlers: prohibited and unnecessary; and
- native/custom third-party compressors: licensing, security, deployment, and
  Autonomous incompatibility.

## Final acceptance sequence

1. Obtain the explicit narrow v2 charter/schema approval.
2. Freeze v2 field names, order, frame byte order, hash order, and error rules.
3. Pass 300 SQL-oracle frames byte/hash/RLE/metadata exactly, including all
   presentation modes and mutation cases.
4. Select the <=5 ms p95 packed-codec-plus-BLOB path under Oracle's 2 CPU/2 GiB
   limit and verified native OJVM methods.
5. Update the thin client and independently verify malformed length/base64/hash,
   transpose, palette, and mode mutations.
6. Run the complete 270-unique-moving-frame database, AutoREST, and browser
   p50/p95 gate locally and on Autonomous.

Packed v2 solves the isolated codec problem with measured headroom. It does not
by itself prove 30 FPS: the 5.706 ms HotSpot renderer still needs production
OJVM selection, BLOB/ORDS/browser work remains unmeasured for v2, and the
render-free SQL simulation p95 remains independently above the complete frame
budget.
