# P13 local clock-tail triage — 2026-07-21

## Conclusion

The recurring 0.3–2.5 second multiplayer/input tails on this host are not a
mode-specific renderer defect. Colima 0.10.1 uses Lima 2.1.1 on macOS
Virtualization.framework; Lima's host agent checks guest time every ten seconds
and abruptly corrects drift above 100 ms. The guest is commonly 128–181 ms
ahead. Oracle VKTM detects each backward step and records `Time stalled` until
its published low-resolution time catches up.

Local correlation is definitive:

- 865 Oracle stalls in the sampled 18-hour instance;
- 98.7% were within 1.5 seconds of a Lima clock adjustment;
- 97.6% of consecutive alert intervals were multiples of ten seconds;
- Oracle alert-pair elapsed time was 1.030 s p50, 1.061 s p95, 1.358 s max;
- the guest kernel independently recorded 52 backward time jumps.

Lima documents the VZ RTC problem and implements the correction with a
ten-second host timer plus Linux `settimeofday()`:
[design discussion](https://github.com/lima-vm/lima/pull/4527),
[host timer](https://raw.githubusercontent.com/lima-vm/lima/v2.1.1/pkg/hostagent/timesync.go),
[guest clock setter](https://raw.githubusercontent.com/lima-vm/lima/v2.1.1/pkg/guestagent/timesync/timesync_linux.go).
Oracle documents VKTM as its wall-clock and interval-time publisher:
[Oracle background processes](https://docs.oracle.com/en/database/oracle/oracle-database/26/refrn/background-processes.html).

## Bounded experiments

1. Restarting the entire VZ Colima VM preserved the database volume but did not
   help: ~145–150 ms corrections resumed every ten seconds.
2. A separate native-x86_64 QEMU profile was created without touching the VZ
   profile. Generic TSC, `host` CPU, isolated execution, and a live HPET trial
   all retained ~114–158 ms corrections every ten seconds. No database was
   migrated into the rejected profile.
3. The retained match scheduler now derives its absolute cadence from
   `DBMS_UTILITY.GET_TIME`, not `SYSTIMESTAMP`. This removes wall-clock arithmetic
   from the game loop, although an Oracle sleep/wakeup may still be delayed by
   the hypervisor event.
4. The database container now uses cpuset `0,1` instead of a two-CPU CFS quota
   and grants only `SYS_NICE`. The recreated container has `NanoCpus=0`, the
   expected cpuset/capability, and no VKTM/LGWR ORA-00800 priority error.
5. After those changes, the live single-player browser gate passed with 36.7 ms
   input-to-submit and 207.9 ms input-to-correlated-paint, including movement,
   firing animation, mouse capture, Tab menu, and Escape behavior.

## Evidence policy

Correctness hashes, replay parity, and median architectural comparisons remain
valid. Browser `performance.now()` truthfully measures the degraded local user
experience, but a short 300-frame run may miss the ten-second event and p95 can
hide it. Final P13/T12 tail acceptance must run on stable-clock native Linux or
OCI, reject any Oracle/Lima clock event in the measurement window, and report
p99.9 and maximum inter-frame/input gaps in addition to p50/p95.

Do not suppress Oracle's alert, grant `SYS_TIME`, run the database privileged,
or weaken the frame/input gates. Docker documents `SYS_NICE` and CFS quota
semantics here: [resource constraints](https://docs.docker.com/engine/containers/resource_constraints/).
