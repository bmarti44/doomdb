# MLE tic cost versus awake population — 2026-07-24

Verdict: awake monster population is a material cost predictor, but it is not
a complete linear scaling law. Across the 52 complete 100-tic windows,
Pearson correlation is 0.620 for awake living monsters and 0.653 for all
living kill-count monsters. Action/state mix therefore remains a material
residual variable.

The measured Free-edition requirement is:

- quiet late-game plateau: 105.990–108.719 ms/tic, requiring
  3.710–3.805x to reach the 28.571 ms Doom tic slot;
- peak combat: 290.124 ms/tic at 20 awake / 28 living monsters, requiring
  10.154x;
- practical density-dependent bracket: approximately 4x quiet to 10x peak.

## Method

The authoritative MLE timing source is the parked-slot, quiet-host replay of
the preserved 5,250-tic deathmatch stream. A diagnostic-only build of the
same Java/TeaVM source replayed the exact stream in Node and sampled the
thinker inventory after every 100 tics. `awakeMonsters` means a living
`MF_COUNTKILL` mobj with a non-null target; dead monsters are excluded.
Diagnostic construction occurs after each timing window and is excluded from
the next window. Node time is not used as MLE performance evidence.

The joined, auditable data is in
`awake-scaling-windows-2026-07-24.txt`. Its columns are window-ending tic,
MLE average milliseconds per tic, thinker count, living monster count, awake
monster count, moving living monster count, and required speedup versus
35 Hz.

## Interpretation

The early rise from 9 to 20 awake monsters coincides with cost rising from
192.077 to 290.124 ms/tic. Monster deaths then reduce both population and
cost. However, the long interval with 15 awake monsters ranges from roughly
106 to 215 ms/tic. Count alone therefore cannot predict the combat tail:
sight checks, attacks, collision work, and state transitions vary while the
population is unchanged.

This evidence rejects both extremes: total thinker count is too weak, while
awake count is useful but not sufficient. Optimization A/Bs must continue to
use the exact command stream and report both quiet and peak-combat windows.

## Provenance

- Fixture SHA-256:
  `3f625da2ab4166426c008a430a994d504e4ce65be1a9bede24b30abcb227d6b4`
- MLE timing log SHA-256:
  `b4837f7916dd67d97450281eaf664d4e3bd181c2b3b728b1329bba6e3e8fe3c5`
- Node population log SHA-256:
  `48a301a21ec7e87794611b992ab5106a1abe7128008562b3ec874a4038cd638b`
- Diagnostic TeaVM artifact SHA-256:
  `4b13332c9726ecf06c8cd897beff6d552e95b79dda5e9a74316a0ca84278f9e6`

