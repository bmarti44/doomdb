# P12.0 SecureFile response-BLOB tail latency — research handoff

Date: 2026-07-16
Scope: narrowly targeted at the durable response/state BLOB copy tail (p95 ~3.5–13 ms,
rare 32–146 ms outliers) reported from the 1,000-frame retained-worker runs. The
ORDS/OJVM resident-worker architecture is settled and is NOT reopened here.

Status of claims: LOCAL-FACT = read from this repo at HEAD. DOC = Oracle documentation
or reproducible published measurement (URL given). HYPOTHESIS = mechanism documented
but magnitude unmeasured on this system — must be benchmarked before selection.

---

## 1. Definitive local facts (write-path audit)

1. The worker inserts a **fresh `doom_worker_result` row per tic** (`empty_blob()`
   RETURNING locators), then does one `dbms_lob.trim` + one `dbms_lob.copy` from a
   Java-filled temporary BLOB into each persistent locator
   (`sql/sim/080_unified_worker.sql:324-399`). It does not overwrite a shared row.
   LOCAL-FACT. Consequence: overwrite-versioning is NOT the primary suspect;
   **allocation-side costs are** (new-chunk allocation, segment growth, space
   management, datafile extension).
2. LOB storage clauses at HEAD (`sql/schema/035_unified_worker.sql:106-107`):
   `delta_blob` and `response_blob` are `SECUREFILE (CACHE)` with everything else
   defaulted (LOGGING, RETENTION AUTO, ENABLE STORAGE IN ROW 4000). LOCAL-FACT.
3. **`tic_commands.state_blob` (211,307 bytes/tic) and `state_history.snapshot_blob`
   (~211 KB every 4th tic) have NO explicit LOB clause**
   (`sql/sim/040_history_replay.sql:13-18`, `sql/schema/030_dynamic.sql:210-216`).
   The Oracle default for LOB caching is **NOCACHE**, meaning every state copy and
   every history snapshot is a **synchronous direct-path write** to the container
   filesystem — the buffer cache is never used for these writes. DOC:
   "NOCACHE — LOB values are never brought into the buffer cache" and "Applications
   that write to LOB segments that are stored as NOCACHE tend to bottleneck on
   ['direct path write (lob)']"
   (https://docs.oracle.com/en/database/oracle/oracle-database/23/adlob/creating-new-LOB-column.html,
   https://docs.oracle.com/cd/B16240_01/doc/doc.102/e16282/oracle_database_help/oracle_database_wait_bottlenecks_direct_path_write_lob_pct.html).
4. Total durable LOB volume per tic ≈ 250–300 KB (state 211 KB + response ~42 KB
   packed-v2 + delta + 211 KB history on every 4th tic). At 30 Hz that is roughly
   **8–9 MB/s of both segment growth and (for LOGGING paths) redo**. LOCAL-FACT
   (sizes) + arithmetic. Nothing in `deploy/local/` sizes redo logs, datafiles, or
   sets `filesystemio_options`; only sga/pga targets are overridden
   (`deploy/local/db-entrypoint.sh:15-16`). LOCAL-FACT.
5. All commits are plain `commit;` (`080_unified_worker.sql:458`); no COMMIT WRITE
   anywhere in the repo. LOCAL-FACT. **Inside PL/SQL the default commit behavior for
   nondistributed transactions is BATCH NOWAIT** when COMMIT_LOGGING/COMMIT_WAIT are
   unset — the worker's per-tic commits are group-committed asynchronously and are
   only guaranteed on disk when the outer call returns. DOC:
   https://docs.oracle.com/en/database/oracle/oracle-database/18/sqlrf/COMMIT.html.
   Two consequences:
   - The amendment's "durable before the response is signaled" property is currently
     weaker than its text implies (crash window = last unfsynced redo batch, i.e.
     one-to-few frames).
   - The 32–146 ms outliers are **unlikely to be foreground `log file sync`** —
     which redirects suspicion to the LOB/space/redo-backpressure paths below.
6. Codex reports switching the response LOB to **CACHE READS**. DOC: "CACHE READS —
   LOB values are brought into the buffer cache only during read operations and not
   during write operations" — i.e. this makes every response copy a synchronous
   direct-path write, the same pathology as item 3. The schema at HEAD still says
   CACHE; the CACHE READS selection should be reverted for the write side
   (see §3.1).

---

## 2. Attribution model for the tails (ranked)

The 3.5–5 ms "good" band, the 10–13 ms band, and the 32–146 ms outliers likely have
different owners. Candidates ranked by fit to the evidence; §4 Experiment 1 decides.

| # | Candidate cause | Mechanism | Expected wait-event signature | Fit |
|---|---|---|---|---|
| 1 | Synchronous direct-path LOB writes (NOCACHE-default state/history; CACHE READS response) | Foreground writes whole chunks to the container fs and waits; overlay/ext4-in-Docker jitter lands directly in the copy timer | `direct path write (lob)` / `direct path write` | Explains the 3.5–13 ms band scaling with payload; fs jitter explains sporadic 30+ ms |
| 2 | Space management on ~9 MB/s segment growth: SMCO/Wnnn preallocation lagging, foreground `segment cfs allocations`, HWM extension, **datafile autoextend** | Fresh LOB chunks allocated every tic; when background preallocation lags, the foreground allocates (bursty); datafile extension stalls everything | `enq: HW - contention`, `Data file init write`, buffer busy waits on `1st level bmp`, statistic `segment cfs allocations` | Best fit for the rare 32–146 ms outliers: bursty, rare, magnitude matches file-extension stalls. DOC prior art: Bug 17479510 pathology; SMCO preallocation cases (https://magnusjohanssontuning.wordpress.com/2013/03/06/high-buffer-busy-waits-securefiles/) |
| 3 | Redo backpressure at ~MB/s on unsized container redo logs | CACHE LOGGING generates redo ≈ data volume; small redo logs switch every few tens of seconds; `log file switch (checkpoint incomplete)` freezes all DML for tens–hundreds of ms | `log buffer space`, `log file switch (checkpoint incomplete)`, high log-switch rate in v$log | Also fits the rare large outliers; compounds with candidate 2. Docker fs `log file sync` regressions documented (https://github.com/oracle/docker-images/issues/868) |
| 4 | LGWR CPU starvation on the 2-core cap | Worker (render+sim) + ORDS + LGWR + DBWR + SMCO share 2 cores; LGWR scheduling delay inflates commit-adjacent waits | `log file sync` >> `log file parallel write` ('redo synch time overhead') | Secondary; commits are BATCH NOWAIT so foreground exposure is limited |
| 5 | SecureFile versioning/retention churn | Old versions kept in-segment under RETENTION AUTO even for insert-then-read rows | segment growth beyond payload arithmetic | Weak primary suspect given fresh-row inserts, but RETENTION NONE is still free efficiency (DOC: "most efficient setting in terms of space utilization") |

Reader interaction (settled): the ORDS reader selects a **different, already-committed
row** per request_id (`080_unified_worker.sql:875-882`), so reader CR reconstruction
does not sit on the writer's critical path, and versioning work happens regardless of
readers. RETENTION NONE is viable; the only residual risk is reader-side ORA-01555/
ORA-22924 if a slot is reclaimed mid-read, which the fresh-row-per-tic design already
avoids.

---

## 3. Immediate corrections (cheap, do before/alongside experiments)

3.1 **Revert CACHE READS → CACHE on `response_blob`**, and add explicit
    `SECUREFILE (CACHE LOGGING RETENTION NONE)` to `tic_commands.state_blob` and
    `state_history.snapshot_blob` (both currently NOCACHE-default). This moves all
    per-tic LOB writes through the buffer cache (DBWR does the physical I/O later)
    instead of synchronous direct-path writes. DOC mechanism; HYPOTHESIS magnitude —
    expected to compress the 3.5–13 ms band substantially. Note CACHE implies
    LOGGING (cannot combine with FILESYSTEM_LIKE_LOGGING).
3.2 **Make commit durability an explicit, recorded decision.** Options:
    (a) accept BATCH NOWAIT semantics (a lost frame is regenerated 33 ms later;
    AQ visibility is still commit-consistent) and amend the amendment text to say
    "commit-consistent, crash window ≤ one redo batch"; or (b) require strict
    per-tic durability with `COMMIT WRITE IMMEDIATE WAIT` and pay measured
    `log file sync` per tic. Either is defensible; comparing storage A/B results
    without pinning this invalidates the comparison (async-commit baseline vs
    sync-commit candidate). DOC: PL/SQL default commit is BATCH NOWAIT.
3.3 **Size the I/O substrate for ~9 MB/s**: check `v$log` switch frequency during a
    1,000-frame run; if switching more than ~once/minute, create larger redo groups
    (e.g. 2–4 GB). Presize the LOB tablespace/datafiles (or set large AUTOEXTEND
    NEXT) so no datafile extension happens mid-run. Review
    `filesystemio_options` (SETALL on ext4-in-Docker has a documented `log file
    sync` regression — docker-images#868). All in `deploy/local/db-entrypoint.sh` /
    a bootstrap DDL. DOC + LOCAL-FACT (currently unset).
3.4 **Add a purge policy for run-generated rows** (`doom_worker_result`,
    per-tic `tic_commands.state_blob`, `state_history`). At ~9 MB/s a long run
    approaches Oracle Free's 12 GB user-data cap in under half an hour, and an
    ever-growing segment keeps SMCO permanently busy. Purge between runs at minimum;
    consider retaining response BLOBs for only the last N tics during a run
    (delete-behind), since the canonical replay record is deltas + interval
    snapshots, not response payloads. LOCAL-FACT (no purge found) + arithmetic.
3.5 **Benchmark-validity guard:** the projectile-lifecycle leak (retained objects
    296→385 over long runs) makes long-run per-stage numbers non-stationary. Until
    removal lifecycle lands, selection decisions should use matched-length runs
    only.

---

## 4. Bounded experiments (≤3, in order)

**Experiment 1 — Attribute the tail before changing storage (half a day).**
Instrument one 1,000-frame run three ways simultaneously:
  (a) 10046 level 8 trace on the worker session
      (`DBMS_MONITOR.SESSION_TRACE_ENABLE(waits=>true)`), tkprof afterwards —
      pack-free, gives exact wait events per tic;
  (b) `v$event_histogram_micro` deltas (before/after) for: `direct path write (lob)`,
      `log file sync`, `log file parallel write`, `log buffer space`,
      `log file switch (checkpoint incomplete)`, `enq: HW - contention`,
      `buffer busy waits`, `db file sequential read`, `Data file init write`;
  (c) `v$sysstat` deltas for `segment cfs allocations`, redo size, plus `v$log`
      switch count.
Note: the official 23ai/26ai licensing manual lists Diagnostics+Tuning packs as
**included with Free**, so AWR/ASH are also usable (verify
CONTROL_MANAGEMENT_PACK_ACCESS in the gvenzl image); Statspack is the pack-free
fallback. Pass criterion: the >32 ms histogram buckets land on identifiable events
whose counts match the observed outlier frequency. This decides whether §3.1
(direct-path writes), §3.3 (redo/datafile), or space management (candidate 2) owns
the tail.

**Experiment 2 — Storage-shape A/B on the same commit mode (one day).**
With commit mode pinned per §3.2, run 1,000 frames in each configuration:
  (A) HEAD baseline;
  (B) §3.1 applied (all three LOBs CACHE LOGGING RETENTION NONE) + §3.3 sizing;
  (C) B + ring-buffer publication: UPDATE N preallocated `doom_worker_result` slot
      rows (slot = tic mod N, N≈8) with `dbms_lob.write` in place instead of a fresh
      INSERT per tic, publishing the request_id→slot pointer in a small indexed row.
      This eliminates per-tic segment growth entirely (allocation happens once).
      The AQ correlation/read path keys by request_id exactly as today; only the
      storage row is recycled. Requires the reader tolerance analysis from §2
      (reader reads committed slot; N≈8 slots gives ~264 ms of physical separation
      at 30 Hz).
Compare `response_copy_us` / `state_blob_us` / `history_blob` p50/p95/max via the
existing `unified-worker-live-benchmark.sql` stages. Pass criterion: response-copy
p95 ≤ 2 ms and max ≤ 15 ms sustained over 1,000 frames. HYPOTHESIS ranking: B fixes
the band, C fixes the outliers.

**Experiment 3 — Only if B/C fail: chunked inline relational ring buffer (one day).**
The single storage shape that exits LOB machinery entirely (extended RAW>3964 B,
OSON>8 KB, and in-row>8 KB all route back into hidden LOB storage — DOC):
`frame_chunk(slot, seq, data VARCHAR2(4000), PK(slot,seq))` holding base64 text
(~15 rows per 42 KB frame), written per tic with one FORALL UPDATE into slot
`tic mod N`, pointer publish, commit. Ordinary buffered heap DML: no LOB
versioning, no direct-path I/O, no LOB space management, plain redo-at-commit
durability. AutoREST serving: enable a view
`SELECT slot, tic, JSON_ARRAYAGG(data ORDER BY seq RETURNING JSON) payload ...` —
ORDS 23ai emits native JSON columns raw (no conversion/escaping), or serve the
chunk collection with `?q={"slot":K}` and concatenate client-side. Apply the same
shape to `state_blob` only if it, too, still owns tail after B/C. Pass criterion:
same as Experiment 2. HYPOTHESIS (mechanism DOC'd, latency unmeasured in
literature).

Rejected without experiment:
- **Memoptimized Rowstore fast ingest** — explicitly not durable ("Until [deferred
  write] happens the data is not durable" — Oracle blog); fails the amendment.
- **FILESYSTEM_LIKE_LOGGING / NOLOGGING** — mutually exclusive with CACHE; frame
  data unrecoverable from backup; durability-at-commit subtle. Only reconsider if
  Experiment 1 proves redo volume is the sole owner and B/C both fail.
- **Extended VARCHAR2/RAW(32767), native JSON storage, INROW 8000** — all hidden
  LOB storage above ~3964/8000 bytes; payloads are 42–211 KB. (Also
  MAX_STRING_SIZE=EXTENDED is irreversible.)
- **Global application context** — SGA-only, not durable (already settled: heartbeat
  metadata only).

---

## 5. Interaction with the p95 gate (context, not a storage finding)

At every-4th-tic checkpoint cadence, 25% of frames run the 36.79/52.97 ms checkpoint
path, so the overall p95 (44.29 ms) is arithmetically the checkpoint distribution —
no SecureFile fix changes that. With per-tic deltas already the authoritative durable
record, checkpoint density only bounds replay-reconstruction length; at every-32nd
tic (~3% of frames) checkpoints leave the p95 quantile entirely and reconstruction
stays bounded at ≤32 delta applies. This is a charter-review item (amendment
specifies deltas per tic + interval snapshots; density is a parameter), and it
compounds with §3.1 since the history snapshot is currently a NOCACHE direct-path
write of ~211 KB.

## 6. Key sources

- Oracle 23ai LOB storage (CACHE/NOCACHE/CACHE READS, RETENTION, INROW 8000, chunk):
  https://docs.oracle.com/en/database/oracle/oracle-database/23/adlob/creating-new-LOB-column.html
- Direct path write (lob) bottleneck for NOCACHE writers:
  https://docs.oracle.com/cd/B16240_01/doc/doc.102/e16282/oracle_database_help/oracle_database_wait_bottlenecks_direct_path_write_lob_pct.html
- PL/SQL default commit = BATCH NOWAIT; COMMIT WRITE semantics:
  https://docs.oracle.com/en/database/oracle/oracle-database/18/sqlrf/COMMIT.html,
  https://fritshoogland.wordpress.com/2018/04/16/a-look-into-oracle-redo-part-10-commit_wait-and-commit_logging/
- SecureFile space/versioning behavior on repeated overwrite:
  https://jonathanlewis.wordpress.com/2016/09/13/securefile-space/
- SMCO/Wnnn preallocation + buffer-busy/HW-contention pathologies (Bug 17479510):
  https://magnusjohanssontuning.wordpress.com/2013/03/06/high-buffer-busy-waits-securefiles/,
  https://www.anbob.com/archives/7821.html
- SecureFile metadata-walk write regression (Bug 22905136 / MOS 2189248.1):
  https://perfchron.com/2016/08/13/securefile-lob-performance-issue/
- Docker filesystem `log file sync` regression:
  https://github.com/oracle/docker-images/issues/868
- Extended types are hidden SecureFiles:
  https://docs.oracle.com/en/database/oracle/oracle-database/23/sqlrf/Data-Types.html,
  https://connor-mcdonald.com/2021/03/04/extended-varchar2-and-the-hidden-lob/
- ORDS AutoREST BLOB = base64; native JSON emitted raw:
  https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/25.4/orddg/developing-REST-applications.html,
  https://www.thatjeffsmith.com/archive/2024/05/on-rest-apis-and-oracle-database-23ai-json-native-types/
- Fast ingest not durable:
  https://blogs.oracle.com/database/new-in-oracle-database-19c-memoptimized-rowstore-fast-ingest
- Diagnostics/Tuning packs included with Free (licensing manual):
  https://docs.oracle.com/en/database/oracle/oracle-database/26/dblic/Licensing-Information.html
