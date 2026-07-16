# Local stack

The stack runs the pinned Oracle Free and ORDS images from `versions.lock`.
Oracle is constrained to exactly two CPUs and 2 GiB. The database entrypoint
regenerates the vendor SPFILE with `sga_target=1024m` and
`pga_aggregate_target=256m` before handing control back to the vendor entrypoint.
The first-database initialization hook grants the fixed `DOOM` owner direct
`EXECUTE` capability on `SYS.DBMS_CRYPTO`, which DoomDB requires for canonical
SHA-256 documents. The same first-database hook presizes the USERS datafile to
4 GiB with 512 MiB growth increments and replaces the image's 200 MiB redo logs
with three 1 GiB groups. This prevents per-second datafile growth and roughly
per-minute log switches under the retained worker's durable write rate. These
settings contain no credential and are persisted with the database volume.
On the first run with an empty ORDS configuration volume, the wrapper removes
the ORDS repository bundled in Oracle Free through the supported ORDS CLI; the
official ORDS entrypoint then installs the pinned version and persists its pool.

Create local secrets without placing credentials in Compose environment values:

```sh
cp secrets/oracle_password.txt.example secrets/oracle_password.txt
cp secrets/doom_password.txt.example secrets/doom_password.txt
chmod 600 secrets/oracle_password.txt secrets/doom_password.txt
docker compose up --detach --wait --wait-timeout 1800
```

The placeholder client is at `http://localhost:8080/`, the ORDS context is at
`http://localhost:8080/ords/`, and Oracle listens on `localhost:1521` with
service `FREEPDB1`. Both the page and eventual `/ords/doom` AutoREST API use the
same ORDS origin. Stop and remove the fresh data/config volumes with:

```sh
docker compose down --volumes
```

On Linux ARM64, set `DOOMDB_ORACLE_IMAGE` and `DOOMDB_ORDS_IMAGE` to the ARM64
tag-plus-digest pairs recorded in `versions.lock`; unpinned overrides are not
permitted. Port and secret source paths can be overridden with the documented
`DOOMDB_*_PORT` and `DOOMDB_*_PASSWORD_FILE` variables in `compose.yaml`.
