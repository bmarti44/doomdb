# Hidden-MLE-JIT probe orphan incident — 2026-07-24

Status: **incident recorded; cleanup deferred until the active exhaustive
ledger terminates**.

Fable's diagnostic hidden-parameter probe left one parked Oracle session:

- SID: `42`
- serial#: `60842`
- label: `MLE park`

The host-side container observation subsequently found a second SQL*Plus
process and Oracle server process consistent with that report. At observation
time it had accumulated only about eight CPU seconds over approximately
43 minutes, while the exhaustive ledger server process remained at 99.7% CPU.
The process was not attributed to the paused wasm2js worker, which confirmed
zero Oracle, SQL*Plus, Docker build, compile, verifier, or timing calls after
pause.

The exhaustive ledger is explicitly preserved to its terminal marker, so no
new Oracle session is opened to clean up or interrogate the orphan during that
gate. The ledger evidence sidecar must disclose the concurrent parked session;
it must not claim database-session exclusivity.

Before any hidden-parameter matrix cell runs:

1. verify and clean SID 42 / serial# 60842;
2. verify no prior diagnostic MLE session remains;
3. run exactly one controlled cell;
4. clean and verify the session after that cell;
5. classify all hidden-parameter results `DIAGNOSTIC_NOT_GATE`;
6. never carry unsupported parameters into production configuration.
