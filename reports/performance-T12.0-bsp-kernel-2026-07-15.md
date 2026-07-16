# T12.0 clean-room BSP/projection kernel

Date: 2026-07-15

This is the first implementation result after the relational-pixel renderer was
rejected. It is a disposable algorithm-selection spike, not a production
renderer and not a 30 FPS claim.

## Implementation

`scripts/performance/DoomBspKernelBench.java` loads the real E1M1 relations over
JDBC into exact-width primitive arrays:

- 681 BSP nodes and both child bounding boxes;
- 682 subsectors and their contiguous seg ranges;
- 2,057 seg endpoint pairs;
- the 320 canonical camera coordinates; and
- all 64 canonical direction/plane profiles.

The measured hot path performs allocation-free iterative front-to-back BSP
traversal, conservative child-box field-of-view rejection, exact near-plane seg
clipping, bounded column projection, exact determinant/t/u acceptance, and a
two-pass nearest-solid-depth clip. The two-pass design avoids assuming that seg
storage order inside a subsector is strict ray-depth order. It does not yet
implement vertical portal clips, wall drawing, plane spans, masked fragments, or
the production codec.

The runner compiles with the pinned database image's Java 11 HotSpot VM and uses
the image's `ojdbc11.jar`. The password is read only from the Compose secret
inside the container; it is never placed in a command argument, artifact, or
repository file.

## Independent correctness audit

For 12 directions at the real player-one spawn, a separate SQL query evaluates
the production determinant, `t`, and `u` acceptance equations across the real
seg/ray relations. The Java candidate bitmap must contain every SQL-accepted
pair. The selected run found:

| Metric | Result |
| --- | ---: |
| SQL-accepted seg-column pairs | 57,012 |
| Missing from Java candidates | 0 |
| Candidate retention vs. 12 brute 2,057x320 grids | 0.7218% |
| SQL-visible hits through the first solid wall | 21,050 |
| Missing after Java solid-depth coverage | 0 |
| Visible retention vs. brute grids | 0.2706% |
| Maximum nodes visited | 614 / 681 |
| Maximum subsectors visited | 588 / 682 |

Both zero-miss results pass the correctness gate. Projection retains 0.7218% of
brute pairs, and exact solid-depth coverage reduces that to 0.2706%; both pass
the no-more-than-25% gate by a wide margin. Node/subsector visitation remains
high, so vertical portal clips are still required before drawing.

## HotSpot timing

After 5,000 warmups, 20,000 unique angle/nearby-position samples measured with a
64 MiB heap and Serial GC:

| Metric | Result |
| --- | ---: |
| Immutable relational load | 2,357.122 ms |
| Traversal + projection + solid coverage p50 | 0.096178 ms |
| Traversal + projection + solid coverage p95 | 0.447939 ms |
| Traversal + projection + solid coverage p99 | 0.514542 ms |

This passes the <=3 ms component gate on HotSpot. The 2.36-second cold load is
not in the frame path, but it is not an acceptable pooled-session prewarm path;
the planned revision-keyed relational BLOB packs remain necessary.

## OJVM JIT gate failure

The same day, `DBMS_JAVA.COMPILE_METHOD` was tested with a disposable one-line
`public static int f(int)` method and the JVM descriptor `(I)I`. The call failed
to return within the mandatory 60-second limit. It was interrupted and removed
with zero probe objects and zero invalid objects.

A controlled database restart reduced container memory from 94% to 82% of the
2 GiB limit. The identical one-line compilation still exceeded 60 seconds.
`java_jit_enabled` is `TRUE`, `/dev/shm` is a 256 MiB executable tmpfs with about
204 MiB free, and the database remains healthy. This rules out trace residue and
simple PGA pressure; it does not establish the deeper Oracle compiler cause.

Consequences:

- interpreted OJVM timing cannot select the production renderer;
- the local pinned Oracle Free image currently fails the native-method gate;
- the algorithm work may continue in the checked-in Java 11 HotSpot harness;
- production selection requires the one-line probe and every renderer hot
  method to compile within 60 seconds and report `IS_COMPILED=YES` on the target
  Oracle environment; and
- SQL remains the production renderer and exact independent oracle meanwhile.

## Next implementation

1. Add per-column upper/lower portal clip arrays while retaining the zero-miss
   audit.
2. Draw exact opaque wall columns into one reusable 320x200 palette buffer and
   compare world bytes against the SQL oracle.
3. Replace row-by-row cold loading with revision-keyed primitive BLOB packs and
   enforce the 12 MiB/session and 5 ms warm-snapshot gates.
4. Re-run the minimal JIT probe on a second supported Oracle environment before
   investing in an OJVM wrapper or production integration.

Run the current reproducible gate with:

```sh
scripts/performance/run-t12.0-bsp-kernel.sh
```
