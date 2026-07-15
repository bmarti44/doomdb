# T2.1 Freedoom vendor and license

Status: **PASS**

Route: Luna, medium effort, attempt 1. The user-approved generic evaluator
baseline covers this mechanical vendoring task.

## Delivered

- The official Freedoom `v0.13.0` release asset is pinned at
  `vendor/freedoom/0.13.0/freedoom-0.13.0.zip`.
- `COPYING.txt`, `CREDITS.txt`, and `CREDITS-MUSIC.txt` are copied byte for byte
  from that archive. `SOURCE.md` records the official release and asset URLs,
  archive and Phase 1 WAD hashes, and the extraction policy.
- `tests/verify-freedoom-vendor.sh` is a network-free verifier. It checks the
  archive hash before extracting `freedoom1.wad` to a temporary directory,
  requires the WAD member exactly once, checks its hash and four-byte `IWAD`
  identifier, compares all legal copies with their archive members, and checks
  the unique Freedoom license/source-ledger record.
- The existing license/source ledger now identifies the exact official release
  asset and the local provenance record.

The WAD is not stored twice: later ingestion tasks consume the verified member
of the immutable release archive.

## Acceptance evidence

Focused offline acceptance:

```text
$ tests/verify-freedoom-vendor.sh
PASS T2.1 (10/10 assertions; offline)
```

The verified values are:

```text
freedoom-0.13.0.zip  3f9b264f3e3ce503b4fb7f6bdcb1f419d93c7b546f4df3e874dd878db9688f59
freedoom1.wad        7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d
identification       IWAD
```

Earlier-phase static checks and the immutable production-source audit also
remain green:

```text
$ PATH=/usr/local/opt/node@24/bin:$PATH scripts/verify_env.sh
ENV RESULT: PASS
$ tests/verify-oracle-probes.sh
oracle capability probe package: PASS
$ scripts/check-transport-contract.sh
PASS T0.3-static (12/12 assertions)
$ PATH=/usr/local/opt/node@24/bin:$PATH node evaluator/run-foundation.mjs T0.4
PASS T0.4 (8/8 assertions)
$ tests/verify-local-stack.sh
PASS T1.1-static (27 assertions); set DOOMDB_T1_LIVE=1 for fresh-volume acceptance
$ tests/verify-bootstrap-static.sh
PASS T1.2-static (10/10 assertions)
$ tests/verify-cloud-skeleton.sh
PASS T1.3 (12/12 assertions)
$ PATH=/usr/local/opt/node@24/bin:$PATH node evaluator/audit-production.mjs
{"passed":true,"roots":["client/src","sql","deploy"]}
```

The host's default path selects Node 25; the required Node 24 path from the T0.1
host record was therefore used for Node-based verification.

## Changed files

- `vendor/freedoom/0.13.0/freedoom-0.13.0.zip`
- `vendor/freedoom/0.13.0/COPYING.txt`
- `vendor/freedoom/0.13.0/CREDITS.txt`
- `vendor/freedoom/0.13.0/CREDITS-MUSIC.txt`
- `vendor/freedoom/0.13.0/SOURCE.md`
- `tests/verify-freedoom-vendor.sh`
- `reports/license-ledger.tsv`
- `reports/routing.log`
- `reports/task-T2.1.md`

## Integration dispatch

The evaluator-owned root dispatcher may route `./verify.sh task T2.1` to:

```sh
tests/verify-freedoom-vendor.sh
```

No evaluator artifact or root `verify.sh` was changed by T2.1.
