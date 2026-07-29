# OCI 160x84 database-frame deployment — 2026-07-29

Classification: deployed best-current solo and two-view renderer. Solo clears
the database-pixel gate. Two independent POVs now sustain more than 30 FPS on
average, while their strict p95 cadence gate remains open.

Pinned database source tuple:

`PMLE_OCI_SOLO_160X84_ARTIFACT|authority_sha256=66dd235cde82a8b8fbcac88bb905912bacfd6ea40671d2808e5951ce290ce873|renderer_sha256=50835b7130486e5e705bec501c785a43e8158ce5e77202afe2ad9ff4f4133d17|coordinator_sha256=b8d2250f998f7fc5a1a7e4209dff0508abf02fec1672ba41e42de1dda73a5145`

The corrected coordinator transforms only the 168-row world viewport in both
its moving and stationary temporal-reuse paths. The compositor remains the
sole owner of status-bar rows 168 through 199. In a two-view match it also
alternates the expensive exact-world raster phase: each POV is still rastered
once every four tics, but the two calls no longer collide on the same tic.

Current qualifying public-browser result:

`PMLE_OCI_SOLO_160X84|PERFORMANCE_PASS|frames=300|unique_frames=300|sequential_tics=true|fps=34.691|p50_ms=28.200|p95_ms=32.100|p99_ms=32.800|max_ms=33.200|confirmed_drops=0|scored_starvations=0|scored_resyncs=0|first_tic=76|last_tic=375|cleanup_http=200`

The full Playwright harness passed.

Immediate repeat:

`PMLE_OCI_SOLO_160X84_REPEAT|DIAGNOSTIC_NOT_GATE|frames=300|unique_frames=300|sequential_tics=true|fps=34.752|p50_ms=28.200|p95_ms=32.100|p99_ms=33.100|max_ms=63.400|confirmed_drops=0|scored_starvations=1|scored_resyncs=0|first_tic=89|last_tic=388|cleanup_http=200`

The earlier cell confirms sustained average and p95 above 30 FPS but contains
one 63.4 ms tail and one starvation. It is retained as venue-tail evidence, not
silently promoted.

Two-view diagnostic:

`PMLE_OCI_TWO_POV_PHASE_STAGGER|DIAGNOSTIC_NOT_GATE|p0_fps=30.599|p0_p95_ms=47.700|p1_fps=30.536|p1_p95_ms=51.200|unique_frames_per_player=300|confirmed_drops_per_player=0`

This is a material improvement over the unstaggered current-renderer baseline
of 29.982/29.756 FPS. It closes the sustained-average requirement but not the
strict 33.333 ms p95 requirement; no full two-view PASS is claimed.

Postflight:

`PMLE_OCI_SOLO_160X84_POSTFLIGHT|active_matches=0|ready_slots=2|nonready_slots=0`

Evidence:

- `oci-160x84-phase-stagger-solo-browser-repeat-2026-07-29.json`
- `oci-160x84-phase-stagger-solo-browser-repeat-2026-07-29.png`
- `oci-160x84-phase-stagger-solo-browser-2026-07-29.json`
- `oci-160x84-phase-stagger-db-postflight-2026-07-29.log`
- `oci-160x84-two-pov-baseline-2026-07-29.{log,json}`
- `oci-160x84-two-pov-phase-stagger-2026-07-29.{log,json}`
