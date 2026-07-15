# Oracle capability probe report

## Status

**PASS — all nine capabilities executed against pinned local Oracle Free on
2026-07-14.** The run reached `ALL_ORACLE_CAPABILITY_PROBES_OK`, printed
`PASS T0.2 (9/9 capabilities)`, exited zero, and removed `DOOMDB_PROBE`.

The database ran image digest
`sha256:df18ebc6b17107081b8bb8f1ee90e8018195dc9261e288100be99ef7bef268ff`
with exactly 2 CPUs and 2 GiB of memory. Its supported SPFILE settings were
adjusted before startup from the image's 1536 MiB SGA and 512 MiB PGA targets to
1024 MiB and 256 MiB respectively. The original settings exhausted the cgroup
during `FREEPDB1` open; the tuned instance reached ready without changing the
image or resource limits. ORDS repository version `26.2.0.r1732140` was installed
in `FREEPDB1` before the ORDS capability example.

## Evidence

The workspace host was inspected without printing credential values:

- `command -v docker` returned `/usr/local/bin/docker`.
- `command -v sqlplus` and `command -v sql` returned no executable.
- `docker ps` showed only the pre-existing Atelier PostgreSQL and application
  containers; no Oracle Database or ORDS container was running.
- No environment variable name beginning with `ORACLE`, `DB_`, `ORDS`, or `SQL`
  was present.

The result-bearing examples proved:

- `SDO_GEOMETRY` storage, metadata, a `SPATIAL_INDEX_V2` index, and a filtered
  result;
- `CONNECT BY`, `MODEL`, and `MATCH_RECOGNIZE` expected row values;
- ordered JSON `RETURNING CLOB`;
- SQL Property Graph creation and `GRAPH_TABLE` traversal;
- a 32-byte `DBMS_CRYPTO.HASH_SH256` digest;
- a lossless `UTL_COMPRESS` BLOB round trip; and
- `ORDS.ENABLE_SCHEMA` and `ORDS.ENABLE_OBJECT` followed by cleanup.

The probe initially exposed that a PL/SQL package constant cannot be used as a
SQL expression. The SHA-256 example was consequently expressed as a PL/SQL
block while still naming `DBMS_CRYPTO.HASH_SH256`, and both reviewed local and
cloud copies were changed byte-identically.

## Delivered probe

`probes/oracle/capabilities.sql` executes one result-bearing example for each
T0.2 requirement and exits on the first SQL or operating-system error. The
runner:

1. creates the disposable `DOOMDB_PROBE` schema using a random password;
2. grants only the object-creation and package privileges needed by the probe;
3. runs the reviewed SQL as that schema; and
4. drops the schema with `CASCADE` on success, SQL failure, or interruption.

Secrets are sent to SQL*Plus/SQLcl on standard input rather than process
arguments. The runner does not print them. The cloud entrance-gate copy at
`cloud/probes/oracle/capabilities.sql` must remain byte-identical.

## Reproduction

With Oracle Free and ORDS installed and healthy, provide an administrative
connect string and the probe schema's service identifier, then run:

```sh
ORACLE_ADMIN_CONNECT='<admin-connect-string>' \
ORACLE_CONNECT_IDENTIFIER='<host:port/service>' \
  ./probes/oracle/run.sh
```

Success requires all nine capability result rows/messages, the final success
marker, a zero exit status, and successful removal of `DOOMDB_PROBE`. Run
`./tests/verify-oracle-probes.sh` separately to prove cloud-package identity and
the static fail-fast/drop invariants.
