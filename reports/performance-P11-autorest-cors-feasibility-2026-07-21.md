# P11 AutoREST CORS feasibility review — 2026-07-21

## Conclusion

The frozen T11.2 browser contract is not currently implementable through a
documented configuration surface while all three rails remain fixed: an S3
top-level document, Oracle-managed Autonomous ORDS, and generated AutoREST
PL/SQL package endpoints only. This is a contract feasibility conflict, not a
game-engine or S3 CORS problem.

Local ORDS 26.2 returned this response to a literal preflight for
`DOOM_API.NEW_GAME`:

```text
HTTP/1.1 200 OK
Content-Length: 0
```

It returned no `Access-Control-Allow-*` headers. A real Chromium page loaded
from `http://127.0.0.1:8080/` then failed to fetch the same procedure through
`http://localhost:8080/`. The frozen evaluator requires status 204, exact
origin reflection, POST, and `content-type`/`accept` allow headers.

## Supported surfaces

- Oracle documents AutoREST as a deliberately constrained alternative to
  manually created resource modules. Auto-enabled PL/SQL objects use POST with
  `application/json`, so a cross-origin browser request necessarily triggers a
  preflight. [ORDS 26.2 AutoREST documentation](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.2/orddg/developing-REST-applications.html)
- `ORDS.ENABLE_OBJECT` exposes enablement, object alias, object type, and coarse
  authorization. It has no origin or automatic-OPTIONS setting. By contrast,
  `ORDS.SET_MODULE_ORIGINS_ALLOWED` explicitly applies to a manually created
  resource module. [ORDS PL/SQL package reference](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/25.2/orddg/ORDS-reference.html)
- Oracle states that customers cannot modify configuration options on the
  default Oracle-managed Autonomous ORDS service; configuration control requires
  customer-managed ORDS. [Customer-managed ORDS on Autonomous Database](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/26.2/ordig/installing-and-configuring-customer-managed-ords-autonomous-database.html)
- `security.externalSessionTrustedOrigins` is documented for the separate
  legacy PL/SQL Gateway surface, not generated AutoREST RPC. It would also be an
  ORDS configuration option unavailable on the managed service.
  [ORDS PL/SQL Gateway CORS](https://docs.oracle.com/en/database/oracle/oracle-rest-data-services/25.3/orddg/pl-sql-gateway.html)
- S3 bucket CORS cannot authorize a request received by Oracle. AWS evaluates a
  bucket's CORS rules only when S3 receives the cross-origin/preflight request.
  [Amazon S3 CORS behavior](https://docs.aws.amazon.com/AmazonS3/latest/userguide/cors.html)

The absence of a supported automatic-OPTIONS status control is an inference
from the documented API/configuration surfaces, corroborated by the live local
response. It is not a claim that every managed ORDS release must return the same
status. The actual managed endpoint remains the decisive observation.

## Fail-fast managed experiment

Before any S3 upload, send one `OPTIONS` request to the real managed
`DOOM_API.NEW_GAME` URL with:

```text
Origin: https://<bucket>.s3.<region>.amazonaws.com
Access-Control-Request-Method: POST
Access-Control-Request-Headers: content-type,accept
```

Proceed only if the response is 204, reflects the exact origin, allows POST,
and allows both request headers. Otherwise stop before mutating S3 and record
the frozen evaluator/AutoREST conflict. `scripts/verify-cloud-browser.sh` now
performs this exact fail-fast probe after read-only AWS identity/region checks
and before listing, deleting, or uploading bucket objects.

## Reconciliation choices if managed ORDS matches local

1. Permit a minimal ORDS resource module that delegates to the existing Oracle
   game packages and sets the S3 origin. This keeps the browser, protocol, game
   state, and execution inside S3 + Oracle, but relaxes “generated AutoREST
   only.”
2. Permit customer-managed ORDS or an Oracle API gateway with explicit CORS.
   This adds operational architecture and is wider than option 1.
3. Co-locate the static client with ORDS and remove cross-origin transport. This
   violates the frozen real-S3 top-level-document gate.
4. Amend only the expected status from 204 to 200. This is insufficient while
   the required allow headers remain absent.

No reconciliation has been silently selected. Until the managed probe passes
or the charter/evaluator is explicitly amended, T11.2 must remain `NOT RUN`.
