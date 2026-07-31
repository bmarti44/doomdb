# OCI solo input endpoint A/B — 2026-07-31

Classification: promoted incremental latency improvement with a documented
Always Free renderer-tail limitation.

Production artifact tuple after the A/B:

- authority `66dd235cde82a8b8fbcac88bb905912bacfd6ea40671d2808e5951ce290ce873`
- renderer `51aadc21bcb619928cee3e73217c8150cebf19aa3186dfd273ea3535d88e2edb`
- coordinator `15f1664cb9f3e65a60f13a69aa3f4376c612484918b87998431ffacbac2db60a`
- hosted-static manifest `157a79de43970a3790f47f80c23c4b98c6a122fbe9a3d6043116ed98388c82ca`

The worker now distinguishes camera/movement changes from fire/button-only
input revisions by comparing the first four ticcmd bytes. A camera change moves
the already-budgeted solo exact endpoint to the authoritative effective tic.
Intervals of two or three use the existing exact native EPT1 materializer; an
adjacent endpoint is persisted directly. Multiplayer endpoint scheduling is
unchanged.

Node exactness covered direct, interval-two, and interval-three solo endpoints,
every synthesized pixel, held movement, turning, generation reset, and the
unchanged staggered two-POV path.

Public results:

| Cell | FPS | direction p50 | direction p95/max | transport |
|---|---:|---:|---:|---|
| stable clean baseline | 32.894 | 201.4 ms | 230.8/230.8 ms | 0 cancelled/failed |
| camera-only endpoint | 33.159 | 177.9 ms | 219.1/219.1 ms | 0 cancelled/failed |

The confirmation cell encountered a 4.594-second database renderer pause. Its
available direction samples remained 174.2/178.3 ms, but total FPS fell to
27.3 and only three direction samples completed. This is not classified as a
clean promotion gate. The same class was previously observed on the stable
artifact and attributed to the retained `MLE_FRAME` stage with `ON CPU` or
`User I/O / db file parallel read` ASH samples. Endpoint scheduling improves
normal input latency but cannot manufacture pixels while the Always Free
database renderer is descheduled or faulting pages.

Rejected client fusion evidence is retained separately. Fusing movement input
and exact-frame retrieval removed a normal ORDS round trip, but a slow fused
request occupied the venue's sole API lane. The clean cell fell to 31.845 FPS
with 286.7 ms direction p95; the broad fire-inclusive cell fell to 23.071 FPS.
The public client was rolled back byte-for-byte to manifest `157a79de...`.

The two-POV regression retained 32.23 FPS but missed the pre-existing 250 ms
multiplayer input gate (484.9 ms p95). Because the coordinator deliberately
ignores the new input mask for `playerMask=3`, this is recorded as unchanged
multiplayer latency rather than a solo-candidate regression. No multiplayer
latency claim is made by this promotion.
