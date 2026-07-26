# OCI ADB authoritative ticker-pair predeclaration — 2026-07-25

Status: `PREDECLARED_BEFORE_TIMING`

Venue:

- OCI Autonomous AI Transaction Processing Always Free `doomdb-adb`
- Oracle AI Database 26ai
- workload `OLTP`, 1 ECPU
- service alias `doomdb_tp`

Pinned inputs:

- authority SHA-256
  `5ec18cbe4cff7192d384e81d1010e0133d357d44ff17fa65821e1489c4fd1ee3`
- canonical table pack SHA-256
  `058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44`
- Freedoom IWAD SHA-256
  `7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d`
- exact 5,250-tic expanded stream SHA-256
  `fa7637570c30d3a33cbf8456e98268890e9f5bd82f5ba39fd7f69b139ddc4085`

The diagnostic runs two complete passes in one retained ADB session. Each pass
starts by restoring the same tic-zero checkpoint and consumes the same exact
stream. `DBMS_UTILITY.GET_TIME` 100-tic windows are authoritative for
throughput; `SYSTIMESTAMP` is the second clock. A tic is suspect when the two
clocks disagree by more than 30 ms. Each pass may exclude at most 0.5% of its
5,250 tics (26 tics). Raw samples and both clocks are retained.

The release verdict does not use isolated window-to-window improvement:

1. **Route gate:** both complete passes must sustain at least 35.000
   authoritative tics/s.
2. **Peak-combat gate:** the seven previously identified awake-20 windows,
   ending at tics 200, 300, 400, 500, 600, 700, and 800, are fixed before this
   run. Every one of those windows in both passes must sustain at least 35.000
   authoritative tics/s.
3. Both passes must stay within the two-clock exclusion cap and preserve exact
   frontier ordering.
4. Passing the ticker gate only authorizes deployment qualification. The
   release bar additionally requires at least 30 unique moving client frames/s
   on the deployed OCI application.

Expected, not accepted as evidence: route throughput was projected at 31–46
tics/s and peak throughput at 12–24 tics/s. A peak miss selects the next
measured branch; it is not rewritten as a venue or harness failure.

`PMLE_OCI_ADB_TICKER_PREDECLARATION|PASS|passes=2|tics_per_pass=5250|route_tps_min=35.000|peak_window_ends=200,300,400,500,600,700,800|peak_tps_min=35.000|clock_disagreement_ms=30|maximum_clock_suspects_per_pass=26|client_unique_fps_min=30`
