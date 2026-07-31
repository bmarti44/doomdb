# OCI moving-renderer prewarm A/B — 2026-07-31

Classification: rejected producer mitigation and retained diagnostic evidence.

The public exact-frame path was held open for 120 seconds after extending the
throwaway warm-slot route from 96 to 600 rendered movement/combat tics.  The
candidate changed no authoritative state or live pixels: it restored the same
tic-zero checkpoint before `READY`.

## Result

The public cell sustained 33.805 FPS and produced 4,058 unique database frames
from 4,059 presentations.  Direction input-to-paint was 153.5/222.2/222.2 ms
p50/p95/max; the first held-forward response was 155.1 ms.  All 1,840 pixel
exchanges returned HTTP 200 with zero cancellations and zero failures.

The mitigation did **not** remove the producer tail.  Sparse server telemetry
recorded exact raster calls of 370.512 ms at tic 55, 407.830 ms at tic 1,936,
404.962 ms at tic 3,292, 402.970 ms at tic 4,798, and 399.305 ms at tic 5,434.
Authority-step calls independently reached 353.781 ms at tic 2,628 and 351.376
ms at tic 4,062.  The browser's maximum paint gap was 890.5 ms.

The retained authority was SID 23944 / serial 29421.  Administrative ASH over
the exact run window classified the session `ON CPU` in `MLE_FRAME` or
`MLE_STEP`; no row-lock, commit, lifecycle, standby, or ORDS wait explained the
tails.  Because slow raster calls occurred as early as tics 1 and 55 after the
expanded warm route, late generated-code first use is refuted.

## Decision

The 600-render moving prewarm is rejected.  It adds pre-admission work without
changing the tail mechanism.  Production was restored to the pinned 96-render
warm route and the exact solo input-endpoint coordinator
`15f1664cb9f3e65a60f13a69aa3f4376c612484918b87998431ffacbac2db60a`.

The evidence supports treating the remaining sparse tail as single-session
Free-tier CPU/venue variance.  The normal path is healthy and substantially
shorter than the former seconds-long response; masking a multi-hundred-ms
producer pause with more client reserve would directly reintroduce the input
lag this work is intended to remove.
