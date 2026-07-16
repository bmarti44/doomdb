# P12.0 ORDS affinity and state-retention probe — 2026-07-16

## Result

The pinned local ORDS 26.2 path is database-session-affine under a fixed pool,
but it is deliberately **not Java-heap-state-affine**. Across 600 requests at
one-second intervals (about ten minutes):

| Observation | Result |
| --- | --- |
| Distinct SID/AUDSID pairs | 1 (`176/1840351`) |
| Requests on that pair | 600 / 600 |
| Java static counter | `1` on every request |
| PL/SQL package global | `1` on every request |
| Expected counter transitions missed | 1,198 / 1,198 |

The renderer must not depend on static primitive arrays, cached prepared
statements, framebuffers, or any other Java heap value surviving an AutoREST
request. The selected architecture is now one immutable renderer-kernel pack
BLOB plus one packed dynamic-state buffer decoded per request. Native OJVM JIT
status may remain database-persistent, but mutable Java state does not.

## Pool findings

- ORDS defaults were `InitialLimit=0`, `MinLimit=2`, `MaxLimit=10`,
  `MaxConnectionReuseCount=1000`, `InactivityTimeout=1800`, and
  `jdbc.cleanup.mode=RECYCLE`.
- A fixed `1/1/1` pool made AutoREST discovery fail with HTTP 500.
- The smallest viable local pool was `2/2/2`.
- The selected local settings are reuse count 100,000,000, inactivity timeout
  86,400 seconds, `RECYCLE` cleanup, and disabled PL/SQL gateway. These settings
  prevent connection churn but do not preserve Java statics.

Oracle documents that ORDS reinitializes package state after each request; the
Java counter proves that this cleanup also invalidates the OJVM class static in
the proxied schema. See [Oracle's ORDS migration guide](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/19.1/aelig/migrating-mod_plsql-ords.html)
and the [ORDS 26.2 Auto PL/SQL guide](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.2/orddg/oracle-rest-data-services-developers-guide.pdf).

## Transport corrections discovered by the probe

- Pinned ORDS 26.2 generated package-subprogram routes are case-sensitive in
  this image. `doom_api/NEW_GAME` and `doom_ords_affinity_probe/NEXT` resolve;
  their lowercase equivalents return 404.
- `client/src/api.ts` now probes lowercase once for compatibility, retries the
  catalog-uppercase procedure on 404, and retains that choice. STEP therefore
  does not pay a second HTTP request per frame.
- The static dashboard health and AutoREST view health are distinct. The
  restarted database initially had no enabled schema/object metadata, so
  `/health.txt` was green while the game API was absent. Fresh/bootstrap gates
  must check both.

## Reproduction artifacts

- `scripts/performance/DoomOrdsAffinityProbe.java`
- `scripts/performance/ords-affinity-probe.sql`
- `deploy/local/ords-entrypoint.d/10-doomdb-pool.sh`

The probe Java entry point catches `Throwable`, and the dynamic renderer entry
point now does the same, truncating its caller-owned BLOB and returning an
`ERROR:<class>` marker for the PL/SQL boundary to reject. No Java exception is
allowed to escape and silently replace the request's session JVM.
