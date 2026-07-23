# Cloud bootstrap skeleton

All commands default to dry-run and perform no network operation. Dry-run output
is deterministic for a fixed environment and contains the explicit S3 HTTPS
object URL and Autonomous Database managed ORDS health URL.
The placeholder defaults are checked in under `manifests/` and the focused test
rejects any unexplained drift in those generated files.

```sh
deploy/cloud/s3-upload.sh --dry-run
deploy/cloud/autonomous-deploy.sh --dry-run
deploy/cloud/teardown.sh --dry-run
```

The placeholder artifact set is exactly `artifact-allowlist.txt`; extra files,
missing files, traversal entries, and symlinks fail closed. Later production
deployment can select a compiled directory with `DOOMDB_CLIENT_ARTIFACT_DIR`, but
its contents must still exactly match the reviewed allowlist.

Real execution additionally requires `--execute` and
`DOOMDB_CLOUD_EXECUTE=YES`. S3 upload requires `AWS_S3_BUCKET`, `AWS_REGION`,
`AWS_ACCESS_KEY_ID`, and `AWS_SECRET_ACCESS_KEY`. Autonomous deployment requires
`ADB_CONNECTION_STRING`, `ADB_USERNAME`, `ADB_PASSWORD`, and
`ADB_ORDS_BASE_URL`.
Optional AWS session credentials remain environment-only. The scripts verify the
AWS CLI and SQLcl versions pinned in `versions.lock`; database credentials are
fed to SQLcl through standard input, never process arguments. Output passes
through the cloud redactor.

The Autonomous deployment schema must have direct `EXECUTE` capability on
`SYS.DBMS_CRYPTO`; this is a database-engine prerequisite for DoomDB's canonical
SHA-256 documents, not an evaluator grant. `health.sql` verifies SHA-256 before
creating or exposing an ORDS object and aborts deployment if the capability is
absent. A tenant administrator must grant it according to that tenant's
Autonomous Database policy before running `--execute`.

The production target requires Oracle MLE JavaScript; Oracle JVM is neither
required nor permitted in the application schema. The gate uses
`sql/bootstrap/production-order.txt`, purges residual Java call specs and Java
schema objects during in-place upgrades, loads the pinned IWAD through a
database-SHA-fenced JDBC asset loader, and then stages the pinned TeaVM module
and canonical table pack with database-side length/SHA comparison before
`CREATE MLE MODULE`. Wallets, artifacts, loader logs, and passwords remain in
mode-protected temporary storage and are removed on exit.

Teardown is explicit and intentionally separate. Review the dry-run teardown
manifest, then invoke `deploy/cloud/teardown.sh --execute` with the same guarded
environment to delete only the allowlisted S3 object and remove the placeholder
health view/AutoREST exposure. This does not delete an S3 bucket, Autonomous
Database, wallet, schema, or any unrelated object.

## T11.1 production database gate

`scripts/verify-cloud-database.sh` is the fail-closed production gate for the
complete game database. It is separate from the earlier placeholder skeleton.
It requires SQLcl 26.2.0.181.2110, real Autonomous credentials and a wallet
outside the repository, the managed ORDS HTTPS schema root, a freshly collected
local seed observation, and explicit resource bounds. With any input absent it
returns `NOT RUN`, performs no cloud command, and publishes no evidence. A fully
successful live run atomically creates `/tmp/doomdb-t111-evidence.json`; only the
frozen independent evaluator may accept that record.

The gate order is deliberately fail-closed: capability/transport probes,
production schema and seed sources, pinned IWAD load, pinned MLE
module/table-pack load, MLE runtime and REST sources, then catalog/seed/API
evidence. The deployment manifest content-addresses the TeaVM version and build
profile, input/Mocha bytecode, authority module, canonical table pack, and IWAD.

Production execution also requires `DOOMDB_CLOUD_EXECUTE=YES`. The canonical
database account variable is `ADB_USERNAME` in the skeleton, production gate,
environment report, loader, and teardown. The final catalog gate requires zero
Java objects, Java call specs, Java dependencies, or legacy OJVM packages; one
pinned MLE module/environment; exactly 24 MLE call specs; and database hashes
matching the deployment manifest. The OJVM oracle remains in repository/dev
tooling and is intentionally excluded from this production path.

The T11.2 production browser gate requires a dedicated bucket: it enforces the
frozen exact-object inventory by deleting every non-allowlisted key after the
explicit `DOOMDB_CLOUD_EXECUTE=YES` guard. `AWS_S3_BUCKET` must be a DNS-safe
label without dots because the accepted browser URL is the bucket's
virtual-hosted HTTPS URL. The gate accepts the managed ORDS schema root with or
without a trailing slash and normalizes it before constructing AutoREST package
URLs.
