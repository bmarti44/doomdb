# Sol/max investigation: OJVM JIT blocker

Date: 2026-07-15 (trace timestamps are UTC)
Scope: read-only inspection of the running `gvenzl/oracle-free:23.26.2-full`
container, Oracle trace/alert files, cgroup state, and primary technical sources.
No production code or database objects were changed.

## Verdict

OJVM JIT is supported and working. The 60-second probe did **not** reveal a bad
method descriptor, an unusable `/dev/shm`, or an unsupported Free-edition
feature. The post-restart foreground trace reports:

```text
Total of 1 methods compiled in 59470 ms.
```

That is the exact one-method `DoomJitSigProbe.f(int)` request. The client timeout
landed at almost precisely the end of a successful 59.47-second cold compile.
`(I)I` is therefore the correct JVM descriptor for `int f(int)`.

The main blocker is a cold, single-worker, self-hosting JIT bootstrap competing
inside an already saturated two-core/two-GB Oracle Free container. The MZ00
trace shows that the JIT starts normally, then compiles hundreds of JDK,
`jdk.compiler`, and Oracle Zephyr compiler methods—including its own compiler
implementation—before and around the requested work. Oracle documents that
OJVM has one MMON JIT worker and that it can consume CPU and memory comparable
to an active Java session.

The resource constraint is severe, not theoretical:

- cgroup memory is 2,134,474,752 bytes of 2,147,483,648 (99.4%);
- `memory.events:max` reached 2,422, proving repeated cgroup-limit reclaim;
- no OOM or OOM kill occurred;
- CDB PGA allocated is 675.2 MB against a 256 MB aggregate target, with a
  703.2 MB observed maximum;
- MZ00 alone currently holds about 148.5 MB PGA;
- SGA is 1,024 MB;
- 582 of 6,104 CPU quota periods were throttled, totaling 17.68 seconds; and
- the alert log repeatedly reports one- or two-second VKTM time stalls.

The first compile is a deployment/warmup cost, not a frame-time measurement.
It must not be included in the 33.3 ms steady-state render gate. It does,
however, show that the present container cannot safely compile a monolithic
renderer synchronously under a 60-second operational timeout.

## Findings by hypothesis

| Hypothesis | Result | Evidence |
| --- | --- | --- |
| Cold single-worker JIT bootstrap/queue | **Primary cause** | MZ00 starts/runs and compiles a large JDK/Javac/Zephyr cascade; Oracle documents one MMON worker. |
| Two-core/two-GB resource contention | **Major amplifier** | 99.4% cgroup memory, 2,422 limit hits, PGA 675 MB, MZ00 148.5 MB, CPU throttling. |
| Wrong `(I)I` descriptor | **Disproved** | Foreground trace says exactly one method compiled in 59.47 s; JVM specification maps `int` to `I`. |
| Invalid `/dev/shm` | **Disproved** | Actual mount is tmpfs `rw,nodev,relatime`, without `noexec` or `nosuid`; 256 MiB total and about 203 MiB free when checked. No ORA-29516. |
| JIT unsupported in 26ai Free | **Disproved** | `Java=TRUE`, valid `DBMS_JAVA`, `java_jit_enabled=TRUE`, and native methods actually compile. Oracle's 26ai JIT guide has no Free-edition exclusion. |
| Bad host clock source | **Not observed** | Current and available clock source include `tsc`; current is `tsc`, Oracle's recommended VM setting. |
| CPU descheduling/VM timekeeping | **Secondary risk** | Regular VKTM stalls coincide with quota/resource pressure. They undermine 33 ms measurements, but compilation continues, so they are not the primary JIT failure. |
| Product/image/RU defect | **Unproven, not excluded** | `DBA_REGISTRY_SQLPATCH` has no rows and alert says no patches applied. No public primary source identifies this exact symptom. A controlled image/RU A/B is required. |

Docker's `HostConfig.ShmSize=64M` is not authoritative here: the explicit
Compose tmpfs overrides it. `findmnt` and `df` inside the running container show
the effective 256 MiB executable mount. Enlarging it now is unlikely to help and
can make memory pressure worse because tmpfs pages are cgroup-accounted.

The regular VKTM messages deserve an independent host-health check, but changing
the clock inside the container or granting `SYS_TIME` is not justified. The
container already sees `tsc`. First test an idle host and remove redundant
Docker CPU throttling in a disposable run; if stalls persist, inspect the Linux
VM/host's TSC stability and time synchronization.

## Kill-ranked experiment matrix

Run these in order. Every image/configuration experiment must use a disposable
database volume; never attach the production volume to an unproven image.

| Rank | Safe experiment | Pass condition | Kill/decision condition |
| ---: | --- | --- | --- |
| 1 | Stop submitting compile requests and leave the DB otherwise idle until MZ00 finishes its current queue. Do not restart: restart reintroduces cold work. Preserve MZ00 and foreground traces. | Trace reaches a clean idle/exit state; memory and CPU pressure fall. | If MZ00 makes no trace progress for 10 minutes while its session is active, capture its wait stack/session and proceed to rank 4 rather than repeatedly retrying. |
| 2 | Load a tiny client-compiled Java 11 probe (`javac --release 11`, `loadjava -resolve`) in a disposable schema. Invoke it repeatedly, then compile one method with a one-time 5–10 minute deployment timeout. Repeat with a second trivial method after the compiler is warm. | `USER_JAVA_METHODS.IS_COMPILED='YES'`; warm second method is materially faster; calls remain correct. | If a trivial method still takes over 60 s after the queue is idle and memory has headroom, treat it as an image/RU problem and proceed to rank 4. |
| 3 | Measure a representative renderer kernel only after `IS_COMPILED=YES`, in one persistent DB session. Record cold first call separately from warm p50/p95/p99. | Representative kernel plus payload handoff is <=20 ms p95, leaving budget for simulation, ORDS, network, and browser work. | Kill the OJVM 30-FPS route if optimized, compiled steady-state kernel/handoff remains >25 ms p95 or full local frame service remains >33.3 ms p95 after bounded tuning. |
| 4 | A/B fresh disposable databases with identical data, tmpfs, and workload: pinned gvenzl image; matching official Oracle Database Free full image; latest available 26ai RU/image digest. | One image/RU eliminates pathological warm compile latency and preserves correctness. | If all reproduce, package traces and exact inventory for Oracle Support and the gvenzl image project; do not guess at one-off patches. |
| 5 | Resource A/B: stop ORDS and other workload during deployment compilation; test a reduced SGA in a disposable DB (start with 768 MB) while retaining a 256 MB PGA target; test without the redundant Docker two-CPU quota while respecting Free's internal two-core limit. | Lower cgroup limit hits, no VKTM stalls, and substantially shorter warmup with no runtime regression. | Revert any setting that causes paging, invalid objects, startup instability, or worse steady-state latency. Do not expect a container limit above 2 GB to bypass Free's documented 2 GB database limit. |
| 6 | Host timing A/B on an otherwise idle machine/VM; record VKTM messages, cgroup CPU pressure, and monotonic latency. | No VKTM stalls during the acceptance run. | If stalls persist with no quota contention and `tsc` selected, move the same disposable image to a different host/VM before interpreting sub-100-ms timings. |

## Exact diagnostic capture

For every experiment, capture the same before/during/after bundle:

1. Latest `FREE_mz00_*.trc`, foreground `FREE_ora_*.trc`, and alert-log excerpt.
2. MZ00 and caller rows from `V$PROCESS`/`V$SESSION`, including wait event,
   state, `PGA_USED_MEM`, and SQL/action identifiers.
3. `V$PGASTAT`, relevant `V$SGASTAT`, `V$PROCESS_MEMORY`, and parameter values
   for SGA/PGA, `cpu_count`, and `java_jit_enabled`.
4. `memory.current`, `memory.events`, `memory.pressure`, `cpu.stat`, and
   `cpu.pressure` from cgroup v2.
5. Effective `/dev/shm` mount options and free space—not Docker's default
   `ShmSize` metadata.
6. `USER_JAVA_METHODS.IS_COMPILED` before and after, compile return value, cold
   deployment time, and separately measured warm invocation latency.
7. Exact `opatch lsinventory`, `DBA_REGISTRY`, and
   `DBA_REGISTRY_SQLPATCH` output before comparing images or filing a report.

Acceptance must use `IS_COMPILED=YES` plus correct output, not synchronous
`COMPILE_METHOD` wall time alone. A warm compiled method can persist across
calls/sessions/instances, but session-private renderer caches and ORDS pooled
sessions still need their own explicit warmup/measurement plan.

## Configuration guidance

- Keep the effective `/dev/shm` mount as `rw,exec,suid,size=256m,mode=1777`.
  Increase it only if measured free space collapses or Oracle reports shared
  memory exhaustion.
- Do not run `COMPILE_CLASS` against a large renderer while the compiler is
  cold. Compile/load at deployment, permit a bounded warmup window, and compile
  only selected hot methods if explicit compilation remains necessary.
- Do not restart between retries. The trace proves restart triggered another
  compiler bootstrap avalanche.
- Compile source outside the database with Java 11 bytecode. This avoids making
  the database's Javac workload part of the deployment critical path.
- Keep production runtime structures compact and primitive-array based. Oracle
  Free has no memory margin for large object graphs or per-frame allocation.
- Do not disable JIT as a performance fix. It is useful only as an interpreted
  control measurement or emergency fallback; 30 FPS requires proving the
  compiled steady state.
- Do not apply an unverified patch or swap the production volume between
  images. First establish exact patch inventory and reproduce on disposable
  volumes.

## Sources

- Oracle, [Oracle JVM Just-in-Time Compiler](https://docs.oracle.com/en/database/oracle/oracle-database/26/jjdev/Oracle-JVM-JIT.html): automatic/persistent compilation, single MMON worker, `DBMS_JAVA` compile APIs, and Linux `/dev/shm` requirements.
- Oracle, [Oracle AI Database Free licensing restrictions](https://docs.oracle.com/en/database/oracle/oracle-database/26/xeinl/licensing-restrictions.html): two-core and two-GB limits.
- Oracle, [Setting Clock Source for VMs on Linux x86-64](https://docs.oracle.com/en/database/oracle/oracle-database/19/ladbi/setting-clock-source-vm.html): `tsc` recommendation and verification.
- Oracle, [Background processes](https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/background-processes.html): VKTM's wall-clock and high-resolution timing role.
- Oracle, [ALL_JAVA_METHODS](https://docs.oracle.com/en/database/oracle/oracle-database/26/refrn/ALL_JAVA_METHODS.html): compiled-method catalog semantics.
- Oracle, [Java Virtual Machine Specification, method descriptors](https://docs.oracle.com/javase/specs/jvms/se17/html/jvms-4.html#jvms-4.3.3): descriptor grammar and `I` for `int`.
- gvenzl, [Oracle Database Free container images](https://github.com/gvenzl/oci-oracle-free): authoritative source/build documentation for the wrapper image under test.

## Bottom line for the 30 FPS plan

Do not abandon OJVM because a cold explicit compile consumed one minute. The
evidence says it succeeded. First drain/warm the single compiler under controlled
resource conditions, then measure compiled steady-state rendering. Conversely,
do not claim the blocker solved until the MZ00 avalanche is gone and the real
kernel/payload p95 fits its <=20 ms internal budget. If it does not, the
two-core/two-GB Free target—not network latency or the method descriptor—is the
hard architectural constraint.
