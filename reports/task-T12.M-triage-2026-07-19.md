# T12.M live-outage triage and hardening — 2026-07-19

## Reported symptom

"Shooting the gun just stopped working" during live `/play/` sessions, with
mouse control otherwise working, plus follow-up: Ctrl cannot fire on macOS
without triggering the host Dictation prompt.

## Deterministic findings

1. **Fire itself was never broken.** A pure-AutoREST harness
   (`new_game` → `submit_step`/`poll_frame`, fire held after the vanilla
   16-tic weapon raise) produced the `DSPISTOL` audio tuple at tic 25, a
   muzzle-flash frame delta, and a 471-pixel HUD ammo change. The engine-level
   `audio-event-gate` also passed. An early false negative (fire during tics
   9–12) was traced to vanilla weapon-raise timing, not a defect.
2. **The real outage was worker admission.** Public `NEW_GAME` intermittently
   returned HTTP 555 `ORA-20702: worker claim timeout`. Root cause chain:
   - The container VM's virtual clock stalled repeatedly
     (`--ATTENTION-- Time stalled` / `backward drift` in the alert log,
     5,800 lines), after which Oracle's Scheduler job coordinator (`cjq0`)
     stopped honoring asynchronous `RUN_JOB` posts. A trivial probe job took
     59 s to dispatch; worker starts took ~2 minutes or never ran, while
     `claim` polled its whole 120 s window. A full instance restart did NOT
     clear the wedge; bouncing `job_queue_processes` (0 → 8) restored 0.1 s
     dispatch.
   - Delayed duplicate dispatches raced `run_slot`; the loser's unfenced
     cleanup cleared the winner's `doom_worker_control` row (the observed
     `worker ready fence` / `worker state-map fence` `WORKER_FATAL`s at
     12:01:27, 13:17:45, 13:42:10, 13:59:31 — each simultaneous with another
     slot's event).
   - The audit trail shows the user's morning session: eight sessions cycling
     one slot between 12:01 and 12:13 (repeated refreshes against ~60–85 s
     worker starts) — the lived "game stopped working".
3. **Pool exhaustion.** With the deliberate 600 s idle retention and 4 slots,
   four abandoned-but-unexpired sessions refused a fifth player
   (`unified worker pool is full`) for up to 10 minutes.
4. **Latent test assumptions.** Three direct-bridge gates (durable-bridge,
   durable-audio-ledger, presentation-controls) predate the `GAME_ENGINE=MOCHA`
   cutover: their `NEW_GAME` now claims a real worker whose control row
   collides with the manual slot-3 harness on the unique `TARGET_SESSION`
   constraint. `verify-t8.3-pipeline-restart.mjs` predates the WAD-native menu
   flow and waited for a pipeline that can no longer start without menu input.

## Fixes (all deployed and verified live)

- `sql/sim/080_unified_worker.sql`
  - `run_slot`: quiet exit on stale starts (cleared target), supersede-exit
    instead of a fatal when the ready fence loses, and generation-fenced
    stop/failure cleanup so no execution can clobber a claim it does not own.
  - `claim`: re-dispatches `RUN_JOB` every 3 s while the target slot has no
    running Scheduler job, and rebuilds a released claim.
  - `start_worker`: dead-claim takeover (target set, never ready, no running
    job, heartbeat > 60 s stale) plus bounded deterministic eviction of the
    least-recently-active ready worker when the pool is full (T12.M4
    bounded-memory requirement).
- `deploy/local/initdb/30-doom-job-queue.sql`: pins `job_queue_processes=8`
  (Oracle Free derives 4 = exactly the pool size, leaving no slave headroom).
- Gate/test repairs: engine pinning (`GAME_ENGINE='SQL'` + restore) in the
  three direct-bridge gates; menu-flow driving in
  `verify-t8.3-pipeline-restart.mjs`.
- T12.M5 presentation follow-up (plan items):
  - Mocha adapter populates DMF3 byte 9 (`complete`) from `gamestate`
    (recorded chains unchanged: the byte was previously always 0 and stays 0
    during play; tic-zero SHA `a1c9b037…` reverified post-deploy).
  - Client codec enforces one canonical `frame_sha` orientation per producer:
    raw DMF3/DMF4 (Mocha) must hash row-major; gzip envelopes (legacy JSON and
    SQL retained DMF3) must hash the column-major transport. Cross-orientation
    payloads are rejected; `verify-codec-v3.mjs` asserts both directions.
  - `PresentationState` accepts `DEAD`; `Frame` exposes `complete`.
- macOS Ctrl-fire (user follow-up): Ctrl bound to fire on all platforms;
  double-click opts into fullscreen Keyboard Lock (locking both Control keys)
  so macOS Dictation cannot interrupt; single click keeps windowed mouse
  capture. README and status lines updated.

## Verification

- `run-regression-core.sh`: all 10 gates PASS, including exact historical
  hashes (tic-zero `a1c9b037…`, durable-bridge `ticcmd=3228fec000000017`,
  frame `c4261867…`).
- `verify-t8.3-live-client.mjs` PASS (weapon animation, mouse capture/fire,
  input-to-paint 159–165 ms), `verify-play-menu`, `verify-play-initial-frame`,
  `verify-play-visible-unfocused`, `verify-t8.3-pipeline-restart` PASS.
- Codec unit fixtures (`verify-codec-v2/v3`) and source scans
  (`verify-t8.1/8.2/8.3-source`) PASS; `tsc` clean; zero invalid database
  objects.
- Live probes: AutoREST fire harness produces `DSPISTOL` + ammo delta with the
  same frame chain before and after the adapter redeploy; five sequential
  `NEW_GAME`s over a full pool all return 200 (fifth evicts in ~13 s).

## Operational notes

- If worker claims slow down again after host sleep, check the alert log for
  `Time stalled` and bounce the coordinator:
  `ALTER SYSTEM SET job_queue_processes=0; ALTER SYSTEM SET job_queue_processes=8;`
- `NEW_GAME` currently costs ~12–14 s cold (Mocha engine construction in a
  fresh worker session). Unchanged by this work.
