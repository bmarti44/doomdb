# T1.1 local stack

Status: **PASS**

Route: Terra, medium effort, attempt 1. The approved T0.4 generic evaluator
baseline covers this mechanical Compose task.

## Delivered

- `compose.yaml` pins Oracle Free 23.26.2 and ORDS 26.2.0 to the reviewed amd64
  digests. The ARM64 digest override contract points back to `versions.lock`.
- The `db` service has runtime limits of exactly 2 CPUs and 2 GiB, a named data
  volume, a `FREEPDB1` health check, and Docker-secret file inputs. It does not
  set `ORACLE_DATABASE`, because the pinned image already contains FREEPDB1.
- `deploy/local/db-entrypoint.sh` regenerates `spfileFREE.ora` from Oracle's
  generated PFILE with `sga_target=1024m` and
  `pga_aggregate_target=256m`, then executes the unmodified vendor entrypoint.
- The `ords` service is gated on database health and targets
  `db:1521/FREEPDB1`. On the first empty config volume it uses the supported
  ORDS CLI with password-stdin to remove the repository bundled in Oracle Free;
  the official image then installs the pinned repository and persistent pool.
- ORDS serves `client/dist` as `standalone.doc.root`. The placeholder page,
  static health response, and `/ords/` endpoint use one origin.
- Local credential files are ignored. Compose mounts the SYS and DOOM values as
  secrets; neither value is present in rendered Compose environment values,
  container command arguments, nor captured logs.

## Acceptance evidence

Static contract:

```text
$ ./tests/verify-local-stack.sh
PASS T1.1-static (27 assertions); set DOOMDB_T1_LIVE=1 for fresh-volume acceptance
```

Fresh-volume live contract:

```text
$ DOOMDB_T1_LIVE=1 ./tests/verify-local-stack.sh
Container doomdb-t11-1465-db-1 Healthy
Container doomdb-t11-1465-ords-1 Healthy
PASS T1.1-live (36 assertions; fresh volumes)
```

The live path created new Oracle data and ORDS config volumes, waited for both
health checks, and proved:

- live cgroup settings are `NanoCpus=2000000000` and
  `Memory=2147483648`;
- a SQL query returns `DOOMDB_SQL_READY` from the healthy database;
- `/health.txt` returns `DOOMDB_ORDS_READY`, `/` serves the placeholder, and
  `/ords/` responds through the same host and port;
- live ORDS config reports `/var/www/doomdb` as `standalone.doc.root`;
- the two known test credentials occur in neither service logs nor process
  entrypoint/command arguments; and
- teardown removed both fresh test volumes.

The ORDS first-run log additionally recorded a successful CLI uninstall, pinned
26.2.0 reinstall, static-root configuration, and a valid database pool without
printing the supplied SYS password.
