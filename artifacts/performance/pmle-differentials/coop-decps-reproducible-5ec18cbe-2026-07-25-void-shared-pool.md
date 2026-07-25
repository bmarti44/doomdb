# 5ec co-op differential void — shared-pool exhaustion

Classification: `VOID_INFRASTRUCTURE_MEMORY_LIFECYCLE`, not a determinism
verdict.

The 762-tic, every-tic co-op differential began against:

- authority
  `5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3`
  (1,081,335 bytes);
- canonical table pack
  `058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44`;
- Oracle AI Database 26ai Free `23.26.2.0.0`;
- the edition-enforced 50% PDB utilization / two-running-session envelope.

It terminated with `ORA-04031: out of shared memory in shared pool` while
calling `DOOM_TEAVM_SIM_CANONICAL_LENGTH`; no canonical mismatch marker was
emitted. The alert-window independently found the new ORA-04031 incidents and
rejected the enclosing promotion battery.

Oracle diagnostics showed:

- shared pool at its 464 MiB maximum, 81.65 MiB nominally free after failure;
- 13 reserved-pool request failures despite nominal free bytes, consistent
  with fragmentation;
- large `KGLH0` and `JOXLE` allocations after many diagnostic module
  load/unload cycles and repeated OJVM-oracle initialization;
- the failing 4 KiB request was `kglau` in a `KGLH0` heap;
- incident/trace evidence:
  `incdir_5593/FREE_ora_497366_i5593.trc`,
  `FREE_ora_497672.trc`, and `FREE_ora_498469.trc`.

This database instance had accumulated several days of artifact swaps and
diagnostic sessions. The production design does not repeatedly replace its
authority module. The corrective gate is therefore a clean database restart
followed by the same unchanged 762-tic/every-tic route. A restart is not a
PASS: the rerun must produce the normal co-op differential terminal and a
clean alert window. The failed raw log remains
`coop-decps-reproducible-5ec18cbe-2026-07-25-void-shared-pool.log`.

`PMLE_DECPS_COOP_VOID|authority_sha256=5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3|classification=VOID_INFRASTRUCTURE_MEMORY_LIFECYCLE|oracle_error=ORA-04031|determinism_verdict=NONE|threshold_changed=NO`
