# OCI ADB release-venue verdict — 2026-07-26

Classification: release evidence for authoritative ticker throughput and
correctness; presentation persistence results are `DIAGNOSTIC_NOT_GATE`.

## Authoritative ticker

The pinned `5ec18cbe…` authority ran the exact 5,250-tic deathmatch stream
twice on OCI Autonomous AI Database Always Free 26ai in Ashburn:

| Pass | Whole route | Slowest selected awake-20 peak | Clock suspects |
| --- | ---: | ---: | ---: |
| 1 | 317.029 tics/s | 140.845 tics/s | 0 |
| 2 | 302.419 tics/s | 151.515 tics/s | 0 |

Both whole-route passes and every preselected peak window exceed the
35-authoritative-tics/s bar. The browser's 30-unique-moving-FPS release gate
is separate and remains pending deployment.

Correctness was ratified with a full per-tic canonical digest chain, not only
an endpoint comparison. Node and OCI matched at all ten 500-tic progress
points and at the terminal:

- authority SHA-256:
  `5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3`;
- expanded command stream SHA-256:
  `fa7637570c30d3a33cbf8456e98268890e9f5bd82f5ba39fd7f69b139ddc4085`;
- terminal canonical SHA-256:
  `b3f667c9395455fd42e31586dd79006fc9c091132cb09c8b1f4627a7d93a9907`;
- cumulative per-tic chain SHA-256:
  `36b454b6eeda79e4f6869ba2b29eab4a885fd1970b972b7daad6ce5b692012ee`.

The OCI venue therefore passes the authoritative 35 Hz engine gate with at
least 4.02x margin in the slowest selected peak window. Local Oracle Free
throughput is reclassified as development/capacity evidence and no longer
drives engine optimization or release acceptance.

## Exact database-frame persistence diagnostic

The separately pinned presentation artifact `e55d5f11…` replayed canonical
stream tics 311–640. Node established a 300/300 unique-frame chain
`4e6159b218afc6ec15a763026acaea83038d8bb0764c097069094fe988578a6a`;
both OCI arms matched it exactly with zero clock suspects.

| Persistence arm | Pipeline p50 | Pipeline p95 | Temporary LOB delta |
| --- | ---: | ---: | ---: |
| persistent locator | 141.721 ms | 212.095 ms | 0 |
| direct `Uint8Array` BLOB bind | 142.388 ms | 214.009 ms | +330 |

Both arms fail the diagnostic 33.333 ms p95 bar. This does not alter the
approved architecture: live presentation remains browser rendering from
confirmed database transitions. The stored-frame ORDS GET leg is measured
with the real hosted endpoint during deployment.

`PMLE_OCI_RELEASE_VENUE|PASS|authority_sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3|route_tps_min=302.419|slowest_peak_tps=140.845|digest_binding=FULL_CHAIN_PASS|client_unique_fps=PENDING`

`PMLE_OCI_PRESENTATION_PERSIST|DIAGNOSTIC_NOT_GATE|samples=300|unique=300|locator_p95_ms=212.095|direct_p95_ms=214.009|exact_30fps=FAIL|chain_sha256=4e6159b218afc6ec15a763026acaea83038d8bb0764c097069094fe988578a6a`
