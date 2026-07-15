# T9.1 ordered MODEL fire evaluator

This evaluator freezes a full-size Oracle-authored fire animation: exactly 150
frames numbered 0 through 149, each exactly 160 by 96 intensity cells in
row-major order. Production exposes `DOOM_FIRE.GENERATE`, canonical rows in
`DOOM_FIRE_FRAME_RUN(FRAME_NO,RUN_NO,START_OFFSET,RUN_LENGTH,INTENSITY)`, and
compact ordered feasibility evidence in `DOOM_FIRE_BUILD_PROBE`. It may not
persist redundant cell rows, JSON frames, frame BLOBs, or evaluator answers.

The independent TypeScript recurrence is fully stated in `fixtures.json`. Its
coordinate-only integer noise has no Oracle RNG dependency. Frame zero contains
only the deterministic source row. Later non-source cells read the prior frame
one row below at a wrapped noise-selected lateral coordinate and subtract a
noise-selected decay. All 150 independent frame SHA-256 values and the complete
animation digest are frozen in `expectations.json`.

The production insert must be one documented static SQL operation containing
one `MODEL` clause, explicit `RULES SEQUENTIAL ORDER`, and explicit rule
dimension ordering `(frame ASC, y DESC, x ASC)`. The small 8×16×12 probe and the
full 150×160×96 feasibility/memory probe must pass in that order before the
full insert. Any full failure is terminal: no dimension, frame, sampling, or
quality reduction is permitted.

Candidate-only checks:

```sh
node evaluator/t9.1/self-check.mjs
node evaluator/t9.1/mutation-self-check.mjs
node evaluator/t9.1/source-audit.mjs
```

`run-visible.sh` additionally requires Oracle capability evidence and the real
production objects. The visual checkpoint deliberately starts `PENDING` with
no accepted artifact or image hashes. After live SQL acceptance, a real decoded
150-frame database animation must be reviewed; evaluator output is not a visual
golden and cannot auto-approve that checkpoint.
