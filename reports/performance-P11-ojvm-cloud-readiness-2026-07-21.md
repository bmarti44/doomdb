# P11 Autonomous OJVM readiness — 2026-07-21

## Decision

The production P11 database gate now carries the complete selected engine. The
former gate installed SQL call specifications but did not build or load Mocha
Doom classes or the Freedoom IWAD, and finalized runtime objects before those
dependencies existed. That shape is rejected.

The selected artifact is a deterministic Java 8 JAR built from pinned Mocha
Doom revision `c0af1322ee5fd168b5cf8aaaf504cab2d1aabe93` plus the tracked DoomDB
adapter and patches:

- classes: 830
- classfile major: 52
- JAR SHA-256: `a27903f2dcd81aecb0292f605453969ad3d4389382bebdb8386dff3cb13f23ab`
- IWAD bytes: 28,795,076
- IWAD SHA-256: `7323bcc168c5a45ff10749b339960e98314740a734c30d4b9f3337001f9e703d`

The cloud sequence is capability/transport probe, OJVM preflight, pre-Java
schema/seed deployment, client-side class and IWAD load, post-Java
runtime/REST deployment, native hot-class compilation, and evidence capture.
Autonomous `JAVAVM` must be enabled and the database restarted by an
administrator before the gate. Missing or incompatible OJVM fails before
production schema mutation.

## Local acceptance

The exact release-8 graph was loaded into the local Oracle runtime and its 78
selected gameplay/render classes were natively compiled. The complete eleven-
gate Mocha regression passed: control codec, initial frame, replay, save/load,
durable bridge/audio, crash reconstruction, concurrent sessions, gameplay
defects, presentation controls, and standby worker.

Two independent 300-frame browser replays then produced identical state, frame,
and payload chains at 32.39 and 35.51 displayed FPS. The fixed replay SHA-256 is
`1ad47bc8e2a5b7518d68b937a333492d66d7d539f827980086d4b4fdad327fe3`.
Recent retained-worker p50/p95 timings were 0.092/0.454 ms for actor simulation
and 0.731/2.755 ms for render. A separate run containing one 716.7 ms Lima VM
pause measured 29.67 aggregate FPS while ordinary paint-gap p50/p95 remained
31.19/32.10 ms; this matches the already documented local host-clock defect and
does not reject the release-8 engine.

## Remaining external gate

No live Autonomous or S3 mutation was attempted. P11 remains `NOT RUN` until a
real administrator-enabled Autonomous target, wallet, managed ORDS origin,
pinned SQLcl, and S3 deployment authority are provided outside the repository.
