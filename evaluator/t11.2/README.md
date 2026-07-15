# T11.2 independent S3 browser evaluator

This evaluator accepts only a live Chromium run whose top-level document is the
explicit HTTPS `index.html` object in the deployed S3 bucket and whose dynamic
requests go directly to the T11.1 managed ORDS origin. A local server, S3 website
HTTP endpoint, CloudFront, reverse proxy, mocked route, replayed trace, dry run,
or source-only audit cannot pass. Missing external credentials or URLs produces
nonzero `NOT RUN`, never PASS.

The production upload driver must build the managed ORDS URL into the compiled
client, derive a byte-exact allowlist, upload only that allowlist using AWS CLI
2.34.36, set deterministic content types and cache controls, and collect live S3
HEAD/GET/version/TLS provenance. `index.html` is always revalidated; immutable
long caching is allowed only for content-addressed objects whose filename digest
matches their bytes. Source maps, evaluator material, WAD tooling, reports,
goldens, secrets, wallets and runtime configuration are forbidden artifacts.

Playwright 1.61.0 uses one pinned Chromium worker with routing interception and
service workers disabled. It records actual requests, OPTIONS and response CORS
headers, then covers new game, STEP, palette/asset transport, raw canvas bytes,
database-authored audio, save/load, replay and E1M1 completion smoke. The network
ledger may contain only the one attested S3 origin and the one attested Oracle
managed ORDS origin; redirects, failed requests, console/page errors, mocks,
websockets and all other dependencies fail.

AWS and ADB credentials, bucket names, regions, account ids, object URLs, ORDS
URLs, tokens, authorization headers and session ids remain environment-only and
must not occur in retained evidence. Evidence keeps lower-case SHA-256 identities
and redacted live observations, is written atomically only after success, and is
validated only after evaluator integrity, foundation and adversarial gates pass.

