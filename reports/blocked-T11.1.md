# T11.1 cloud database implementation — externally blocked

The approved frozen evaluator lineage is `04d1282dfc05f918a471737ccef1b065232c4d4ff7977abbf675dda3f03459ea`.
The production driver and pinned observation/deployment assets are implemented,
but T11.1 is not accepted and no PASS evidence has been manufactured.

Implemented source:

- `scripts/verify-cloud-database.sh`: fail-closed credential/wallet/tool/version
  preflight; unchanged P0 capability and transport execution; exact bootstrap,
  generated seed, engine, REST, and least-grant deployment; bounded SQL/HTTP;
  live catalog/resource/exposure/grant/seed/API observations; redaction and
  atomic evidence publication.
- `deploy/cloud/t11.1/source-policy.json`: SQLcl 26.2.0.181.2110 and reviewed P0
  SHA-256 pins.
- `deploy/cloud/t11.1/catalog-observation.sql`, `seed-observation.sql`, and
  `least-grants.sql`: target provenance, compilation/constraint/catalog state,
  resource bounds, exact exposure, least public grants, and canonical seed row
  chains.
- `scripts/t11.1-cloud-api.mjs`: direct same-origin managed-ORDS workflows for
  all 17 evaluator API families, including gzip, assets, persistence, replay,
  errors, method handling, and CORS.
- Secret-free evidence/deployment manifest builders and a focused source gate.
- `scripts/mochadoom/build-ojvm-jar.sh`, `load-cloud-ojvm.sh`, and
  `deploy/cloud/t11.1/ojvm-preflight.sql`: deterministic 830-class Java 8
  artifact, target-JDK fail-fast check, supported client-side class load, and
  SHA-verified IWAD load before runtime call-spec finalization. The deployment
  manifest binds the release, pinned revision, class count, and JAR SHA-256.

Verified without external access:

```text
PASS T11.1-EVAL-SELF-CHECK (22/22 fixture-contract assertions)
PASS T11.1-EVAL-MUTATION-SELF-CHECK (24/24 isolated mutations killed)
PASS T11.1-SOURCE-POLICY-SELF-CHECK (synthetic positive and negative canaries)
PASS T11.1-SOURCE-AUDIT (pinned fail-closed cloud driver)
PASS T11.1-SOURCE-FIRST (shell/static/self 22/22; mutations 24/24; guards fail closed)
PASS T11.1-OJVM-ARTIFACT (830 deterministic Java 8 classes; client load+resolve 830/830)
PASS MOCHADOOM-CRASH-RECONSTRUCT oldGeneration=20 newGeneration=21 commands=102 identicalFrameAfterSeam=1
PASS T12.1-BROWSER-TWO-RUN (32.39/35.51 FPS; identical 300-frame chains)
```

The fresh local seed prerequisite now passes against the running Oracle stack:
24/24 populated domains and 29,596 canonical rows. This exercise also corrected
the collector's invalid wildcard-JSON syntax and replaced three empty legacy
sprite/audio tables with the populated canonical asset domains.

External blockers are now limited to a real Autonomous Database 23ai-or-later
target authority with administrator-enabled/restarted `JAVAVM`,
`ADB_CONNECTION_STRING`, `ADB_USERNAME`, `ADB_PASSWORD`, a mode-0600 wallet
directory, its managed ORDS HTTPS schema origin, declared resource bounds, and
pinned SQLcl 26.2.0.181.2110. None of the required `ADB_*` inputs is present in
this shell. Until those exist, live capability, transport, OJVM preflight,
deployment, catalog, seed equality, and direct API evidence remain `NOT RUN`;
`/tmp/doomdb-t111-evidence.json` is not created.

The production entry point additionally requires the explicit
`DOOMDB_CLOUD_EXECUTE=YES` guard. No credential presence alone can trigger a
cloud mutation.
