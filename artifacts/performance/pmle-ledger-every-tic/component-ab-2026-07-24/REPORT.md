# `a942…` versus `103e…` component A/B — 2026-07-24

Status: **PASS — `103e…` promoted under the five-percent ticker parity rule**.

The retained pool was fully parked and the host was quiet for both cells.
Both artifacts ran the same first 500 commands of the accepted E1M1 ledger.
Canonical state was materialized, exported, natively hashed, and accumulated
on every tic.

| Component | `a942…` p50 | `103e…` p50 | Change |
|---|---:|---:|---:|
| ticker | 134.299 ms | 130.152 ms | -3.088% |
| canonical material | 2,209.481 ms | 2,194.695 ms | -0.669% |
| raw export | 24.377 ms | 24.335 ms | -0.172% |
| combined | 2,375.234 ms | 2,359.885 ms | -0.646% |

Ticker p95 changed from 187.222 ms to 192.968 ms (+3.069%). The governing
p50 and p95 changes are both within the approved 5% parity band. The p99
sample changed from 225.188 ms to 239.414 ms; this sparse-tail movement is
recorded but is not substituted for the predeclared p50/p95 promotion rule.

Both cells produced the same terminal cumulative digest:

```
ae3c44e8937729a4fed42f4acb09c84121cdc964582d154cb3c978750bbaa22b
```

Raw logs:

- `a942.log`
- `103e.log`

SQLcl folded the long terminal markers across physical lines. The extractor
was therefore hardened to reassemble only component-profile continuation
lines before applying its anchored exact-length digest check. Its mandatory
offline self-test covers both unwrapped and SQLcl-wrapped markers.

The canonical-material work intentionally dominates this diagnostic and is
not part of ordinary live simulation. Promotion is based on ticker parity and
canonical identity, not the approximately 20-minute diagnostic-export cell
duration.
