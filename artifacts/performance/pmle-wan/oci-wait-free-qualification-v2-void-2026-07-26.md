# OCI wait-free qualification v2 — VOID

Classification: `VOID_HARNESS_PRIVILEGE_NOT_GATE`.

The 50±10 ms profile passed lobby startup, both-client presentation, and the
background/refocus scenario. During the scored window the generic local soak
harness attempted its 60-second memory sample through `V_$SESSTAT`. Managed
ADB deliberately does not grant that SYS view to the application schema, so
the harness terminated with `ORA-00942` before any profile or matrix terminal.

This is not a product, transport, or gameplay verdict. Cleanup completed and
the raw logs remain unmodified under the v2 tag.

The correction does not expand the production privilege surface. Managed-ADB
WAN runs now use `DOOM_MATCH_WORKER_CONTROL`'s already-persisted
`cpu_sample_tic`, `cpu_window_ms`, and `cpu_percent` fields, plus the existing
`V_$SESSION` liveness grant. Evidence explicitly states that memory growth is
owned by the separate retained-session soak. Local soak runs retain their
original PGA/UGA/Java-memory assertions.
