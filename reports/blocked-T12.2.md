# T12.2 selected-engine optimization status

Status: **LOCAL PROFILE LOOP PENDING T12.1 CUTOVER; FINAL PUBLICATION DEFERRED
UNTIL P11 ADDS CLOUD EVIDENCE**.

The optimization ledger, capture schema, stop rule, artifact verification, and
tamper/redaction tests are implemented. Their production, evaluator, and
mutation self-checks pass after reconciling the reviewed T12.1 manifest ancestry
to `8a93c521…551d4`; no evaluator result is being replaced by synthetic timing.

The live loop now targets the retained Mocha/OJVM path. Each attempt must:

1. use the content-addressed selected-engine replay;
2. preserve its complete state/frame/payload chain and all correctness/mutation
   gates;
3. measure the primary browser run with diagnostics off;
4. collect private worker stages and SQL cursor plans in a separate identical
   replay, because route diagnostics add DML and a second commit per tic;
5. retain regressions and stop only after the first two technically distinct
   reviewed attempts below five-percent improvement.

Local attempt capture and the selected local replay proceed before cloud.
Final T12.2 publication remains correctly fail-closed until P11 appends the
identical real S3/managed-ORDS verification. Cloud credentials are not required
for the local profile loop and are never placed in argv or retained artifacts.
