# MLE checkpoint-restore profile — 2026-07-24

Classification: `DIAGNOSTIC_NOT_GATE`

The pinned 103e authority was profiled in Node with the same emitted
JavaScript used by MLE. Absolute Node timings are not acceptance evidence;
the profile ranks generated-code costs that are then verified by direct MLE
wall-clock A/B.

The successful restore-only run measured 73.629 ms. Inclusive profile time
attributed about 51.1 ms to the `InitNew` path reached from
`restoreCheckpointCore`, roughly 69% of the restore. The retained recovery
context is already initialized at the exact durable tic-zero origin, so this
work constructs E1M1 and immediately overwrites it with the checkpoint.

The first two logs are preserved harness-void attempts: the first exposed an
optional-output-buffer guard defect and the second an output-path error.
Neither produced a terminal marker and neither is cited as evidence. Runs v3
and v4 completed with terminal PASS markers; v4 is the restore-only profile.

Candidate: add a distinct, fail-closed warm restore export. It omits
`InitNew` only when the retained engine matches the checkpoint's tic, skill,
episode, map, player membership, netgame/deathmatch, and console/display
player. The general restore path remains unchanged.
