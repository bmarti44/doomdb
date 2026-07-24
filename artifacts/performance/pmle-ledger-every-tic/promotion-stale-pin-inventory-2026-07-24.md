# `103e…` promotion stale-pin inventory — 2026-07-24

Status: **source inventory complete; rewrite is gated on the active exhaustive
ledger PASS**.

Candidate authority:

- bytes: `1,170,639`;
- SHA-256:
  `103e15e913b3a8f9a84497af601666fde5f47a720ac4b22fd7843db2559b665e`;
- content-addressed browser name:
  `doom-mle-authority-103e15e913b3.js`;
- input bytecode:
  `83ebc323785cefcacf7b2c434b856e6d62f1f9ae4f77b063e6bce1f0a0e0f099`.

`versions.lock` already records the candidate. That is candidate provenance,
not proof that all production consumers have been promoted. The following
current-runtime references remain on `a942…` or `06ac…` and must change only
after the ledger PASS, compile/source-verifier PASS, and two-tic progress
smoke:

- `sql/sim/088_mle_match_runtime.sql`;
- `probes/mle/teavm-engine/load-mle-module.sh`;
- `probes/mle/teavm-engine/load-tic0-checkpoint-bank.sh`;
- `probes/mle/teavm-engine/package-browser-assets.sh`;
- `probes/mle/teavm-engine/profile-checkpoint-node.mjs`;
- `probes/mle/teavm-engine/profile-command-stream-node.mjs`;
- `client/src/teavm-browser.ts`;
- generated `client/staging/teavm-browser.js`;
- generated `client/dist/play/teavm-browser.js`;
- `deploy/cloud/t11.1/source-policy.json`;
- `deploy/cloud/t11.1/catalog-observation.sql`;
- `scripts/t11.1-deployment-manifest.mjs`;
- `tests/verify-t11.1-source.sh`;
- current-artifact assertions in `tests/verify-mle-dashboard.mjs` and
  `tests/verify-mle-dashboard-live.mjs`.

The candidate JavaScript currently exists only as
`artifacts/performance/pmle-worker-soak/checkpoint-index-map-candidate-2026-07-24.js`.
Promotion copies those exact bytes to the content-addressed browser path and
re-hashes both copies. It does not rebuild TeaVM.

## Dashboard truth split

`scripts/build-mle-dashboard-status.mjs` currently reads the authority pin
from `versions.lock` but validates it against historical `a942…` init-diet and
ledger evidence and `06ac…` soak evidence. With `versions.lock` on `103e…`,
that generator is internally inconsistent.

The promotion rewrite must distinguish:

1. **current candidate/artifact identity** — `103e…`;
2. **candidate correctness evidence** — canonical 330, co-op 762,
   membership, and the active every-tic ledger;
3. **last fully soaked artifact evidence** — historical `06ac…`/`a942…`
   records, explicitly labelled as superseded rather than attributed to
   `103e…`;
4. **open candidate lifecycle gates** — cadence, stratified recovery,
   admission, and final soak remain pending until actually rerun;
5. **current performance truth** — do not retain the dashboard's unqualified
   `34.5 FPS` statement. The latest production-shaped live stream is below
   30 FPS and remains under active acceleration investigation.

Generated `client/staging/mle-status.json`,
`client/dist/mle-status.json`, and the current-artifact portions of both
dashboard `index.html` copies update from that split. Their historical prose
about the voided `a942…` soak remains unchanged.

## Historical references that must not be rewritten

- `PLAN.md` dated decisions;
- `probes/mle/teavm-engine/REPORT.md` dated artifact sections;
- every file under `artifacts/performance/`;
- dashboard evidence paths such as
  `promotion-a942cd2d-2026-07-23.log` when labelled as the init-diet
  promotion;
- dashboard prose explicitly describing the voided `a942…` attempt;
- old content-addressed JavaScript binaries retained as provenance.

Promotion is a targeted current-pin rewrite, never a repository-wide hash
replacement.
