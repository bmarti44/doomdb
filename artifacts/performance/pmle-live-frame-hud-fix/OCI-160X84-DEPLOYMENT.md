# OCI 160x84 database-frame deployment — 2026-07-29

Classification: deployed best-current solo renderer; the first cell clears
the 30 FPS database-pixel performance bar, while the repeat cell records one
managed-service tail and therefore is not represented as a clean repeat gate.

Pinned database source tuple:

`PMLE_OCI_SOLO_160X84_ARTIFACT|authority_sha256=66dd235cde82a8b8fbcac88bb905912bacfd6ea40671d2808e5951ce290ce873|renderer_sha256=50835b7130486e5e705bec501c785a43e8158ce5e77202afe2ad9ff4f4133d17|coordinator_sha256=903ee45498ea637da2150fcda226e46480f4257bcc650b4e30930527882fdf8b`

The corrected coordinator transforms only the 168-row world viewport in both
its moving and stationary temporal-reuse paths. The compositor remains the
sole owner of status-bar rows 168 through 199.

Primary public-browser result:

`PMLE_OCI_SOLO_160X84|PERFORMANCE_PASS|frames=300|unique_frames=300|sequential_tics=true|fps=34.995|p50_ms=28.200|p95_ms=31.900|p99_ms=32.300|max_ms=32.799|confirmed_drops=0|scored_starvations=0|scored_resyncs=0|first_tic=80|last_tic=379|cleanup_http=200`

The Playwright process classified the cell as failed because two requests
were cancelled by the intentional page-hide/leave cleanup. Those cancellations
occurred after scoring; the performance data and database cleanup result are
retained, but this is not called an unqualified full-harness PASS.

Immediate repeat:

`PMLE_OCI_SOLO_160X84_REPEAT|DIAGNOSTIC_NOT_GATE|frames=300|unique_frames=300|sequential_tics=true|fps=34.117|p50_ms=28.300|p95_ms=32.400|p99_ms=33.200|max_ms=225.000|confirmed_drops=0|scored_starvations=1|scored_resyncs=0|first_tic=81|last_tic=380|cleanup_http=200`

The repeat confirms sustained average and p95 above 30 FPS but contains one
225 ms tail and one starvation. It is retained as venue-tail evidence, not
silently promoted.

Postflight:

`PMLE_OCI_SOLO_160X84_POSTFLIGHT|active_matches=0|ready_slots=2|nonready_slots=0`

Evidence:

- `oci-160x84-solo-browser-pass-2026-07-29.json`
- `oci-160x84-solo-browser-pass-2026-07-29.png`
- `oci-160x84-solo-browser-repeat-2026-07-29.json`
- `oci-160x84-db-postflight-2026-07-29.log`
