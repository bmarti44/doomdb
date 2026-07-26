# OCI de-CPS presentation diagnostic — 2026-07-26

Classification: `DIAGNOSTIC_NOT_GATE`

## Verdict

The final authorized de-CPS presentation shape does not meet the exact live
database-rendering bar on the OCI release venue. The 100-frame locator cell
measured 191.276 ms pipeline p95 against 33.333 ms, so the predeclared
300-frame acceptance arm was not run. This closes live exact database
rendering on the de-CPS compiled venue. It does not change the approved
release architecture: authoritative MLE simulation plus confirmed browser
rendering remains the live path, and exact MLE rendering remains suitable for
asynchronous audit/DVR work.

Correctness passed independently of performance:

- 100/100 moving frames were unique.
- The database frame chain was
  `44852aabf9f3da7ed1e0adf4d8f3e711798de8cd9a9f43aa7e60eb3f95421acd`,
  exactly matching the Node reference.
- The command stream was staged as 5,250 tics / 173,250 bytes at SHA-256
  `fa7637570c30d3a33cbf8456e98268890e9f5bd82f5ba39fd7f69b139ddc4085`.
- There were zero dual-clock suspect samples.

Measured locator cell:

| Metric | Result |
| --- | ---: |
| authority step + render p50 / p95 | 7.796 / 11.058 ms |
| BLOB persistence p50 / p95 / p99 | 88.689 / 180.003 / 189.084 ms |
| full pipeline p50 / p95 / p99 | 96.361 / 191.276 / 432.652 ms |
| exact 30 FPS | FAIL |
| temporary LOB delta | +2 (hygiene FAIL) |

The persistence leg, not the de-CPS engine step, dominates the result. The
temporary-LOB miss is retained as a second failure; it is not used to explain
or waive the latency failure.

## Candidate provenance

Selected candidate:

- artifact SHA-256
  `118c37717b362d9e7669b5a3a1e73c87b3916479b6e53651f08e85be9ae8f2d3`
- bytes: 1,167,481
- input bytecode SHA-256
  `2ca1278998385efb83aba0358119f70f2e135b569b446f6b43f6afddf51ca914`
- Mocha bytecode SHA-256
  `0c4c97dc003b97ea849b48c72326ff73d3bd833152321d1f208a87f266a1e7a1`
- patch-set SHA-256
  `6c14bdeaf107bf27a954afd99023f4cb2f9c45d179e957341acafd2537415bae`
- optimization: `ADVANCED`, minifying: `true`

TeaVM 0.15.0 did not reproduce byte-identical presentation output from those
identical inputs. Minified runs emitted `a72fd580…`, `2e85aca1…`,
`41282bdd…`, and the selected `118c3771…`; two non-minified debug builds also
diverged (`f00f64ae…`, `696ea0a7…`). The first structural divergence is class
emission order in a charset-decoder region, so the minifier is exonerated.
No supported reproducible-build switch is exposed by the pinned TeaVM Maven
surface. This candidate is therefore exact-SHA selected and preserved, not
claimed reproducible.

## Run integrity and incidents

Attempts v1–v4 are preserved as infrastructure failures and contain no
performance verdict. They exposed and closed:

1. suppressed server output in the pool-park wrapper;
2. SQLcl multi-option `SET` incompatibility in the module loader;
3. an unstaged diagnostic command-vector table;
4. the same SQLcl setting defect in the stream emitter; and
5. rollback verification that omitted recompilation of the package body
   invalidated by MLE module replacement.

The v5 runner stages and SHA-verifies its fixture, uses the shared
adversarially self-tested DB-output parser for every critical marker, parks
capacity, runs the exact candidate, restores production, recompiles and
verifies the worker contract, removes the diagnostic table, and reopens
capacity last.

Postflight observation:

- production authority restored to `5ec18cbe…` / 1,081,335 bytes;
- table pack restored to `058cd0df…` / 180,272 bytes;
- `DOOM_MLE_MATCH_RUNTIME` package body `VALID`;
- zero active matches;
- two READY retained slots;
- diagnostic `DOOM_MLE_PERF_VECTOR` absent.

Key evidence SHA-256:

- rank log:
  `effdab7bd67345888228193008f211b98ca1104578acb91894ff883e9e42f1e4`
- independent verdict:
  `1dc55d1ebd18ee5a007abe5825aa97864a76bf495070559f7c6e43797fd31085`
- rollback log:
  `3c8e6a80351234db5cebd3651290d0dacae0f4e8a6183b29d742018f1ee06afa`
- selected build log:
  `40dc7b02c197f45d47758f4e2096540fca6e8887edf49858be0fc22f95dc377a`
- Node oracle log:
  `9c1d9497e26ab188c8ab64d34ccb48df31a0cd3a0bed1b4845276971289c3746`
