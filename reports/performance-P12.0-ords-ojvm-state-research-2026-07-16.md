# ORDS request-state reset and the resident render worker (2026-07-16)

Research deliverable for the P12.0 blocker: ORDS reuses one SID but Java
statics and PL/SQL package globals reinitialize after every AutoREST request,
making every request pay ~481 ms of cold initialization against a 33.3 ms
budget. Method: three parallel research passes over primary Oracle
documentation with adversarial re-verification of load-bearing quotes.
VERIFIED = fetched verbatim from the cited source; HYPOTHESIS = labeled
inference.

Post-research selection note: the repository subsequently measured persistent
AQ directly at 2.122/3.843 ms p50/p95 over 300 correlated messages with zero
mismatches, so AQ—not the unmeasured DBMS_PIPE hypothesis—is the selected
rendezvous. The retained AQ/Scheduler renderer then passed at 15.671/17.590 ms
p50/p95 request-through-commit. See
`performance-P12.0-ords-ojvm-worker-2026-07-16.md` for the newer local evidence.

## Definitive conclusion

**The per-request reset is unconditional, documented, and has no supported
off switch; no supported OJVM mechanism shares application data across
sessions. Therefore warm state can never live in an ORDS request session.
30 FPS is NOT architecturally impossible: the supported, Oracle-sanctioned
pattern is a single database-resident DBMS_SCHEDULER worker session that
holds the warm OJVM renderer for the life of the instance, fronted by a
DBMS_PIPE request/response rendezvous from the AutoREST procedure.** This is
25-year-old documented Oracle architecture (the DBMS_PIPE "External Service
Interface" daemon in Oracle's own package docs; RMAN's production pipe
mode), keeps everything inside Oracle Database, keeps AutoREST as the only
transport, and keeps SQL authoritative for simulation.

## Verified facts (with sources)

### The reset is by design and cannot be disabled

1. ORDS Developer's Guide (26.1, identical back to 19.1), PL/SQL gateway
   chapter, mod_plsql migration table: *"ORDS always performs:
   dbms_session.modify_package_state ( dbms_session.reinitialize ) at the
   end of each request."* The mod_plsql knob controlling this is listed as
   "N/A" in ORDS.
   <https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.1/orddg/pl-sql-gateway.html>
2. `jdbc.cleanup.mode` has exactly two documented values: `recycle`
   (default, keep the proxy session, reset its state) and `dispose` (close
   the proxy session — strictly more cleanup). The full documented `jdbc.*`
   key list contains no state-preservation or connection-labeling setting.
   <https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/25.1/ordig/about-REST-configuration-files.html>
3. Oracle formally classifies ORDS/APEX as stateless: *"REST, Oracle REST
   Data Services (ORDS), Oracle Application Express (APEX) are examples of
   stateless applications."*
   <https://docs.oracle.com/en/database/oracle/oracle-database/23/adfns/high-availability.html>
4. `DBMS_SESSION.MODIFY_PACKAGE_STATE(REINITIALIZE)` semantics: reinitializes
   all stateful packages in the session (no per-package exemption; no
   package-name argument). Stateless program units are untouched.
   <https://docs.oracle.com/en/database/oracle/oracle-database/23/arpls/DBMS_SESSION.html>
5. The Java-statics teardown alongside package reset is **undocumented** for
   MODIFY_PACKAGE_STATE (verified absence in DBMS_SESSION and the Java
   Developer's Guide). The one documented "OJVM is cleared" mechanism is the
   23ai `RESET_STATE=LEVEL1` service attribute (Development Guide §6.5.1).
   Diagnostic (cheap): check `DBA_SERVICES.RESET_STATE` for the service ORDS
   connects through. Either way the observed behavior stands; only the
   attribution differs.

### No OJVM sharing facility exists

6. Java Developer's Guide, verbatim: *"neither this data is visible to other
   sessions nor the data can be shared in any way with other sessions."*
   Shared across sessions: class metadata/bytecode (java pool) and
   JIT-compiled native code (`/dev/shm` shm files). Never shared: statics,
   objects, arrays.
   <https://docs.oracle.com/en/database/oracle/oracle-database/23/jjdev/Oracle-JVM-overview.html>
7. Within one session, statics persist across calls for the session's whole
   life (*"The same JVM instance remains in place for the entire duration of
   the session"*), ending only on JVM exit (uncaught exception, System.exit,
   fatal error) or session end. This is what the resident worker exploits.
8. The only SGA-resident, reset-surviving user data facility is the globally
   accessed application context — VARCHAR2, 4 KB per attribute
   (<https://docs.oracle.com/en/database/oracle/oracle-database/23/arpls/DBMS_SESSION.html>).
   Useful for worker heartbeat/revision flags; useless for the 2.87 MB pack
   or 42 KB frames.

### The rendezvous primitives are fast where it matters

9. DBMS_PIPE: SGA-based, non-transactional, in Free. 23ai `maxpipesize`
   default is 65,536 bytes and auto-grows; per-message buffer is 4,096 bytes
   (a 42 KB frame = ~11 chunked RAW messages).
   <https://docs.oracle.com/en/database/oracle/oracle-database/23/arpls/DBMS_PIPE.html>
10. `RECEIVE_MESSAGE`/`SEND_MESSAGE` timeouts are INTEGER seconds — **but
    waiters are posted on message arrival, not on the timeout tick** (wait
    event "pipe get": blocked, woken by sender, 5 s backstop re-check).
    Integer-second granularity therefore bounds only the dead-worker
    fallback path, never happy-path latency.
    <https://docs.oracle.com/en/database/oracle/oracle-database/23/refrn/descriptions-of-wait-events.html>
11. DBMS_SCHEDULER: jobs may run indefinitely (no max duration;
    `max_run_duration` only raises an event); `restartable => TRUE` +
    `restart_on_recovery => TRUE` give automatic relaunch after failure and
    instance restart; a job slave is an ordinary dedicated session with no
    documented OJVM restriction. Singleton enforcement: exclusive
    DBMS_LOCK 'UL' lock held for the worker session's life (auto-released on
    death; requires explicit GRANT EXECUTE ON DBMS_LOCK).
    <https://docs.oracle.com/en/database/oracle/oracle-database/23/arpls/DBMS_SCHEDULER.html>,
    <https://docs.oracle.com/en/database/oracle/oracle-database/23/arpls/DBMS_LOCK.html>
12. Prior art: Oracle's own DBMS_PIPE docs ship the daemon pattern
    ("External Service Interface": client packs its
    `DBMS_PIPE.UNIQUE_SESSION_NAME` reply pipe + request, blocks on the
    reply pipe); RMAN's pipe interface is production Oracle software using
    exactly this shape.
    <https://docs.oracle.com/en/database/oracle/oracle-database/19/bradv/starting-interacting-with-rman-client.html>

### Attribution of the measured 481 ms cold path (HYPOTHESIS, grounded)

- The 167 ms pack load is ~17 MB/s — an order of magnitude below cached
  SecureFile read throughput; it is almost certainly Java-side decode
  (possibly interpreted) and array copies, not LOB I/O.
- The 268 ms snapshot from a fresh session is likely OJVM first-call session
  setup + first-execution costs, not raw SQL (attribute via
  `V$SESS_TIME_MODEL` / `V$SQL.parse_calls`). Statement caching is
  per-session — worthless fresh-per-request, decisive in a resident worker.
- No public number exists for the fresh-Java-session floor; nobody has
  published OJVM first-call, kprb LOB-read, or DBMS_PIPE latency figures —
  this project's measurements are novel. The floor is plausibly tens of ms,
  which alone would sink any fresh-per-request design.

## Decision table

| Mechanism | Supported | Survives request cleanup | Expected performance | Compatible with constraints |
| --- | --- | --- | --- | --- |
| Disable/soften ORDS reset | **No** (no such config) | — | — | — |
| Shared/SGA Java application data | **No** (explicitly contradicted by docs) | — | — | — |
| Global application context | Yes | Yes (SGA) | fast | Only for ≤4 KB VARCHAR2 flags (heartbeat/revision), not data |
| Class-constant-baked assets (chunked strings) | Yes | Metadata shared; decode+heap copy still per session | Cuts the 167 ms, floor still ≳ tens of ms/request | Fails budget alone; fresh-JVM floor remains |
| Result cache | Yes | Yes | — | Not viable: unique per-frame data never hits |
| Batching tics per request | Yes | — | Doesn't amortize init (init is per request, and gate requires 30 unique presented frames/s) | Fails gate |
| Long-running/pipelined request | Yes | — | Holds a connection; ORDS request model + gate cadence break | Rejected by constraints |
| Buffered AQ/TxEventQ rendezvous | Yes (in Free) | Worker state, yes | ~1–3 ms/round trip (HYPOTHESIS) | Yes — runner-up |
| **DBMS_PIPE rendezvous + DBMS_SCHEDULER resident worker** | **Yes** | **Yes — worker session is never touched by ORDS** | **~0.5–2 ms IPC + warm render ~10.5 ms (HYPOTHESIS on IPC; render measured)** | **Yes — AutoREST unchanged, all in Oracle, SQL owns sim** |

## Recommended architecture

One `DBMS_SCHEDULER` job (`restartable`, `restart_on_recovery`,
`repeat_interval => 'freq=minutely'` as supervision belt-and-suspenders):

- On start: take exclusive 'UL' lock (`timeout => 0`; duplicate instances
  exit immediately), warm the OJVM renderer (packs, JIT already
  instance-shared), create/purge the request pipe, then loop on
  `RECEIVE_MESSAGE('doom_render_req', timeout => 5)` re-checking a stop flag
  each timeout. Catch-all around the loop body (an uncaught exception kills
  the JVM statics — reload and continue).
- AutoREST `doom_api.step()` (unchanged endpoint): run `APPLY_BATCH` (SQL
  simulation, authoritative, in the request session as today); build the
  packed dynamic snapshot (pose + mobjs + sector deltas + presentation
  scalars — a few KB, the same pack Workstream A2 already calls for); purge
  its `UNIQUE_SESSION_NAME` reply pipe; send snapshot + correlation id +
  reply-pipe name on the request pipe; block on the reply pipe
  (`timeout => 1`); reassemble ~11 RAW chunks into the response BLOB.
- **Pass the snapshot through the pipe, not via worker table reads.** This
  sidesteps cross-session read-consistency entirely (the worker never needs
  to see uncommitted simulation state), avoids the worker's query costs, and
  reuses the A2 packed-snapshot design. The worker becomes a pure function:
  packed state in → frame BLOB chunks out.
- Fallback on timeout/return-code 1 (worker dead/busy): render in-session
  via the existing SQL parity path and log the degradation; a globally
  accessed application context attribute can carry worker liveness/pack
  revision for a zero-cost pre-check.
- Restart safety: pipes are empty after instance restart by design; the
  worker rebuilds all state on relaunch; the fallback covers the warmup gap.
  This satisfies the charter's restart-safety rule.

Budget accounting (steady state, per request): SQL simulation (currently
21–37 ms — still Workstream B's problem) + IPC ~0.5–2 ms + warm render +
codec ~10.5 ms + ORDS/wire/decode. IPC replaces the 481 ms cold path. The
renderer side of the budget is solved by this architecture; the simulation
side is unchanged and remains the gating workstream.

## Charter assessment

The worker is arguably compliant without amendment: the browser still talks
only to AutoREST objects (rule 1–2 govern *browser traffic*; DBMS_PIPE is
intra-database IPC, not an alternate API or application server); rendering
stays inside Oracle; SQL remains authoritative for simulation; the worker
owns only render/codec work — squarely inside the approved 2026-07-15 OJVM
amendment; frames remain byte-exact against the SQL oracle. Because the
charter forbids latest-answer-wins reinterpretation, record a one-paragraph
clarifying note (human-approved) that the approved OJVM render/codec path
may be hosted in a single database-resident scheduler session reached via
DBMS_PIPE from AutoREST procedures. That is the narrowest change; a full
amendment is only needed if the evaluator rules the worker an "alternate
API," which the documented Oracle daemon pattern argues against.

## Three bounded experiments (in order)

1. **Pipe ping-pong benchmark** (~half a day): two dedicated sessions,
   request message + 42 KB chunked-RAW reply, ≥1,000 warm iterations;
   measure round-trip p50/p95; also verify behavior under ORDS (request
   session sends/receives fine despite state reset — pipes are
   session-state-independent). **Pass: ≤2 ms p95 IPC round trip.** Fail →
   rerun with buffered TxEventQ RAW (2×32 KB messages); if that also fails
   ≤5 ms, the worker returns frames via table row + `COMMIT WRITE NOWAIT` +
   sub-10 ms poll (`DBMS_SESSION.SLEEP` accepts hundredths).
2. **Resident worker skeleton** (~2–3 days): scheduler job + 'UL' singleton
   + warm renderer + pipe protocol + in-session fallback; drive through the
   real AutoREST endpoint. **Pass: request-path overhead excluding
   `APPLY_BATCH` (IPC + render + codec + BLOB + ORDS dispatch) ≤14 ms p95
   over ≥270 unique moving frames.** Also verify worker survival across
   `shutdown immediate`/startup and kill -9 of the job session
   (supervision relaunches; fallback serves during warmup).
3. **Fresh-session floor attribution** (~half a day, runs in parallel):
   `V$SESS_TIME_MODEL`/`V$SQL` attribution of the 268 ms snapshot and a
   trivial-Java-call timing in a brand-new session on a warm instance.
   **Purpose: permanently close the fresh-per-request line of inquiry with
   a number.** If the bare fresh-JVM floor exceeds ~15 ms (expected), record
   it in the do-not-retry ledger so no future pass re-attempts per-request
   initialization tricks (class-constant baking included).

Also, one-query diagnostic alongside: `SELECT reset_state FROM dba_services`
for the ORDS service — if LEVEL1, the Java-statics wipe has a documented
cause worth recording.

## If experiments fail

If pipe AND AQ AND table-handoff all miss their thresholds (not expected —
each has independent grounding), the impossibility argument is complete for
the current charter: per-request state is unpreservable (documented,
unconditional), cross-session Java data sharing does not exist (documented),
and per-request reinitialization has a measured floor above budget. The
narrowest amendment in that world is relaxing "no custom ORDS handlers" to
allow one `ORDS.DEFINE_MODULE` streaming/affinity endpoint — but do not
propose it until the three experiments above have produced their numbers.
