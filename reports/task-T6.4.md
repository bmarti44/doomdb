# T6.4 implementation report

Status: **PASS — 28/28 IDs, 848/848 assertions**

`sql/sim/040_history_replay.sql` installs lineage-qualified command/event hash
chains, fixed four-tic and save-point snapshot envelopes, atomic save pointers,
deterministic load/rewind branches, and replay cursors independent of live state.
Canonical state closure includes player noclip, complete mobjs, sectors including
`light_timer`, lines, and active movers including `mover_kind`, `origin_height`,
and `source_linedef_id`. Persistence lineage/frontier fields are excluded from
logical state identity and bound separately by snapshot hashes.

`DOOM_TIC_TX` captures each authoritative logical tic after movement and world
machines, including multi-command batches, without taking a transaction boundary.
Legacy reviewed pre-history lineages retain the T6.1 response/snapshot contract;
new SHA-256 lineages receive frame identity and fixed-interval history semantics.

Evidence on a fresh isolated Oracle stack:

```text
PASS T6.4-EVAL-SELF-CHECK (69/69)
PASS T6.4-EVAL-MUTATION-SELF-CHECK (20/20)
PASS T6.4-SOURCE-AUDIT
PASS T6.4-ORACLE-PRODUCTION
PASS T6.4-VISIBLE (28/28 test ids, 848/848 declared assertions)
PASS T6.1-VISIBLE (20/20 test ids, 430/430 declared assertions)
PASS T6.2-VISIBLE (22/22 test ids, 372/372 declared assertions)
PASS T6.3-VISIBLE (28/28 test ids, 906/906 declared assertions)
```

Frozen refreshed evaluator manifest:
`49df1e47ef6612dbaf50671f7d362c5f6546d40818c588e9b69d053d1d007081`.
