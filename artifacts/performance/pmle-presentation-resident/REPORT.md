# Resident exact presentation experiment — 2026-07-29

Classification: `DIAGNOSTIC_NOT_GATE`; rejected as the live renderer.

Two source-only TeaVM patches removed synchronized texture access and
prehydrated every wall column, composite, flat, and sprite lump used by the
real Mocha raster graph. The final candidate
`ac8cfcee9348c32d8638f8f705f0eacd9068f59cb524e19507abb1d3e700967d`
(1,178,687 bytes) contains no TeaVM suspension call in the reachable render
graph and matches the accepted Node frame chain.

On OCI, 100 exact database-rendered frames retained the accepted command
stream and frame-chain digests but measured:

- authority step p95: 10.075 ms;
- render plus persistent-locator write p95: 157.036 ms;
- complete pipeline p95: 167.955 ms;
- temporary-LOB delta: 1.

This is only about 2% faster than the partial resident candidate and remains
roughly five times the 33.333 ms frame budget. Removing CPS/suspension edges
did not make Oracle compile the real generated raster graph. The experiment
therefore does not replace the shipping specialized live renderer. Automatic
rollback restored authority `66dd235c…`, and both retained slots returned to
`READY`.
