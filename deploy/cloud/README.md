# OCI Autonomous Database deployment

The active production venue is OCI Autonomous AI Transaction Processing Always
Free in `us-ashburn-1`, running Oracle AI Database 26ai. OCI CLI is the
provisioning and lifecycle control surface. The pinned application schema is
`DOOM`, exposed through the managed ORDS alias `doom`.

The production topology has one origin:

```text
https://<managed-ords-host>/ords/doom/
  doom_api/...   generated AutoREST game API
  app/...        database-resident static client
```

The static client is stored in `DOOM_HOSTED_ASSET` BLOBs and served by the
dedicated `doom.hosted.app` ORDS module. There is no S3, Object Storage,
CloudFront, reverse proxy, CORS bridge, Lambda, API Gateway, EC2 service, or
custom middle tier in the release path.

## Production gates

`scripts/verify-cloud-database.sh` is T11.1, the fail-closed schema and managed
ORDS gate. It runs capability and transport probes, installs only the reviewed
production manifest, loads the pinned IWAD and TeaVM artifacts through
database-side length/SHA checks, builds the tic-zero checkpoint bank, and then
verifies catalog, grants, seed parity and live API behavior. A PASS is written
atomically to `/tmp/doomdb-t111-evidence.json`.

`scripts/verify-cloud-browser.sh` is T11.2. It requires a valid T11.1 record,
builds an exact 24-object prefix-safe client, installs the static module, loads
all BLOBs in one transaction, verifies the database and anonymous ORDS
inventories, and GETs every object to confirm bytes, MIME and cache metadata.
The PL/SQL handlers emit each stored MIME type and stored SHA-256 as a strong
ETag, return an empty-body `304` for matching `If-None-Match`, apply
`no-cache` to entry HTML, and apply one-year immutable caching only to
content-addressed assets. Fable independently confirmed those four properties
against the live public endpoint; the attestation is retained alongside the
automated evidence.
Pinned Chromium then creates a real MLE-authoritative match and gates 300
sequential, unique moving frames at at least 30 FPS with p95 frame interval no
greater than 33.333 ms. It releases the match before atomically publishing
`/tmp/doomdb-t112-evidence.json`.

Both drivers require `DOOMDB_CLOUD_EXECUTE=YES`, the pinned SQLcl wrapper,
wallet and passwords outside retained evidence, and real external authority.
Absent inputs produce `NOT RUN`, never PASS. Underlying errors are preserved
through the redactor; wrappers redact secrets, not diagnosis.

On Docker Desktop, use `scripts/sqlcl-dedicated-container.sh` and set
`DOOMDB_SQLCL_DOCKER_WALLET` to the ignored, host-shareable wallet directory.
The verifier may continue to use its externally scoped `ADB_WALLET_DIR`.
SQLcl runs in a separate capped Java container so its heap cannot compete with
the local Oracle SGA/PGA while streaming the production manifest.

The direct privilege surface is declared exclusively in
`t11.1/schema-grants.sql` and is source-fenced as an exact inventory. `CREATE
PROPERTY GRAPH` is install-validation-only; the live MLE ticker does not depend
on a property graph. OJVM is absent from the production schema and deployment
manifest but remains in repository/dev tooling as the permanent differential
oracle.

## Venue facts

The Always Free database currently uses 1 ECPU and 20 GB storage with
autoscaling disabled. The same pinned `5ec18cbe…` authority completed the
5,250-tic OCI command stream at 302.419 tics/s on the slower of two full passes;
the slowest preselected awake-20 peak window sustained 140.845 tics/s. A
canonical digest-bound pass matched the accepted Node chain. Those measurements
clear the 35-Hz authoritative ticker bar on this venue.

Always Free has no SLA and may stop after seven idle days. The accepted policy
currently records that property and does not generate keep-alive traffic. Cloud
harnesses check lifecycle state and fail closed rather than interpreting a
stopped database as an application result.

The legacy `autonomous-deploy.sh`, `s3-upload.sh`, `teardown.sh`, placeholder
health SQL and manifests are retained only as historical pre-T11 scaffolding.
They are not referenced by the production manifest or either release gate and
must not be used for the OCI-hosted application.
