# P12.0 ORDS/OJVM state blocker and database-worker route

Date: 2026-07-16

## Conclusion

ORDS connection affinity cannot preserve renderer arrays. ORDS invokes
`DBMS_SESSION.MODIFY_PACKAGE_STATE(REINITIALIZE)` after each request; Oracle
defines OJVM objects and static field values as database-session private. JIT
code may be shared, but application arrays are not. The selected next bounded
experiment is therefore a database-resident Scheduler worker: AutoREST enqueues
one command through AQ and waits for its correlated committed response, while a
long-lived worker session retains the warmed OJVM renderer.

The first queue gate passed, but this is not yet a production selection or a
30 FPS claim.

## Local evidence

The fixed 2/2/2 ORDS pool reused one SID/AUDSID for the complete ten-minute
probe, but both the OJVM static counter and PL/SQL package counter returned `1`
on every request. Pool pinning prevents connection churn; it does not prevent
request cleanup.

The first immutable renderer pack was 4,587,043 bytes and remained exact. A
bulk byte-cursor implementation plus explicit decoder warmup still measured a
fresh-session 93.076 ms pack load. Its complete fresh-session path was 93.076
ms pack + 114.581 ms JDBC snapshot + 28.091 ms render + 3.122 ms codec.

A one-byte palette plus opacity-bitset representation reduced the pack to
2,872,196 bytes and retained exact tic-8 SQL parity (`0|0|0|320|-1|200|-1`).
It nevertheless measured 167.014 ms pack load + 268.258 ms snapshot + 42.201
ms render + 3.531 ms codec in the decisive fresh session. It is rejected for
the per-request path. The compact sampling representation also regressed the
warm renderer and must not replace the short-array renderer merely to reduce
cold pack size.

The attempted actor-snapshot `BULK COLLECT` rewrite passed all 2,565 T7.2
assertions and the 163-command route, but the profiled snapshot remained
1,168.745 ms/163 tics versus the prior 1,157.735 ms. It was reverted.

## Platform findings

- ORDS cleanup reinitializes package state after every request; `RECYCLE`
  controls pooled connection handling, not retention of application globals.
- OJVM shares definitions/code, not Java application objects or global field
  values between database sessions.
- JIT-generated code can be shared across sessions, which explains why a warm
  instance improves fresh-session compute without preserving arrays.
- `DBMS_SHARED_POOL.KEEP`, OJDS/JNDI persistence, SecureFile `CACHE`, and the
  PL/SQL result cache do not provide a shared multi-megabyte Java heap.

Primary references:

- <https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/23.4/orddg/migrating-mod_plsql-ords.html>
- <https://docs.oracle.com/en/database/oracle/oracle-database/26/jjdev/Oracle-JVM-overview.html>
- <https://docs.oracle.com/en/database/oracle/oracle-database/26/jjdev/Oracle-JVM-JIT.html>
- <https://docs.oracle.com/en/database/oracle/oracle-database/26/adque/aq-operations-using-pl-sql.html>
- <https://docs.oracle.com/en/database/oracle/oracle-database/26/adque/aq-introduction.html>
- <https://docs.oracle.com/en/database/oracle/oracle-database/26/arpls/DBMS_SCHEDULER.html>

## Bounded selection gates

1. A disposable persistent-AQ echo probe must demonstrate one request enqueue,
   one worker dequeue, one correlated completion, and p95 database queue
   round-trip at or below 5 ms over at least 300 unique messages.
2. The worker must retain a generation counter and renderer arrays across all
   messages, recover from a killed worker through an idempotent restart, reject
   duplicate `(session,tic,command_sha)` work, and expose a heartbeat.
3. Replace the echo with the warm renderer only after the queue gate. Use the
   original exact short-array renderer, a SQL-produced packed dynamic buffer,
   and the existing persistent response BLOB. Warm worker render+codec+BLOB
   remains capped at 20 ms p95.
4. The full SQL simulation remains independently capped at 10 ms p95. The
   worker architecture removes ORDS cold starts; it does not excuse the current
   36.939 ms conservative simulation p95.

## AQ echo result

The disposable persistent-AQ/Scheduler echo probe processed 300 unique
correlated messages through one worker generation and one worker SID:

| Samples | p50 | p95 | Maximum | Mismatches |
| ---: | ---: | ---: | ---: | ---: |
| 300 | 2.122 ms | 3.843 ms | 54.740 ms | 0 |

This passes the <=5 ms p95 database queue round-trip gate. The one maximum
outlier remains visible and must be included in later integrated distributions.
The probe removed its queues, queue tables, Scheduler job, package, and sample
tables after measurement. The next gate is worker restart/idempotency/fencing,
followed by the original short-array renderer in the retained worker session.

## Warm renderer worker result

After a foreground instance-JIT warmup and ten worker-local cache-settling
frames, the retained Scheduler session rendered 300 tic-zero frames into
persistent SecureFile locators and returned correlated AQ completion tokens:

| Metric | p50 | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Queue request through committed response | 28.040 ms | 32.414 ms | 330.654 ms |
| Worker fill (insert + render/codec/BLOB + update) | — | 28.216 ms | — |
| Renderer | — | 22.105 ms | — |
| Codec | — | 3.069 ms | — |
| Persistent BLOB write | — | 0.640 ms | — |

All 300 payloads were 44,112 bytes and used one worker generation/SID. This
proves that the worker removes recurring ORDS/OJVM cold starts and that the
database-only request path can approach the frame boundary. It does not select
the renderer: the 28.216 ms fill misses the <=20 ms renderer/codec/BLOB gate,
and the 32.414 ms database p95 leaves no budget for SQL simulation, dynamic
snapshot, ORDS, wire, browser decode, or blit. The 330.654 ms maximum must also
remain in integrated evidence.

A 500-frame JIT warmup inside the Scheduler worker was rejected: Oracle stopped
the job slave after 2:22 before readiness. `DBMS_JAVA.COMPILE_CLASS` then
returned `0` (declined). The safe deployment order is a bounded foreground
instance warmup, explicit compiled-method audit after the known status race,
then worker startup with only cache loading and a small settling loop.

### Selected plane-hoist follow-up

Tracing isolated the regression to `drawPlanes`: it performed animated-flat
string construction and HashMap lookup for every plane pixel, measuring 21.607
ms p95 by itself. Resolving the active ceiling/floor asset twice per sector per
frame and indexing primitive arrays inside the pixel loop retained exact tic-8
SQL payload parity (`0|0|0|320|-1|200|-1`).

The repeated 300-frame worker probe then measured:

| Metric | p50 | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Queue request through committed response | 15.671 ms | 17.590 ms | 208.068 ms |
| Worker fill | — | 13.643 ms | — |
| Renderer | — | 7.471 ms | — |
| Codec | — | 3.168 ms | — |
| Persistent BLOB write | — | 0.639 ms | — |

Stage p95 was BSP 0.335, solid coverage 0.704, portal walk 3.393, planes
2.662, sprites 0.456, and presentation 0.240 ms. All 300 payloads were 44,112
bytes and the run used one worker generation/SID. The renderer/codec/BLOB
slice now passes its <=20 ms gate. The 208.068 ms maximum is worker-local cold
settling and remains visible; production readiness must exclude a worker from
traffic until its warmup and compiled-method audit finish.

## Live-state snapshot result

The retained worker then exercised the real live player/182-sector/53-mobj/
audio snapshot. One internal-JDBC UNION cursor measured 95.343 ms p95 and was
rejected. A procedural 21,834-byte binary pack improved from 29.6 to 23.9 ms
average after bounded RAW chunking, but remained too slow.

Native `JSON_OBJECT`/`JSON_ARRAYAGG` produced the equivalent 14,099-byte
snapshot in about 2 ms average in isolation. Its exact Java parser, unique-map-
coordinate/direction geometry cache, renderer, codec, and BLOB retained frame
SHA `9ab02d35667f551317527a3f528540334ede92f20cf4e532271123638c05c346`.
The decisive 300-frame worker composite measured:

| Metric | p50 | p95 | Maximum |
| --- | ---: | ---: | ---: |
| Request through committed response | 29.265 ms | 42.373 ms | 1,031.177 ms |
| Worker fill | — | 33.155 ms | — |
| SQL/JSON pack | — | 4.031 ms | — |
| Java snapshot/geometry | — | 10.874 ms | — |
| Renderer | — | 16.088 ms | — |
| Codec | — | 5.511 ms | — |
| BLOB | — | 0.987 ms | — |

This fails the live-state <=17 ms gate and the complete frame budget before
simulation/ORDS. Neither snapshot builder is a bootstrap dependency. The
evidence supports the narrow worker amendment: simulation and rendering share
one array-resident state in the retained database worker, SQL remains the
persistence/parity authority, and each tic writes relational deltas and exact
checkpoints rather than rebuilding the Java state from relational rows.

## Array-resident simulation slice 1

The first implementation establishes the intended boundary rather than another
relational snapshot experiment. `DoomResidentSimulationBench` loads the current
player/frontier once into session-private primitive state, accepts a versioned
binary batch of one to four validated turn commands, and emits one versioned
binary delta. It performs no JDBC or JSON work per tic. A session-token fence
prevents cross-game reuse, the batch validates into local variables before
committing retained state, and every public Java entry catches `Throwable`.

The live Oracle probe passed:

- 270/270 unique scalar turn results against the SQL `MOD(angle + turn *
  5.625 + 360, 360)` oracle;
- 4/4 results through the production-shaped packed batch boundary;
- atomic rejection of an invalid/gapped batch without partial mutation; and
- a kernel-only ten-million-turn reproducible diagnostic at 286.749 ns/tic.

The nanosecond result is not an FPS measurement: it excludes collision, world
machines, actors, state hashing, relational delta persistence, rendering, AQ,
ORDS, wire transfer, decode, and blit. Its value is architectural: retained
primitive computation is negligible compared with the rejected 10.874 ms
snapshot rebuild and 24.162/36.939 ms SQL simulation. The next differential
slice extends this same packed boundary with player movement and collision.

The transaction hardening follow-up replaced immediate mutation with committed
and pending state. `prepare` emits deltas while committed state remains visible;
`discard` abandons it, and `accept` publishes only after the caller's relational
commit. Session, lineage, generation, and request IDs fence every transition.
The retained batch path no longer allocates `ByteBuffer` or scratch arrays.

An exact-number feasibility matrix then matched all 1,152 canonical-angle
movement delta `NUMBER` encodings and one quadratic endpoint-contact root
byte-for-byte against SQL. Preloaded lookup plus exact addition measured
0.54–0.69 microseconds/op; the exact quadratic calculation measured 9.7–15.0
microseconds/op. Runtime trig is rejected from the hot loop; movement tables are
prebuilt by SQL and only narrow exact collision/final-coordinate operations use
`oracle.sql.NUMBER`.

The immutable worker catalog is now concrete. One SQL-built, SHA-verified
200,699-byte BLOB contains 681 BSP nodes, 682 subsector ownership entries,
1,175 collision lines, 182 sector baselines, all 1,152 raw movement NUMBER
pairs, compact REJECT/sound matrices, and all 256 canonical RNG values. It loads once per worker generation. The decoded BSP locator matched
`DOOM_BSP_LOCATE` at 270/270 deterministic points, and the packed movement
values retained 1,152/1,152 byte parity. Relational row walking is confined to
the offline builder and is not a tic/frame operation.

Raw Oracle `NUMBER` collision length/directions and the immutable
864-cell/2,064-reference BLOCKMAP now live in that catalog. The exact retained
swept-circle, two-contact slide, BSP destination, and two-hop portal kernel
matches 270/270 sequential calls to `DOOM_PLAYER_MOVE_PAYLOAD`, including 124
contact samples. Scanning all 1,175 lines was rejected at
9.966/16.746/25.070 ms p50/p95/max. BLOCKMAP candidate enumeration preserves
the corpus and measures 0.165/0.734/2.079 ms, so movement is now inside budget.

The selected kernel is also connected to the worker transaction model. A
version-2 command pack advances turn and exact position in pending state and
returns fixed-width raw NUMBER deltas. Across 270 real-session tics, every
pending delta matched SQL and every pre-accept committed frontier remained
unchanged. A separate 300-call production-shaped prepare+accept matrix measured
0.261/0.762/5.821 ms p50/p95/max. This excludes dirty-row DML and render but
includes command decode, exact movement, delta encode, and both Java boundaries.

## Bounded common-actor phase

The next retained component implements only the common monster housekeeping
that precedes the SQL actor loop: copy current health into
`monster_health_seen` and decrement positive attack cooldown. A rollback-only
fixture makes all 53 E1M1 monsters alive, asleep, unheard, and REJECT-hidden,
then compares the packed retained deltas against the untouched
`DOOM_MONSTERS.ADVANCE` oracle in stable mobj-id order.

The result is 53/53 exact rows. Every non-housekeeping actor field and the RNG
cursor remain unchanged; pending load, wrong-request accept/discard, double
accept/discard, and all worker fences reject without publishing state. After
five warmups, 300 retained prepare+accept calls measured
0.783/1.241/2.290 ms p50/p95/max after retained eligibility lookup.

This is not a complete actor tic or a playability result. The entry point
derives REJECT eligibility from live coordinates and retained actor sectors;
the transitional frozen sound bit is still supplied by the caller. Production
routing waits for that bit to come from the retained event buffer plus exact
pain, LOS, state transition, chase, attack, drop, RNG, and event ordering. Later
decisions must use the prior actor snapshot—including the old cooldown—even
though the common delta is persisted first.

The catalog now also retains compact directed REJECT and sound-reach matrices.
All 33,124 sector pairs match the SQL relations exactly. The actor probe derives
the player sector from live coordinates and classifies each retained actor
sector without JDBC or JSON work on the tic path.

The first behavior extension supports audible wakes when REJECT proves
visibility is zero. A frozen `DRY_FIRE` input wakes all 53 sound-reachable
fixture actors exactly like SQL, including 53/53 ordered `MONSTER_WAKE` events,
the player target, NULL number, and `HEARD` text. RNG is unchanged and pending
state remains invisible.

The exact retained LOS follow-up uses the packed BLOCKMAP, immutable line
geometry, and live retained sector heights. It matches 270/270 independent SQL
rays, including 132 REJECT-open pairs. The warmed internal 53-actor batch
measures 0.074/0.245/0.476 ms p50/p95/max; the rejected one-call-per-ray probe
measured 1.681 ms p95 because it repaid the SQL/Java boundary for every actor.
With LOS in the same retained pass, all 53 visible wakes and their ordered
`SEEN` events also match SQL exactly. The pain extension then consumes RNG in
the same prior-snapshot mobj order as SQL: all 53 actor rows and cursor advances
match, and the 36 successful rolls emit 36/36 ordered `MONSTER_PAIN` events.

The next bounded active-state phase handles awake actors whose old state timer
is greater than one. All 53 rows decrement from three tics to two exactly like
SQL, with zero events and an unchanged RNG cursor. Catalog version 4 additionally
packs all 151 database-defined state timers, next-state indices, and action
classifications; every definition matches SQL. Expiring actors now follow
ordinary no-action edges with 53/53 row parity, zero events, and unchanged RNG.
CHASE, melee, hitscan, and projectile dispatch remain fail-closed. The resulting
catalog is 202,515 bytes with SHA-256
`21719458f28e3e91efe4691081e02ef54959a75186a93566191b4cdf8e3e191d`.
Already-processed corpses also follow timer and next-state edges at 53/53 SQL
parity with zero events and unchanged RNG. The fresh-death extension matches
53/53 actor mutations, 25/25 full drop spawns, and 78/78 ordered death/drop
events, including kill credit, MOBJ allocation, cleanup fields, and transaction
fences. A separate no-attack CHASE helper matches 212/212 movements across four
target quadrants using exact coordinates and the frozen prior-actor snapshot.
Both remain differential kernels until player, actor, RNG, ID, event, and tic
frontiers are merged behind one prepare/persist/commit/accept boundary.

Repeated `loadjava -force` during iterative development eventually caused the
2 GiB local instance's MMAN to terminate with fatal `ORA-00822`. The Oracle
alert trace identifies MMAN memory management rather than an uncaught Java game
entry. The harness now supports `DOOMDB_SKIP_LOADJAVA=1` for repeat probes after
one successful deployment; production deploys one revision, restarts the
worker, warms it, and audits compiled methods before admitting traffic.

Large frames remain in relational SecureFile rows. AQ carries only a small,
unguessable request identifier and command metadata. The worker commits the
authoritative state and response before signaling completion. AutoREST enforces
game ownership and uses bounded waits plus idempotent retry behavior.
