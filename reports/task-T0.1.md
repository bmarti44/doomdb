# T0.1 Versions and host preflight

## Route

`T0.1 | Luna | medium | attempt 1` — mechanical version locks, host checks,
dependency caching, and license records with exact acceptance criteria.

## Delivered

- Exact Node 24 LTS and npm versions in `.nvmrc`, `package.json`, and
  `versions.lock`.
- Lockfile v3 with exact direct TypeScript 7.0.2 and Playwright 1.61.0
  dependencies and integrity-pinned transitives.
- Platform-specific `linux/amd64` and `linux/arm64` image manifest digests for
  Oracle Free 23.26.2, ORDS 26.2.0, and Playwright 1.61.0 noble. Tags remain
  next to digests for readability.
- An explicit online cache-population command and an offline-only host verifier.
- A license/source ledger covering every locked runtime, image, deployment
  tool, WAD input, and npm dependency family before ingestion.

## Host observations

- Host: macOS 15.7.3, `x86_64`, mapped to `linux/amd64` container manifests.
- Docker client 29.4.1; server 29.2.1; Compose 5.1.3.
- Node 24.18.0/npm 11.16.0 installed at `/usr/local/opt/node@24/bin` because the
  host's default PATH selects Node 25.9.0. `.nvmrc` is the portable selector.
- jq 1.7.1, curl 8.7.1, unzip 6.00, GNU sha256sum 9.11, and Apple shasum 6.02
  are available. The SHA-256 probe hashes `abc` to its standard digest.
- More than 20 GiB disk was available.
- AWS credentials: PRESENT. ADB credentials: ABSENT. No secret value was printed.
  Missing ADB credentials are non-blocking until P11 under Plan section 4.3.

## Commands and results

```text
PATH=/usr/local/opt/node@24/bin:$PATH scripts/cache_dependencies.sh
PASS — npm dependencies and all three linux/amd64 images are cached by digest.

PATH=/usr/local/opt/node@24/bin:$PATH scripts/verify_env.sh
PASS — 34 checks passed; ENV RESULT: PASS.

PATH=/usr/local/opt/node@24/bin:$PATH scripts/test_verify_env_rejections.sh
PASS — floating tag, unlocked package, and missing license entry rejected;
offline verifier contains no fetch operation and npm is forced offline.
```

The verification path makes no registry or HTTP request: package installation
uses `npm ci --offline`, and image checks use local `docker image inspect`.
Network is needed only by the separately named `cache_dependencies.sh` command.

## Changed files

- `.nvmrc`
- `.gitignore`
- `package.json`
- `package-lock.json`
- `versions.lock`
- `scripts/cache_dependencies.sh`
- `scripts/verify_env.sh`
- `scripts/test_verify_env_rejections.sh`
- `reports/license-ledger.tsv`
- `reports/routing.log`
- `reports/task-T0.1.md`

## Integration dispatch

The evaluator-owned root dispatcher should map `./verify.sh env` to:

```sh
scripts/verify_env.sh
```

No evaluator artifact or root `verify.sh` was changed by T0.1.
