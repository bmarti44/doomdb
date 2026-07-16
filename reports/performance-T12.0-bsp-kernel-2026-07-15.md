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
two-pass nearest-solid-depth clip, an exact ordered sector portal walk, and
per-column upper/lower portal clips. The two-pass design avoids assuming that
seg storage order inside a subsector is strict ray-depth order. Exact wall
regions are drawn front-to-back into one reusable indexed buffer, sampling the
real relational textures and colormap. Sector intervals also bound an exact
array-based floor/ceiling/sky raster into the same buffer. Transparent middle
walls and relational sprite-state/rotation primitives are depth-ranked into a
reusable presentation buffer. It does not yet implement sparse first-person
presentation or the production codec; horizontal plane-span
coalescing remains a later resolution-scaling optimization.

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
| Production SQL active portal hits | 12,487 |
| Java portal missing / extra | 0 / 0 |
| Final upper/lower clip mismatches | 0 |
| Production SQL opaque wall pixels at spawn east | 26,165 |
| Java wall missing / extra / palette mismatch | 0 / 0 / 0 |
| Production SQL complete world pixels | 64,000 |
| Java world missing / extra / palette mismatch | 0 / 0 / 0 |
| Globally selected SQL masked-wall pixels | 4,702 |
| Globally selected SQL sprite pixels | 2,404 |
| Java full masked missing / extra / palette mismatch | 0 / 0 / 0 |
| Maximum nodes visited | 614 / 681 |
| Maximum subsectors visited | 588 / 682 |

Both zero-miss results pass the correctness gate. Projection retains 0.7218% of
brute pairs, and exact solid-depth coverage reduces that to 0.2706%; both pass
the no-more-than-25% gate by a wide margin. Node/subsector visitation remains
high. The portal stream and final clip arrays now match the production SQL
`MATCH_RECOGNIZE` oracle exactly across the same 12 directions. At spawn east,
all 26,165 wall coordinates and palette values match the production SQL world
oracle. A narrowly bounded integer snap reconciles SQL exact-number wall
flooring with binary-double values such as `22.999999999999986`. Planes use the
stored 20,480 ray components, the database-computed projection constant, and
raw binary-double flooring for negative world coordinates. The fail-closed
oracle now guards all 64,000 world bytes.

The tic-zero dynamic snapshot resolves symbolic state identifiers to dense
primitive catalog indices at load time. The renderer then applies the exact
rotation, screen bounds, interval/solid visibility, flip, transparency, and
depth/source/asset-coordinate tie rules. All 7,106 globally selected masked
pixels match SQL exactly.

## HotSpot timing

After 5,000 warmups, 20,000 unique angle/nearby-position samples measured with a
64 MiB heap and Serial GC:

| Metric | Result |
| --- | ---: |
| Immutable relational load including walls/flats/sprites/rays | 5,713.943 ms |
| Complete exact world + masked p50 | 3.060035 ms |
| Complete exact world + masked p95 | 5.389510 ms |
| Complete exact world + masked p99 | 5.942101 ms |

The geometry/clip portion previously passed its <=3 ms component gate, and the
complete exact world remains inside the <=8 ms opaque-world gate on HotSpot.
Masked composition adds about 0.60 ms at p95, passing its <=3 ms gate. The
5.71-second row-by-row cold load is not in the frame path, but it is
not an acceptable pooled-session prewarm path; the planned revision-keyed
relational BLOB packs remain necessary.

## OJVM JIT cold-bootstrap result

The same day, `DBMS_JAVA.COMPILE_METHOD` was tested with a disposable one-line
`public static int f(int)` method and the JVM descriptor `(I)I`. The foreground
Oracle trace later established that the method successfully compiled in 59,470
ms. The client-side cutoff landed almost exactly at completion. The descriptor,
JIT support, and executable 256 MiB `/dev/shm` are therefore valid.

Sol/max inspection found cold single-worker self-hosting JIT bootstrap under
severe cgroup contention: memory reached 99.4% of 2 GiB, CDB PGA reached 675.2
MiB against a 256 MiB target, MZ00 held about 148.5 MiB, and CPU quota throttled
17.68 seconds. The compiler was building a large JDK/Javac/Oracle compiler
method cascade. Cold deployment compilation is separated from frame latency;
the next compile probe uses an external Java 11 class and a bounded 5-10 minute
deployment window, then requires `IS_COMPILED=YES` before timing calls.

Consequences:

- interpreted OJVM timing cannot select the production renderer;
- the local pinned Oracle Free image supports JIT but has a costly cold compile;
- the algorithm work may continue in the checked-in Java 11 HotSpot harness;
- production selection requires a bounded cold deployment warmup, then every
  renderer hot method to compile within 60 seconds and report `IS_COMPILED=YES`
  on the target Oracle environment; and
- SQL remains the production renderer and exact independent oracle meanwhile.

## Next implementation

1. Add exact first-person weapon/HUD/pause/menu presentation and compare the
   composed indexed frame.
2. Replace row-by-row cold loading with revision-keyed primitive BLOB packs and
   enforce the 12 MiB/session and 5 ms warm-snapshot gates.
3. Externally compile/load the representative methods, allow bounded cold JIT
   warmup, and require compiled steady-state timing before integration.
4. Coalesce plane work into horizontal spans before activating 640x400; the
   current direct indexed raster already passes 320x200 but scales per pixel.

Run the current reproducible gate with:

```sh
scripts/performance/run-t12.0-bsp-kernel.sh
```
