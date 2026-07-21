# P13.5 30-minute multiplayer soak

Status: **PASS for local correctness/resource/session soak; stable-host extreme
tail certification remains pending**.

## Defect found and fixed

The first 1,800-second attempt failed at exactly 20 minutes. `doom_match` was
created with `expires_at = created_at + 20 minutes`, but authenticated activity
updated only `last_activity_at`. A healthy active match therefore became
unavailable at a fixed wall-clock deadline.

`DOOM_API` now treats `expires_at` as an idle lease. Capability-authenticated
status, input, or frame polling renews it from less than ten minutes remaining
back to twenty minutes. The retained Scheduler worker does not renew it, so an
abandoned match still expires. The conditional update avoids the match-row lock
convoy caused by an initial per-poll implementation.

The live T13.1 source/schema/lifecycle/rate/AutoREST suite passes. A 30-second
post-fix browser smoke then advanced both clients from tic 136 to 1,174 with
zero resyncs and bounded storage.

## Accepted run

Command:

```sh
DOOMDB_MULTIPLAYER_SOAK_SECONDS=1800 \
  bash tests/verify-p13.5-multiplayer-soak.sh
```

Result:

```text
PASS P13.5-MULTIPLAYER-SOAK seconds=1800 tics=136/136-59904/59904 maxLag=8 maxReconnectSeconds=0 resyncs=0/0 frames=258 checkpoints=2 bytes=867245 disconnectedNeutral=0 initialNeutral=292 paint999Max=195.6/1517.3,200.4/1556.2 memory=123582784/124565824 java=3328000/3395584 gc=33/47
```

Both clients presented at least 25 FPS on average for the complete measured
window, with strictly increasing authoritative tics and a consecutive final
run. The durable command frontier, two-player frame ring, checkpoints, worker
session count, DOOM session count, PGA/UGA, Java session heap, response bytes,
and neutral-command provenance all stayed within their enforced bounds.

## Timing qualification

Paint p99.9/max was 195.6/1,517.3 ms and 200.4/1,556.2 ms. These tails are real
for this browser on this host, but the same interval ran inside the already
diagnosed Colima/Lima guest-clock environment. Correctness, lease, storage,
memory, and replay evidence is valid; final extreme-tail acceptance must repeat
on stable-clock native Linux or OCI as required by PLAN.md.
