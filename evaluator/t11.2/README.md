# T11.2 independent OCI hosted-browser evaluator

This evaluator accepts only a live Chromium run whose top-level document and
dynamic API calls share the managed ORDS origin of the deployed Autonomous
Database. Static files are stored as database BLOBs and served by the dedicated
`doom.hosted.app` ORDS module under the `doom` schema alias. A local server,
object store, CDN, reverse proxy, mocked route, replayed trace, dry run, or
source-only audit cannot pass.

The production driver builds an exact 17-object database-pixel client
allowlist. Browser authority, presentation, canonical-table and IWAD payloads
are excluded; redistribution notices remain. The database loader uses one
transaction, deletes
extraneous objects, streams each BLOB, and verifies its length and SHA-256 in
Oracle before commit. A live GET of every object must reproduce the build hash,
MIME type and cache policy. Anonymous exposure is limited to the intended
AutoREST objects and the dedicated two-route static module.

Playwright 1.61.0 uses one Chromium worker with service workers blocked and no
route fulfillment. It creates a real authoritative MLE match, verifies that
complete database-generated framebuffers—not browser simulation—produce 300
sequential and byte-unique moving frames at at least 30 FPS with p95 frame
interval no greater than 33.333 ms, and releases match capacity. A database
postflight binds runtime artifact SHAs and proves at least two checkpoints in
the scored window with no checkpoint step over 100 ms. The complete network
ledger may contain only
same-origin database static or Oracle API requests; redirects, failed requests,
websockets, mocks, console/page errors and other origins fail.

ADB credentials, wallet paths, URLs, match tokens and session identifiers remain
environment-only and must not occur in retained evidence. Evidence retains only
SHA-256 identities and redacted live observations and is written atomically
after all gates pass.
