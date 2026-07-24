# Checkpoint cadence decision — 2026-07-24

Status: **maximum-distance evidence measured; cadence change deferred for
restore-path optimization**.

The former production cadence was tic 32 followed by every 1,024 tics. At the
measured Free-edition replay rate, 1,024 tics cannot satisfy the 60-second
recovery contract even when checkpoint restore itself is fast.

The governing bound is:

```
maximum replay interval
  <= (60 seconds - detection time - checkpoint restore time)
     / measured replay time per tic
```

This bound is density-stratified, not flat. The 128–256-tic bracket came from
the approximately 150 ms/tic average replay cost. At the measured sustained
peak of approximately 290 ms/tic, replaying a maximum-distance checkpoint can
take roughly 74 seconds before detection and restore are included. The
worst-case total can therefore reach approximately 80–90 seconds. The current
constants are an implementation candidate, not yet proof of the 60-second
contract at peak density.

The production source now uses:

- minimum checkpoint opportunity: 128 tics;
- hard maximum checkpoint interval: 256 tics;
- opportunity probe cadence: 16 tics;
- preferred low-awake window: `awakeMonsters <= 16`;
- unchanged DMC1 payload format and serializer;
- no production tic-32 checkpoint;
- a tic-64 checkpoint only when the separate, default-off
  `checkpoint_test_hook=1`, explicitly fenced as test scaffolding;
- `route_diagnostics=1` records cadence decisions but never changes
  checkpoint placement.

Because probes occur on absolute 16-tic boundaries, the forced threshold is
`256 - 16 + 1 = 241`. This guarantees that an off-boundary prior checkpoint
is followed by another checkpoint within at most 256 tics. The source-derived
arithmetic test covers all 256 possible prior-checkpoint offsets:

```
PASS PMLE-CHECKPOINT-CADENCE offsets=256
  minimum=128 maximum=256 probe=16 low_awake=16
```

For a quiet opportunity, the next checkpoint occurs 128–143 tics after the
previous checkpoint. If no low-awake opportunity appears, forced placement
occurs after 241–256 tics.

Recovery never requires a checkpoint older than the hard maximum interval.
This is why pruning the tic-zero origin after tic 256 is sound.

This decision deliberately does **not** introduce copy-on-write, incremental
serialization, a new checkpoint format, or checkpoint-based ledger resume.
Those options would invalidate current byte-identity tooling or add snapshot
isolation risk while simulation throughput remains the primary open problem.

Acceptance remains pending on the promoted authority artifact:

1. database compilation and source verifier;
2. cadence observation in a paced live match;
3. slow-checkpoint suppression;
4. killed-session recovery, including a kill at the maximum checkpoint
   distance during a sustained high-awake window;
5. stratified match-bound standby, unbound warm-slot, and cold recovery;
6. concurrent double recovery, proving exactly one tier-2 claim wins under
   the generation fence;
7. New Game admission latency;
8. full lifecycle differential/recovery battery.

The cadence constants are retuned only from the maximum-distance high-awake
measurement, not from the average-cost estimate above.

That measurement is now complete. At distance 255 and 20 awake monsters,
restore cost 18.809 seconds, replay cost 76.065 seconds (298.3 ms/tic),
publish cost 173 ms, and caller/orchestration overhead cost 1.391 seconds.
Fixed 128 projects to approximately 58.3 seconds against the 45-second
measured-phase budget and is rejected as insufficient. Fixed 64 projects to
approximately 39.2 seconds, but the separately measured 673 ms synchronous
SAVE every approximately 1.8 seconds would create recurring player-visible
stalls. It is not adopted merely to make the recovery arithmetic pass.

The current 128–256 candidate remains in place while the fixed
18.809-second restore path is profiled. Reducing restore below approximately
5.5 seconds would allow fixed 128 to satisfy the phase budget at the measured
peak replay rate. No awake-stratified policy or codec-format change is
authorized by this evidence.

The pending measurement uses private route diagnostics without altering
production cadence. `CHECKPOINT_TEST_HOOK` is a separate, default-off control
used only by the tic-64 liveness scaffold. At each real opportunity probe,
`doom_match_checkpoint_probe` records the prior checkpoint, distance, awake
monster count, and `LOW_AWAKE`, `DEFER_HIGH`, or `FORCED_MAX` decision. The
maximum-distance diagnostic feeds the preserved live deathmatch command
stream, requires three consecutive high-awake deferrals, kills the exact
authority incarnation on the final tic before the scheduled forced checkpoint,
and reports the measured restore/replay duration as `DIAGNOSTIC_NOT_GATE`.
It re-reads the durable frontier and newest checkpoint after killing the
authority, so a race into the forced checkpoint cannot masquerade as a
maximum-distance result. Only that measurement may set or retune the
production recovery threshold. After any required retune, the same scenario
runs with `DOOMDB_HIGH_AWAKE_RECOVERY_GATE=1`; that acceptance mode requires
the durable kill distance to be 240–255 tics.

The diagnostic clock is deliberately narrower than the production SLA clock.
Its `elapsed_ms` starts immediately before the authority kill and covers
kill, checkpoint restore, deterministic replay, and authoritative publish.
It excludes production failure detection: the normal probe interval is 5
seconds and the recovery backstop is 15 seconds. Consequently the measured
phase is budgeted against approximately 45 seconds, not 60 seconds. Gate mode
adds the 15-second detection budget explicitly and hard-fails unless both the
restore/replay/publish phase is at most 45 seconds and the estimated end-to-end
total is at most 60 seconds.
