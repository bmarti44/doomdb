# T10.3 local end-to-end implementation status

Status: **SOURCE-FIRST READY; LIVE ACCEPTANCE PARKED**.

The approved frozen evaluator manifest remains byte-identical at
`530095621f343aae15a6dcbe1c19fe1164c17e93f23e412279150a3e5277ef3e`.
No evaluator source, manifest, shared bootstrap, shared `verify.sh` route, or
running stack was changed by this implementation item.

Implemented production harness assets:

- `scripts/verify-local-e2e.sh`: two unpredictable fresh project identities,
  new mode-0600 credentials per run, hard per-operation and whole-gate bounds,
  fail-closed health/exit handling, live resource/sandbox inspection, secret
  scanning, volume/orphan cleanup, record extraction, and confined repeat-ledger
  comparison.
- `deploy/local/t10.3/compose.yaml`: unexposed internal test network, pinned DB,
  ORDS and Playwright image inputs, exact two-CPU/two-GiB database limits, and a
  non-root/read-only/capability-free evaluator with no Docker socket.
- `deploy/local/t10.3/Dockerfile` and `db_sql.sh`: immutable evaluator workspace,
  pinned Chromium runtime, direct SQL*Plus network transport to Oracle, and no
  host-Docker SQL transport.
- `scripts/t10.3-inspect.mjs` and `t10.3-extract-record.mjs`: strict topology and
  evidence validation with negative unit canaries.
- `.dockerignore`: secret, wallet, environment, report, artifact and local
  dependency exclusion from evaluator build context.

Source-first evidence:

```text
PASS T10.3-INSPECT-UNIT (8/8 topology mutations checked)
PASS T10.3-RECORD-UNIT (4/4 extraction mutations checked)
PASS T10.3-EVAL-SELF-CHECK (21/21 fixture-contract assertions)
PASS T10.3-EVAL-MUTATION-SELF-CHECK (24/24 isolated mutations killed)
PASS T10.3-SOURCE-AUDIT (bounded host orchestration and confined evaluator runner)
PASS T10.3-SOURCE-FIRST (10/10 static and orchestration-unit assertions)
```

The two live fresh-volume runs were intentionally not started. Their immutable
24-family inventory includes T10.1/T10.2 and routes through T10.2 that are not
yet complete; starting now could not produce valid 14-row/16-domain acceptance
and would consume the live stack without acceptance value. Once upstream
production and all visible routes are complete, run `scripts/verify-local-e2e.sh`
unchanged and retain its two run records and repeat-ledger digest.
