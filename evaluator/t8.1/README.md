# T8.1 full E1M1 completion replay evaluator

This evaluator freezes the full-run boundary without manufacturing completion
goldens. Production is driven only through the Section 5.4 `NEW_GAME`, `STEP`,
`START_REPLAY`, and `STEP_REPLAY` contracts. The reviewed route is an ordered,
versioned, run-length encoded stream of ordinary tic commands; expansion must
produce consecutive `seq` values and batches of at most four commands. No route
row may contain coordinates, targets, damage, pickups, hashes, or game outcomes.

The route must start skill 3 from a normal new game, collect a needed key and
resources, fight representative hitscan/melee/projectile monsters, operate a
keyed door and a lift, discover a secret once, trigger the exit, and enter
intermission. Nine named milestones bind exact command sequence ranges to
authoritative state/frame hashes, counters, inventory, map status, and PNG review
artifacts. Completion is accepted only when the uninterrupted run, a fresh
rerun, split-versus-batched execution, and database replay all agree.

`fixtures.json` deliberately keeps `approvedScriptSha`, milestone hashes, and
screenshot hashes empty with review status `PENDING`. `route-candidate.json`
defines the exact candidate command stream and semantic checkpoints, but does
not claim that the unfinished upstream game completes it. After T7.1-T7.3 live
acceptance, the evaluator captures real observations, presents all milestone
PNGs and the route summary for review, and only evaluator-author work may record
the separately approved hashes.

Candidate checks:

```sh
node evaluator/t8.1/self-check.mjs
node evaluator/t8.1/mutation-self-check.mjs
node evaluator/t8.1/source-audit.mjs
```

The live path fails closed while upstream production, an approved route hash,
or reviewed milestone goldens are absent. No mutable production source is pinned.
