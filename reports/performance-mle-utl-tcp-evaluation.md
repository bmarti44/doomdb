# Oracle MLE JavaScript and UTL_TCP performance evaluation

Date: 2026-07-15
Scope: read-only architecture evaluation and bounded t81 capability/microbench
probes. No production object, evaluator, `PLAN.md`, renderer, game session, or
network ACL was created or changed.

## Decision

**Do not put MLE JavaScript or UTL_TCP in DoomDB's production render,
simulation, codec, or transport path.** Confidence is **high** for this decision
under the current charter and measured bottleneck.

MLE is available on the local database and can execute small JavaScript snippets,
but it does not make the dominant relational renderer plan cheaper. Moving that
renderer into JavaScript would be a second procedural game engine and directly
conflict with `PLAN.md` Sections 0.3 and 1.6. Moving only RLE, JSON, LOB copying,
or compression would attack work that begins after the observed multi-minute
renderer bottleneck and would add SQL/JavaScript conversion and execution-context
cost. `UTL_TCP` is an outbound client API, cannot accept a browser connection,
cannot bypass the required inbound AutoREST call, and is tightly restricted on
Autonomous Database. An external TCP receiver would also be an expressly
forbidden alternate API/middle tier.

The productive next performance experiment remains the already demonstrated SQL
renderer refactor: derive renderer relations once, keep the session predicate at
the earliest legal boundary, reduce repeated macro expansion, and preserve every
golden. Only after that should T12 measure RLE/JSON/hash/compression separately.

## Existing contracts that control the answer

The following are source facts, not new recommendations:

- `PLAN.md` Section 0.1 requires SQL to perform visibility, projection, texture
  sampling, pixel composition, simulation, and AI. PL/SQL may only orchestrate
  bounded set-based statements.
- Section 0.3 explicitly makes MLE JavaScript a non-goal and requires AutoREST as
  the only dynamic HTTP surface; custom handlers and alternate APIs are excluded.
- Sections 1.5 and 5.4 fix the transport as a gzip BLOB containing canonical JSON
  returned through the AutoREST-enabled `DOOM_API` package.
- Section 1.6 says that an MLE/WASM/foreign-language renderer port defeats the
  Oracle-specific design.
- Section 2 requires SQL/set-based DML ownership, forbids dynamic SQL, and limits
  HTTP traffic to objects enabled by `ORDS.ENABLE_OBJECT`.
- Section 6.6 and T12 require measurement before optimization; correctness,
  320x200 resolution, response schema, and goldens are fixed.

Oracle documents Auto PL/SQL as a stateless HTTP(S) RPC: ORDS unmarshals request
JSON through JDBC, invokes the enabled PL/SQL object, and marshals OUT parameters
back into a JSON response. Enabling a package exposes its public members and the
supported method/content type is POST with `application/json`.
[Oracle ORDS Developer's Guide, Auto PL/SQL](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.1/orddg/developing-REST-applications.html#GUID-8B659165-75AD-4399-AB84-D9F893EFEA9C)

## Measured evidence

### Repository measurements already present

| Observation | Measured result | Meaning |
|---|---:|---|
| Clean production `DOOM_API.NEW_GAME(3)` | 121.79 s | End-to-end local database call with no pre-existing sessions |
| `DOOM_HISTORY.SAVE_GAME` during staged tic 0 | <0.01 s | History is not the blocker |
| `FRAME_COLUMN` setup | 0.01 s | Canvas-column setup is not the blocker |
| `FRAME_PIXEL` insert, contaminated/multi-session case | >200 s | Renderer materialization dominates before RLE/JSON/hash/compression starts |
| Direct committed R2 pixel relation | >70 s | Relational render plan itself is expensive |
| Non-shipping shared-portal SQL probe | 35.39 s for 53,760 world rows | One relational derivation and smaller plan materially improve the dominant stage |
| Clean compressed `NEW_GAME` response | 92,658 bytes | Current output is already compact compared with 64,000 raw pixels |
| Frozen T5.2 verification suite | 69.35 s | Includes many evaluator operations and is not a per-frame latency number |
| Review capture of 64,000 pixels plus palette and PNG | 12.49 s | Diagnostic path, not production AutoREST frame timing |

Sources: `reports/performance-T8.1-new-game.md` and
`reports/performance-T5.2.md`. The most important ordering fact is measured:
RLE, JSON, hashing, and compression had **not begun** when the `FRAME_PIXEL`
insert exceeded 200 seconds.

The local transport contract separately measured a 1.89 MB AutoREST wire body in
2 seconds and a 7.57 MB body in 9 seconds. Those deliberately large,
high-entropy contract probes establish ORDS representation and memory behavior;
they are not representative 92 KB game-frame timings. Source:
`reports/transport-contract.md`.

### Bounded t81 probes run for this evaluation

Environment: `doomdb-t81-live-db-1`, Oracle AI Database Free 23.26.2.0.0,
healthy shared t81 container. The probes took less than three seconds each and
did not call a renderer or alter persistent objects.

Capability/catalog results:

- `SYS.DBMS_MLE` and `SYS.UTL_TCP` are valid packages with public synonyms and
  public `EXECUTE` grants.
- `MLE_PROG_LANGUAGES=all`.
- The DOOM session has `CREATE MLE` and `EXECUTE DYNAMIC MLE`.
- `USER_MLE_MODULES=0`; production currently contains no MLE module.
- A create/evaluate/drop dynamic MLE context probe succeeded.

Microbench results (warm-up excluded, `DBMS_UTILITY.GET_TIME` centisecond clock):

| Probe | Iterations | Measured elapsed | Derived mean |
|---|---:|---:|---:|
| `CREATE_CONTEXT` + `EVAL('1+1')` + `DROP_CONTEXT` | 100 | 0.64 s | ~6.4 ms/call |
| `EVAL('1+1')` in one reused context | 100 | 0.01 s | ~0.1 ms/eval; coarse-clock result |
| `UTL_COMPRESS.LZ_COMPRESS` synthetic 512,000-byte highly compressible BLOB | 20 | 0.06 s | ~3 ms/call |
| `UTL_COMPRESS.LZ_UNCOMPRESS` resulting 616-byte gzip | 20 | 0.01 s | ~0.5 ms/call; coarse-clock result |

These microbenchmarks establish order of magnitude only. They do **not** compare
MLE call specifications with PL/SQL, do not time the real canonical response,
and do not prove cloud performance. The synthetic compression ratio is not a
frame-compression claim. Even treating the measured 3 ms compression cost as if
it could be removed entirely would save only about 0.0025% of the measured
121.79-second clean `NEW_GAME` call. That percentage is an inference from two
local measurements, not a representative-replay result.

## MLE assessment by stage

### Renderer SQL: no valid material improvement

The renderer is a relational pipeline whose expensive statement expands portal,
hit, interval, plane, masked-object, weapon, HUD, and final-priority relations.
MLE cannot optimize that SQL plan merely by wrapping its invocation. If MLE
queries those relations itself, it still executes SQL in the current database
session; Oracle documents the MLE JavaScript driver as synchronous, using only
the implicit current connection, with no connection pool and **no statement
cursor caching**. Result fetching also introduces Oracle-to-JavaScript type
conversion.
[Oracle MLE JavaScript driver differences](https://docs.oracle.com/en/database/oracle/oracle-database/23/mlejs/api-differences-node-oracledb-and-mle-js-oracledb.html)

Fetching tens of thousands of candidates or 64,000 final pixels into JavaScript
therefore leaves the costly SQL work in place and adds a language/data boundary.
Reimplementing traversal, projection, sampling, or pixel composition in MLE
could avoid some SQL operations, but that is precisely the forbidden second
engine, not an optimization of DoomDB. Expected valid impact: **approximately
0%, with material regression risk**. This is an architectural inference backed
by the measured stage isolation; it is not a renderer MLE benchmark.

Oracle supports stored MLE modules exposed through call specifications and
dynamic `DBMS_MLE` contexts. Dynamic execution explicitly creates, evaluates,
and drops a context; module call specifications use isolated runtime contexts.
[Oracle dynamic MLE workflow](https://docs.oracle.com/en/database/oracle/oracle-database/23/mlejs/dynamic-execution-workflow.html)
[Oracle MLE call specifications](https://docs.oracle.com/en/database/oracle/oracle-database/23/mlejs/call-specifications-functions.html)
The t81 result shows context creation is measurable, but context overhead is not
the reason to reject MLE for this stage—the engine/SQL work is.

### RLE, JSON, LOB, and compression: too late and contract-constrained

- Canonical RLE must be produced with `MATCH_RECOGNIZE`; replacing it in
  JavaScript violates the mission even if byte-identical.
- SQL `JSON_ARRAYAGG` already produces ordered canonical CLOB JSON. JavaScript
  serialization would require transferring all runs or pixels into MLE and then
  transferring a CLOB/BLOB back.
- Oracle maps CLOB/BLOB values to wrappers or JavaScript string/`Uint8Array`.
  Its synchronous MLE driver does not provide Node-style LOB streaming or query
  streaming. This makes a large codec handoff a risk, not a demonstrated win.
  [Oracle MLE type conversions](https://docs.oracle.com/en/database/oracle/oracle-database/23/mlejs/mle-type-conversions.html)
  [Oracle MLE driver LOB limitations](https://docs.oracle.com/en/database/oracle/oracle-database/23/mlejs/api-differences-node-oracledb-and-mle-js-oracledb.html)
- Native `UTL_COMPRESS` took about 3 ms for the bounded 512 KB synthetic input.
  The observed renderer takes at least four orders of magnitude longer.

Expected end-to-end MLE impact before renderer repair: **below measurement noise
if positive, and plausibly negative**. After renderer repair, T12 should measure
the real RLE, JSON, frame-hash, UTF-8 conversion, gzip, ORDS marshal, browser
decode, and blit stages independently before considering any codec change.

### Tic batching: no RTT or SQL reduction

`DOOM_API.STEP` already accepts one to four commands, parses them set-wise, calls
one transactional simulation batch, renders once, and caches an exact response.
An MLE wrapper would neither reduce tics executed nor eliminate the single
render. Issuing simulation SQL from MLE would use synchronous calls in the same
session and the MLE driver lacks statement cursor caching. Expected impact:
**0% or negative**. The existing four-command batch is the valid RTT lever.

### Network RTT and ORDS: neither feature removes the required hop

Putting MLE behind `DOOM_API` leaves the browser-to-ORDS HTTP request, ORDS JDBC
invocation, package call, OUT BLOB marshal, base64 JSON representation, browser
base64 decode, gzip decode, JSON parse, and canvas blit unchanged. Therefore MLE
cannot improve network RTT. It could only change database CPU inside the same
request, where the measured bottleneck is relational rendering.

`UTL_TCP` points in the wrong direction. Oracle states that it only initiates
connections and cannot accept connections initiated from outside. It is an
outbound TCP client, not an inbound server or ORDS response stream.
[Oracle `UTL_TCP` rules and limits](https://docs.oracle.com/en/database/oracle/oracle-database/23/arpls/UTL_TCP.html#GUID-5B4079BC-8A3B-4C67-BF58-2F889E2FF659)
Sending a frame to another host would add a second network hop and require that
host to relay data to the browser. That is an alternate dynamic surface/middle
tier and violates Sections 0.1, 0.3, 2, 4.3, 5.4, and T11.2. Expected compliant
impact: **exactly 0%**, because it cannot be used on the public path.

## Autonomous Database portability and security

MLE is a supported database facility in current Oracle releases, but deployments
must grant only the required privileges. Dynamic MLE requires `EXECUTE DYNAMIC
MLE`; stored modules/environments require `CREATE MLE`, and call specifications
also require procedure-creation privilege. Oracle explicitly recommends minimum
privilege.
[Oracle MLE privilege requirements](https://docs.oracle.com/en/database/oracle/oracle-database/23/mlejs/system-and-object-privileges-required-working-javascript-mle.html)

Execution contexts isolate runtime state, and state lasts no longer than a
database session. MLE can be disabled at CDB, PDB, or session level through
`MLE_PROG_LANGUAGES`. A `PURE` restricted environment can deny database-state
access, but a renderer that queries game tables could not be pure. Introducing
MLE would add stored source, privilege, environment/import, audit, error, and
golden-validation surface without a demonstrated benefit.
[Oracle MLE security considerations](https://docs.oracle.com/en/database/oracle/oracle-database/23/mlejs/security-considerations-mle.html)

Normal `UTL_TCP` access is governed by network ACLs; outbound `connect` and name
resolution privileges must be managed for destination hosts.
[Oracle network ACL administration](https://docs.oracle.com/en/database/oracle/oracle-database/23/arpls/DBMS_NETWORK_ACL_ADMIN.html)
Autonomous Database is substantially more restrictive: IP addresses cannot be
used as host names, TLS is enforced, public outbound connections are limited to
HTTPS on 443 or SMTP on 25/587, wallet arguments are ignored, and private
endpoint egress can be routed through VCN rules. These constraints rule out a
portable arbitrary raw-TCP Doom stream even apart from the charter.
[Oracle Autonomous Database PL/SQL package notes: `UTL_TCP`](https://docs.oracle.com/en-us/iaas/autonomous-database-serverless/doc/autonomous-plsql-packages.html#GUID-AF78697C-EE30-4A8D-9E41-42B4C1A6AFC0)

The t81 catalog's public `EXECUTE` on `UTL_TCP` does not grant destination
access through an ACL and is not evidence that the cloud target permits a given
connection. No outbound connection was attempted during this evaluation.

## Recommendation and stopping rule

1. Keep Sections 0.3 and 1.6 unchanged: no MLE production engine or codec.
2. Do not grant/configure a `UTL_TCP` destination for DoomDB and do not create an
   external frame receiver.
3. In T12, first benchmark the shared-portal/single-derivation SQL approach with
   all goldens. The existing probe's 35.39-second result is the only evaluated
   option here that materially attacks the measured bottleneck.
4. Add out-of-band stage timers around renderer materialization, RLE, canonical
   JSON, frame hash, UTF-8 conversion, gzip, and response copy. Use the fixed
   300-frame replay; do not infer a codec bottleneck from synthetic data.
5. Preserve the maximum-four-command batch and response cache; measure one- and
   four-command network latency locally and on managed ORDS.
6. Revisit MLE only after an explicit charter amendment and only if a measured
   post-render stage becomes dominant. A valid experiment would have to preserve
   SQL-authored pixels, `MATCH_RECOGNIZE` RLE, canonical decompressed bytes,
   AutoREST, and every golden. Under those restrictions, a material win is
   unlikely.

## Concrete `PLAN.md` amendment text (not applied)

No amendment is required to make the decision—the existing charter already
forbids both relevant designs. If the project wants the evaluated rationale
recorded in the plan, add the following after Section 1.7 without changing the
charter:

> ### 1.8 MLE and UTL_TCP performance decision
>
> MLE JavaScript is not a renderer, simulation, RLE, JSON, LOB, compression, or
> tic-batching fallback. A measured local evaluation found renderer SQL
> materialization to dominate production frame latency before RLE, JSON,
> hashing, or compression begins. Wrapping that SQL in MLE does not change its
> plan; fetching its rows into JavaScript adds a language boundary, and moving
> render decisions into JavaScript violates Sections 0.1, 0.3, and 1.6.
>
> UTL_TCP is outbound-only and is not an HTTP response transport. It may not be
> used to bypass AutoREST or send dynamic game data to a relay. All public
> dynamic traffic remains the Section 5.4 `DOOM_API` AutoREST contract.
>
> T12 optimizes the measured relational renderer first. It separately times
> RLE, JSON aggregation, frame hashing, UTF-8 conversion, `UTL_COMPRESS`, ORDS
> marshaling, browser decode, and blit before proposing a codec change. Any
> future MLE experiment requires a charter amendment, fresh independent
> evaluation, local and Autonomous capability probes, and all existing goldens.

## Reproducibility and evidence boundaries

- Measured: all numeric results explicitly labeled above.
- Inferred: stage impact estimates, regression risks, and expected MLE behavior
  when applied to this renderer. No production MLE renderer/codec was built.
- Not measured: managed Autonomous MLE execution, managed ORDS game-frame RTT,
  real 300-frame T12 replay, SQL-to-MLE transfer of 64,000 pixels/runs, MLE call
  specification warm/cold latency, and an outbound `UTL_TCP` connection.
- Official sources only were used for external documentation. Repository source
  and local t81 catalog/runtime probes supply the project-specific evidence.
