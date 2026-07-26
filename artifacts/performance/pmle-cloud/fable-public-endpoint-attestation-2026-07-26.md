# Independent public-endpoint attestation — 2026-07-26

Source: Fable review relayed by Brian Martin.

Fable independently inspected the live public OCI managed-ORDS endpoint and
confirmed:

- entry HTML returns the `no-cache` policy;
- entry HTML carries a strong stored-SHA-256 ETag;
- content-addressed assets return the immutable one-year cache policy; and
- an `If-None-Match` request returns `304 Not Modified`.

This is independent corroboration of the retained T11.2 live-header evidence.
It does not replace the automated byte, MIME, cache-class, ETag, empty-body
304, browser-authority, or 300-unique-frame gates.
