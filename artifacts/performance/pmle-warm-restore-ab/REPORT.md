# Fail-closed warm checkpoint restore A/B — 2026-07-24

Candidate authority:

- bytes: `1,171,896`
- SHA-256: `e485b9418e5845b78e9e1593918d8bbb6f3c441c41a43cb8f3faf046e595148b`
- parent authority: `103e15e913b3a8f9a84497af601666fde5f47a720ac4b22fd7843db2559b665e`
- canonical table pack:
  `058cd0df9444131b356762a096fd422d5131ac3aea91163aee056e8ad4965b44`

## Results

Node rank test, canonical-verified:

- general restore: 63.561 ms
- warm restore: 10.099 ms
- speedup: 6.29x

Direct MLE wall-clock A/B on Oracle Database 26ai Free, with the retained
pool parked and resource metadata captured:

- general samples: 13,657.951 / 13,446.767 / 13,711.076 ms
- general mean: 13,605.265 ms
- warm samples: 788.509 / 726.131 / 706.335 ms
- warm mean: 740.325 ms
- speedup: 18.377x
- every sample restored the same canonical SHA-256:
  `c76a014d15377f629ed69533da50b7124f3fd3512d5d00e94ccaa4465dff4ddd`

The Node continuation test compared every canonical state for 64 tics after
tic-32 restore and passed. It also proved fail-closed rejection of a wrong
expected tic and a deathmatch/co-op origin mismatch.

## Cadence implication

The prior maximum-distance recovery decomposed to 18.809 s restore,
76.065 s replay for 255 tics (298.3 ms/tic), 0.173 s publish, plus 1.391 s
caller overhead. Substituting the measured 0.740 s warm restore gives a
fixed-128 worst-case projection of about 40.2 s for the recovery phase and
55.2 s including the separately budgeted 15 s detection backstop. That is
inside the 45 s phase / 60 s total contract, but cadence is not retuned from
projection alone. The candidate must first pass the differential/recovery
battery and a measured maximum-distance fixed-128 recovery.

The A/B itself changed no production pin: the candidate ran under isolated
`doom_restore_ab*` database objects, which were removed afterward. Following
the A/B, e485 passed the canonical 330-tic, every-tic 762-tic co-op, and
membership restore differentials and was promoted. Its measured fixed-128
maximum-distance recovery completed at distance 127 with 20 awake monsters:
42.337 seconds from kill through authoritative publication and 57.337 seconds
including the separately budgeted 15-second detection backstop. Both the
45-second recovery-phase and 60-second end-to-end gates passed.
