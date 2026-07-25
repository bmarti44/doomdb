# Async admission decision — 2026-07-25

Artifact:
`5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3`.

The accepted metric is browser-observed `READY_MATCH` click to the first
generation-fenced `ACTIVE` status. The client polls every 100 ms. Each cell
uses ten fresh solo/skill-3 matches, waits for both retained slots to return
to idle `READY` between samples, records the Free-edition Resource Manager
metadata, requires a quiet host, and scans the Oracle alert window.

The worker reuses the exact hash-verified tic-zero checkpoint bank entry
after `prepare_origin_warm`; cold starts retain the serialization path. This
removes redundant checkpoint serialization from the user-facing admission
path without changing checkpoint bytes or durability ordering.

The post-READY scheduling yield is an explicit Free-edition heuristic, not a
correctness dependency:

| Yield | p50 | p95 | Verdict |
|---:|---:|---:|:---|
| 100 ms | 4,599 ms | 4,906 ms | PASS |
| 0 ms | 6,506 ms | 8,749 ms | FAIL |

The full browser-observed sample spreads, in execution order, were:

- 100 ms: `4525, 4900, 4725, 4906, 4571, 4418, 4473, 4723, 4599, 4899`
- 0 ms: `8749, 7423, 6429, 6441, 6628, 6506, 4288, 7308, 7580, 6339`

Both cells had zero new Oracle errors. Removing the yield lets authority and
standby work contend with the waiting ORDS status request under the
edition-enforced two-running-session cage. The production value therefore
remains 100 ms. This is venue-local Free-edition evidence, not a portable
constant: it is tunable and must be remeasured during the OCI cloud
acceptance run under that venue's session/CPU envelope.

Evidence:

- `warm-pool-admission-decps-5ec18cbe-bank-yield100ms-2026-07-25.log`
- `warm-pool-admission-decps-5ec18cbe-bank-yield0ms-2026-07-25.log`
