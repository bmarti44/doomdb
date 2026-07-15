# T1.3 Cloud skeleton

## Route

`T1.3 | Terra | medium | attempt 1` — deterministic S3 and Autonomous
Database deployment skeletons from a closed cloud-bootstrap contract.

## Delivered

- Default-safe S3 upload, Autonomous SQL deployment, and teardown scripts.
- A single-file placeholder client governed by an exact artifact allowlist.
- Health-view DDL that enables only `PUBLIC_HEALTH` through managed ORDS.
- Checked-in, byte-stable dry-run manifests with explicit S3 HTTPS and managed
  ORDS URLs.
- A stream redactor for AWS and ADB secret fields, environment-held secret
  values, and SQLcl connect strings.
- Two-factor mutation protection: real operations require both `--execute` and
  `DOOMDB_CLOUD_EXECUTE=YES`; missing credentials and wrong pinned CLI versions
  then fail closed.
- Narrow teardown instructions that remove only the placeholder object and
  health view, without deleting buckets, schemas, wallets, or databases.

## Verification

`tests/verify-cloud-skeleton.sh` passes 12/12 focused assertions. It verifies:

- repeatable dry-run output and exact agreement with checked-in manifests;
- exactly one allowlisted client artifact and exactly one health DDL input;
- explicit S3 object and managed ORDS endpoint URL shapes;
- exact redaction of representative secret fixtures;
- rejection of an extra artifact;
- rejection of execute mode without its explicit opt-in guard; and
- presence of guards in every mutating entrypoint.

Shell syntax, ShellCheck, JavaScript syntax, and JSON parsing also pass.

No AWS or Autonomous mutation was attempted. The real placeholder smoke is
optional in T1.3 and cannot substitute for the mandatory P11 cloud gates.

## Integration dispatch

The evaluator-owned root dispatcher should map `./verify.sh task T1.3` to:

```sh
tests/verify-cloud-skeleton.sh
```

No evaluator artifact or root `verify.sh` was changed by T1.3.
