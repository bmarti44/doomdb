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
real relational textures and colormap. It does not yet implement plane spans,
masked fragments, or the production codec.

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
| Maximum nodes visited | 614 / 681 |
| Maximum subsectors visited | 588 / 682 |

Both zero-miss results pass the correctness gate. Projection retains 0.7218% of
brute pairs, and exact solid-depth coverage reduces that to 0.2706%; both pass
the no-more-than-25% gate by a wide margin. Node/subsector visitation remains
high. The portal stream and final clip arrays now match the production SQL
`MATCH_RECOGNIZE` oracle exactly across the same 12 directions. At spawn east,
all 26,165 wall coordinates and palette values match the production SQL world
oracle. A narrowly bounded integer snap reconciles SQL exact-number flooring
with binary-double values such as `22.999999999999986`; the fail-closed byte
oracle guards that compatibility rule.

## HotSpot timing

After 5,000 warmups, 20,000 unique angle/nearby-position samples measured with a
64 MiB heap and Serial GC:

| Metric | Result |
| --- | ---: |
| Immutable relational load including 1,256,192 wall texels | 4,368.997 ms |
| Traversal through exact wall draw p50 | 1.060739 ms |
| Traversal through exact wall draw p95 | 1.435519 ms |
| Traversal through exact wall draw p99 | 1.651697 ms |

The geometry/clip portion previously passed its <=3 ms component gate, and the
combined exact wall path remains well inside the <=8 ms opaque-world gate on
HotSpot. The 4.37-second row-by-row cold load is not in the frame path, but it is
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
- production selection requires the one-line probe and every renderer hot
  method to compile within 60 seconds and report `IS_COMPILED=YES` on the target
  Oracle environment; and
- SQL remains the production renderer and exact independent oracle meanwhile.

## Next implementation

1. Add exact floor/ceiling boundary arrays and horizontal plane spans into the
   same indexed buffer, then compare all 64,000 world bytes.
2. Replace row-by-row cold loading with revision-keyed primitive BLOB packs and
   enforce the 12 MiB/session and 5 ms warm-snapshot gates.
3. Externally compile/load the representative methods, allow bounded cold JIT
   warmup, and require compiled steady-state timing before integration.

Run the current reproducible gate with:

```sh
scripts/performance/run-t12.0-bsp-kernel.sh
```
