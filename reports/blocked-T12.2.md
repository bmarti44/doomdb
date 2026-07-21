# T12.2 selected-engine optimization status

Status: **LOCAL COMPLETE; FINAL PUBLICATION DEFERRED UNTIL P11 ADDS CLOUD
EVIDENCE**.

The optimization ledger, capture schema, stop rule, artifact verification, and
tamper/redaction tests are implemented. Their production, evaluator, and
mutation self-checks pass after reconciling the reviewed T12.1 manifest ancestry
to `8a93c521…551d4`; no evaluator result is being replaced by synthetic timing.

The retained-Mocha local loop is complete. It retained three measured attempts:

1. `transport`, 5 ms → 2 ms readiness: accepted, +28.13% p50 improvement,
   31.25 effective serial FPS;
2. `transport`, 2 ms → 1 ms: rolled back, -21.30%, one clock anomaly;
3. `index`, redundant request/status poll index: rolled back, -3.92%, unchanged
   frame plan.

Attempts 2 and 3 are the first consecutive technically distinct sub-5% pair,
so the stop rule is satisfied. The rejected index is absent and production is
back on the selected 2 ms source. Two selected browser runs pass at 31.81/31.59
FPS with identical state/frame/payload chains. `verify.sh task T12.2` validates
the local ledger fail-closed.

The final publication continues to require that each cloud attempt:

1. use the content-addressed selected-engine replay;
2. preserve its complete state/frame/payload chain and all correctness/mutation
   gates;
3. measure the primary browser run with diagnostics off;
4. collect private worker stages and SQL cursor plans in a separate identical
   replay, because route diagnostics add DML and a second commit per tic;
5. retain regressions and stop only after the first two technically distinct
   reviewed attempts below five-percent improvement.

Local attempt capture and the selected local replay are complete. Final T12.2
publication remains correctly fail-closed until P11 appends the
identical real S3/managed-ORDS verification. Cloud credentials are not required
for the local profile loop and are never placed in argv or retained artifacts.
