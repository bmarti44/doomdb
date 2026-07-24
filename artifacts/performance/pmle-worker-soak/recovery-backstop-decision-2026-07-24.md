# Recovery backstop decision — 2026-07-24

The recovery heartbeat backstop remains **15 seconds**.

The source comment and last-audited deployment specified 15 seconds, while an
uncommitted constant and verifier had drifted to 30 seconds. No recorded retune
decision supported 30 seconds. The original 15-second value was derived from a
measured 8.56-second legitimate checkpoint call. The accepted identity-index
checkpoint candidate subsequently reduced the direct MLE checkpoint time to
approximately 0.58–0.60 seconds.

Recovery discrimination remains ordered as follows:

1. An unexpired `busy_until` lease suppresses recovery.
2. Exact `SID + serial#` session identity plus `MLE_CHECKPOINT` action is the
   secondary discriminator.
3. A live exact-incarnation session receives the 15-second heartbeat
   backstop.
4. A missing exact-incarnation session recovers immediately.

Therefore 15 seconds retains substantial margin over measured legitimate work
without adding an unsupported 15 seconds to stale-worker detection. The
constant and source verifier are pinned to 15 seconds. Final acceptance still
requires the slow-checkpoint and killed-session adversarial recovery gates on
the promoted checkpoint artifact.
