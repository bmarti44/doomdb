# OCI Always Free 26ai MLE venue verdict — 2026-07-25

The prepared arithmetic tier probe ran on OCI Autonomous Database
`doomdb-adb` in `us-ashburn-1` (Always Free, OLTP, 1 ECPU, Oracle AI Database
26ai). The initial audited run measured 171–173 ns per warmed arithmetic
iteration and 91 ns per gathered byte, with stable consecutive calls and no
compilation step-down. A repository-controlled repeat measured 189.328 and
188.638 ns per iteration with the same checksum.

Both runs are above the standing 100 ns closure threshold. Therefore:

- Autonomous MLE on this venue is interpreter-tier;
- the ADB-JIT branch is closed;
- exact live 30 FPS database rendering is permanently closed for this venue;
- exact database rendering remains asynchronous audit/DVR work only;
- the live architecture remains MLE-authoritative simulation with a
  confirmed-only browser renderer.

The venue is approximately 1.7–2.5 times faster than the local constrained
Free container on comparable primitives. That is capacity/envelope evidence,
not a 35 Hz peak-combat claim. Full cloud performance, WAN, lifecycle, and
browser acceptance still run against the identical pinned artifact before
deployment is called qualified.

Probe hygiene: every SQL*Plus/SQLcl harness that embeds MLE JavaScript uses
`set define off`; otherwise JavaScript such as `value & 255` is corrupted by
SQL substitution. Probe objects were removed after measurement.
